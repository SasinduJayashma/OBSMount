@echo off
rem ----------------------------------------------------------------------
rem Script Name: mount.cmd
rem Author:      Sasindu Jayashma
rem Date Created: May 26, 2025
rem Version:     2.0 (Modified for multi-profile support)
rem
rem Description: This script mounts a Huawei OBS (Object Storage Service)
rem              bucket as a local drive using rclone.exe.
rem              It accepts a profile identifier (typically the drive letter)
rem              as a command-line argument. Based on this ID, it reads
rem              configuration from 'obs-config-[ID].ini' and 'rclone-[ID].conf'.
rem              It uses a unique log file 'mount-[ID].log' and a unique
rem              RC port specified in its 'obs-config-[ID].ini'.
rem
rem Dependencies:
rem              - rclone.exe (in the same directory)
rem              - obs-config-[ID].ini (in the same directory, with bucket details & rc_port)
rem              - rclone-[ID].conf (in the same directory, for base rclone config)
rem
rem Modification History:
rem Date        Author             Description
rem ----------- ------------------ -------------------------------------------
rem 2025-05-24  Sasindu Jayashma   Initial script development.
rem 2025-05-26  Sasindu Jayashma   Added unmount.cmd and RC enablement.
rem 2025-05-29  Sasindu Jayashma   Modified for multi-profile support:
rem                                - Accepts profile ID (drive letter) as %1.
rem                                - Loads profile-specific config files.
rem                                - Uses profile-specific log file.
rem                                - Reads and uses unique RC port from config.
rem ----------------------------------------------------------------------

set "PROFILE_ID=%~1"
if "%PROFILE_ID%"=="" (
    echo ERROR: No profile ID (drive letter) provided to mount.cmd.
    rem Optionally, could write to a common error log here if needed for hidden execution
    exit /b 1
)

echo Mounting OBS Drive for Profile: %PROFILE_ID%

rem === Define profile-specific configuration file paths ===
set "OBS_CONFIG_FILE=%~dp0obs-config-%PROFILE_ID%.ini"
set "RCLONE_PROFILE_CONFIG_PATH=%~dp0rclone-%PROFILE_ID%.conf"
set "RCLONE_LOG_FILE=%LOCALAPPDATA%\rclone\mount-%PROFILE_ID%.log"

rem === Initialize variables ===
set "BUCKET="
set "REGION="
set "ENDPOINT="
set "AK="
set "SK="
set "DRIVE="
set "RC_PORT="
set "PERMISSIONS="

rem === Read values from the profile-specific INI file ===
if not exist "%OBS_CONFIG_FILE%" (
    echo ERROR: Configuration file not found: %OBS_CONFIG_FILE%
    exit /b 1
)
for /f "usebackq tokens=1,* delims==" %%A in (`findstr /r "^[a-z]" "%OBS_CONFIG_FILE%"`) do (
  if "%%A"=="bucket"   set BUCKET=%%B
  if "%%A"=="region"   set REGION=%%B
  if "%%A"=="endpoint" set ENDPOINT=%%B
  if "%%A"=="ak"       set AK=%%B
  if "%%A"=="sk"       set SK=%%B
  if "%%A"=="drive"    set DRIVE=%%B
  if "%%A"=="rc_port"  set RC_PORT=%%B
  if "%%A"=="permissions" set PERMISSIONS=%%B
)

rem === Validate essential variables were read ===
if "%BUCKET%"=="" echo WARNING: Bucket not set for profile %PROFILE_ID%
if "%DRIVE%"=="" echo WARNING: Drive letter not set for profile %PROFILE_ID%
if "%DRIVE%" NEQ "%PROFILE_ID%" echo WARNING: Drive letter '%DRIVE%' from config does not match profile ID '%PROFILE_ID%'. Using '%DRIVE%'.
if "%RC_PORT%"=="" (
    echo ERROR: rc_port not set in %OBS_CONFIG_FILE% for profile %PROFILE_ID%. Cannot start mount.
    exit /b 1
)

rem === Ensure rclone.conf to be used is the profile-specific one ===
echo Using specific rclone config: %RCLONE_PROFILE_CONFIG_PATH%
echo Using OBS config: %OBS_CONFIG_FILE%
echo Mounting to Drive: %DRIVE%
echo Using RC Port: %RC_PORT%
echo Permissions: %PERMISSIONS%
echo Logging to: %RCLONE_LOG_FILE%
echo.

rem === Ensure log directory exists (common for all profiles, but log files are unique) ===
echo Ensuring log directory exists at %LOCALAPPDATA%\rclone\
if not exist "%LOCALAPPDATA%\rclone\" (
    mkdir "%LOCALAPPDATA%\rclone\"
    if errorlevel 1 (
        echo WARNING: Failed to create log directory "%LOCALAPPDATA%\rclone\". Logging might fail.
    ) else (
        echo Log directory created or already verified.
    )
) else (
    echo Log directory already exists.
)
echo.

set "RCLONE_EXTRA_ARGS="
if /I "%PERMISSIONS%"=="readonly" (
    set "RCLONE_EXTRA_ARGS=--read-only"
    echo Applying read-only permissions.
)

"%~dp0\rclone.exe" mount huaweiOBS:%BUCKET% %DRIVE%: ^
  --config "%RCLONE_PROFILE_CONFIG_PATH%" ^
  %RCLONE_EXTRA_ARGS% ^
  --s3-provider Other ^
  --s3-endpoint "%ENDPOINT%" ^
  --s3-access-key-id "%AK%" ^
  --s3-secret-access-key "%SK%" ^
  --s3-region "%REGION%" ^
  --links ^
  --vfs-cache-mode writes --network-mode ^
  --dir-cache-time 5m ^
  --log-file "%RCLONE_LOG_FILE%" ^
  --rc ^
  --rc-addr localhost:%RC_PORT% ^
  --rc-no-auth