@echo off
setlocal EnableDelayedExpansion

set PATH=%PATH%;%USERPROFILE%\flutter_sdk\flutter\bin
set ANDROID_SDK_ROOT=%LOCALAPPDATA%\Android\Sdk
set ANDROID_HOME=%LOCALAPPDATA%\Android\Sdk
set JAVA_HOME=C:\Program Files\Android\Android Studio\jbr
set ADB="%ANDROID_SDK_ROOT%\platform-tools\adb.exe"
set EMULATOR="%ANDROID_SDK_ROOT%\emulator\emulator.exe"
set AVD_DIR=%USERPROFILE%\.android\avd\ShipsTime_Test.avd

cd /d "%~dp0"

echo Checking emulator status...
%ADB% devices | findstr /r "emulator-5554.*device$" >nul
if not errorlevel 1 goto bootwait

echo No ready emulator found. Cleaning up any stuck emulator process...
taskkill /F /T /IM qemu-system-x86_64.exe >nul 2>&1
taskkill /F /T /IM emulator.exe >nul 2>&1
timeout /t 1 >nul
if exist "%AVD_DIR%\*.lock" del /F /Q "%AVD_DIR%\*.lock" >nul 2>&1
for /d %%L in ("%AVD_DIR%\*.lock") do rd /s /q "%%L" >nul 2>&1
rem A snapshot saved from a forcibly-killed emulator can be corrupted and
rem resume into a frozen state every time. Clear it so the next boot is clean.
if exist "%AVD_DIR%\snapshots\default_boot" rd /s /q "%AVD_DIR%\snapshots\default_boot" >nul 2>&1
%ADB% kill-server >nul 2>&1
timeout /t 2 >nul
%ADB% start-server >nul 2>&1

echo Starting emulator, please wait...
rem -no-snapshot forces a real cold boot instead of resuming a saved
rem snapshot, which can be corrupted after a forced shutdown.
start "" %EMULATOR% -avd ShipsTime_Test -no-snapshot
start "" /min powershell -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0fix_emulator_window.ps1"

echo Waiting for the device to attach (up to 2 minutes)...
set WAITED=0

:waitattach
%ADB% devices | findstr /r "emulator-5554.*device$" >nul
if not errorlevel 1 goto bootwait
set /a WAITED+=2
if !WAITED! GEQ 120 goto attachtimeout
timeout /t 2 >nul
goto waitattach

:attachtimeout
echo.
echo Timed out waiting for the emulator to appear ^(or it is stuck offline^).
echo Close any leftover Android Emulator windows, then run this file again.
pause
exit /b 1

:bootwait
echo Waiting for boot to finish...
set BOOTWAITED=0

:bootwaitloop
set BOOTED=
for /f "delims=" %%i in ('%ADB% shell getprop sys.boot_completed 2^>nul') do set BOOTED=%%i
if "!BOOTED!"=="1" goto bootdone
set /a BOOTWAITED+=2
if !BOOTWAITED! GEQ 90 goto boottimeout
timeout /t 2 >nul
goto bootwaitloop

:boottimeout
echo.
echo The emulator device is attached but never finished booting ^(or is stuck offline^).
echo Close any leftover Android Emulator windows, then run this file again.
pause
exit /b 1

:bootdone
cd /d "%~dp0typhoon_ship_tracker"
echo Building and launching the app (PERSONAL build, Open-Meteo enabled)...
echo First run can take a few minutes...
call flutter run -d emulator-5554 --dart-define=PERSONAL_BUILD=true

echo.
echo Done.
pause
