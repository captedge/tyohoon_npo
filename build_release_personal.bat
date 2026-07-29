@echo off
cd /d "%~dp0typhoon_ship_tracker"
echo Building release version (PERSONAL build, Open-Meteo enabled)...
call flutter build windows --release --dart-define=PERSONAL_BUILD=true
if errorlevel 1 goto :buildfailed

echo NOTE: build\windows output folder is shared with the mainline build.
echo Do not run build_release.bat right after this without re-zipping first.

echo Zipping release folder...
powershell -NoProfile -Command "Compress-Archive -Path 'build\windows\x64\runner\Release\*' -DestinationPath '%~dp0TyphoonShipTrackerPersonal.zip' -Force"
if errorlevel 1 goto :zipfailed

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
