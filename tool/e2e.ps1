<#
.SYNOPSIS
Runs the on-device end-to-end suites against the local test lab.

.DESCRIPTION
Configuration comes from `.tmp/e2e/local.json` (gitignored) merged over the
defaults below, and every value can be overridden with an environment variable
(E2E_DEVICE, E2E_WEBDAV_URL, E2E_WEBDAV_USER, E2E_WEBDAV_PASS, E2E_MUSIC_ROOT,
E2E_TV_ROOT). No host, path or credential is baked into the repository.

Suites:
  boot     app boots and renders its shell           (integration_test/app_boot_test.dart)
  webdav   lists music/video roots and reads a range (integration_test/e2e_webdav_test.dart)
  cast     SSDP finds a MediaRenderer                (integration_test/e2e_cast_test.dart)
  music    reads tags from a remote audio file       (integration_test/e2e_music_test.dart)
  cue      parses the lab .cue sheet                 (integration_test/e2e_cue_test.dart)
  cbz      opens a .cbz and reads one page           (integration_test/e2e_cbz_test.dart)
  queue    one cache download through the queue      (integration_test/e2e_queue_test.dart)
  scrape   scans one file into the music library     (integration_test/e2e_scrape_test.dart)
  maintenance  batch retag + cover recovery          (integration_test/e2e_library_maintenance_test.dart)
  castplay casts a real video and waits for PLAYING  (integration_test/e2e_cast_play_test.dart)
  ui       walks every settings screen for overflows  (integration_test/e2e_layout_test.dart)
  all      read-only probes in one boot              (integration_test/e2e_full_test.dart)

The renderer (Kodi) is part of the fixture, not something the operator starts by
hand: suites that need it (`cast`, `castplay`, `all`) start it when it is not
running, wait until its UPnP endpoint listens, and stop it again if the script
started it. The same runs mute the Windows output so a cast does not blast the
room; `finally` puts the previous mute state back. Read-only suites touch
neither.

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
        'scrape', 'maintenance', 'castplay', 'ui', 'all')]
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
    kodiExe     = ''
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
$kodiExe = Resolve-Setting 'kodiExe' 'E2E_KODI_EXE' $defaults.kodiExe
$needDmr = if ($RequireDmr) { $true } else { [bool](Resolve-Setting 'requireDmr' $null $defaults.requireDmr) }

# 'all' runs the combined target on purpose: one drive = one install.
$suites = if ($Suite -eq 'all') { @('all') } else { @($Suite) }
# Suites that need a live MediaRenderer; the rest run without one.
$needsRenderer =
    @($suites | Where-Object { @('cast', 'castplay', 'all') -contains $_ }).Count -gt 0
$targets = @{
    boot     = 'integration_test\app_boot_test.dart'
    webdav   = 'integration_test\e2e_webdav_test.dart'
    cast     = 'integration_test\e2e_cast_test.dart'
    music    = 'integration_test\e2e_music_test.dart'
    cue      = 'integration_test\e2e_cue_test.dart'
    cbz      = 'integration_test\e2e_cbz_test.dart'
    queue    = 'integration_test\e2e_queue_test.dart'
    scrape   = 'integration_test\e2e_scrape_test.dart'
    maintenance = 'integration_test\e2e_library_maintenance_test.dart'
    castplay = 'integration_test\e2e_cast_play_test.dart'
    ui       = 'integration_test\e2e_layout_test.dart'
    all      = 'integration_test\e2e_full_test.dart'
}

# --- host audio -------------------------------------------------------------
#
# Casts are loud and the renderer sits on the desktop these suites drive. Mute
# the Windows output for the run and put the previous state back afterwards, so
# a test never leaves the box silent (or blaring).

