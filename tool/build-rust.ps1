<#
.SYNOPSIS
  One-shot build of WDMM Rust FFI (libwdmm_ffi.so) into android jniLibs.
  Windows PC only (local E:/ checkout); not for Linux CI/box.

.DESCRIPTION
  Mirrors .github/workflows/testbuild.yml cargo-ndk steps for local Windows use:
  submodule check → NDK resolve → optional FFmpeg vendor fetch → cargo ndk → verify .so.

  Prerequisites (install yourself once):
    - Rust stable + cargo
    - cargo-ndk  (script can `cargo install cargo-ndk` if missing)
    - Android NDK (ANDROID_NDK_HOME / ANDROID_HOME\ndk\<ver> / Flutter side-by-side NDK)
    - Network once for android-arm64 FFmpeg vendor (PowerShell download; no Git Bash)

  Run from anywhere:
    pwsh -ExecutionPolicy Bypass -File tool\build-rust.ps1
    pwsh -File tool\build-rust.ps1 -Abi arm64-v8a,x86_64
    pwsh -File tool\build-rust.ps1 -DebugBuild
    pwsh -File tool\build-rust.ps1 -SkipFfmpeg
    pwsh -File tool\build-rust.ps1 -Ffmpeg
    tool\build-rust.bat

.PARAMETER Abi
  Android ABIs for cargo-ndk. Default: arm64-v8a (same as Testbuild / sandbox).

.PARAMETER DebugBuild
  Build Rust debug profile instead of --release.
  (Named -DebugBuild because -Debug is reserved by PowerShell.)

.PARAMETER SkipFfmpeg
  Skip the legacy android-arm64 FFmpeg vendor (hzw-ffmpeg / hzw-ffprobe) download.
  This is unrelated to -Ffmpeg: the current crates/wdmm-ffmpeg/build.rs links
  libav* shared libraries instead of spawning those binaries.

.PARAMETER Ffmpeg
  Build with the real FFmpeg bindings enabled: download the prebuilt android
  libav* shared libraries from the `ffmpeg-android-libs` rolling release,
  drop them into jniLibs/<abi>/ (so the APK ships them), and pass
  `--features ffmpeg` plus WDMM_FFMPEG_LIB_DIR to cargo-ndk.
  Supported ABIs: arm64-v8a, x86_64. Requires network once per ABI
  (cached under .tmp\ffmpeg-android-libs).

.PARAMETER InstallCargoNdk
  Run `cargo install cargo-ndk` when cargo-ndk is missing (default: try install).
#>

