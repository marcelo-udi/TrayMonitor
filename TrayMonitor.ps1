# TrayMonitor - mostra Temperatura, CPU, Memoria e Rede (download/upload) na bandeja do sistema
Add-Type -AssemblyName System.Windows.Forms, System.Drawing

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Net.NetworkInformation;
using System.Collections.Generic;
public static class SysInfo {
    [DllImport("kernel32.dll")] static extern bool GetSystemTimes(out long idle, out long kernel, out long user);
    [StructLayout(LayoutKind.Sequential)]
    public class MEMSTAT {
        public uint dwLength = (uint)Marshal.SizeOf(typeof(MEMSTAT));
        public uint dwMemoryLoad; public ulong ullTotalPhys; public ulong ullAvailPhys;
        public ulong ullTotalPageFile; public ulong ullAvailPageFile;
        public ulong ullTotalVirtual; public ulong ullAvailVirtual; public ulong ullAvailExtendedVirtual;
    }
    [DllImport("kernel32.dll")] static extern bool GlobalMemoryStatusEx([In, Out] MEMSTAT m);
    [DllImport("user32.dll")] public static extern bool DestroyIcon(IntPtr h);

    static long pIdle, pTotal;
    public static double Cpu() {
        long i, k, u; GetSystemTimes(out i, out k, out u);
        long total = k + u; // kernel inclui idle
        long dI = i - pIdle, dT = total - pTotal;
        pIdle = i; pTotal = total;
        return dT <= 0 ? 0 : Math.Max(0, Math.Min(100, 100.0 * (dT - dI) / dT));
    }
    public static MEMSTAT Mem() { var m = new MEMSTAT(); GlobalMemoryStatusEx(m); return m; }

    // taxa de rede em bytes/s desde a ultima chamada (soma das interfaces ativas, sem loopback/tunel)
    static long pRx = -1, pTx = -1; static DateTime pT;
    public static double[] Net() {
        long rx = 0, tx = 0;
        foreach (var n in NetworkInterface.GetAllNetworkInterfaces()) {
            if (n.OperationalStatus != OperationalStatus.Up) continue;
            if (n.NetworkInterfaceType == NetworkInterfaceType.Loopback || n.NetworkInterfaceType == NetworkInterfaceType.Tunnel) continue;
            try { var s = n.GetIPStatistics(); rx += s.BytesReceived; tx += s.BytesSent; } catch {}
        }
        var now = DateTime.UtcNow;
        double sec = (now - pT).TotalSeconds;
        double[] r = new double[2];
        if (pRx >= 0 && sec > 0) {
            r[0] = Math.Max(0, (rx - pRx) / sec);
            r[1] = Math.Max(0, (tx - pTx) / sec);
        }
        pRx = rx; pTx = tx; pT = now;
        return r;
    }
}

// processos que mais consomem: le todos de uma vez via NtQuerySystemInformation (sem precisar de admin)
public static class Procs {
    [DllImport("ntdll.dll")] static extern int NtQuerySystemInformation(int cls, IntPtr buf, int len, out int ret);

    public static string TopCpu = "", TopMem = "", TopIo = "";
    static Dictionary<long, long> pCpu = new Dictionary<long, long>(), pIo = new Dictionary<long, long>();
    static DateTime pT;

    static void Add(Dictionary<string, double> d, string k, double v) { double o; d.TryGetValue(k, out o); d[k] = o + v; }

    static string Top(Dictionary<string, double> d, int n, Func<double, string> fmt, double min) {
        var l = new List<KeyValuePair<string, double>>(d);
        l.Sort((a, b) => b.Value.CompareTo(a.Value));
        var s = "";
        for (int i = 0; i < l.Count && i < n; i++) {
            if (l[i].Value < min) break;
            string name = l[i].Key.Length > 28 ? l[i].Key.Substring(0, 27) + "." : l[i].Key;
            s += "\n" + name + "\t" + fmt(l[i].Value);
        }
        return s;
    }

    public static string Bytes(double b) {
        if (b >= 1073741824) return (b / 1073741824).ToString("0.0") + " GB";
        if (b >= 1048576) return (b / 1048576).ToString("0") + " MB";
        return (b / 1024).ToString("0") + " KB";
    }

