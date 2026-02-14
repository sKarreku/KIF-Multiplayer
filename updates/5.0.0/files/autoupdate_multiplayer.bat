@echo off
echo ========================================
echo KIF Multiplayer Auto-Updater
echo ========================================
echo.

ruby autoupdater.rb

if %ERRORLEVEL% EQU 0 (
    echo.
    echo Update process completed successfully.
) else (
    echo.
    echo Update process failed with error code: %ERRORLEVEL%
)

echo.
echo Press any key to exit...
pause >nul
