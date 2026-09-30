# TrayMonitor

Indicadores na bandeja do sistema do Windows: **Temperatura**, **CPU**, **Memória**, **Download** e **Upload**.

Ao passar o mouse sobre um indicador, aparece uma caixa com os 10 processos que mais consomem aquele recurso
(CPU, memória, ou E/S de disco+rede no caso dos indicadores de rede).

## Uso

- **Executável:** `dist\TrayMonitor.exe`
- **Script:** `TrayMonitor.vbs` (roda `TrayMonitor.ps1` sem janela de console)

Clique direito em qualquer indicador: *Gerenciador de Tarefas* / *Sair*.

## Compilar

```powershell
Install-Module ps2exe -Scope CurrentUser
.\build.ps1
```

## Arquivos

| Arquivo | Descrição |
|---|---|
| `TrayMonitor.ps1` | Código-fonte |
| `TrayMonitor.vbs` | Inicia o script oculto |
| `build.ps1` | Gera `dist\TrayMonitor.exe` com ps2exe |
| `make-bear-icon.ps1` | Gera o ícone `urso-dormindo.ico` |
| `dist\TrayMonitor.exe` | Versão compilada |
