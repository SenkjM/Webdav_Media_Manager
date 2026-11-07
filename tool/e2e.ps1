<#
.SYNOPSIS
Runs the on-device end-to-end suites against the local test lab.

.DESCRIPTION
Configuration comes from `.tmp/e2e/local.json` (gitignored) merged over the
defaults below, and every value can be overridden with an environment variable
(E2E_DEVICE, E2E_WEBDAV_URL, E2E_WEBDAV_USER, E2E_WEBDAV_PASS, E2E_MUSIC_ROOT,
E2E_TV_ROOT, E2E_DMR_RPC). No host, path or credential is baked into the repository.

Suites:
  boot     app boots and renders its shell           (integration_test/app_boot_test.dart)
  webdav   lists music/video roots and reads a range (integration_test/e2e_webdav_test.dart)
  cast     SSDP finds a MediaRenderer                (integration_test/e2e_cast_test.dart)
  music    reads tags from a remote audio file       (integration_test/e2e_music_test.dart)
  cue      parses the lab .cue sheet                 (integration_test/e2e_cue_test.dart)
  cbz      opens a .cbz and reads one page           (integration_test/e2e_cbz_test.dart)
  queue    one cache download through the queue      (integration_test/e2e_queue_test.dart)
  scrape   scans one file into the music library     (integration_test/e2e_scrape_test.dart)
  castplay casts a real video and waits for PLAYING  (integration_test/e2e_cast_play_test.dart)
  ui       walks every settings screen for overflows  (integration_test/e2e_layout_test.dart)
  all      read-only probes in one boot              (integration_test/e2e_full_test.dart)

Before the first suite the script mutes the lab renderer over JSON-RPC
(`dmrRpc`, e.g. http://kodi-host:9090/jsonrpc) so a cast does not blast the
room, and restores the mute/volume state in `finally`.

Suites run against the **autodev** flavour, not dev. On a device `flutter test
<target> -d <serial>` compiles the test file as the app entrypoint and installs
that build, which a manual launcher tap cannot start; keeping a separate flavour
means the dev install the user actually runs is never replaced. autodev holds
its own data, so a run also stops mutating the real library.

The script never uninstalls the flavour and never clears its data: on this lab
phone an uninstall/reinstall forces the user to re-confirm the install and
re-grant runtime permissions. Suites run through
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
    [ValidateSet('boot', 'webdav', 'cast', 'music', 'cue', 'cbz', 'queue',
        'scrape', 'castplay', 'ui', 'all')]
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
    mangaRoot   = '/Local/Downloads/Manga'
    cuePath     = ''
    cbzPath     = ''
    dmrName     = 'Kodi'
    dmrRpc      = ''
    requireDmr  = $false
}

$pkg = 'com.senkjm.media_manager.autodev'
$apk = Join-Path $root 'build\app\outputs\flutter-apk\app-autodev-debug.apk'
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
$manga = Resolve-Setting 'mangaRoot' 'E2E_MANGA_ROOT' $defaults.mangaRoot
$cue = Resolve-Setting 'cuePath' 'E2E_CUE_PATH' $defaults.cuePath
$cbz = Resolve-Setting 'cbzPath' 'E2E_CBZ_PATH' $defaults.cbzPath
$dmrName = Resolve-Setting 'dmrName' 'E2E_DMR_NAME' $defaults.dmrName
$dmrRpc = Resolve-Setting 'dmrRpc' 'E2E_DMR_RPC' $defaults.dmrRpc
$needDmr = if ($RequireDmr) { $true } else { [bool](Resolve-Setting 'requireDmr' $null $defaults.requireDmr) }

