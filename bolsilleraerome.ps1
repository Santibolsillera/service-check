function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    return ([Security.Principal.WindowsPrincipal]::new($id)).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-BootDate {
    if ($script:LogonTime) { return $script:LogonTime }
    return (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
}

# Fecha de ultima escritura de una clave de registro (HKLM). PowerShell no la expone.
if (-not ('RegLastWrite' -as [type])) {
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using Microsoft.Win32;
using Microsoft.Win32.SafeHandles;

public static class RegLastWrite {
    [DllImport("advapi32.dll")]
    private static extern int RegQueryInfoKey(
        SafeRegistryHandle hKey, IntPtr lpClass, IntPtr lpcClass, IntPtr lpReserved,
        IntPtr lpcSubKeys, IntPtr lpcbMaxSubKeyLen, IntPtr lpcbMaxClassLen,
        IntPtr lpcValues, IntPtr lpcbMaxValueNameLen, IntPtr lpcbMaxValueLen,
        IntPtr lpcbSecurityDescriptor, out long lpftLastWriteTime);

    public static object Get(string subKey) {
        using (RegistryKey k = Registry.LocalMachine.OpenSubKey(subKey, false)) {
            if (k == null) return null;
            long ft;
            int rc = RegQueryInfoKey(k.Handle, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero,
                IntPtr.Zero, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero,
                IntPtr.Zero, IntPtr.Zero, out ft);
            if (rc != 0 || ft <= 0) return null;
            return DateTime.FromFileTimeUtc(ft).ToLocalTime();
        }
    }
}
"@
}

function Get-LastEvent {
    param([string]$LogName, [int[]]$Id, [string]$ProviderName)
    $f = @{ LogName = $LogName; Id = $Id }
    if ($ProviderName) { $f['ProviderName'] = $ProviderName }
    Get-WinEvent -FilterHashtable $f -MaxEvents 1 -ErrorAction SilentlyContinue
}


# ----------------------------------------------------------------------------
#  1) PROCESOS JAVA / MINECRAFT  (argumentos de la JVM sospechosos)
# ----------------------------------------------------------------------------
function Get-MinecraftProcesses {
    Write-Section "MINECRAFT / JAVA PROCESSES"

    $procs = @(Get-CimInstance Win32_Process -Filter "Name='javaw.exe' OR Name='java.exe'" -ErrorAction SilentlyContinue)
    if ($procs.Count -eq 0) {
        Write-Item "Java processes" "none running" -Level Warn
        return
    }

    # javaagents que consideras legitimos (launchers). Editalo a gusto.
    $knownAgents = @('theseus.jar')

    # PIDs que tienen archivo hsperfdata (de todos los usuarios + TEMP actual)
    $hsperf = @{}
    $roots = @("$env:TEMP\hsperfdata*", "$env:SystemDrive\Users\*\AppData\Local\Temp\hsperfdata*")
    foreach ($r in $roots) {
        Get-ChildItem -Path $r -Recurse -Force -File -ErrorAction SilentlyContinue |
            ForEach-Object { $hsperf[$_.Name] = $true }
    }

    # regla = patron regex sobre la linea de comandos + nivel
    $rules = @(
        @{ Name = 'javaagent';        Pattern = '-javaagent:("[^"]+"|\S+)';              Level = 'Flag' }
        @{ Name = 'agentlib/path';    Pattern = '-agent(?:lib|path):("[^"]+"|\S+)';      Level = 'Flag' }
        @{ Name = 'extra mods dir';   Pattern = '-D(?:fabric|loader)\.(?:addMods|modsFolder|modsDir)=("[^"]+"|\S+)'; Level = 'Flag' }
        @{ Name = 'bootclasspath';    Pattern = '-Xbootclasspath\S*';                    Level = 'Warn' }
        @{ Name = 'perfdata off';     Pattern = '-XX:-UsePerfData';                      Level = 'Warn' }
        @{ Name = 'attach disabled';  Pattern = '-XX:\+DisableAttachMechanism';          Level = 'Warn' }
        @{ Name = 'verify off';       Pattern = '-noverify|-Xverify:none|-XX:-BytecodeVerification\S*'; Level = 'Warn' }
    )

    foreach ($p in $procs) {
        $cmd  = [string]$p.CommandLine
        $isMc = $cmd -match '(?i)--gameDir|net\.minecraft|\.minecraft|fabricmc|minecraftforge|quiltmc|cpw\.mods'
        $kind = if ($isMc) { 'Minecraft' } else { 'Java' }

        Write-Host ""
        Write-Item "$kind process" "$($p.Name) (PID $($p.ProcessId))" -Level Info
        if ($p.CreationDate) {
            Write-Item "  Started" ("{0:dd-MM-yyyy HH:mm:ss}" -f $p.CreationDate)
        }

        $gd = [regex]::Match($cmd, '--gameDir\s+("([^"]+)"|(\S+))')
        if ($gd.Success) {
            $dir = if ($gd.Groups[2].Success) { $gd.Groups[2].Value } else { $gd.Groups[3].Value }
            Write-Item "  Game dir" $dir
        }

        $hit = $false
        foreach ($rule in $rules) {
            foreach ($m in [regex]::Matches($cmd, $rule.Pattern)) {
                $level = $rule.Level
                if ($rule.Name -eq 'javaagent') {
                    foreach ($ok in $knownAgents) {
                        if ($m.Value -match [regex]::Escape($ok)) { $level = 'Ok' }
                    }
                }
                Write-Item "  $($rule.Name)" $m.Value -Level $level
                if ($level -ne 'Ok') { $hit = $true }
            }
        }

        if (-not $hsperf.ContainsKey([string]$p.ProcessId)) {
            Write-Item "  hsperfdata" "no file for this PID (perfdata disabled or cleaned)" -Level Warn
            $hit = $true
        }

        if (-not $hit) { Write-Item "  Arguments" "nothing suspicious" -Level Ok }
    }
}


function Get-SuspiciousEvents {
    Write-Section "SUSPICIOUS EVENTS"

    $boot  = Get-BootDate
    $admin = Test-IsAdmin

    $checks = @(
        @{ Label = 'USN Journal Deleted';  Log = 'Application'; Id = 3079; Note = '(Application 3079)'; Kind = 'clear'; Admin = $false }
        @{ Label = 'System Log Cleared';   Log = 'System';      Id = 104;  Note = '(System 104)';       Kind = 'clear'; Admin = $false }
        @{ Label = 'Security Log Cleared'; Log = 'Security';    Id = 1102; Note = '(Security 1102)';    Kind = 'clear'; Admin = $true  }
        @{ Label = 'Time Changed (Sec)';   Log = 'Security';    Id = 4616; Note = '(Security 4616)';    Kind = 'time';  Admin = $true  }
        @{ Label = 'Last PS Pipeline';     Log = 'Microsoft-Windows-PowerShell/Operational'; Id = 4103; Note = '(PowerShell 4103)'; Kind = 'info'; Admin = $false }
    )

    foreach ($c in $checks) {
        if ($c.Admin -and -not $admin) {
            Write-Item $c.Label "requires administrator" -Level Warn
            continue
        }
        $e = Get-LastEvent -LogName $c.Log -Id $c.Id
        if (-not $e) {
            Write-Item $c.Label "no records" -Level $(if ($c.Kind -eq 'clear') { 'Ok' } else { 'Info' })
            continue
        }
        $when = "{0:dd-MM-yyyy HH:mm:ss}" -f $e.TimeCreated
        $level = 'Info'
        if ($c.Kind -eq 'clear') { $level = if ($e.TimeCreated -ge $boot) { 'Flag' } else { 'Warn' } }
        if ($c.Kind -eq 'time')  { $level = 'Warn' }
        Write-Item $c.Label "$when $($c.Note)" -Level $level
    }

    # EventLog arrancado mucho despues del boot = servicio detenido y vuelto a iniciar
    # (Fast Startup puede dar falso positivo, por eso es Warn)
    $start = Get-LastEvent -LogName 'System' -Id 6005
    if ($start) {
        $delta = ($start.TimeCreated - $boot).TotalMinutes
        Write-Item "EventLog Started" ("{0:dd-MM-yyyy HH:mm:ss} (boot {1:+0;-0} min)" -f $start.TimeCreated, $delta) `
            -Level $(if ($delta -gt 5) { 'Warn' } else { 'Ok' })
    }

    # Cambios de hora del sistema desde el arranque (Kernel-General 1)
    $tc = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-Kernel-General'; Id = 1; StartTime = $boot } -ErrorAction SilentlyContinue)
    if ($tc.Count -gt 0) {
        Write-Item "Time Changes" "$($tc.Count) since boot (last $("{0:HH:mm:ss}" -f $tc[0].TimeCreated))" -Level Warn
    } else {
        Write-Item "Time Changes" "none since boot" -Level Ok
    }

    # Servicios clave detenidos / reiniciados / con tipo de inicio cambiado despues del boot
    $keyServices  = 'EventLog', 'DPS', 'PcaSvc', 'SysMain', 'Schedule', 'WSearch'
    $displayNames = @{}
    foreach ($s in $keyServices) {
        $svc = Get-Service -Name $s -ErrorAction SilentlyContinue
        if ($svc) { $displayNames[$svc.DisplayName] = $s }
    }

    $scm = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Service Control Manager'; Id = 7036, 7040; StartTime = $boot } -ErrorAction SilentlyContinue)
    $hits = @()
    foreach ($e in $scm) {
        if ($e.Properties.Count -lt 1) { continue }
        $name = [string]$e.Properties[0].Value
        if (-not $displayNames.ContainsKey($name)) { continue }
        if ($e.TimeCreated -lt $boot.AddMinutes(10)) { continue }   # ruido del arranque
        $detail = ($e.Properties | Select-Object -Skip 1 | ForEach-Object { [string]$_.Value }) -join ' | '
        $hits += [pscustomobject]@{ Time = $e.TimeCreated; Id = $e.Id; Service = $displayNames[$name]; Detail = $detail }
    }
    if ($hits.Count -gt 0) {
        foreach ($h in ($hits | Sort-Object Time | Select-Object -First 8)) {
            Write-Item "Service Changed" ("{0:HH:mm:ss} {1} (SCM {2}) {3}" -f $h.Time, $h.Service, $h.Id, $h.Detail) -Level Flag
        }
    } else {
        Write-Item "Service Changes" "none after boot" -Level Ok
    }

    # Servicios / drivers instalados desde el arranque (7045)
    $new = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Service Control Manager'; Id = 7045; StartTime = $boot } -ErrorAction SilentlyContinue)
    if ($new.Count -gt 0) {
        foreach ($e in ($new | Select-Object -First 8)) {
            if ($e.Properties.Count -lt 2) { continue }
            $svcName = [string]$e.Properties[0].Value
            $img     = [string]$e.Properties[1].Value
            $lvl = if ($img -match '(?i)\\(Users|Temp|AppData|ProgramData)\\') { 'Flag' } else { 'Warn' }
            Write-Item "Service Installed" ("{0:HH:mm:ss} {1} -> {2}" -f $e.TimeCreated, $svcName, $img) -Level $lvl
        }
    } else {
        Write-Item "Service Installed" "none since boot" -Level Ok
    }
}

function Get-UsnJournalStatus {
    Write-Section 'USN JOURNAL ($UsnJrnl:$J)'

    if (-not (Test-IsAdmin)) {
        Write-Item "Status" "requires administrator" -Level Warn
        return
    }

    $drive = $env:SystemDrive
    $raw   = & fsutil usn queryjournal $drive 2>&1
    $code  = $LASTEXITCODE
    $text  = ($raw | Out-String)

    # El primer valor hex de 16 digitos es el Journal ID (funciona con Windows en cualquier idioma)
    $m = [regex]::Match($text, '0x[0-9a-fA-F]{16}')
    if ($code -ne 0 -or -not $m.Success) {
        Write-Item "Status" "journal NOT active / query failed" -Level Flag
        Write-Item "Drive" $drive
        return
    }

    $created = $null
    try {
        $ft = [Convert]::ToInt64($m.Value.Substring(2), 16)
        $created = [DateTime]::FromFileTime($ft)
    } catch { }

    if (-not $created) {
        Write-Item "Status" "active (ID $($m.Value))" -Level Info
        return
    }

    $boot    = Get-BootDate
    $install = (Get-CimInstance Win32_OperatingSystem).InstallDate

    Write-Item "Drive" $drive
    Write-Item "Journal ID" $m.Value
    Write-Item "Created" ("{0:dd-MM-yyyy HH:mm:ss}" -f $created)
    if ($install) { Write-Item "OS Installed" ("{0:dd-MM-yyyy HH:mm:ss}" -f $install) }

    if ($created -ge $boot) {
        Write-Item "State" "RECREATED AFTER BOOT (journal was deleted)" -Level Flag
    } elseif (((Get-Date) - $created).TotalHours -lt 24) {
        Write-Item "State" "created in the last 24h (possible delete + recreate)" -Level Flag
    } elseif ($install -and $created -gt $install.AddDays(1)) {
        Write-Item "State" "created after OS install (possible delete + recreate)" -Level Warn
    } else {
        Write-Item "State" "Intact" -Level Ok
    }
}

function Get-PrefetchIntegrity {
    Write-Section "PREFETCH INTEGRITY"

    if (-not (Test-IsAdmin)) {
        Write-Item "Status" "requires administrator" -Level Warn
        return
    }

    $pf = "$env:SystemRoot\Prefetch"
    if (-not (Test-Path -LiteralPath $pf)) {
        Write-Item "Folder" "not found" -Level Flag
        return
    }

    $files = @(Get-ChildItem -LiteralPath $pf -Filter *.pf -Force -ErrorAction SilentlyContinue)
    Write-Item "Files (.pf)" "$($files.Count)" -Level $(if ($files.Count -lt 50) { 'Warn' } else { 'Info' })

    if ($files.Count -eq 0) { return }

    $newest = $files | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    $oldest = $files | Sort-Object CreationTime            | Select-Object -First 1
    Write-Item "Newest" ("{0:dd-MM-yyyy HH:mm:ss}  {1}" -f $newest.LastWriteTime, $newest.Name)
    Write-Item "Oldest created" ("{0:dd-MM-yyyy HH:mm:ss}  {1}" -f $oldest.CreationTime, $oldest.Name)

    $seen = @{}
    $sus  = 0
    foreach ($f in $files) {
        $reasons = @()

        if ($f.IsReadOnly) { $reasons += 'Read-Only' }
        if ($f.Attributes -band [IO.FileAttributes]::Hidden) { $reasons += 'Hidden' }

        # En Windows 10/11 los .pf empiezan con la firma "MAM"
        try {
            $fs  = [IO.File]::Open($f.FullName, 'Open', 'Read', 'ReadWrite')
            $buf = New-Object byte[] 3
            [void]$fs.Read($buf, 0, 3)
            $fs.Close()
            if (-not ($buf[0] -eq 0x4D -and $buf[1] -eq 0x41 -and $buf[2] -eq 0x4D)) { $reasons += 'No MAM header' }
        } catch { $reasons += 'Unreadable' }

        # Dos .pf distintos con el mismo hash = uno fue copiado/falsificado
        $h = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256 -ErrorAction SilentlyContinue).Hash
        if ($h) {
            if ($seen.ContainsKey($h)) { $reasons += "Duplicate of $($seen[$h])" }
            else { $seen[$h] = $f.Name }
        }

        if ($reasons.Count -gt 0) {
            $sus++
            Write-Item $f.Name ($reasons -join ', ') -Level Flag
        }
    }

    if ($sus -eq 0) { Write-Item "Integrity" "Prefetch folder is clean" -Level Ok }
}

function Get-JavaArtifacts {
    Write-Section "JAVA ARTIFACTS (TEMP)"

    $tmp = $env:TEMP
    if (-not (Test-Path -LiteralPath $tmp)) {
        Write-Item "TEMP" "not found" -Level Flag
        return
    }

    # JavaLauncher.log: registro de ejecuciones "-jar"
    $jl = Join-Path $tmp 'JavaLauncher.log'
    if (Test-Path -LiteralPath $jl) {
        $f = Get-Item -LiteralPath $jl -Force
        Write-Item "JavaLauncher.log" ("found (modified {0:dd-MM-yyyy HH:mm:ss})" -f $f.LastWriteTime) -Level Info

        if ((($f.Attributes -band [IO.FileAttributes]::Hidden) -ne 0) -or $f.IsReadOnly) {
            Write-Item "  Attributes" "$($f.Attributes)" -Level Flag
        }

        $lines = @(Get-Content -LiteralPath $jl -ErrorAction SilentlyContinue | Where-Object { $_ -match '(?i)-jar' })
        if ($lines.Count -gt 0) {
            Write-Item "  Jar executions" "$($lines.Count)" -Level Warn
            foreach ($l in ($lines | Select-Object -Last 10)) {
                Write-Host "    $l" -ForegroundColor Yellow
            }
        } else {
            Write-Item "  Jar executions" "none logged" -Level Ok
        }
    } else {
        Write-Item "JavaLauncher.log" "not found" -Level Ok
    }

    # JNativeHook: libreria que apps Java extraen a TEMP para hooks globales de teclado/mouse
    $jn = @(Get-ChildItem -LiteralPath $tmp -Filter 'JNativeHook*' -Force -ErrorAction SilentlyContinue)
    if ($jn.Count -gt 0) {
        foreach ($x in $jn) {
            Write-Item "JNativeHook" ("{0:dd-MM-yyyy HH:mm:ss}  {1}" -f $x.LastWriteTime, $x.FullName) -Level Warn
        }
    } else {
        Write-Item "JNativeHook" "no files found" -Level Ok
    }
}
function Get-RegistryTamper {
    Write-Section "REGISTRY TAMPERING"

    $boot = Get-BootDate

    $items = @(
        @{ Label = 'ScriptBlock Logging';   Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging'; Name = 'EnableScriptBlockLogging'; Bad = @(0) }
        @{ Label = 'Activity Feed';         Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'; Name = 'EnableActivityFeed';     Bad = @(0) }
        @{ Label = 'Publish Activities';    Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'; Name = 'PublishUserActivities';  Bad = @(0) }
        @{ Label = 'Compat Assistant (a)';  Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppCompat'; Name = 'DisablePCA';          Bad = @(1) }
        @{ Label = 'Compat Assistant (b)';  Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppCompat'; Name = 'DisabledPCA';         Bad = @(1) }
        @{ Label = 'Command Prompt policy'; Path = 'HKCU:\Software\Policies\Microsoft\Windows\System';    Name = 'DisableCMD';          Bad = @(1, 2) }
        @{ Label = 'Track Programs';        Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'Start_TrackProgs'; Bad = @(0) }
        @{ Label = 'Recent Docs History';   Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer'; Name = 'NoRecentDocsHistory'; Bad = @(1) }
        @{ Label = 'Prefetcher';            Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters'; Name = 'EnablePrefetcher'; Bad = @(0) }
        @{ Label = 'BAM start type';        Path = 'HKLM:\SYSTEM\CurrentControlSet\Services\bam';       Name = 'Start'; Bad = @(4) }
        @{ Label = 'DPS start type';        Path = 'HKLM:\SYSTEM\CurrentControlSet\Services\DPS';       Name = 'Start'; Bad = @(4) }
        @{ Label = 'PcaSvc start type';     Path = 'HKLM:\SYSTEM\CurrentControlSet\Services\PcaSvc';    Name = 'Start'; Bad = @(4) }
        @{ Label = 'SysMain start type';    Path = 'HKLM:\SYSTEM\CurrentControlSet\Services\SysMain';   Name = 'Start'; Bad = @(4) }
        @{ Label = 'EventLog start type';   Path = 'HKLM:\SYSTEM\CurrentControlSet\Services\EventLog';  Name = 'Start'; Bad = @(4) }
    )

    foreach ($i in $items) {
        $val = $null
        try { $val = (Get-ItemProperty -LiteralPath $i.Path -Name $i.Name -ErrorAction Stop).($i.Name) } catch { }

        if ($null -eq $val) {
            Write-Item $i.Label "not set (default)" -Level Ok
            continue
        }

        $isBad = $i.Bad -contains $val
        Write-Item $i.Label ("{0} ({1})" -f $(if ($isBad) { 'DISABLED' } else { 'Enabled' }), $val) `
            -Level $(if ($isBad) { 'Flag' } else { 'Ok' })

        if ($i.Path -like 'HKLM:*') {
            $lw = [RegLastWrite]::Get($i.Path.Substring(6))
            if ($lw) {
                if ($isBad) {
                    Write-Item "  Last modified" ("{0:dd-MM-yyyy HH:mm:ss}" -f $lw)
                } elseif ($lw -gt $boot) {
                    Write-Item "  Key modified" ("after boot ({0:dd-MM-yyyy HH:mm:ss})" -f $lw) -Level Warn
                }
            }
        }
    }

    # IFEO: 
    $ifeoRoots = @(
        'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options',
        'HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows NT\CurrentVersion\Image File Execution Options'
    )
    $found = 0
    foreach ($root in $ifeoRoots) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        foreach ($k in (Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue)) {
            $dbg = (Get-ItemProperty -LiteralPath $k.PSPath -ErrorAction SilentlyContinue).Debugger
            if ($dbg) {
                $found++
                Write-Item "IFEO Debugger" "$($k.PSChildName) -> $dbg" -Level Flag
            }
        }
    }
    if ($found -eq 0) { Write-Item "IFEO Debuggers" "not found" -Level Ok }
}


