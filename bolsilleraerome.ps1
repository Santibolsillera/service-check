<#
.DESCRIPTION
    Diagnostico de solo lectura. No modifica, no borra, no escribe nada en el
    sistema. Todo hallazgo marcado como FLAG es contexto, no veredicto.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'SilentlyContinue'

# ---------------------------------------------------------------------------
# Helpers de salida
# ---------------------------------------------------------------------------

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

# ---------------------------------------------------------------------------
# SYSTEM BOOT TIME
# ---------------------------------------------------------------------------

function Get-BootTime {
    Write-Section "SYSTEM BOOT TIME"
    $os   = Get-CimInstance Win32_OperatingSystem
    $boot =$os.LastBootUpTime
    $up   = (Get-Date) -$boot

    Write-Item "Last Boot" "$boot"
    Write-Item "Uptime" "$($up.Days) days, $($up.ToString('hh\:mm\:ss'))" `
        -Level $(if ($up.TotalMinutes -lt 30) { 'Flag' } else { 'Info' })
}

# ---------------------------------------------------------------------------
# CONNECTED DRIVES
# ---------------------------------------------------------------------------

function Get-ConnectedDrives {
    Write-Section "CONNECTED DRIVES"
    Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" | ForEach-Object {
        $sizeGb = [math]::Round($_.Size / 1GB, 1)
        $freeGb = [math]::Round($_.FreeSpace / 1GB, 1)
        Write-Item "$($_.DeviceID)" "$($_.FileSystem) | $sizeGb GB | $freeGb GB free"
    }
}

# ---------------------------------------------------------------------------
# SERVICE STATUS 
# ---------------------------------------------------------------------------

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

    # Encabezados de la tabla
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

# ---------------------------------------------------------------------------
# REGISTRY / CONFIGURATION
# ---------------------------------------------------------------------------

function Get-RegistryConfig {
    Write-Section "REGISTRY / CONFIGURATION"

    $cmdAvailable = Test-Path "$env:SystemRoot\System32\cmd.exe"
    Write-Item "CMD" $(if ($cmdAvailable) { "Available" } else { "Not Found" }) `
        -Level $(if ($cmdAvailable) { 'Info' } else { 'Flag' })

    $moduleLog = (Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ModuleLogging' `
                  -Name EnableModuleLogging -ErrorAction SilentlyContinue).EnableModuleLogging
    Write-Item "PowerShell Logging" $(if ($moduleLog -eq 1) { "Enabled" } else { "Disabled" }) `
        -Level $(if ($moduleLog -eq 1) { 'Ok' } else { 'Warn' })

    $actFeed = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer' `
                -Name EnableActivityFeed -ErrorAction SilentlyContinue).EnableActivityFeed
    Write-Item "Activities Cache" $(if ($actFeed -eq 0) { "Disabled" } else { "Available" }) `
        -Level $(if ($actFeed -eq 0) { 'Flag' } else { 'Info' })

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
    Write-Item "UserAssist" $(if ($hasEntries) { "Available" } else { "Not Found" }) `
        -Level $(if ($hasEntries) { 'Info' } else { 'Flag' })
}

# ---------------------------------------------------------------------------
# CONSOLE HOST HISTORY
# ---------------------------------------------------------------------------

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

# ---------------------------------------------------------------------------
# EVENT LOGS
# ---------------------------------------------------------------------------

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

    $cleared = @()
    $cleared += Get-WinEvent -FilterHashtable @{ LogName = 'Security'; Id = 1102 } -MaxEvents 5 -ErrorAction SilentlyContinue
    $cleared += Get-WinEvent -FilterHashtable @{ LogName = 'System'; Id = 104 } -MaxEvents 5 -ErrorAction SilentlyContinue

    if ($cleared.Count -gt 0) {
        Write-Item "Logs Cleared" "YES ($($cleared.Count) evento(s))" -Level Flag
    } else {
        Write-Item "Logs Cleared" "No" -Level Ok
    }
}

# ---------------------------------------------------------------------------
# RECYCLE BIN
# ---------------------------------------------------------------------------

