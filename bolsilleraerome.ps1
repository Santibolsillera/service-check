        (($titulo.ToCharArray() | ForEach-Object {
            $font[[string]$_][$fila]
        }) -join '').TrimEnd()
    }

    $anchoTitulo = ($tituloLineas | ForEach-Object { $_.Length } | Measure-Object -Maximum).Maximum
    $margenTitulo = [Math]::Max(0, [int](($anchoConsola - $anchoTitulo) / 2))

    foreach ($linea in $tituloLineas) {
        Write-Host ((' ' * $margenTitulo) + $linea) -ForegroundColor Cyan
    }

    Write-Host ""

    $subtitulo = 'S E R V I C E   C H E C K'
    $decoracion = '───────'
    $subLinea = "$decoracion  $subtitulo  $decoracion"
    $margenSub = [Math]::Max(0, [int](($anchoConsola - $subLinea.Length) / 2))

    Write-Host ((' ' * $margenSub)) -NoNewline
    Write-Host $decoracion -ForegroundColor DarkMagenta -NoNewline
    Write-Host "  $subtitulo  " -ForegroundColor Cyan -NoNewline
    Write-Host $decoracion -ForegroundColor DarkMagenta

    Write-Host ""


    $corazon = @(
        '          ▄██▄     ▄██▄'
        '        ███████▄ ▄███████'
        '       ███████████████████'
        '       ███████████████████'
        '        █████████████████'
        '          █████████████'
        '            █████████'
        '              █████'
        '                █'
    )

    $anchoCorazon = ($corazon | ForEach-Object { $_.Length } | Measure-Object -Maximum).Maximum
    $margenCorazon = [Math]::Max(0, [int](($anchoConsola - $anchoCorazon) / 2))

    foreach ($linea in $corazon) {
        Write-Host ((' ' * $margenCorazon) + $linea) -ForegroundColor Magenta
    }

    Write-Host ""

    $byPrefix = '♥  By '
    $byName   = 'bolsilleraerome'
    $byline   = $byPrefix + $byName
    $margenBy = [Math]::Max(0, [int](($anchoConsola - $byline.Length) / 2))

    Write-Host ((' ' * $margenBy)) -NoNewline
    Write-Host '♥' -ForegroundColor Magenta -NoNewline
    Write-Host '  By ' -ForegroundColor DarkCyan -NoNewline
    Write-Host $byName -ForegroundColor Cyan

    $version = 'Version 912.18'
    $margenVersion = [Math]::Max(0, [int](($anchoConsola - $version.Length) / 2))
    Write-Host ((' ' * $margenVersion) + $version) -ForegroundColor DarkGray
    Write-Host ""
}


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