function Get-DefenderStatus {
    Write-Section "WINDOWS DEFENDER"

    if (-not (Test-IsAdmin)) {
        Write-Item "Status" "requires administrator" -Level Warn
        return
    }

    $mp = Get-MpPreference     -ErrorAction SilentlyContinue
    $st = Get-MpComputerStatus -ErrorAction SilentlyContinue
    if (-not $mp -or -not $st) {
        Write-Item "Status" "Defender not available (third-party AV?)" -Level Warn
        return
    }

    Write-Item "Real-time protection" $(if ($st.RealTimeProtectionEnabled) { 'Enabled' } else { 'DISABLED' }) `
        -Level $(if ($st.RealTimeProtectionEnabled) { 'Ok' } else { 'Warn' })

    $any = $false
    foreach ($p in @($mp.ExclusionPath)) {
        if (-not $p) { continue }
        $any = $true
        $lvl = if ($p -match '(?i)\\(Users|Downloads|Desktop|AppData|Temp|ProgramData)(\\|$)') { 'Flag' } else { 'Warn' }
        Write-Item "Excluded path" $p -Level $lvl
    }
    foreach ($p in @($mp.ExclusionProcess))   { if ($p) { $any = $true; Write-Item "Excluded process" $p   -Level Warn } }
    foreach ($p in @($mp.ExclusionExtension)) { if ($p) { $any = $true; Write-Item "Excluded extension" $p -Level Warn } }

    if (-not $any) { Write-Item "Exclusions" "none" -Level Ok }
}


# ----------------------------------------------------------------------------
#  ORQUESTADOR  (esta es la unica linea que agregas al bloque final)
# ----------------------------------------------------------------------------
function Invoke-BypassChecks {
    Write-Section "PRIVILEGES"
    if (Test-IsAdmin) {
        Write-Item "Administrator" "Yes" -Level Ok
    } else {
        Write-Item "Administrator" "NO - some checks will be limited" -Level Warn
    }

    Get-MinecraftProcesses
    Get-SuspiciousEvents
    Get-UsnJournalStatus
    Get-PrefetchIntegrity
    Get-JavaArtifacts
    Get-RegistryTamper
    Get-DefenderStatus
}