# 'all' runs the combined target on purpose: one drive = one install.
$suites = if ($Suite -eq 'all') { @('all') } else { @($Suite) }
$targets = @{
    boot     = 'integration_test\app_boot_test.dart'
    webdav   = 'integration_test\e2e_webdav_test.dart'
    cast     = 'integration_test\e2e_cast_test.dart'
    music    = 'integration_test\e2e_music_test.dart'
    cue      = 'integration_test\e2e_cue_test.dart'
    cbz      = 'integration_test\e2e_cbz_test.dart'
    queue    = 'integration_test\e2e_queue_test.dart'
    scrape   = 'integration_test\e2e_scrape_test.dart'
    castplay = 'integration_test\e2e_cast_play_test.dart'
    ui       = 'integration_test\e2e_layout_test.dart'
    all      = 'integration_test\e2e_full_test.dart'
}

# --- renderer audio (Kodi JSON-RPC) -----------------------------------------
#
# Casts are loud: the lab renderer sits on the desktop these suites drive. Mute
# it for the run and put the previous mute/volume state back afterwards, so a
# test never leaves the box silent or blaring.

$script:rendererAudio = $null

function Invoke-RendererRpc([string] $method, $params) {
    $body = @{ jsonrpc = '2.0'; id = 1; method = $method; params = $params } |
        ConvertTo-Json -Depth 6 -Compress
    Invoke-RestMethod -Uri $dmrRpc -Method Post -ContentType 'application/json' `
        -Body $body -TimeoutSec 5
}

function Save-RendererAudio {
    if (-not $dmrRpc) {
        Write-Host 'e2e: no dmrRpc configured — leaving the renderer audio alone'
        return
    }
    try {
        $props = (Invoke-RendererRpc 'Application.GetProperties' @('mute', 'volume')).result
        $script:rendererAudio = @{
            mute   = [bool] $props.mute
            volume = [int] $props.volume
        }
        # 0-100 on this endpoint; keep the level so the unmute is not a jump.
        Invoke-RendererRpc 'Application.SetMute' @{ mute = $true } | Out-Null
        Write-Host ("e2e: renderer muted (was mute={0} volume={1})" -f `
                $script:rendererAudio.mute, $script:rendererAudio.volume)
    } catch {
        $script:rendererAudio = $null
        Write-Host "e2e: could not mute the renderer ($($_.Exception.Message)) — continuing" `
            -ForegroundColor Yellow
    }
}

function Restore-RendererAudio {
    if (-not $dmrRpc -or $null -eq $script:rendererAudio) { return }
    $saved = $script:rendererAudio
    try {
        Invoke-RendererRpc 'Application.SetVolume' @{ volume = $saved.volume } | Out-Null
        Invoke-RendererRpc 'Application.SetMute' @{ mute = $saved.mute } | Out-Null
        Write-Host ("e2e: renderer audio restored (mute={0} volume={1})" -f `
                $saved.mute, $saved.volume)
    } catch {
        Write-Host "e2e: could not restore the renderer audio ($($_.Exception.Message))" `
            -ForegroundColor Yellow
    }
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
    "--dart-define=E2E_MANGA_ROOT=$manga",
    "--dart-define=E2E_CUE_PATH=$cue",
    "--dart-define=E2E_CBZ_PATH=$cbz",
    "--dart-define=E2E_DMR_NAME=$dmrName",
    "--dart-define=E2E_REQUIRE_DMR=$(if ($needDmr) { '1' } else { '0' })"
)

$env:FLUTTER_ALREADY_LOCKED = 'true'
Push-Location $root
$failures = @()
try {
    Save-RendererAudio
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
            '--flavor', 'autodev',
            '--no-version-check'
        )
        $arguments += $defines
        & $flutter @arguments
        $code = $LASTEXITCODE
        Write-Host "e2e: $name -> exit $code"

        # Never let a run leave autodev uninstalled: an uninstall would
        # cost a manual install confirmation and every runtime permission.
        # A device that dropped mid-run cannot be repaired here -- report it and
        # keep the suite's own exit code instead of masking it with an adb error.
        if ((& adb devices) -join "`n" -notmatch [regex]::Escape($dev)) {
            Write-Host "e2e: device $dev is gone — skipping the install check" `
                -ForegroundColor Yellow
            if ($code -ne 0) { $failures += $name }
            continue
        }
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
    Restore-RendererAudio
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