[CmdletBinding()]
param(
    [string[]] $Abi = @('arm64-v8a'),
    [switch] $DebugBuild,
    [switch] $SkipFfmpeg,
    [switch] $Ffmpeg,
    [switch] $NoInstallCargoNdk
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$core = Join-Path $root 'rust\wdmm-core'
$outJni = Join-Path $root 'android\app\src\main\jniLibs'

function Write-Step([string] $msg) { Write-Host "==> $msg" -ForegroundColor Cyan }
function Write-Ok([string] $msg) { Write-Host "OK  $msg" -ForegroundColor Green }
function Fail([string] $msg) { throw $msg }

# --- helpers ---
function Test-Cmd([string] $Name) {
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}


function Resolve-NdkHome {
    if ($env:ANDROID_NDK_HOME -and (Test-Path -LiteralPath $env:ANDROID_NDK_HOME)) {
        return (Resolve-Path $env:ANDROID_NDK_HOME).Path
    }
    if ($env:NDK_HOME -and (Test-Path -LiteralPath $env:NDK_HOME)) {
        return (Resolve-Path $env:NDK_HOME).Path
    }

    $sdkRoots = @()
    foreach ($v in @($env:ANDROID_SDK_ROOT, $env:ANDROID_HOME, $env:ANDROID_SDK_HOME)) {
        if ($v) { $sdkRoots += $v }
    }
    $localApp = [Environment]::GetFolderPath('LocalApplicationData')
    $sdkRoots += @(
        (Join-Path $localApp 'Android\Sdk'),
        'C:\Android\Sdk',
        'D:\Android\Sdk'
    )
    # Flutter default on this project's Windows boxes
    if ($env:FLUTTER_ROOT) {
        $sdkRoots += (Join-Path $env:FLUTTER_ROOT '..\Android\Sdk')
    }

    foreach ($sdk in ($sdkRoots | Select-Object -Unique)) {
        if (-not $sdk) { continue }
        $ndkRoot = Join-Path $sdk 'ndk'
        if (-not (Test-Path -LiteralPath $ndkRoot)) { continue }
        $dirs = Get-ChildItem -LiteralPath $ndkRoot -Directory -ErrorAction SilentlyContinue |
            Sort-Object Name -Descending
        if ($dirs) {
            return $dirs[0].FullName
        }
    }
    return $null
}

function Ensure-RustTarget([string] $Triple) {
    $installed = & rustup target list --installed 2>$null
    if ($LASTEXITCODE -ne 0) { Fail 'rustup failed; is Rust installed and on PATH?' }
    if ($installed -notcontains $Triple) {
        Write-Step "rustup target add $Triple"
        & rustup target add $Triple
        if ($LASTEXITCODE -ne 0) { Fail "rustup target add $Triple failed" }
    }
}

$abiToTriple = @{
    'arm64-v8a'   = 'aarch64-linux-android'
    'armeabi-v7a' = 'armv7-linux-androideabi'
    'x86_64'      = 'x86_64-linux-android'
    'x86'         = 'i686-linux-android'
}

# Prebuilt android libav* shared libs come from the rolling `ffmpeg-android-libs`
# release (same assets .github/workflows/testbuild.yml consumes).
$ffmpegLibAssets = @{
    'arm64-v8a' = 'ffmpeg-android-arm64-v8a.tar.gz'
    'x86_64'    = 'ffmpeg-android-x86_64.tar.gz'
}
$ffmpegLibsBase = 'https://github.com/SenkjM/Webdav_Media_Manager/releases/download/ffmpeg-android-libs'
$ffmpegLibsCache = Join-Path $root '.tmp\ffmpeg-android-libs'

function Ensure-FfmpegLibs([string] $Abi) {
    if (-not $ffmpegLibAssets.ContainsKey($Abi)) {
        Fail "-Ffmpeg has no prebuilt libav* for '$Abi' (available: $($ffmpegLibAssets.Keys -join ', '))"
    }
    $asset = $ffmpegLibAssets[$Abi]
    $srcDir = Join-Path $ffmpegLibsCache $Abi
    $marker = Join-Path $srcDir 'libavcodec.so'
    $markerOk = (Test-Path -LiteralPath $marker) -and ((Get-Item -LiteralPath $marker).Length -gt 0)

    if ($markerOk) {
        Write-Ok "FFmpeg shared libs cached: $srcDir"
    } else {
        New-Item -ItemType Directory -Force -Path $ffmpegLibsCache | Out-Null
        $tgz = Join-Path $ffmpegLibsCache $asset
        if (-not ((Test-Path -LiteralPath $tgz) -and ((Get-Item -LiteralPath $tgz).Length -gt 0))) {
            $url = "$ffmpegLibsBase/$asset"
            Write-Step "download FFmpeg android shared libs $asset"
            Write-Host "  GET $url"
            try {
                Invoke-WebRequest -Uri $url -OutFile $tgz -UseBasicParsing
            } catch {
                Fail "download failed for $asset : $_"
            }
            if ((Get-Item -LiteralPath $tgz).Length -le 0) { Fail "download empty for $asset" }
        }
        Write-Step "extract $asset"
        & tar -xzf $tgz -C $ffmpegLibsCache
        if ($LASTEXITCODE -ne 0) { Fail "tar extract failed for $asset" }
        if (-not (Test-Path -LiteralPath $marker)) { Fail "missing $marker after extracting $asset" }
        Write-Ok "FFmpeg shared libs ready: $srcDir"
    }

    $destDir = Join-Path $outJni $Abi
    New-Item -ItemType Directory -Force -Path $destDir | Out-Null
    Copy-Item -Path (Join-Path $srcDir 'lib*.so') -Destination $destDir -Force
    Write-Ok "FFmpeg libs -> $destDir"
}

function Assert-FfmpegLinked([string] $So) {
    $bin = Join-Path $env:ANDROID_NDK_HOME 'toolchains\llvm\prebuilt\windows-x86_64\bin'
    $readelf = Join-Path $bin 'llvm-readelf.exe'
    if (-not (Test-Path -LiteralPath $readelf)) {
        Write-Host '  (llvm-readelf not found; skipping libav* link verification)'
        return
    }
    $needed = & $readelf -d $So | Select-String 'NEEDED' | ForEach-Object { $_.Line }
    if (-not ($needed -match 'libavformat\.so')) {
        Fail "libwdmm_ffi.so has no libav* NEEDED entry; --features ffmpeg did not link: $So"
    }
    Write-Ok "link verified: libav* NEEDED present in $So"

    # A NEEDED entry only proves the link happened; dlopen() additionally needs
    # every undefined av*/swr*/sws* symbol to exist in the packaged libav*.so.
    # FFmpeg 7 made av_q2d() a static inline, so an `extern av_q2d` left the whole
    # library unloadable on device ("cannot locate symbol", FFI unavailable).
    $nm = Join-Path $bin 'llvm-nm.exe'
    if (-not (Test-Path -LiteralPath $nm)) {
        Write-Host '  (llvm-nm not found; skipping libav* symbol resolution check)'
        return
    }
    $libDir = Split-Path -Parent $So
    $defined = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($lib in Get-ChildItem -Path $libDir -Filter 'libav*.so' -File) {
        foreach ($line in (& $nm -D --defined-only $lib.FullName 2>$null)) {
            $parts = @($line -split '\s+' | Where-Object { $_ })
            if ($parts.Count -ge 2) { [void]$defined.Add(($parts[-1] -split '@')[0]) }
        }
    }
    foreach ($lib in Get-ChildItem -Path $libDir -Filter 'libsw*.so' -File) {
        foreach ($line in (& $nm -D --defined-only $lib.FullName 2>$null)) {
            $parts = @($line -split '\s+' | Where-Object { $_ })
            if ($parts.Count -ge 2) { [void]$defined.Add(($parts[-1] -split '@')[0]) }
        }
    }
    if ($defined.Count -eq 0) {
        Write-Host '  (no libav* exports enumerated; skipping symbol resolution check)'
        return
    }
    $missing = @()
    foreach ($line in (& $nm -D --undefined-only $So 2>$null)) {
        $parts = @($line -split '\s+' | Where-Object { $_ })
        if ($parts.Count -lt 2) { continue }
        $sym = ($parts[-1] -split '@')[0]
        if ($sym -notmatch '^(av|swr|sws)_') { continue }
        if (-not $defined.Contains($sym)) { $missing += $sym }
    }
    if ($missing.Count -gt 0) {
        Fail ("libwdmm_ffi.so needs libav* symbols that the packaged libs do not export " +
            "(dlopen would fail on device): " + (($missing | Sort-Object -Unique) -join ', '))
    }
    Write-Ok 'symbol resolution verified: every libav* import is exported by the packaged libs'
}

# --- start ---
Write-Step "repo: $root"

if (-not (Test-Path -LiteralPath (Join-Path $core 'Cargo.toml'))) {
    Write-Step 'init submodule rust/wdmm-core'
    Push-Location $root
    try {
        & git submodule update --init --recursive rust/wdmm-core
        if ($LASTEXITCODE -ne 0) { Fail 'git submodule update failed for rust/wdmm-core' }
    } finally {
        Pop-Location
    }
    if (-not (Test-Path -LiteralPath (Join-Path $core 'Cargo.toml'))) {
        Fail "rust/wdmm-core missing Cargo.toml after submodule init"
    }
}

if (-not (Test-Cmd 'cargo')) {
    Fail 'cargo not found on PATH. Install Rust from https://rustup.rs'
}
if (-not (Test-Cmd 'rustup')) {
    Fail 'rustup not found on PATH'
}

$ndk = Resolve-NdkHome
if (-not $ndk) {
    Fail @"
Android NDK not found.
Set ANDROID_NDK_HOME to your NDK root (…\Android\Sdk\ndk\<version>),
or install an NDK under ANDROID_HOME\ndk\.
"@
}
$env:ANDROID_NDK_HOME = $ndk
$env:NDK_HOME = $ndk
Write-Ok "NDK: $ndk"

if (-not (Test-Cmd 'cargo-ndk')) {
    if ($NoInstallCargoNdk) {
        Fail 'cargo-ndk not on PATH. Install with: cargo install cargo-ndk'
    }
    Write-Step 'cargo install cargo-ndk'
    & cargo install cargo-ndk
    if ($LASTEXITCODE -ne 0) { Fail 'cargo install cargo-ndk failed' }
}

foreach ($a in $Abi) {
    if (-not $abiToTriple.ContainsKey($a)) {
        Fail "Unknown ABI '$a'. Use: $($abiToTriple.Keys -join ', ')"
    }
    Ensure-RustTarget $abiToTriple[$a]
}

if (-not $SkipFfmpeg) {
    # Windows-local only: download android-arm64 vendor with PowerShell (no bash).
    $arm64Vendor = Join-Path $core 'crates\wdmm-ffmpeg\vendor\android-arm64'
    $ffOut = Join-Path $arm64Vendor 'ffmpeg'
    $fpOut = Join-Path $arm64Vendor 'ffprobe'
    $cache = Join-Path $core '.ffmpeg-vendor-cache'
    $ffUrl = 'https://github.com/SenkjM/WDMM-core/releases/download/ffmpeg-vendor-seed-20261025/hzw-ffmpeg-arm64'
    $fpUrl = 'https://github.com/SenkjM/WDMM-core/releases/download/ffmpeg-vendor-seed-20261025/hzw-ffprobe-arm64'
    $ffCache = Join-Path $cache 'hzw-ffmpeg-arm64'
    $fpCache = Join-Path $cache 'hzw-ffprobe-arm64'

    New-Item -ItemType Directory -Force -Path $arm64Vendor | Out-Null
    New-Item -ItemType Directory -Force -Path $cache | Out-Null

    if ((Test-Path -LiteralPath $ffOut) -and (Test-Path -LiteralPath $fpOut) `
        -and ((Get-Item -LiteralPath $ffOut).Length -gt 0) `
        -and ((Get-Item -LiteralPath $fpOut).Length -gt 0)) {
        Write-Ok "FFmpeg vendor already present: $arm64Vendor"
    } else {
        Write-Step 'download FFmpeg vendor (android-arm64)'
        foreach ($pair in @(
            @{ Url = $ffUrl; Dest = $ffCache; Name = 'hzw-ffmpeg-arm64' },
            @{ Url = $fpUrl; Dest = $fpCache; Name = 'hzw-ffprobe-arm64' }
        )) {
            if ((Test-Path -LiteralPath $pair.Dest) -and ((Get-Item -LiteralPath $pair.Dest).Length -gt 0)) {
                Write-Ok "cached $($pair.Name)"
                continue
            }
            Write-Host "  GET $($pair.Url)"
            try {
                Invoke-WebRequest -Uri $pair.Url -OutFile $pair.Dest -UseBasicParsing
            } catch {
                Fail "download failed for $($pair.Name): $_"
            }
            if (-not (Test-Path -LiteralPath $pair.Dest) -or ((Get-Item -LiteralPath $pair.Dest).Length -le 0)) {
                Fail "download empty for $($pair.Name)"
            }
        }
        Copy-Item -LiteralPath $ffCache -Destination $ffOut -Force
        Copy-Item -LiteralPath $fpCache -Destination $fpOut -Force
        Write-Ok "FFmpeg vendor ready: $arm64Vendor"
    }
} else {
    Write-Step 'SkipFfmpeg: not fetching vendor'
}

New-Item -ItemType Directory -Force -Path $outJni | Out-Null

$profileArgs = if ($DebugBuild) { @('build', '-p', 'wdmm-ffi') } else { @('build', '--release', '-p', 'wdmm-ffi') }

if ($Ffmpeg) {
    # One cargo-ndk run per ABI: WDMM_FFMPEG_LIB_DIR is a single link-search dir,
    # so ABI-specific libav* copies cannot be mixed in one invocation.
    foreach ($a in $Abi) {
        Ensure-FfmpegLibs $a
        $env:WDMM_FFMPEG_LIB_DIR = (Join-Path $outJni $a)
        $callArgs = @('-t', $a, '-o', $outJni) + $profileArgs + @('--features', 'ffmpeg')
        Write-Step ("cargo ndk " + ($callArgs -join ' ') + "   [WDMM_FFMPEG_LIB_DIR=$($env:WDMM_FFMPEG_LIB_DIR)]")
        Push-Location $core
        try {
            & cargo ndk @callArgs
            if ($LASTEXITCODE -ne 0) { Fail "cargo ndk failed for $a (exit $LASTEXITCODE)" }
        } finally {
            Pop-Location
        }
        Assert-FfmpegLinked (Join-Path $outJni "$a\libwdmm_ffi.so")
    }
    Remove-Item Env:\WDMM_FFMPEG_LIB_DIR -ErrorAction SilentlyContinue
} else {
    $ndkArgs = @()
    foreach ($a in $Abi) { $ndkArgs += @('-t', $a) }
    $ndkArgs += @('-o', $outJni)

    Write-Step ("cargo ndk " + ($ndkArgs + $profileArgs -join ' '))
    Push-Location $core
    try {
        & cargo ndk @ndkArgs @profileArgs
        if ($LASTEXITCODE -ne 0) { Fail "cargo ndk failed (exit $LASTEXITCODE)" }
    } finally {
        Pop-Location
    }
}

$missing = @()
foreach ($a in $Abi) {
    $so = Join-Path $outJni "$a\libwdmm_ffi.so"
    if (Test-Path -LiteralPath $so) {
        $len = (Get-Item -LiteralPath $so).Length
        Write-Ok "$so ($len bytes)"
    } else {
        $missing += $so
    }
}
if ($missing.Count -gt 0) {
    Fail ("libwdmm_ffi.so missing:`n  " + ($missing -join "`n  "))
}

Write-Host ''
Write-Ok 'Rust FFI build finished. jniLibs is gitignored — keep the .so locally for flutter run/build.'
