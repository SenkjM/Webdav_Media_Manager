<#
.SYNOPSIS
  One-shot build of WDMM Rust FFI (libwdmm_ffi.so) into android jniLibs (Windows).

.DESCRIPTION
  Mirrors .github/workflows/testbuild.yml cargo-ndk steps for local Windows use:
  submodule check → NDK resolve → optional FFmpeg vendor fetch → cargo ndk → verify .so.

  Prerequisites (install yourself once):
    - Rust stable + cargo
    - cargo-ndk  (script can `cargo install cargo-ndk` if missing)
    - Android NDK (ANDROID_NDK_HOME / ANDROID_HOME\ndk\<ver> / Flutter side-by-side NDK)
    - For FFmpeg vendor: Git Bash (bash.exe) so rust/wdmm-core/scripts/fetch-ffmpeg-vendor.sh runs

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
  Skip fetch-ffmpeg-vendor.sh (use when vendor/android-arm64 already present).

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
$fetchSh = Join-Path $core 'scripts\fetch-ffmpeg-vendor.sh'

function Write-Step([string] $msg) { Write-Host "==> $msg" -ForegroundColor Cyan }
function Write-Ok([string] $msg) { Write-Host "OK  $msg" -ForegroundColor Green }
function Fail([string] $msg) { throw $msg }

# --- helpers ---
function Test-Cmd([string] $Name) {
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Resolve-Bash {
    $cmd = Get-Command bash.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $candidates = @(
        'C:\Program Files\Git\bin\bash.exe',
        'C:\Program Files\Git\usr\bin\bash.exe',
        'C:\Program Files (x86)\Git\bin\bash.exe'
    )
    foreach ($c in $candidates) {
        if (Test-Path -LiteralPath $c) { return $c }
    }
    return $null
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
    if (-not (Test-Path -LiteralPath $fetchSh)) {
        Fail "missing $fetchSh"
    }
    $bash = Resolve-Bash
    if (-not $bash) {
        Write-Host 'WARN: bash.exe not found (Git for Windows). Skipping FFmpeg vendor fetch.' -ForegroundColor Yellow
        Write-Host '      Re-run with Git Bash on PATH, or pass -SkipFfmpeg if vendor is already filled.' -ForegroundColor Yellow
    } else {
        Write-Step 'fetch FFmpeg vendor (android-arm64)'
        $cache = Join-Path $env:TEMP 'wdmm-ffmpeg-vendor-cache'
        New-Item -ItemType Directory -Force -Path $cache | Out-Null
        # Git Bash needs /c/... ; Windows C:\... CACHE breaks (backslash / MSYS) and
        # the .sh then falls back to /workspace/agent-tools/... which does not exist here.
        if ($cache -match '^([A-Za-z]):\\(.*)$') {
            $cacheUnix = '/' + $Matches[1].ToLowerInvariant() + '/' + ($Matches[2] -replace '\\', '/')
        } else {
            $cacheUnix = ($cache -replace '\\', '/')
        }
        $env:WDMM_FFMPEG_ONLY = 'android-arm64'
        $env:WDMM_FFMPEG_CACHE = $cacheUnix
        # Windows checkouts often CRLF the .sh. Strip CR into a temp under the core
        # tree and invoke with a relative path (absolute TEMP paths break under Git Bash).
        $fetchLf = Join-Path $core 'scripts\.fetch-ffmpeg-vendor.lf.sh'
        $raw = [System.IO.File]::ReadAllText($fetchSh)
        [System.IO.File]::WriteAllText($fetchLf, ($raw -replace "`r", ''))
        Push-Location $core
        try {
            $bashCmd = "export WDMM_FFMPEG_ONLY=android-arm64; export WDMM_FFMPEG_CACHE='$cacheUnix'; bash './scripts/.fetch-ffmpeg-vendor.lf.sh'"
            & $bash --noprofile --norc -c $bashCmd
            if ($LASTEXITCODE -ne 0) {
                Fail 'fetch-ffmpeg-vendor.sh failed (need network once, or -SkipFfmpeg)'
            }
        } finally {
            Pop-Location
            Remove-Item -LiteralPath $fetchLf -Force -ErrorAction SilentlyContinue
        }
        Write-Ok 'FFmpeg vendor ready'
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
