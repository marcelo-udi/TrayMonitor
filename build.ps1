# Compila TrayMonitor.ps1 em dist\TrayMonitor.exe (requer: Install-Module ps2exe -Scope CurrentUser)
Import-Module ps2exe
$root = $PSScriptRoot
New-Item -ItemType Directory -Force "$root\dist" | Out-Null
Invoke-ps2exe -inputFile "$root\TrayMonitor.ps1" -outputFile "$root\dist\TrayMonitor.exe" `
    -iconFile "$root\urso-dormindo.ico" -noConsole -STA -title 'TrayMonitor' `
    -description 'Monitor de CPU, memoria, temperatura e rede na bandeja' -version '1.0.0.0'
