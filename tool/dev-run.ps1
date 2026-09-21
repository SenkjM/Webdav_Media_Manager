# 开发辅助：在真机上以 debug 模式运行并持续写日志。
# 用法：powershell -ExecutionPolicy Bypass -File tool\dev-run.ps1
# 日志：.dev-run.log（已 gitignore）
#
# 为什么不直接 `flutter run`：本机 shell 是每个命令一个进程，
# 长驻进程容易被回收导致 "Lost connection to device"。
# 这里用重定向把输出落到文件，进程本身独立存活。

param(
    [string] $Device = '',
    [switch] $Release
)

$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $PSScriptRoot
$log = Join-Path $root '.dev-run.log'

if (Test-Path $log) { Remove-Item $log -Force }

$args = @('run')
if ($Device) { $args += @('-d', $Device) }
if ($Release) {
    $args += @('--release')
} else {
    $args += @('--dart-define=AUDIO_NOTIF_DEBUG=true')
}

Push-Location $root
try {
    # 2>&1 会把原生 stderr 变成 ErrorRecord，用重定向而非管道避开。
    & flutter @args *> $log
} finally {
    Pop-Location
}
