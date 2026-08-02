@echo off
set PATH=%PATH%;%USERPROFILE%\flutter_sdk\flutter\bin
set ANDROID_SDK_ROOT=%LOCALAPPDATA%\Android\Sdk
set ANDROID_HOME=%LOCALAPPDATA%\Android\Sdk
set JAVA_HOME=C:\Program Files\Android\Android Studio\jbr

cd /d "%~dp0typhoon_ship_tracker"
echo Building release APK (PERSONAL build, Open-Meteo enabled)...
echo First build can take several minutes...
call flutter build apk --release --dart-define=PERSONAL_BUILD=true
if errorlevel 1 goto :buildfailed

echo NOTE: build\app output folder is shared with the mainline build.
echo Do not run build_apk.bat right after this without re-building first.

set SRC=build\app\outputs\flutter-apk\app-release.apk
if not exist "%SRC%" goto :apknotfound

echo Copying APK into the project root folder...
copy /Y "%SRC%" "%~dp0TyphoonShipTrackerPersonal.apk"
if errorlevel 1 goto :copyfailed

echo.
echo Done. APK saved to:
echo   %~dp0TyphoonShipTrackerPersonal.apk
echo.
echo Transfer this file to an Android phone and open it to install.
echo The phone must allow install from unknown sources for the app
echo used to open the file, e.g. Files or Chrome.
goto :end

:buildfailed
echo Build failed. See the messages above for details.
goto :end

:apknotfound
echo Build reported success but the APK was not found at %SRC%.
goto :end

:copyfailed
echo WARNING: Build succeeded, but copying the APK failed.
echo Use the APK directly from this path instead:
echo   %~dp0typhoon_ship_tracker\%SRC%
goto :end

:end
pause
