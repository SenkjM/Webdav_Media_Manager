# 开发辅助：在真机上以 debug 模式运行，进程完全脱离当前 shell。
#
# 为什么不用 `tool\dev-run.ps1`：那个脚本是同步运行的，宿主的每个命令都是独立进程，
# 长驻的 `flutter run` 会被回收，于是 "Lost connection to device"、
# 热重载（r）也就没了。
#
# 这里用 Start-Process 开一个独立进程并立刻返回，把 pid / VM Service URI
# 写到 .tmp\ 下，方便稍后用 `flutter attach` 重新接上调试会话。
#
# 用法：
#   powershell -ExecutionPolicy Bypass -File tool\dev-run-bg.ps1 -Device <serial>
#   # 停止：
#   powershell -ExecutionPolicy Bypass -File tool\dev-run-bg.ps1 -Stop
#
# 拿到 VM Service URI 后可以：
#   flutter attach --debug-uri <uri>        # 重新获得热重载 / DevTools

param(
    [string] $Device = '',
    [switch] $Stop
)

$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $PSScriptRoot
$tmpDir = Join-Path $root '.tmp'
if (-not (Test-Path $tmpDir)) { New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null }

$pidFile = Join-Path $tmpDir 'dev-run.pid'
$logFile = Join-Path $tmpDir 'dev-run-bg.log'
$uriFile = Join-Path $tmpDir 'vm-service-uri.txt'

# --- 停止模式 ---------------------------------------------------------------
if ($Stop) {
    if (Test-Path $pidFile) {
        $oldPid = (Get-Content $pidFile -Raw).Trim()
        if ($oldPid) {
            Write-Output "停止 flutter run (pid=$oldPid) …"
            Stop-Process -Id $oldPid -Force -ErrorAction SilentlyContinue
        }
        Remove-Item $pidFile -Force -ErrorAction SilentlyContinue
    }
    Write-Output '已停止。'
    exit 0
}

# --- 清理旧实例 -------------------------------------------------------------
if (Test-Path $pidFile) {
    $oldPid = (Get-Content $pidFile -Raw).Trim()
    if ($oldPid -and (Get-Process -Id $oldPid -ErrorAction SilentlyContinue)) {
        Write-Output "先停止已有实例 (pid=$oldPid) …"
        Stop-Process -Id $oldPid -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    }
    Remove-Item $pidFile -Force -ErrorAction SilentlyContinue
}
Remove-Item $logFile -Force -ErrorAction SilentlyContinue
Remove-Item $uriFile -Force -ErrorAction SilentlyContinue

# --- 组装命令 ---------------------------------------------------------------
$argList = @('run')
if ($Device) { $argList += @('-d', $Device) }
$argList += @('--dart-define=AUDIO_NOTIF_DEBUG=true')

$flutter = (Get-Command flutter).Source
# `powershell -Command` 让子进程自己处理重定向，父进程立刻返回。
$inner = "& '$flutter' $($argList -join ' ') *> '$logFile'"

$proc = Start-Process -FilePath 'powershell' `
    -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', $inner) `
    -WindowStyle Hidden -PassThru

$proc.Id | Out-File -FilePath $pidFile -Encoding ascii
Write-Output "已启动 flutter run（独立进程 pid=$($proc.Id)）"
Write-Output "日志：$logFile"

# --- 等待 VM Service 就绪 ---------------------------------------------------
Write-Output '等待 Dart VM Service …'
$uri = $null
for ($i = 0; $i -lt 90; $i++) {
    Start-Sleep -Seconds 2
    if (Test-Path $logFile) {
        $m = Select-String -Path $logFile -Pattern 'A Dart VM Service on \S+ is available at: (\S+)' -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($m) { $uri = $m.Matches[0].Groups[1].Value; break }
    }
    if (-not (Get-Process -Id $proc.Id -ErrorAction SilentlyContinue)) { break }
}

if ($uri) {
    $uri | Out-File -FilePath $uriFile -Encoding ascii
    Write-Output "VM Service: $uri"
    Write-Output "重新接上调试会话：flutter attach --debug-uri $uri"
} else {
    Write-Output '未捕获到 VM Service URI，请查看日志。'
}
