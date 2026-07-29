@echo off
cd /d "%~dp0"
git add -A
git commit -F commit_message.txt
git push -u origin main
pause