    public static void Sample(int n) {
        if (IntPtr.Size != 8) return; // offsets abaixo sao da estrutura x64
        int len = 1 << 20, ret; IntPtr buf;
        while (true) {
            buf = Marshal.AllocHGlobal(len);
            int st = NtQuerySystemInformation(5, buf, len, out ret); // SystemProcessInformation
            if (st == 0) break;
            Marshal.FreeHGlobal(buf);
            if (st != unchecked((int)0xC0000004)) return;
            len = Math.Max(len * 2, ret + 65536);
        }
        var now = DateTime.UtcNow;
        double el = (now - pT).TotalSeconds;
        var cpu = new Dictionary<string, double>(); var mem = new Dictionary<string, double>(); var io = new Dictionary<string, double>();
        var nCpu = new Dictionary<long, long>(); var nIo = new Dictionary<long, long>();
        try {
            int off = 0;
            while (true) {
                IntPtr p = new IntPtr(buf.ToInt64() + off);
                int next = Marshal.ReadInt32(p, 0);
                long pid = Marshal.ReadIntPtr(p, 80).ToInt64();
                int nameLen = (ushort)Marshal.ReadInt16(p, 56);
                IntPtr nameBuf = Marshal.ReadIntPtr(p, 64);
                if (pid != 0 && nameBuf != IntPtr.Zero) {
                    string name = Marshal.PtrToStringUni(nameBuf, nameLen / 2);
                    if (name.EndsWith(".exe", StringComparison.OrdinalIgnoreCase)) name = name.Substring(0, name.Length - 4);
                    long key = Marshal.ReadInt64(p, 32) * 31 + pid; // CreateTime + PID: evita confundir PID reaproveitado
                    long t = Marshal.ReadInt64(p, 40) + Marshal.ReadInt64(p, 48);                       // User + Kernel (100ns)
                    long ioB = Marshal.ReadInt64(p, 232) + Marshal.ReadInt64(p, 240) + Marshal.ReadInt64(p, 248); // Read+Write+Other bytes
                    Add(mem, name, Marshal.ReadInt64(p, 8)); // WorkingSetPrivateSize (= "Memoria" do Gerenciador de Tarefas)
                    long prev;
                    if (pCpu.TryGetValue(key, out prev)) Add(cpu, name, t - prev);
                    if (pIo.TryGetValue(key, out prev)) Add(io, name, ioB - prev);
                    nCpu[key] = t; nIo[key] = ioB;
                }
                if (next == 0) break;
                off += next;
            }
        } finally { Marshal.FreeHGlobal(buf); }
        pCpu = nCpu; pIo = nIo;
        bool first = pT == default(DateTime); pT = now;
        TopMem = Top(mem, n, Bytes, 0);
        if (first || el <= 0) return;
        double cpuDiv = el * 1e7 * Environment.ProcessorCount / 100.0;
        TopCpu = Top(cpu, n, v => (v / cpuDiv).ToString("0.0") + "%", cpuDiv * 0.1);
        TopIo = Top(io, n, v => Bytes(v / el) + "/s", 1024 * el);
    }
}
"@

function Get-Temp {
    try {
        $z = Get-CimInstance Win32_PerfFormattedData_Counters_ThermalZoneInformation -ErrorAction Stop
        $k = ($z | Measure-Object HighPrecisionTemperature -Maximum).Maximum
        if ($k -gt 0) { return [math]::Round($k / 10 - 273.15) }
    } catch {}
    return $null
}

function Get-Color([double]$v, [double]$warn, [double]$crit) {
    if ($v -ge $crit) { return [Drawing.Color]::FromArgb(255, 90, 90) }
    if ($v -ge $warn) { return [Drawing.Color]::FromArgb(255, 200, 60) }
    return [Drawing.Color]::White
}

# taxa compacta para caber no icone: 0, 85K, .4M, 12M
function Format-RateShort([double]$bps) {
    $kb = $bps / 1KB
    if ($kb -lt 1) { return '0' }
    if ($kb -lt 100) { return '{0}K' -f [math]::Round($kb) }
    if ($kb -lt 1000) { return '.{0}M' -f [math]::Min(9, [math]::Max(1, [math]::Round($kb / 1024 * 10))) }
    return '{0}M' -f [math]::Round($bps / 1MB)
}

function Format-Rate([double]$bps) {
    if ($bps -ge 1MB) { return '{0:N1} MB/s' -f ($bps / 1MB) }
    return '{0:N0} KB/s' -f ($bps / 1KB)
}

