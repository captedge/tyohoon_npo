@echo off
cd /d "%~dp0"
git add .
git commit -F commit_message.txt
git push -u origin main
pause
