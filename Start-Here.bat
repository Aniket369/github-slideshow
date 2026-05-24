@echo off
:: ================================================================
::  IT Tools - Personal Machine Setup
::  Double-click this file to set everything up.
::  It will ask for Admin permission (needed to register the URL).
:: ================================================================

title IT Tools Setup
color 0A

:: ── Auto-elevate to Administrator ──────────────────────────────
:: If not running as admin, relaunch ourselves as admin
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo Requesting administrator permission...
    echo (A Windows security prompt will appear - click YES)
    powershell -Command "Start-Process cmd -ArgumentList '/c \"\"%~f0\"\"' -Verb RunAs"
    exit /b
)

:: ── Now we are running as Administrator ────────────────────────
cls
echo.
echo  =====================================================
echo    IT Tools  -  Personal Machine Setup
echo  =====================================================
echo.
echo  This will:
echo    1. Copy the scripts to  C:\IT-Tools\
echo    2. Register the  ittools://  shortcut in Windows
echo    3. Open the website in your browser
echo.
echo  Press any key to continue, or close this window to cancel.
echo.
pause > nul

:: ── Step 1: Create the install folder ──────────────────────────
echo.
echo  [1/3] Creating C:\IT-Tools\ ...

if exist "C:\IT-Tools\" (
    echo        Folder already exists - will update files inside it.
) else (
    mkdir "C:\IT-Tools\"
    if %errorLevel% neq 0 (
        echo  ERROR: Could not create C:\IT-Tools\
        echo  Make sure you clicked YES on the admin prompt.
        pause
        exit /b 1
    )
)
echo        OK.

:: ── Step 2: Copy the scripts ───────────────────────────────────
echo.
echo  [2/3] Copying scripts to C:\IT-Tools\ ...

:: Figure out which folder THIS bat file is sitting in
set "SOURCE=%~dp0setup"

if not exist "%SOURCE%\handler.ps1" (
    echo.
    echo  ERROR: Cannot find the setup\ folder next to this bat file.
    echo  Make sure you kept all the downloaded files together.
    echo  Expected location: %SOURCE%
    echo.
    pause
    exit /b 1
)

copy /Y "%SOURCE%\handler.ps1"          "C:\IT-Tools\handler.ps1"          > nul
copy /Y "%SOURCE%\Clear-TeamsCache.ps1" "C:\IT-Tools\Clear-TeamsCache.ps1" > nul
copy /Y "%SOURCE%\Restart-PC.ps1"       "C:\IT-Tools\Restart-PC.ps1"       > nul

:: Unblock the scripts so Windows doesn't flag them as "downloaded from internet"
powershell -Command "Get-ChildItem 'C:\IT-Tools\*.ps1' | Unblock-File" > nul 2>&1

echo        OK - 3 scripts copied and unblocked.

:: ── Step 3: Register ittools:// in Windows Registry ───────────
echo.
echo  [3/3] Registering ittools:// URL protocol in Windows ...

set "CMD=powershell.exe -ExecutionPolicy Bypass -WindowStyle Normal -File \"C:\IT-Tools\handler.ps1\" \"%%1\""

reg add "HKLM\SOFTWARE\Classes\ittools"                    /ve /d "URL:IT Tools Protocol"  /f > nul
reg add "HKLM\SOFTWARE\Classes\ittools"                    /v "URL Protocol" /d "" /f         > nul
reg add "HKLM\SOFTWARE\Classes\ittools\shell"              /ve /d "" /f                        > nul
reg add "HKLM\SOFTWARE\Classes\ittools\shell\open"         /ve /d "" /f                        > nul
reg add "HKLM\SOFTWARE\Classes\ittools\shell\open\command" /ve /d "%CMD%" /f                   > nul

if %errorLevel% neq 0 (
    echo  ERROR: Could not write to Windows Registry.
    pause
    exit /b 1
)
echo        OK - Windows now knows what to do when a button is clicked.

:: ── Done! Open the website ─────────────────────────────────────
echo.
echo  =====================================================
echo    Setup complete!
echo  =====================================================
echo.
echo  Opening the website in your browser now...
echo.
echo  When you click a button on the website, your browser
echo  will ask "Allow this page to open IT Tools?"
echo  Just click OPEN and the script will run.
echo.

:: Open the HTML file from the same folder as this bat file
start "" "%~dp0tools.html"

echo  This window will close in 5 seconds.
timeout /t 5 > nul