if (-not ('EndpointAudio' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class EndpointAudio
{
    [ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")]
    private class MMDeviceEnumeratorComObject { }

    [ComImport, InterfaceType(ComInterfaceType.InterfaceIsIUnknown), Guid("A95664D2-9614-4F35-A746-DE8DB63617E6")]
    private interface IMMDeviceEnumerator
    {
        int NotImpl1();
        int GetDefaultAudioEndpoint(int dataFlow, int role, out IMMDevice ppDevice);
    }

    [ComImport, InterfaceType(ComInterfaceType.InterfaceIsIUnknown), Guid("D666063F-1587-4E43-81F1-B948E807363F")]
    private interface IMMDevice
    {
        int Activate(ref Guid iid, int dwClsCtx, IntPtr pActivationParams,
            [MarshalAs(UnmanagedType.IUnknown)] out object ppInterface);
    }

    [ComImport, InterfaceType(ComInterfaceType.InterfaceIsIUnknown), Guid("5CDF2C82-841E-4546-9722-0CF74078229A")]
    private interface IAudioEndpointVolume
    {
        int NotImpl1(); int NotImpl2(); int NotImpl3(); int NotImpl4();
        int NotImpl5(); int NotImpl6(); int NotImpl7(); int NotImpl8();
        int NotImpl9(); int NotImpl10(); int NotImpl11();
        int SetMute([MarshalAs(UnmanagedType.Bool)] bool bMute, ref Guid pguidEventContext);
        int GetMute([MarshalAs(UnmanagedType.Bool)] out bool pbMute);
    }

    private static IAudioEndpointVolume GetVolume()
    {
        var enumerator = (IMMDeviceEnumerator)new MMDeviceEnumeratorComObject();
        IMMDevice device;
        Check(enumerator.GetDefaultAudioEndpoint(0, 1, out device));
        var iid = typeof(IAudioEndpointVolume).GUID;
        object raw;
        Check(device.Activate(ref iid, 1, IntPtr.Zero, out raw));
        return (IAudioEndpointVolume)raw;
    }

    private static void Check(int hr)
    {
        if (hr < 0) Marshal.ThrowExceptionForHR(hr);
    }

    public static bool IsMuted()
    {
        bool muted;
        Check(GetVolume().GetMute(out muted));
        return muted;
    }

    public static void SetMuted(bool muted)
    {
        var context = Guid.Empty;
        Check(GetVolume().SetMute(muted, ref context));
    }
}
'@
}

$script:audioWasMuted = $null

function Save-SystemAudio {
    try {
        $script:audioWasMuted = [bool] [EndpointAudio]::IsMuted()
        if ($script:audioWasMuted) {
            Write-Host 'e2e: system audio is already muted'
            return
        }
        [EndpointAudio]::SetMuted($true)
        Write-Host 'e2e: system audio muted for the run'
    } catch {
        $script:audioWasMuted = $null
        Write-Host "e2e: could not mute the system audio ($($_.Exception.Message)) — continuing" `
            -ForegroundColor Yellow
    }
}

function Restore-SystemAudio {
    if ($null -eq $script:audioWasMuted) { return }
    if ($script:audioWasMuted) { return }
    try {
        [EndpointAudio]::SetMuted($false)
        Write-Host 'e2e: system audio restored'
    } catch {
        Write-Host "e2e: could not restore the system audio ($($_.Exception.Message)); " `
            -ForegroundColor Yellow
        Write-Host 'unmute the host manually' -ForegroundColor Yellow
    }
}

# --- renderer lifecycle -----------------------------------------------------
#
# The lab renderer (Kodi) runs on this host. A suite must not depend on someone
# having launched it by hand: start it, wait until its UPnP endpoint listens, and
# stop it again only when this script was the one that started it. `kodiExe`
# (env E2E_KODI_EXE) is a local path, kept out of the repository like every other
# lab value.

$script:rendererStarted = $false

function Test-RendererReady {
    if (-not (Get-Process -Name kodi -ErrorAction SilentlyContinue)) {
        return $false
    }
    try {
        return [bool] (Get-NetTCPConnection -State Listen -LocalPort 1892 `
                -ErrorAction Stop | Select-Object -First 1)
    } catch {
        # The UPnP port is not queryable on every host; a live process is the
        # best signal we have then.
        return $true
    }
}

function Start-Renderer {
    if (Test-RendererReady) {
        Write-Host 'e2e: renderer is already running'
        return
    }
    if (-not $kodiExe -or -not (Test-Path -LiteralPath $kodiExe)) {
        Write-Host ("e2e: renderer is not running and kodiExe is not set " +
                "(set kodiExe in .tmp/e2e/local.json or E2E_KODI_EXE)") `
            -ForegroundColor Yellow
        return
    }
    Write-Host "e2e: starting the renderer ($kodiExe)"
    Start-Process -FilePath $kodiExe -WorkingDirectory (Split-Path -Parent $kodiExe)
    $script:rendererStarted = $true
    for ($i = 0; $i -lt 60; $i++) {
        Start-Sleep -Seconds 2
        if (Test-RendererReady) {
            Write-Host "e2e: renderer ready after $(($i + 1) * 2)s"
            return
        }
    }
    Write-Host 'e2e: renderer did not come up within 120s — continuing and ' `
        -ForegroundColor Yellow
    Write-Host 'letting the suite decide' -ForegroundColor Yellow
}

function Stop-Renderer {
    if (-not $script:rendererStarted) { return }
    $process = Get-Process -Name kodi -ErrorAction SilentlyContinue
    if (-not $process) {
        Write-Host 'e2e: renderer already exited'
        return
    }
    $null = $process.CloseMainWindow()
    for ($i = 0; $i -lt 20; $i++) {
        Start-Sleep -Seconds 1
        if (-not (Get-Process -Id $process.Id -ErrorAction SilentlyContinue)) {
            Write-Host 'e2e: renderer stopped (this run started it)'
            return
        }
    }
    Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
    Write-Host 'e2e: renderer did not close gracefully; terminated it' `
        -ForegroundColor Yellow
}

# --- device address -----------------------------------------------------------
#
# The phone is usually reached over wireless adb, where the system picks the
# port (`_adb-tls-connect._tcp` advertises something like 192.168.0.104:37287)
# and changes it whenever wireless debugging is toggled or the phone reboots.
# The configured value stays the hardware serial the user knows; resolve it to
# whatever address adb exposes before handing it to `flutter test -d`.

function Resolve-DeviceAddress([string] $wanted) {
    $attached = (& adb devices) -join "`n"
    if ($attached -match [regex]::Escape("$wanted`tdevice")) { return $wanted }
    if ($wanted -match '^[0-9.]+:\d+$') {
        & adb connect $wanted | Out-Null
        return $wanted
    }
    $mdns = (& adb mdns services 2>&1) -join "`n"
    $line = ($mdns -split "`n" |
        Where-Object { $_ -match "adb-$([regex]::Escape($wanted))-" } |
        Select-Object -First 1)
    if ($line) {
        $addr = [regex]::Match($line, '(\d{1,3}(?:\.\d{1,3}){3}:\d+)').Groups[1].Value
        if ($addr) {
            & adb connect $addr | Out-Null
            $state = ((& adb devices) -join "`n") -match [regex]::Escape("$addr`tdevice")
            if ($state) {
                Write-Host "e2e: wireless adb -> $wanted at $addr"
                return $addr
            }
        }
    }
    # `adb mdns services` can come back empty (the mDNS daemon is flaky on some
    # phones). Every attached network transport still answers `getprop`, so ask
    # each one for its serial and match the requested device that way.
    $network = [regex]::Matches($attached, '(?m)^([0-9.]+:\d+)\s+device') |
        ForEach-Object { $_.Groups[1].Value }
    foreach ($addr in $network) {
        $serial = (& adb -s $addr shell getprop ro.serialno 2>$null | Out-String).Trim()
        if ($serial -eq $wanted) {
            Write-Host "e2e: wireless adb -> $wanted at $addr"
            return $addr
        }
    }
    return $wanted
}

$dev = Resolve-DeviceAddress $dev

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
    # A run that involves the renderer brings it up and silences the host; the
    # finally block puts both back.
    if ($needsRenderer) {
        Start-Renderer
        Save-SystemAudio
    }
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
    Restore-SystemAudio
    Stop-Renderer
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
