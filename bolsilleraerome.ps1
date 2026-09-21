[CmdletBinding()]
param()

$ErrorActionPreference = 'SilentlyContinue'

function Write-Section {
    param([string]$Title)
    Write-Host ""
    Write-Host ">> $Title" -ForegroundColor Cyan
}

function Write-Item {
    param(
        [string]$Label,
        [string]$Value,
        [ValidateSet('Info','Ok','Warn','Flag')][string]$Level = 'Info'
    )
    $color = switch ($Level) {
        'Ok'   { 'Green' }
        'Warn' { 'Yellow' }
        'Flag' { 'Red' }
        default { 'Green' }
    }
    $labelText = "{0,-24} " -f "$Label`:"
    Write-Host $labelText -ForegroundColor White -NoNewline
    Write-Host $Value -ForegroundColor $color
}

function Get-BootTime {
    Write-Section "SYSTEM BOOT TIME"
    $os   = Get-CimInstance Win32_OperatingSystem
    $boot =$os.LastBootUpTime
    $up   = (Get-Date) -$boot
    $script:LogonTime = $boot

    Write-Item "Last Boot" "$boot"
    Write-Item "Uptime" "$($up.Days) days, $($up.ToString('hh\:mm\:ss'))" -Level $(if ($up.TotalMinutes -lt 30) { 'Flag' } else { 'Info' })
}

function Get-ConnectedDrives {
    Write-Section "CONNECTED DRIVES"
    Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" | ForEach-Object {
        $sizeGb = [math]::Round($_.Size / 1GB, 1)
        $freeGb = [math]::Round($_.FreeSpace / 1GB, 1)
        Write-Item "$($_.DeviceID)" "$($_.FileSystem) | $sizeGb GB | $freeGb GB free"
    }
}

function Get-ServiceStatus {
    Write-Section "SERVICE STATUS"

    $services = [ordered]@{
        'SysMain'    = 'SysMain'
        'PcaSvc'     = 'Compatibility Assistant'
        'DPS'        = 'Diagnostic Policy Service'
        'EventLog'   = 'Windows Event Log'
        'Schedule'   = 'Task Scheduler'
        'bam'        = 'Background Activity Moderator'
        'DusmSvc'    = 'Data Usage'
        'Appinfo'    = 'Application Information'
        'CDPSvc'     = 'Connected Devices Platform'
        'DcomLaunch' = 'DCOM Server Process Launcher'
        'PlugPlay'   = 'Plug and Play'
        'WSearch'    = 'Windows Search'
    }

    Write-Host ("{0,-12}{1,-32}| {2,-10}{3}" -f "SERVICIO", "DESCRIPCION", "ESTADO", "HORA DE INICIO") -ForegroundColor DarkGray
    Write-Host ("-" * 74) -ForegroundColor DarkGray

    foreach ($key in $services.Keys) {
        $label = $services[$key]
        $svc   = Get-Service -Name $key -ErrorAction SilentlyContinue

        Write-Host ("{0,-12}{1,-32}" -f $key, $label) -ForegroundColor White -NoNewline
        Write-Host "| " -ForegroundColor Cyan -NoNewline

        if (-not $svc) {
            Write-Host "Not Found" -ForegroundColor Red
            continue
        }

        $status      = if ($svc.Status -eq 'Running') { 'Enabled' } else { 'Disabled' }
        $statusColor = if ($status -eq 'Enabled') { 'Green' } else { 'Red' }
        Write-Host ("{0,-10}" -f $status) -ForegroundColor $statusColor -NoNewline

        if ($key -eq 'bam') {
            Write-Host "SYSTEM" -ForegroundColor Magenta
        } else {
            $timeStr = ""
            if ($status -eq 'Enabled') {
                try {
                    $cimSvc = Get-CimInstance Win32_Service -Filter "Name='$key'" -ErrorAction Stop
                    if ($cimSvc.ProcessId -gt 0) {
                        $proc = Get-Process -Id $cimSvc.ProcessId -ErrorAction Stop
                        $timeStr = $proc.StartTime.ToString('HH:mm:ss')
                    }
                } catch { 
                    $timeStr = "N/A"
                }
            } else {
                $timeStr = "---"
            }
            Write-Host $timeStr -ForegroundColor Cyan
        }
    }
}

