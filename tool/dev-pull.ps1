# 开发辅助：从真机 debug 应用里拉取文件到本地。
#
# 为什么需要它：`adb exec-out ... > file` 和 `adb shell run-as ... cat > file`
# 经过 PowerShell 时会被当成文本流编码，二进制数据（sqlite、图片）会被破坏。
# 这里走 base64 文本传输再解码，稳定可靠。
#
# 用法：
#   powershell -ExecutionPolicy Bypass -File tool\dev-pull.ps1 -Path app_flutter/download_queue.db
#   powershell -ExecutionPolicy Bypass -File tool\dev-pull.ps1 -Path app_flutter/download_queue.db -Out .tmp\q.db
#
# 常用路径（相对 app_flutter）：
#   download_queue.db    下载队列（status / progress / error_message）
#   music_library.db     账号 + 音乐库 + CUE 表 + 缓存 annex
#   playlists.db         歌单

param(
    [Parameter(Mandatory = $true)]
    [string] $Path,
    [string] $Out = '',
    [string] $Package = 'com.webdav.webdav_music_player'
)

$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $PSScriptRoot
$remote = "/data/data/$Package/$Path"

if (-not $Out) {
    $Out = Join-Path $root ('.tmp\' + (Split-Path -Leaf $Path))
}
$outDir = Split-Path -Parent $Out
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }

# 1. 设备上 base64（run-as 保证以应用 uid 读取私有目录）
$b64 = adb shell "run-as $Package sh -c 'base64 $remote'" 2>&1
if ($LASTEXITCODE -ne 0 -or -not $b64) {
    Write-Error "读取失败：$remote`n$b64"
    exit 1
}

# 2. base64 是纯 ASCII，可以安全地拼成字符串再解码
$joined = ($b64 -join '').Trim()
try {
    $bytes = [System.Convert]::FromBase64String($joined)
} catch {
    Write-Error "base64 解码失败：$_"
    exit 1
}

[System.IO.File]::WriteAllBytes($Out, $bytes)
Write-Output "已保存 $($bytes.Length) 字节 -> $Out"
