param([string]$AhkRoot = 'C:\Program Files\AutoHotkey')
$ErrorActionPreference = 'Stop'
$runtime = Join-Path $AhkRoot 'v2\AutoHotkey64.exe'
$compiler = Join-Path $AhkRoot 'Compiler\Ahk2Exe.exe'
foreach ($required in @($runtime, $compiler)) {
    if (!(Test-Path -LiteralPath $required)) { throw "Не найден: $required" }
}
Push-Location $PSScriptRoot
try {
    foreach ($scriptArgs in @(
        @('/ErrorStdOut', 'tests\CoreTests.ahk'),
        @('/ErrorStdOut', 'tests\FeaturesTests.ahk'),
        @('/ErrorStdOut', 'Kweety.ahk', '--smoke-test')
    )) {
        $check = Start-Process -FilePath $runtime -ArgumentList $scriptArgs -Wait -PassThru -NoNewWindow
        if ($check.ExitCode -ne 0) { throw "Проверка не прошла: $($scriptArgs -join ' ')" }
    }
    New-Item -ItemType Directory -Path 'dist' -Force | Out-Null
    $compile = Start-Process -FilePath $compiler -ArgumentList @(
        '/in', 'Kweety.ahk', '/out', 'dist\Kweety.exe',
        '/base', ('"' + $runtime + '"'), '/icon', 'assets\Kweety.ico', '/silent'
    ) -Wait -PassThru -NoNewWindow
    if ($compile.ExitCode -ne 0 -or !(Test-Path -LiteralPath 'dist\Kweety.exe')) {
        throw 'Не удалось собрать Kweety.exe'
    }
    $smoke = Start-Process -FilePath 'dist\Kweety.exe' -ArgumentList '--smoke-test' -Wait -PassThru -NoNewWindow
    if ($smoke.ExitCode -ne 0) { throw 'Собранный EXE не прошёл проверку запуска' }
    Write-Output "Готово: $PSScriptRoot\dist\Kweety.exe"
} finally {
    Pop-Location
}