function New-TextIcon([string]$letter, [string]$text, [Drawing.Color]$color, [Drawing.Color]$accent) {
    $bmp = New-Object Drawing.Bitmap 32, 32
    $g = [Drawing.Graphics]::FromImage($bmp)
    $g.TextRenderingHint = [Drawing.Text.TextRenderingHint]::AntiAliasGridFit
    $g.Clear([Drawing.Color]::Transparent)
    $sf = New-Object Drawing.StringFormat
    $sf.Alignment = 'Center'; $sf.LineAlignment = 'Center'
    # letra identificadora no topo, na cor do indicador
    $lf = New-Object Drawing.Font 'Segoe UI', 14, ([Drawing.FontStyle]::Bold), ([Drawing.GraphicsUnit]::Pixel)
    $g.DrawString($letter, $lf, (New-Object Drawing.SolidBrush $accent), (New-Object Drawing.RectangleF 0, -2, 32, 16), $sf)
    # valor embaixo
    $size = if ($text.Length -ge 3) { 14 } else { 19 }
    $font = New-Object Drawing.Font 'Segoe UI', $size, ([Drawing.FontStyle]::Bold), ([Drawing.GraphicsUnit]::Pixel)
    $g.DrawString($text, $font, (New-Object Drawing.SolidBrush $color), (New-Object Drawing.RectangleF -2, 12, 36, 21), $sf)
    $g.Dispose(); $font.Dispose(); $lf.Dispose()
    $h = $bmp.GetHicon(); $bmp.Dispose()
    return [Drawing.Icon]::FromHandle($h)
}

function Set-TrayIcon($ni, $icon) {
    $old = $ni.Icon
    $ni.Icon = $icon
    if ($old) { [void][SysInfo]::DestroyIcon($old.Handle); $old.Dispose() }
}

# caixa propria ao passar o mouse (a dica nativa do Windows e limitada a 127 caracteres).
# Texto: 1a linha = titulo; linhas com TAB = "processo<TAB>valor" em duas colunas; demais = subtitulo
Add-Type -ReferencedAssemblies System.Windows.Forms, System.Drawing -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Windows.Forms;
public class TipForm : Form {
    [DllImport("dwmapi.dll")] static extern int DwmSetWindowAttribute(IntPtr h, int attr, ref int val, int size);
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    string[] lines = new string[0];
    Font fTitle = new Font("Segoe UI Semibold", 10f), fRow = new Font("Segoe UI", 9f);
    int pad = 10, colGap = 24, nameW, valW, lineH, titleH;
    public TipForm() {
        FormBorderStyle = FormBorderStyle.None; ShowInTaskbar = false; StartPosition = FormStartPosition.Manual;
        TopMost = true; DoubleBuffered = true; BackColor = Color.FromArgb(38, 38, 38);
    }
    protected override bool ShowWithoutActivation { get { return true; } }
    protected override CreateParams CreateParams {
        get { var cp = base.CreateParams; cp.ExStyle |= 0x08000000 | 0x80 | 0x8; return cp; } // NOACTIVATE | TOOLWINDOW | TOPMOST
    }
    protected override void OnHandleCreated(EventArgs e) {
        base.OnHandleCreated(e);
        int round = 2; try { DwmSetWindowAttribute(Handle, 33, ref round, 4); } catch {} // cantos arredondados (Win11)
    }
    public void SetText(string text) {
        lines = text.Replace("\r", "").Split('\n');
        nameW = 0; valW = 0; int headW = 0;
        lineH = TextRenderer.MeasureText("Ag", fRow).Height + 2;
        titleH = TextRenderer.MeasureText("Ag", fTitle).Height + 4;
        for (int i = 0; i < lines.Length; i++) {
            int t = lines[i].IndexOf('\t');
            if (t >= 0) {
                nameW = Math.Max(nameW, TextRenderer.MeasureText(lines[i].Substring(0, t), fRow).Width);
                valW = Math.Max(valW, TextRenderer.MeasureText(lines[i].Substring(t + 1), fRow).Width);
            } else headW = Math.Max(headW, TextRenderer.MeasureText(lines[i], i == 0 ? fTitle : fRow).Width);
        }
        int w = Math.Max(headW, nameW + colGap + valW) + pad * 2;
        int h = pad * 2 - 2;
        for (int i = 0; i < lines.Length; i++) h += i == 0 ? titleH : lineH;
        Size = new Size(w, h);
        Invalidate();
    }
    public void ShowNear(Point p) {
        Rectangle wa = Screen.FromPoint(p).WorkingArea;
        int x = Math.Max(wa.Left + 4, Math.Min(p.X - Width / 2, wa.Right - Width - 4));
        int y = p.Y - Height - 16;
        if (y < wa.Top) y = p.Y + 20;
        if (y + Height > wa.Bottom) y = wa.Bottom - Height - 4;
        Location = new Point(x, y);
        if (!Visible) Show();
    }
    protected override void OnPaint(PaintEventArgs e) {
        var g = e.Graphics;
        using (var pen = new Pen(Color.FromArgb(70, 70, 70))) g.DrawRectangle(pen, 0, 0, Width - 1, Height - 1);
        int y = pad - 1;
        var flags = TextFormatFlags.NoPadding | TextFormatFlags.NoPrefix;
        for (int i = 0; i < lines.Length; i++) {
            string s = lines[i];
            int t = s.IndexOf('\t');
            if (i == 0) {
                TextRenderer.DrawText(g, s, fTitle, new Point(pad, y), Color.White, flags);
                y += titleH;
                using (var pen = new Pen(Color.FromArgb(70, 70, 70))) g.DrawLine(pen, pad, y - 4, Width - pad, y - 4);
                continue;
            }
            if (t >= 0) {
                TextRenderer.DrawText(g, s.Substring(0, t), fRow, new Point(pad, y), Color.FromArgb(200, 200, 200), flags);
                string v = s.Substring(t + 1);
                int vw = TextRenderer.MeasureText(g, v, fRow, Size.Empty, flags).Width;
                TextRenderer.DrawText(g, v, fRow, new Point(Width - pad - vw, y), Color.White, flags);
            } else {
                TextRenderer.DrawText(g, s, fRow, new Point(pad, y), Color.FromArgb(140, 170, 220), flags);
            }
            y += lineH;
        }
    }
}
"@
[void][TipForm]::SetProcessDPIAware()
$tipForm = New-Object TipForm
$script:tips = @{}
$script:hover = $null
$script:anchor = [Drawing.Point]::Empty

