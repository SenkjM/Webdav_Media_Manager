@echo off
setlocal
REM One-click wrapper: build libwdmm_ffi.so into android\app\src\main\jniLibs
REM Keeps the console open after finish so double-click users can read the log.
cd /d "%~dp0.."
where pwsh >nul 2>&1
if %ERRORLEVEL%==0 (
  pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0build-rust.ps1" %*
) else (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0build-rust.ps1" %*
)
set EXITCODE=%ERRORLEVEL%
echo.
if %EXITCODE% neq 0 (
  echo FAILED — exit %EXITCODE%
) else (
  echo DONE
)
echo.
pause
exit /b %EXITCODE%
