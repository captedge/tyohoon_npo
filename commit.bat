@echo off
cd /d "%~dp0"
git add CLAUDE.md TASKS.md commit.bat run_windows.bat
git add docs/completed-log.md docs/operation-rules.md docs/devlog-map-design.md
git add docs/data-format-notes.md docs/devlog-map-overlays.md docs/devlog-wheel-zoom.md
git add typhoon_ship_tracker/.gitignore typhoon_ship_tracker/README.md typhoon_ship_tracker/test/widget_test.dart
git add typhoon_ship_tracker/lib/screens/map_screen.dart typhoon_ship_tracker/lib/widgets/map_painter.dart typhoon_ship_tracker/lib/utils/jtwc_parser.dart
git add typhoon_ship_tracker/windows/.gitignore typhoon_ship_tracker/windows/CMakeLists.txt typhoon_ship_tracker/windows/flutter/CMakeLists.txt
git add typhoon_ship_tracker/windows/runner/CMakeLists.txt typhoon_ship_tracker/windows/runner/Runner.rc typhoon_ship_tracker/windows/runner/flutter_window.cpp
git add typhoon_ship_tracker/windows/runner/flutter_window.h typhoon_ship_tracker/windows/runner/main.cpp typhoon_ship_tracker/windows/runner/resource.h
git add typhoon_ship_tracker/windows/runner/runner.exe.manifest typhoon_ship_tracker/windows/runner/utils.cpp typhoon_ship_tracker/windows/runner/utils.h
git add typhoon_ship_tracker/windows/runner/win32_window.cpp typhoon_ship_tracker/windows/runner/win32_window.h
git commit -F commit_message.txt
git push -u origin main
pause
