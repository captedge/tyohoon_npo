@echo off
set PATH=C:\Users\KOTA\flutter_sdk\flutter\bin;%PATH%
cd /d "%~dp0typhoon_ship_tracker"
echo Running flutter clean (removes build/ and .dart_tool/) ...
flutter clean
echo Done.
pause
