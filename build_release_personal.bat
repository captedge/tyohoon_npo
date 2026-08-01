@echo off
cd /d "%~dp0typhoon_ship_tracker"
echo Building release version (PERSONAL build, Open-Meteo enabled)...
call flutter build windows --release --dart-define=PERSONAL_BUILD=true
if errorlevel 1 goto :buildfailed

echo NOTE: build\windows output folder is shared with the mainline build.
echo Do not run build_release.bat right after this without re-zipping first.

echo Staging release files (excluding any local UserData folder from past test runs)...
if exist "%TEMP%\tst_personal_zip_staging" rmdir /s /q "%TEMP%\tst_personal_zip_staging"
robocopy "build\windows\x64\runner\Release" "%TEMP%\tst_personal_zip_staging" /E /XD UserData
if errorlevel 8 goto :zipfailed

echo Zipping staged folder...
if exist "%~dp0TyphoonShipTrackerPersonal.zip" del /f /q "%~dp0TyphoonShipTrackerPersonal.zip"
powershell -NoProfile -Command "$ErrorActionPreference = 'Stop'; Compress-Archive -Path '%TEMP%\tst_personal_zip_staging\*' -DestinationPath '%~dp0TyphoonShipTrackerPersonal.zip'"
if errorlevel 1 goto :zipfailed

rmdir /s /q "%TEMP%\tst_personal_zip_staging"

echo Done. TyphoonShipTrackerPersonal.zip created in the project root folder.
goto :end

:buildfailed
echo Build failed. See the messages above for details.
goto :end

:zipfailed
echo Zip step failed. Check that PowerShell is available.
goto :end

:end
pause
