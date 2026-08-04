@echo off
cd /d "%~dp0"
git add -A
git commit --amend -F commit_message.txt
git push --force-with-lease origin HEAD
pause
