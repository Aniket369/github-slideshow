@echo off
:: ================================================================
::  IT Tools - One-Time Setup
::  Run this ONCE. After that, just use the website.
::  No admin needed.
:: ================================================================

title IT Tools Setup
color 0A

cls
echo.
echo  =====================================================
echo    IT Tools  -  One-Time Setup
echo  =====================================================
echo.
echo  This sets up the connection between the website
echo  and your PC. Run this once - that's it.
echo.
echo  After setup, just open tools.html and click buttons.
echo  Scripts always run the latest version automatically.
echo.
echo  Press any key to start, or close this window to cancel.
echo.
pause > nul

:: ── Step 1: Create install folder ─────────────────────────────────
echo.
echo  [1/3] Creating install folder...
set "INSTALL=%USERPROFILE%\IT-Tools"
if not exist "%INSTALL%" mkdir "%INSTALL%"
echo        %INSTALL%
echo        OK.

:: ── Step 2: Copy ONLY the handler (scripts come from GitHub live) ──
echo.
echo  [2/3] Installing handler...

set "SOURCE=%~dp0setup"

if not exist "%SOURCE%\handler.ps1" (
    echo.
    echo  ERROR: Cannot find the setup\ folder next to this bat file.
    echo  Make sure Start-Here.bat and the setup\ folder are together.
    echo.
    pause
    exit /b 1
)

copy /Y "%SOURCE%\handler.ps1" "%INSTALL%\handler.ps1" > nul
powershell -Command "Unblock-File '%INSTALL%\handler.ps1'" > nul 2>&1
echo        OK.

:: ── Step 3: Register ittools:// protocol (no admin needed) ────────
echo.
echo  [3/3] Registering ittools:// in Windows...

set "CMD=powershell.exe -ExecutionPolicy Bypass -WindowStyle Normal -File \"%INSTALL%\handler.ps1\" \"%%1\""

reg add "HKCU\SOFTWARE\Classes\ittools"                    /ve /d "URL:IT Tools Protocol" /f > nul
reg add "HKCU\SOFTWARE\Classes\ittools"                    /v  "URL Protocol" /d "" /f        > nul
reg add "HKCU\SOFTWARE\Classes\ittools\shell"              /ve /d "" /f                        > nul
reg add "HKCU\SOFTWARE\Classes\ittools\shell\open"         /ve /d "" /f                        > nul
reg add "HKCU\SOFTWARE\Classes\ittools\shell\open\command" /ve /d "%CMD%" /f                   > nul

echo        OK.

:: ── Done ──────────────────────────────────────────────────────────
echo.
echo  =====================================================
echo    Setup complete! Opening website now...
echo  =====================================================
echo.
echo  From now on, just open tools.html and click buttons.
echo  No more setup needed - ever.
echo.

start "" "%~dp0tools.html"
timeout /t 3 > nul
