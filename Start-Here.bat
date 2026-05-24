@echo off
:: ================================================================
::  IT Tools - Personal Machine Setup
::  Just double-click this. No admin needed.
:: ================================================================

title IT Tools Setup
color 0A

cls
echo.
echo  =====================================================
echo    IT Tools  -  Personal Machine Setup
echo  =====================================================
echo.
echo  This will:
echo    1. Copy scripts to your user folder (no admin needed)
echo    2. Register the ittools:// shortcut in Windows
echo    3. Open the website in your browser
echo.
echo  Press any key to start, or close this window to cancel.
echo.
pause > nul

:: ── Step 1: Create install folder in user profile (no admin needed) ──
echo.
echo  [1/3] Creating install folder...

set "INSTALL=%USERPROFILE%\IT-Tools"

if not exist "%INSTALL%" mkdir "%INSTALL%"
echo        Folder: %INSTALL%
echo        OK.

:: ── Step 2: Copy the scripts ──────────────────────────────────────────
echo.
echo  [2/3] Copying scripts...

set "SOURCE=%~dp0setup"

if not exist "%SOURCE%\handler.ps1" (
    echo.
    echo  ERROR: Cannot find the setup\ folder.
    echo  Make sure Start-Here.bat and the setup\ folder are in the same place.
    echo.
    pause
    exit /b 1
)

copy /Y "%SOURCE%\handler.ps1"          "%INSTALL%\handler.ps1"          > nul
copy /Y "%SOURCE%\Clear-TeamsCache.ps1" "%INSTALL%\Clear-TeamsCache.ps1" > nul
copy /Y "%SOURCE%\Restart-PC.ps1"       "%INSTALL%\Restart-PC.ps1"       > nul

:: Unblock scripts so Windows doesnt flag them as downloaded from internet
powershell -Command "Get-ChildItem '%INSTALL%\*.ps1' | Unblock-File" > nul 2>&1

echo        OK - 3 scripts copied.

:: ── Step 3: Register ittools:// under HKCU (no admin needed!) ─────────
echo.
echo  [3/3] Registering ittools:// in Windows...

set "CMD=powershell.exe -ExecutionPolicy Bypass -WindowStyle Normal -File \"%INSTALL%\handler.ps1\" \"%%1\""

reg add "HKCU\SOFTWARE\Classes\ittools"                    /ve /d "URL:IT Tools Protocol" /f > nul
reg add "HKCU\SOFTWARE\Classes\ittools"                    /v  "URL Protocol" /d "" /f        > nul
reg add "HKCU\SOFTWARE\Classes\ittools\shell"              /ve /d "" /f                        > nul
reg add "HKCU\SOFTWARE\Classes\ittools\shell\open"         /ve /d "" /f                        > nul
reg add "HKCU\SOFTWARE\Classes\ittools\shell\open\command" /ve /d "%CMD%" /f                   > nul

echo        OK - Windows now knows what to do when you click a button.

:: ── Done ──────────────────────────────────────────────────────────────
echo.
echo  =====================================================
echo    All done! Opening website in your browser...
echo  =====================================================
echo.

start "" "%~dp0tools.html"

echo  This window will close in 3 seconds.
timeout /t 3 > nul
