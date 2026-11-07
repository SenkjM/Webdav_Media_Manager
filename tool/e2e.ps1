<#
.SYNOPSIS
Runs the on-device end-to-end suites against the local test lab.

.DESCRIPTION
Configuration comes from `.tmp/e2e/local.json` (gitignored) merged over the
defaults below, and every value can be overridden with an environment variable
(E2E_DEVICE, E2E_WEBDAV_URL, E2E_WEBDAV_USER, E2E_WEBDAV_PASS, E2E_MUSIC_ROOT,
E2E_TV_ROOT). No host, path or credential is baked into the repository.

Suites:
  boot    app boots and renders its shell          (integration_test/app_boot_test.dart)
  webdav  lists music/video roots and reads a range (integration_test/e2e_webdav_test.dart)
  cast    SSDP finds a MediaRenderer                (integration_test/e2e_cast_test.dart)

The script never uninstalls the app and never clears its data: on this lab phone
an uninstall/reinstall forces the user to re-confirm the install and re-grant
runtime permissions. Suites run through
`flutter test <target> -d <serial> --no-uninstall`, which installs with
`adb install -r` and keeps data and grants.

On failure the run drops logcat and a uiautomator dump into
`.tmp/e2e/<timestamp>/` so the state can be inspected without re-running.

.EXAMPLE
  pwsh -File tool\e2e.ps1 -Suite webdav

.EXAMPLE
  pwsh -File tool\e2e.ps1 -Suite all -RequireDmr
#>
[CmdletBinding()]
param(
    [ValidateSet('boot', 'webdav', 'cast', 'all')]
    [string] $Suite = 'all',

    [string] $Device,

    [switch] $RequireDmr
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$flutter = Join-Path ($env:FLUTTER_ROOT ?? 'D:\flutter') 'bin\flutter.bat'
if (-not (Test-Path -LiteralPath $flutter)) {
    throw "Flutter launcher not found: $flutter"
}

$defaults = [ordered]@{
    device      = '45d9d41f'
    webdavUrl   = 'http://192.168.0.107:5244/dav'
    webdavUser  = 'guest'
    webdavPass  = 'guest'
    musicRoot   = '/Local/Music'
    tvRoot      = '/Local/Downloads/TV'
    requireDmr  = $false
}

$pkg = 'com.senkjm.media_manager.dev'
$apk = Join-Path $root 'build\app\outputs\flutter-apk\app-dev-debug.apk'
$configPath = Join-Path $root '.tmp\e2e\local.json'
$config = @{}
if (Test-Path -LiteralPath $configPath) {
    $config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json -AsHashtable
    Write-Host "config: $configPath"
} else {
    Write-Host "config: defaults (create $configPath to override)"
}

function Resolve-Setting([string] $key, [string] $envName, $fallback) {
    if ($envName -and (Get-Item -LiteralPath "Env:$envName" -ErrorAction SilentlyContinue)) {
        return (Get-Item -LiteralPath "Env:$envName").Value
    }
    if ($config.ContainsKey($key) -and $null -ne $config[$key]) { return $config[$key] }
    return $fallback
}

$dev = if ($Device) { $Device } else { Resolve-Setting 'device' 'E2E_DEVICE' $defaults.device }
$url = Resolve-Setting 'webdavUrl' 'E2E_WEBDAV_URL' $defaults.webdavUrl
$user = Resolve-Setting 'webdavUser' 'E2E_WEBDAV_USER' $defaults.webdavUser
$pass = Resolve-Setting 'webdavPass' 'E2E_WEBDAV_PASS' $defaults.webdavPass
$music = Resolve-Setting 'musicRoot' 'E2E_MUSIC_ROOT' $defaults.musicRoot
$tv = Resolve-Setting 'tvRoot' 'E2E_TV_ROOT' $defaults.tvRoot
$needDmr = if ($RequireDmr) { $true } else { [bool](Resolve-Setting 'requireDmr' $null $defaults.requireDmr) }

# 'all' runs the combined target on purpose: one drive = one install.
$suites = if ($Suite -eq 'all') { @('all') } else { @($Suite) }
$targets = @{
    boot   = 'integration_test\app_boot_test.dart'
    webdav = 'integration_test\e2e_webdav_test.dart'
    cast   = 'integration_test\e2e_cast_test.dart'
    all    = 'integration_test\e2e_full_test.dart'
}

$devices = (& adb devices) -join "`n"
if ($devices -notmatch [regex]::Escape($dev)) {
    throw "device $dev not attached:`n$devices"
}

$defines = @(
    "--dart-define=E2E_WEBDAV_URL=$url",
    "--dart-define=E2E_WEBDAV_USER=$user",
    "--dart-define=E2E_WEBDAV_PASS=$pass",
    "--dart-define=E2E_MUSIC_ROOT=$music",
    "--dart-define=E2E_TV_ROOT=$tv",
    "--dart-define=E2E_REQUIRE_DMR=$(if ($needDmr) { '1' } else { '0' })"
)

$env:FLUTTER_ALREADY_LOCKED = 'true'
Push-Location $root
$failures = @()
try {
    foreach ($name in $suites) {
        Write-Host ""
        Write-Host "=== e2e: $name ===" -ForegroundColor Cyan
        # `flutter test` in device mode instead of `flutter drive`: drive runs
        # the integration-test path with `--uninstall` defaulting to true, so it
        # removes the app (and its data) after every run. `--no-uninstall` keeps
        # the install, the granted permissions and the app data.
        $arguments = @(
            'test',
            $targets[$name],
            '-d', $dev,
            '--no-uninstall',
            '--flavor', 'dev',
            '--no-version-check'
        )
        $arguments += $defines
        & $flutter @arguments
        $code = $LASTEXITCODE
        Write-Host "e2e: $name -> exit $code"

        # Never let a run leave the phone without the app: an uninstall would
        # cost a manual install confirmation and every runtime permission.
        $installed = (& adb -s $dev shell pm path $pkg) -join ''
        if ($installed -notmatch 'package:') {
            Write-Host "e2e: app is no longer installed ($pkg) — reinstalling " -NoNewline -ForegroundColor Yellow
            Write-Host "with adb install -r (keeps data)..." -ForegroundColor Yellow
            & adb -s $dev install -r $apk
            if ($LASTEXITCODE -ne 0) { throw "
could not restore $pkg; install it manually" }
        }
        if ($code -ne 0) { $failures += $name }
    }
} finally {
    Pop-Location
}

if ($failures.Count -gt 0) {
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $outDir = Join-Path $root ".tmp\e2e\$stamp"
    New-Item -ItemType Directory -Force -Path $outDir | Out-Null
    & adb -s $dev logcat -d *> (Join-Path $outDir 'logcat.txt')
    & adb -s $dev shell uiautomator dump /sdcard/e2e-dump.xml *> $null
    & adb -s $dev pull /sdcard/e2e-dump.xml (Join-Path $outDir 'dump.xml') *> $null
    Write-Host "artifacts: $outDir" -ForegroundColor Yellow
    throw "e2e failed: $($failures -join ', ')"
}

Write-Host "e2e passed: $($suites -join ', ')" -ForegroundColor Green
