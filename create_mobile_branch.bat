@echo off
cd /d "%~dp0"

echo Switching to main...
call git checkout main
if errorlevel 1 goto :checkoutfailed

echo Pulling latest main...
call git pull
if errorlevel 1 goto :pullfailed

echo Creating branch feature/mobile from main...
call git checkout -b feature/mobile
if errorlevel 1 goto :branchfailed

echo Pushing feature/mobile branch to GitHub...
call git push -u origin feature/mobile
if errorlevel 1 goto :pushfailed

echo.
echo Done. Now on branch feature/mobile, tracking origin/feature/mobile.
goto :end

:checkoutfailed
echo Checkout failed. See the error above.
goto :end

:pullfailed
echo Pull failed. See the error above.
goto :end

:branchfailed
echo Branch creation failed (it may already exist). See the error above.
goto :end

:pushfailed
echo Push failed. See the error above.
goto :end

:end
pause
