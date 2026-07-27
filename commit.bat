@echo off
cd /d "%~dp0"
git add -u
git add docs/devlog-map-zoom-rendering.md docs/devlog-passage-plan-multi.md
git add typhoon_ship_tracker/assets/ship_icon01.png typhoon_ship_tracker/assets/typhoon_icon01.png
git add typhoon_ship_tracker/lib/models/ship_waypoint.dart typhoon_ship_tracker/lib/models/voyage_plan_entry.dart
git add typhoon_ship_tracker/lib/screens/voyage_plan_screen.dart
git add typhoon_ship_tracker/lib/utils/app_state_storage.dart typhoon_ship_tracker/lib/utils/marker_icons.dart
git add typhoon_ship_tracker/lib/utils/voyage_plan.dart typhoon_ship_tracker/lib/utils/voyage_plan_parser.dart
git commit -F commit_message.txt
git push -u origin main
pause
