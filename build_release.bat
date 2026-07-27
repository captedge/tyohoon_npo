@echo off
cd /d "%~dp0typhoon_ship_tracker"
echo Building release version...
call flutter build windows --release
if errorlevel 1 goto :buildfailed

echo Zipping release folder...
powershell -NoProfile -Command "Compress-Archive -Path 'build\windows\x64\runner\Release\*' -DestinationPath '%~dp0TyphoonShipTracker.zip' -Force"
if errorlevel 1 goto :zipfailed

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
