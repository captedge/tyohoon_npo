@echo off
cd /d "%~dp0"
git add CLAUDE.md TASKS.md commit.bat
git add docs/completed-log.md docs/devlog-map-design.md docs/flutter-windows-env-notes.md
git add typhoon_ship_tracker
git commit -F commit_message.txt
git push -u origin main
pause
