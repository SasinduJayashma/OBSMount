@echo off
rem ----------------------------------------------------------------------
rem Script Name: unmount.cmd
rem Author:      Sasindu Jayashma
rem Date Created: May 29, 2025 (Modified for multi-profile support)
rem Version:     2.0
rem
rem Description: This script gracefully stops/unmounts a specific OBS Drive
rem              profile that was started by mount.cmd. It accepts a profile
rem              identifier (typically the drive letter) as a command-line
rem              argument. It reads the 'obs-config-[ID].ini' to find the
rem              correct RC port for that instance.
rem
rem Usage:       unmount.cmd [DriveLetter]
rem Example:     unmount.cmd Q
rem ----------------------------------------------------------------------

set "PROFILE_ID=%~1"
if "%PROFILE_ID%"=="" (
    echo ERROR: No profile ID (drive letter) provided to unmount.cmd.
    echo.
    echo Usage:   unmount.cmd [DriveLetter]
    echo Example: unmount.cmd Q
    pause
    exit /b 1
)

echo Unmounting OBS Drive for Profile: %PROFILE_ID%

set "OBS_CONFIG_FILE=%~dp0obs-config-%PROFILE_ID%.ini"
set "RC_PORT="

if not exist "%OBS_CONFIG_FILE%" (
    echo ERROR: Configuration file not found for profile %PROFILE_ID%: %OBS_CONFIG_FILE%
    pause
    exit /b 1
)

for /f "usebackq tokens=1,* delims==" %%A in (`findstr /i "^rc_port=" "%OBS_CONFIG_FILE%"`) do (
  if /i "%%A"=="rc_port" set RC_PORT=%%B
)

if "%RC_PORT%"=="" (
    echo ERROR: Could not read rc_port for profile %PROFILE_ID% from %OBS_CONFIG_FILE%.
    echo Ensure 'rc_port=[port_number]' line exists in the config file.
    pause
    exit /b 1
)

echo Attempting to gracefully stop OBS Drive (Profile: %PROFILE_ID%, RC Port: %RC_PORT%)...
"%~dp0\rclone.exe" rc core/quit --rc-addr localhost:%RC_PORT% --timeout 30s

if errorlevel 0 (
    echo OBS Drive (Profile: %PROFILE_ID%) has been requested to shut down gracefully.
    echo Please allow a few moments for it to unmount and close connections.
) else (
    echo Failed to send shutdown command or command timed out for Profile: %PROFILE_ID%.
    echo The OBS Drive (rclone for %PROFILE_ID%) might not be running,
    echo rc was not configured correctly for it, or it did not respond in time.
    echo You might need to check Task Manager if it's still running (look for rclone.exe).
)
echo.
pause