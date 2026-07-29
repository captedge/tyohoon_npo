@echo off
cd /d "%~dp0"
git add -u
git add build_release.bat
git add docs/devlog-map-zoom-rendering.md docs/devlog-passage-plan-multi.md
git add typhoon_ship_tracker/assets/ship_icon01.png typhoon_ship_tracker/assets/typhoon_icon01.png
git add typhoon_ship_tracker/lib/models/ship_waypoint.dart typhoon_ship_tracker/lib/models/voyage_plan_entry.dart
git add typhoon_ship_tracker/lib/screens/voyage_plan_screen.dart
git add typhoon_ship_tracker/lib/utils/app_state_storage.dart typhoon_ship_tracker/lib/utils/marker_icons.dart
git add typhoon_ship_tracker/lib/utils/voyage_plan.dart typhoon_ship_tracker/lib/utils/voyage_plan_parser.dart
git add docs/devlog-online-xml.md
git add docs/devlog-architecture-roadmap.md docs/devlog-csv-library.md docs/devlog-playback-anchor-reset.md
git add typhoon_ship_tracker/assets/passage_plan.png
git add typhoon_ship_tracker/lib/utils/csv_library.dart typhoon_ship_tracker/lib/utils/jma_feed_fetcher.dart typhoon_ship_tracker/lib/utils/jma_xml_parser.dart
git add *.pdf
git add *.docx
git commit -F commit_message.txt
git push -u origin main
pause
