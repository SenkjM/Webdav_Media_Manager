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
    tool\build-rust.bat

.PARAMETER Abi
  Android ABIs for cargo-ndk. Default: arm64-v8a (same as Testbuild / sandbox).

.PARAMETER DebugBuild
  Build Rust debug profile instead of --release.
  (Named -DebugBuild because -Debug is reserved by PowerShell.)

.PARAMETER SkipFfmpeg
  Skip android-arm64 FFmpeg vendor download (use when vendor already present).

.PARAMETER InstallCargoNdk
  Run `cargo install cargo-ndk` when cargo-ndk is missing (default: try install).
#>

[CmdletBinding()]
param(
    [string[]] $Abi = @('arm64-v8a'),
    [switch] $DebugBuild,
    [switch] $SkipFfmpeg,
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

$ndkArgs = @()
foreach ($a in $Abi) { $ndkArgs += @('-t', $a) }
$ndkArgs += @('-o', $outJni)
$profileArgs = if ($DebugBuild) { @('build', '-p', 'wdmm-ffi') } else { @('build', '--release', '-p', 'wdmm-ffi') }

Write-Step ("cargo ndk " + ($ndkArgs + $profileArgs -join ' '))
Push-Location $core
try {
    & cargo ndk @ndkArgs @profileArgs
    if ($LASTEXITCODE -ne 0) { Fail "cargo ndk failed (exit $LASTEXITCODE)" }
} finally {
    Pop-Location
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