function Get-RegistryConfig {
    Write-Section "REGISTRY / CONFIGURATION"

    $cmdAvailable = Test-Path "$env:SystemRoot\System32\cmd.exe"
    Write-Item "CMD" $(if ($cmdAvailable) { "Available" } else { "Not Found" }) -Level $(if ($cmdAvailable) { 'Info' } else { 'Flag' })

    $psOpt = Get-PSReadLineOption -ErrorAction SilentlyContinue
    if ($psOpt) {
        if ($psOpt.HistorySaveStyle -eq 'SaveNothing') {
            Write-Item "PowerShell Logging" "Disabled (SaveNothing)" -Level Flag
        } else {
            Write-Item "PowerShell Logging" "Enabled ($($psOpt.HistorySaveStyle))" -Level Ok
        }
    } else {
        Write-Item "PowerShell Logging" "No disponible" -Level Warn
    }

    $actFeed = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer' -Name EnableActivityFeed -ErrorAction SilentlyContinue).EnableActivityFeed
    Write-Item "Activities Cache" $(if ($actFeed -eq 0) { "Disabled" } else { "Available" }) -Level $(if ($actFeed -eq 0) { 'Flag' } else { 'Info' })

    $prefetch = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters' -Name EnablePrefetcher -ErrorAction SilentlyContinue).EnablePrefetcher
    Write-Item "Prefetch Enable" $(if ($prefetch -in 1,2,3) { "Available ($prefetch)" } else { "Disabled" }) -Level $(if ($prefetch -in 1,2,3) { 'Info' } else { 'Warn' })

    $userAssistRoot = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\UserAssist'
    $hasEntries =$false
    if (Test-Path $userAssistRoot) {
        foreach ($guidKey in (Get-ChildItem $userAssistRoot -ErrorAction SilentlyContinue)) {
            $countPath = Join-Path $guidKey.PSPath 'Count'
            if (Test-Path $countPath) {
                $props = Get-ItemProperty -Path $countPath -ErrorAction SilentlyContinue
                if ($props -and ($props.PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' }).Count -gt 0) {
                    $hasEntries =$true
                    break
                }
            }
        }
    }
    Write-Item "UserAssist" $(if ($hasEntries) { "Available" } else { "Not Found" }) -Level $(if ($hasEntries) { 'Info' } else { 'Flag' })
}

function Get-ConsoleHistory {
    Write-Section "CONSOLE HOST HISTORY"

    $path = "$env:APPDATA\Microsoft\Windows\PowerShell\PSReadLine\ConsoleHost_history.txt"

    if (Test-Path -LiteralPath $path) {
        Write-Item "Status" "Found" -Level Ok
        Write-Item "Path" $path
    } else {
        Write-Item "Status" "NOT FOUND" -Level Flag
        Write-Host "FLAG" -ForegroundColor Red
    }
}

function Get-EventLogsInfo {
    Write-Section "EVENT LOGS"

    $shutdown = Get-WinEvent -FilterHashtable @{ LogName = 'System'; Id = 1074 } -MaxEvents 1 -ErrorAction SilentlyContinue
    if ($shutdown) {
        Write-Item "Last PC Shutdown" "$($shutdown.TimeCreated)"
    } else {
        Write-Item "Last PC Shutdown" "no registrado" -Level Warn
    }

    $eventLogSvc = Get-Service -Name EventLog -ErrorAction SilentlyContinue
    $started = if ($eventLogSvc -and $eventLogSvc.Status -eq 'Running') { 
        try {
            $cimSvc = Get-CimInstance Win32_Service -Filter "Name='EventLog'" -ErrorAction Stop
            if ($cimSvc.ProcessId -gt 0) { (Get-Process -Id $cimSvc.ProcessId -ErrorAction Stop).StartTime.ToString('yyyy-MM-dd HH:mm:ss') }
        } catch { }
    }
    Write-Item "Event Log Started" $(if ($started) { $started } else { "desconocido" })

    Write-Item "System Time" "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"

    $filterSec = @{ LogName = 'Security'; Id = 1102 }
    $filterSys = @{ LogName = 'System'; Id = 104 }
    
    if ($script:LogonTime) {
        $filterSec['StartTime'] = $script:LogonTime
        $filterSys['StartTime'] = $script:LogonTime
    }

    $cleared = @()
    $cleared += Get-WinEvent -FilterHashtable $filterSec -MaxEvents 20 -ErrorAction SilentlyContinue
    $cleared += Get-WinEvent -FilterHashtable $filterSys -MaxEvents 20 -ErrorAction SilentlyContinue

    if ($cleared.Count -gt 0) {
        Write-Item "Logs Cleared" "YES ($($cleared.Count) evento(s))" -Level Flag
    } else {
        Write-Item "Logs Cleared" "No" -Level Ok
    }
}

function Get-RecycleBinInfo {
    Write-Section "RECYCLE BIN"

    $sid = ([Security.Principal.WindowsIdentity]::GetCurrent()).User.Value
    $bin = "$($env:SystemDrive)\`$Recycle.Bin\$sid"

    if (-not (Test-Path -LiteralPath $bin)) {
        Write-Item "Status" "not found" -Level Warn
        return
    }

    $dir     = Get-Item -LiteralPath $bin -Force$allMeta = Get-ChildItem -LiteralPath $bin -Force -Filter '$I*' -ErrorAction SilentlyContinue
    $meta    = if ($script:LogonTime) { $allMeta \vert{} Where-Object {$_.LastWriteTime -ge $script:LogonTime } } else {$allMeta }

    Write-Item "Last Modified" "$($dir.LastWriteTime)" -Level $(if ((New-TimeSpan -Start$dir.LastWriteTime).TotalHours -lt 12) { 'Warn' } else { 'Info' })
    
    if ($meta) {
        Write-Item "Items Deleted Today" "$($meta.Count)" -Level Warn
    } else {
        Write-Item "Items Deleted Today" "0" -Level Ok
    }
}

function Get-NetworkInfo {
    Write-Section "NETWORK ADAPTER"
    
    $adapters = Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object Status -eq 'Up'
    
    if (-not $adapters) {
        Write-Item "Mac Address" "No active physical adapters" -Level Warn
        return
    }

    $ouiMap = @{
        '00:05:69' = 'VMware'; '00:0C:29' = 'VMware'; '00:1C:14' = 'VMware'; '00:50:56' = 'VMware';
        '08:00:27' = 'VirtualBox'; '00:03:FF' = 'Hyper-V'; '00:15:5D' = 'Hyper-V'; '00:16:3E' = 'Xen'
    }

    foreach ($adapter in$adapters) {
        $mac =$adapter.MacAddress.Replace('-','')
        $oui =$mac.Substring(0,6) -replace '(..)','$1:'
        $oui =$oui.TrimEnd(':')

        $type = 'Physical'
        if ($ouiMap.ContainsKey($oui)) {
            $type = "VM ($($ouiMap[$oui]))"
        }
        Write-Item "Mac Address ($($adapter.InterfaceAlias))" "$($adapter.MacAddress) [$type]" -Level $(if ($type -match 'VM') { 'Flag' } else { 'Ok' })
    }
}

function Get-VmProcesses {
    Write-Section "VM PROCESSES"
    
    $vmProcs  = @('vmtoolsd','vboxservice','vboxtray','vm3dservice','vmwareuser','VGAuthService','qemu-ga')$procHits = Get-Process -ErrorAction SilentlyContinue | Where-Object { $vmProcs -contains$_.Name }

    if ($procHits) {
        foreach ($p in$procHits) {
            Write-Item "Found Process" "$($p.Name) (ID: $($p.Id))" -Level Flag
        }
    } else {
        Write-Item "Status" "No VM processes detected" -Level Ok
    }
}

function Get-BloqueoWebs {
    Write-Section "BLOQUEO DE WEBS"

    $hostsPath = "$env:SystemRoot\System32\drivers\etc\hosts"

    if (Test-Path -LiteralPath $hostsPath) {
        $lines = Get-Content -LiteralPath$hostsPath -ErrorAction SilentlyContinue
        $foundAny =$false
        
        foreach ($l in$lines) {
            if ($l -match '^\s*#') { continue }
            if ($l -match '^\s*$') { continue }
            if ($l -match '\b(echo|discord|github)\b') {
                $foundAny =$true
                Write-Host "• " -ForegroundColor Red -NoNewline
                if ($l -match '\bgithub\b') {
                    Write-Host "$l <<< INSTA BAN >>> " -ForegroundColor Red -NoNewline
                    Write-Host "[`u{26A0}]" -ForegroundColor Red
                } else {
                    Write-Host "$l " -ForegroundColor Yellow -NoNewline
                    Write-Host "[`u{26A0}]" -ForegroundColor Yellow
                }
            }
        }
        if (-not $foundAny) {
            Write-Item "Hosts File" "No suspicious blocks found" -Level Ok
        }
    } else {
        Write-Item "Hosts File" "No encontrado" -Level Warn
    }
}

Write-Host "`n============== SERVICE CHECK ==============" -ForegroundColor Cyan
Get-BootTime
Get-ConnectedDrives
Get-ServiceStatus
Get-RegistryConfig
Get-ConsoleHistory
Get-EventLogsInfo
Get-RecycleBinInfo
Get-NetworkInfo
Get-VmProcesses
Get-BloqueoWebs
Write-Host "`n================Los errores de sintaxis se deben a que al introducir el código se perdieron espacios, saltos de línea y puntos y comas (`;`) obligatorios, lo que hizo que varias instrucciones se fusionaran incorrectamente. Además, la nueva función de bloqueo web tiene llaves `{ }` mal emparejadas. 

Aunque la captura de pantalla que compartes muestra que el inicio del script está bien estructurado[cite: 1], los problemas se encuentran en las líneas inferiores. Para solucionarlo, debes editar el archivo `bolsilleraerome.ps1` en tu repositorio y aplicar estas correcciones:

**1. Separar las variables (Línea 204)**
Falta un punto y coma entre el cierre de la llave y el inicio de la nueva variable.
*   **Busca:** `Id = 1102 }$filterSys`
*   **Reemplaza por:** `Id = 1102 }; $filterSys`

**2. Arreglar el diccionario de red (Línea 258)**
Falta un punto y coma para separar los valores de las direcciones MAC.
*   **Busca:** `'00:50:56' = 'VMware'         '08:00:27'`
*   **Reemplaza por:** `'00:50:56' = 'VMware'; '08:00:27'`

**3. Separar la lista y la variable (Línea 263)**
Falta un punto y coma al terminar el paréntesis antes de declarar `$procHits`.
*   **Busca:** `'qemu-ga')$procHits`
*   **Reemplaza por:** `'qemu-ga'); $procHits`

**4. Reestructurar la función `Get-BloqueoWebs` (Líneas 288-302)**
El bucle `foreach` no tiene el espacio obligatorio (dice `in$lines` en lugar de `in $lines`) y los bloques condicionales no están cerrando sus llaves correctamente. Elimina esa función rota y reemplázala con esta estructura limpia:

```powershell
function Get-BloqueoWebs {
    $hostsPath = "$env:windir\System32\drivers\etc\hosts"
    
    if (Test-Path -LiteralPath $hostsPath) {
        $lines = Get-Content -LiteralPath $hostsPath -ErrorAction SilentlyContinue
        
        foreach ($l in $lines) {
        }
    }
}
