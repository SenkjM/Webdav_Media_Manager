<#
.SYNOPSIS
Resolves Flutter dependencies with a workspace-local pub cache.

.DESCRIPTION
Use only after changing pubspec.yaml, pubspec.lock, or dependency overrides.
This intentionally uses flutter.bat because pub get is a stateful bootstrap
operation. It redirects PUB_CACHE into this repository so a sandboxed session
can write downloaded packages without touching the user-level cache.
#>

[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]] $Arguments
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$flutter = if ($env:FLUTTER_ROOT) {
    Join-Path $env:FLUTTER_ROOT 'bin\flutter.bat'
} else {
    'D:\flutter\bin\flutter.bat'
}

if (-not (Test-Path -LiteralPath $flutter)) {
    throw "Flutter launcher not found: $flutter"
}

$env:PUB_CACHE = Join-Path $root '.pub-cache'
$env:FLUTTER_STORAGE_BASE_URL = 'https://storage.flutter-io.cn'

Push-Location $root
try {
    & $flutter pub get @Arguments
    exit $LASTEXITCODE
} finally {
    Pop-Location
}
