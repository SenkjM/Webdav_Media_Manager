<#
.SYNOPSIS
Runs common Flutter verification commands with cache-aware safeguards.

.DESCRIPTION
Uses the Dart SDK directly for static analysis, avoiding Flutter's startup
cache mutation entirely. Static analysis may still fail if the environment
prevents the analysis-server child process from starting; report that failure
and do not request elevation. Flutter-dependent commands use Flutter's
cached Dart snapshot while skipping the shared-cache lock, version freshness
network check, and implicit pub get. Dependencies and required SDK artifacts
must already be resolved before using Test or GenL10n.

Set FLUTTER_ROOT to your Flutter SDK root; defaults to D:\flutter.

Run from the repository root, for example:
  pwsh -File tool\flutter-sandbox.ps1 Analyze
  pwsh -File tool\flutter-sandbox.ps1 Test
  pwsh -File tool\flutter-sandbox.ps1 Test test\download_queue_ordering_test.dart
  pwsh -File tool\flutter-sandbox.ps1 GenL10n
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateSet('Analyze', 'Test', 'GenL10n')]
    [string] $Command,

    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]] $Arguments
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$flutterRoot = if ($env:FLUTTER_ROOT) { $env:FLUTTER_ROOT } else { 'D:\flutter' }
$dart = Join-Path $flutterRoot 'bin\cache\dart-sdk\bin\dart.exe'
$snapshot = Join-Path $flutterRoot 'bin\cache\flutter_tools.snapshot'
$packages = Join-Path $flutterRoot 'packages\flutter_tools\.dart_tool\package_config.json'

foreach ($path in @($dart, $snapshot, $packages)) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Flutter tool prerequisite not found: $path"
    }
}

Push-Location $root
try {
    if ($Command -eq 'Analyze') {
        # `dart analyze` reads the resolved project package configuration but
        # never runs Flutter's universal-artifact update (for example,
        # libimobiledevice.stamp under the Flutter cache). It still needs
        # to spawn Dart's analysis server, which the environment may deny.
        & $dart analyze --fatal-infos --fatal-warnings @Arguments
        exit $LASTEXITCODE
    }

    # These commands only read pre-cached Flutter artifacts, so avoid the
    # shared cache lock and version freshness fetch. If an SDK artifact is
    # absent or stale, stop and ask the user to initialize the SDK cache;
    # never self-escalate.
    $env:FLUTTER_ALREADY_LOCKED = 'true'
    $commandArguments = switch ($Command) {
        'Test'    { @('--no-version-check', 'test', '--no-pub') + $Arguments }
        'GenL10n' { @('--no-version-check', 'gen-l10n') + $Arguments }
    }
    & $dart "--packages=$packages" $snapshot @commandArguments
    exit $LASTEXITCODE
} finally {
    Pop-Location
}