function Get-RecycleBinInfo {
    Write-Section "RECYCLE BIN"

    $sid = ([Security.Principal.WindowsIdentity]::GetCurrent()).User.Value
    $bin = "$($env:SystemDrive)\`$Recycle.Bin\$sid"

    if (-not (Test-Path -LiteralPath $bin)) {
        Write-Item "Status" "not found" -Level Warn
        return
    }

    $dir  = Get-Item -LiteralPath $bin -Force
    $meta = Get-ChildItem -LiteralPath $bin -Force -Filter '$I*' -ErrorAction SilentlyContinue

    Write-Item "Last Modified" "$($dir.LastWriteTime)" `
        -Level $(if ((New-TimeSpan -Start $dir.LastWriteTime).TotalHours -lt 3) { 'Flag' } else { 'Info' })
    Write-Item "Total Items" "$($meta.Count)"

    if ($meta.Count -gt 0) {
        $latest = $meta | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        Write-Item "Latest Item" $latest.Name
    }
}

# ---------------------------------------------------------------------------
# SYSTEM INFORMATION (deteccion de VM)
# ---------------------------------------------------------------------------

function Get-SystemInformation {
    Write-Section "SYSTEM INFORMATION"

    $cs    = Get-CimInstance Win32_ComputerSystem
    $bios  = Get-CimInstance Win32_BIOS
    $board = Get-CimInstance Win32_BaseBoard

    $combined = "$($cs.Manufacturer) $($cs.Model) $($bios.Manufacturer) $($bios.SMBIOSBIOSVersion) $($board.Manufacturer) $($board.Product)"

    $vmSignatures = @('VMware','VirtualBox','Virtual Machine','QEMU','Xen','innotek','Parallels','Bochs')
    $hwHits = $vmSignatures | Where-Object { $combined -match $_ }

    $ouiMap = @{
        '00:05:69' = 'VMware'; '00:0C:29' = 'VMware'; '00:1C:14' = 'VMware'; '00:50:56' = 'VMware'
        '08:00:27' = 'VirtualBox'; '00:03:FF' = 'Hyper-V'; '00:15:5D' = 'Hyper-V'; '00:16:3E' = 'Xen'
    }
    $macHits = Get-CimInstance Win32_NetworkAdapter -Filter "MACAddress IS NOT NULL" | ForEach-Object {
        $oui = $_.MACAddress.Substring(0,8)
        if ($ouiMap.ContainsKey($oui)) { "MAC $($_.MACAddress) ($($_.Name)) -> $($ouiMap[$oui])" }
    }

    $vmProcs   = @('vmtoolsd','vboxservice','vboxtray','vm3dservice','vmwareuser','VGAuthService','qemu-ga')
    $procHits  = Get-Process -ErrorAction SilentlyContinue |
                 Where-Object { $vmProcs -contains $_.Name.ToLower() } |
                 ForEach-Object { "Proceso activo: $($_.Name)" }

    $allHits = @()
    if ($hwHits)  { $allHits += $hwHits | ForEach-Object { "Firma de hardware: $_" } }
    if ($macHits) { $allHits += $macHits }
    if ($procHits){ $allHits += $procHits }

    if ($allHits.Count -gt 0) {
        Write-Host ""
        Write-Host ("=" * 74) -ForegroundColor Yellow
        Write-Host "                  VIRTUAL MACHINE DETECTED" -ForegroundColor Yellow
        Write-Host ("=" * 74) -ForegroundColor Yellow
        foreach ($h in $allHits) { Write-Host "  $h" -ForegroundColor Red }
        Write-Host ("=" * 74) -ForegroundColor Yellow
    } else {
        Write-Item "Virtual Machine" "NO VIRTUAL MACHINE" -Level Ok
    }

    Write-Host ""
    Write-Item "Manual check" "Win + R > msinfo32 (ver Fabricante y Modelo del sistema)"
}

# ---------------------------------------------------------------------------
# BLOQUEO DE WEBS
# ---------------------------------------------------------------------------

function Get-BloqueoWebs {
    Write-Section "BLOQUEO DE WEBS"

    $entries = @()

    $hostsPath = "$env:SystemRoot\System32\drivers\etc\hosts"
    if (Test-Path -LiteralPath $hostsPath) {
        $lines = Get-Content -LiteralPath $hostsPath -ErrorAction SilentlyContinue |
                 Where-Object { $_.Trim() -and -not $_.Trim().StartsWith('#') }
        foreach ($l in $lines) {
            $parts = $l.Trim() -split '\s+'
            if ($parts.Count -ge 2) {
                $entries += [pscustomobject]@{ Location = $hostsPath; Domain = $parts[1] }
            }
        }
    }

    $zoneRoots = @(
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings\ZoneMap\Domains',
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Internet Settings\ZoneMap\Domains'
    )
    foreach ($root in $zoneRoots) {
        if (-not (Test-Path $root)) { continue }
        foreach ($domKey in (Get-ChildItem $root -Recurse -ErrorAction SilentlyContinue)) {
            $props = Get-ItemProperty -Path $domKey.PSPath -ErrorAction SilentlyContinue
            foreach ($p in $props.PSObject.Properties) {
                if ($p.Name -like 'PS*') { continue }
                if ($p.Value -ne 4) { continue }
                $domain = ($domKey.Name -split 'Domains\\')[-1]
                $entries += [pscustomobject]@{ Location = "Registro: Sitios Restringidos ($domKey.Name)"; Domain = $domain }
            }
        }
    }

    if ($entries.Count -eq 0) {
        Write-Item "Webs bloqueadas" "CHECK SUCCEEDED - CLEANED" -Level Ok
    } else {
        foreach ($e in $entries) {
            Write-Host "Ubicacion: $($e.Location)" -ForegroundColor Green
            if ($e.Domain -match 'github\.com') {
                Write-Host "  $($e.Domain)   <<< INSTA BAN >>>" -ForegroundColor Red
            } else {
                Write-Host "  $($e.Domain)" -ForegroundColor Gray
            }
        }
    }

    Write-Host ""
    $rules = Get-NetFirewallRule -Direction Outbound -Action Block -Enabled True -ErrorAction SilentlyContinue
    if ($rules) {
        Write-Item "Reglas de firewall (bloqueo saliente)" "$($rules.Count)" -Level Warn
        foreach ($r in ($rules | Select-Object -First 15)) {
            Write-Host "  $($r.DisplayName)" -ForegroundColor Gray
        }
    } else {
        Write-Item "Reglas de firewall (bloqueo saliente)" "ninguna" -Level Ok
    }
}

# ---------------------------------------------------------------------------
# BANNER NUEVO
# ---------------------------------------------------------------------------

function Show-Banner {
    Clear-Host
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8

    Write-Host @"
  ____             _   _ _           _     _ _ _                 
 / ___|  __ _ _ __| |_(_) |__   ___ | |___(_) | | ___ _ __ __ _  
 \___ \ / _` | '__| __| | '_ \ / _ \| / __| | | |/ _ \ '__/ _` | 
  ___) | (_| | |  | |_| | |_) | (_) | \__ \ | | |  __/ | | (_| | 
 |____/ \__,_|_|   \__|_|_.__/ \___/|_|___/_|_|_|\___|_|  \__,_| 
                                                                 
              S E R V I C E   C H E C K                          
"@ -ForegroundColor Cyan

    $anchoConsola =$Host.UI.RawUI.WindowSize.Width
    $corazon = @(
        "   ******   ******   ",
        " ********** ********** ",
        "************************",
        " ********************** ",
        "  ********************  ",
        "    ****************    ",
        "      ************      ",
        "        ********        ",
        "          ****          ",
        "           **           "
    )
    Write-Host ""
    foreach ($linea in $corazon) {$espacios = [Math]::Max(0, [int](($anchoConsola -$linea.Length) / 2))
        Write-Host (" " * $espacios +$linea) -ForegroundColor Red
    }

    Write-Host ""
    Write-Host "By " -ForegroundColor Cyan -NoNewline
    Write-Host "bolsilleraerome" -ForegroundColor Blue
    Write-Host ""
    Write-Host "Version 1.1" -ForegroundColor Green
    Write-Host "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Green
}

# ---------------------------------------------------------------------------
# Ejecucion Principal
# ---------------------------------------------------------------------------

Show-Banner

Get-BootTime
Get-ConnectedDrives
Get-ServiceStatus
Get-RegistryConfig
Get-ConsoleHistory
Get-EventLogsInfo
Get-RecycleBinInfo
Get-SystemInformation
Get-BloqueoWebs

Write-Host ""
Write-Host ("-" * 74) -ForegroundColor Green
Write-Host "CHECK COMPLETE"
Write-Host "Read-only diagnostic. No Windows settings were modified."
Write-Host "Press any key to exit..."
Write-Host ("-" * 74) -ForegroundColor Yellow
[void][System.Console]::ReadKey($true)