function Set-Tip($ni, [string]$text) {
    $script:tips[$ni] = $text
    if ($script:hover -eq $ni -and $tipForm.Visible) { $tipForm.SetText($text); $tipForm.ShowNear($script:anchor) }
}

function Show-Tip($ni) {
    $script:anchor = [Windows.Forms.Cursor]::Position
    if ($script:hover -ne $ni -or -not $tipForm.Visible) {
        $script:hover = $ni
        $tipForm.SetText([string]$script:tips[$ni])
    }
    $tipForm.ShowNear($script:anchor)
}

# esconde a caixa quando o mouse sai de cima do icone
$hideTimer = New-Object Windows.Forms.Timer
$hideTimer.Interval = 150
$hideTimer.Add_Tick({
    if (-not $tipForm.Visible) { return }
    $p = [Windows.Forms.Cursor]::Position
    if ([math]::Abs($p.X - $script:anchor.X) -gt 20 -or [math]::Abs($p.Y - $script:anchor.Y) -gt 20) { $tipForm.Hide(); $script:hover = $null }
})
$hideTimer.Start()

$menu = New-Object Windows.Forms.ContextMenuStrip
[void]$menu.Items.Add('Gerenciador de Tarefas', $null, { Start-Process taskmgr })
[void]$menu.Items.Add('Sair', $null, { $timer.Stop(); $hideTimer.Stop(); $tipForm.Close(); foreach ($n in $icons) { $n.Visible = $false; $n.Dispose() }; [Windows.Forms.Application]::Exit() })

# criados em ordem inversa: o Windows mostra o mais recente a esquerda
# resultado na bandeja: Temp | CPU | Mem | Download | Upload
$niUp   = New-Object Windows.Forms.NotifyIcon
$niDown = New-Object Windows.Forms.NotifyIcon
$niMem  = New-Object Windows.Forms.NotifyIcon
$niCpu  = New-Object Windows.Forms.NotifyIcon
$niTemp = New-Object Windows.Forms.NotifyIcon
$icons = @($niTemp, $niCpu, $niMem, $niDown, $niUp)
foreach ($n in $icons) {
    $n.ContextMenuStrip = $menu; $n.Visible = $true
    $n.Add_MouseMove({ param($s, $e) Show-Tip $s })
    $n.Add_MouseDown({ $tipForm.Hide(); $script:hover = $null })
}

