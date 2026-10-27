@echo off
setlocal
REM One-click wrapper: build libwdmm_ffi.so into android\app\src\main\jniLibs
cd /d "%~dp0.."
where pwsh >nul 2>&1
if %ERRORLEVEL%==0 (
  pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0build-rust.ps1" %*
) else (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0build-rust.ps1" %*
)
exit /b %ERRORLEVEL%
