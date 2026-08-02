@echo off
cd /d "%~dp0"
git status
echo.
echo ====================================================
echo Look at the list above ("modified:" lines).
echo If it only shows the files Claude told you to expect,
echo it is safe to run commit.bat.
echo If you see many OTHER files you did not expect,
echo do NOT run commit.bat yet - tell Claude first.
echo ====================================================
pause