# Windows 11: marca os icones deste processo como "sempre visiveis" (fora da seta ^)
function Set-IconsPromoted {
    $exe = (Get-Process -Id $PID).Path
    $name = Split-Path $exe -Leaf
    Get-ChildItem 'HKCU:\Control Panel\NotifyIconSettings' -ErrorAction SilentlyContinue | ForEach-Object {
        $p = Get-ItemProperty $_.PSPath
        if ($p.ExecutablePath -and (Split-Path $p.ExecutablePath -Leaf) -eq $name -and $p.IsPromoted -ne 1) {
            Set-ItemProperty $_.PSPath -Name IsPromoted -Value 1 -Type DWord
        }
    }
}

$cCpu  = [Drawing.Color]::FromArgb(70, 160, 255)
$cMem  = [Drawing.Color]::FromArgb(80, 200, 120)
$cTemp = [Drawing.Color]::FromArgb(255, 140, 60)
$cDown = [Drawing.Color]::FromArgb(0, 200, 210)
$cUp   = [Drawing.Color]::FromArgb(200, 110, 255)

[void][SysInfo]::Cpu()
[void][SysInfo]::Net()
[Procs]::Sample(10)
$script:tick = 0
$script:temp = Get-Temp

$update = {
    $cpu = [math]::Round([SysInfo]::Cpu())
    $m = [SysInfo]::Mem()
    $usedGB = ($m.ullTotalPhys - $m.ullAvailPhys) / 1GB
    $totGB = $m.ullTotalPhys / 1GB
    $mem = [int]$m.dwMemoryLoad
    $net = [SysInfo]::Net()
    $down = $net[0]; $up = $net[1]
    [Procs]::Sample(10)

    # temperatura via WMI e mais pesada: a cada 3 ciclos
    if ($script:tick % 3 -eq 0) { $script:temp = Get-Temp }
    # o Windows registra os icones com atraso: reforca a promocao no inicio e a cada ~1 min
    if ($script:tick -lt 10 -or $script:tick % 30 -eq 0) { Set-IconsPromoted }
    $script:tick++

    Set-TrayIcon $niCpu (New-TextIcon 'C' "$cpu" (Get-Color $cpu 70 90) $cCpu)
    Set-Tip $niCpu ("CPU: $cpu%" + [Procs]::TopCpu)

    Set-TrayIcon $niMem (New-TextIcon 'M' "$mem" (Get-Color $mem 75 90) $cMem)
    Set-Tip $niMem (('Memoria: {0}% ({1:N1} / {2:N1} GB)' -f $mem, $usedGB, $totGB) + [Procs]::TopMem)

    if ($null -ne $script:temp) {
        $t = $script:temp
        Set-TrayIcon $niTemp (New-TextIcon 'T' "$t" (Get-Color $t 75 90) $cTemp)
        Set-Tip $niTemp ("Temperatura: $t $([char]176)C`nMais CPU:" + [Procs]::TopCpu)
    } else {
        Set-TrayIcon $niTemp (New-TextIcon 'T' '--' ([Drawing.Color]::Gray) $cTemp)
        Set-Tip $niTemp 'Temperatura indisponivel'
    }

    Set-TrayIcon $niDown (New-TextIcon ([string][char]0x25BC) (Format-RateShort $down) ([Drawing.Color]::White) $cDown)
    Set-Tip $niDown ("Download: $(Format-Rate $down)`nMais E/S (disco+rede):" + [Procs]::TopIo)

    Set-TrayIcon $niUp (New-TextIcon ([string][char]0x25B2) (Format-RateShort $up) ([Drawing.Color]::White) $cUp)
    Set-Tip $niUp ("Upload: $(Format-Rate $up)`nMais E/S (disco+rede):" + [Procs]::TopIo)
}

$timer = New-Object Windows.Forms.Timer
$timer.Interval = 2000
$timer.Add_Tick($update)
& $update
$timer.Start()

[Windows.Forms.Application]::Run()
