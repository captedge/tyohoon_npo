@echo off
cd /d "%~dp0typhoon_ship_tracker"
echo Building release version...
call flutter build windows --release
if errorlevel 1 goto :buildfailed

echo Staging release files (excluding any local UserData folder from past test runs)...
if exist "%TEMP%\tst_zip_staging" rmdir /s /q "%TEMP%\tst_zip_staging"
robocopy "build\windows\x64\runner\Release" "%TEMP%\tst_zip_staging" /E /XD UserData
if errorlevel 8 goto :zipfailed

echo Zipping staged folder...
if exist "%~dp0TyphoonShipTracker.zip" del /f /q "%~dp0TyphoonShipTracker.zip"
powershell -NoProfile -Command "$ErrorActionPreference = 'Stop'; Compress-Archive -Path '%TEMP%\tst_zip_staging\*' -DestinationPath '%~dp0TyphoonShipTracker.zip'"
if errorlevel 1 goto :zipfailed

rmdir /s /q "%TEMP%\tst_zip_staging"

echo Done. TyphoonShipTracker.zip created in the project root folder.
goto :end

:buildfailed
echo Build failed. See the messages above for details.
goto :end

:zipfailed
echo Zip step failed. Check that PowerShell is available.
goto :end

:end
pause
