@echo off
cd /d "%~dp0"
git add CLAUDE.md TASKS.md commit.bat run_windows.bat
git add docs/completed-log.md docs/devlog-map-design.md docs/flutter-windows-env-notes.md
git add typhoon_ship_tracker/assets/coastline/README.md
git add typhoon_ship_tracker/assets/coastline/coastline.json
git add typhoon_ship_tracker/lib/screens/map_screen.dart
git add typhoon_ship_tracker/lib/utils/coastline.dart
git add typhoon_ship_tracker/lib/utils/map_bounds.dart
git add typhoon_ship_tracker/lib/widgets/map_painter.dart
git commit -F commit_message.txt
git push -u origin main
pause
