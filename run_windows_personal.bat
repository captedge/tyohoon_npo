@echo off
set PATH=C:\Users\KOTA\flutter_sdk\flutter\bin;%PATH%
cd /d "%~dp0typhoon_ship_tracker"
echo Starting flutter run -d windows (PERSONAL build, Open-Meteo enabled) ...
flutter run -d windows --dart-define=PERSONAL_BUILD=true
pause
