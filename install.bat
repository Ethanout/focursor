@echo off
REM Focursor OBS Script Installer
REM This script helps install the Focursor script to OBS Studio

echo ========================================
echo    Focursor OBS Script Installer
echo ========================================
echo.

REM Get OBS scripts directory
set "OBS_SCRIPTS_DIR=%APPDATA%\obs-studio\plugins\frontend-tools\scripts"

echo Installing to: %OBS_SCRIPTS_DIR%
echo.

REM Create directory if it doesn't exist
if not exist "%OBS_SCRIPTS_DIR%" (
    mkdir "%OBS_SCRIPTS_DIR%"
    echo Created OBS scripts directory.
)

REM Copy the script
copy "focursor.lua" "%OBS_SCRIPTS_DIR%\" >nul 2>&1
if %errorlevel% equ 0 (
    echo ✓ Successfully installed focursor.lua
) else (
    echo ✗ Failed to install focursor.lua
    goto :error
)

REM Copy icons if they exist
if exist "icons" (
    if not exist "%OBS_SCRIPTS_DIR%\icons" (
        mkdir "%OBS_SCRIPTS_DIR%\icons"
    )
    xcopy "icons" "%OBS_SCRIPTS_DIR%\icons\" /E /I /H /Y >nul 2>&1
    echo ✓ Successfully installed icons
)

echo.
echo ========================================
echo    Installation Complete!
echo ========================================
echo.
echo Next steps:
echo 1. Open OBS Studio
echo 2. Go to Tools → Scripts
echo 3. Click the + button and select focursor.lua
echo 4. Configure the script settings
echo 5. Enjoy!
echo.
echo For detailed setup instructions, see README.md
echo.
pause
exit /b 0

:error
echo.
echo Installation failed. Please check the error messages above.
echo.
pause
exit /b 1