@echo off
cd /d "%~dp0"
echo ============================================================
echo  Git history cleanup
echo  This will REWRITE ALL COMMIT HISTORY on every branch and
echo  FORCE PUSH the result to GitHub (origin).
echo  It removes TyphoonShipTrackerPersonal, TyphoonShipTrackerPersonal.apk
echo  and TyphoonShipTrackerPersonal.zip from every past commit,
echo  including your saved UserData files (Passage Plan etc.).
echo  All commit hashes will change. This cannot be undone locally.
echo  Make a backup zip of this whole folder before continuing.
echo ============================================================
echo.
set CONFIRM=
set /p CONFIRM=Type YES and press Enter to continue:
if not "%CONFIRM%"=="YES" goto :cancelled

where git-filter-repo >nul 2>nul
if errorlevel 1 goto :nofilterrepo

echo.
echo Running git filter-repo...
git filter-repo --path TyphoonShipTrackerPersonal --path TyphoonShipTrackerPersonal.apk --path TyphoonShipTrackerPersonal.zip --invert-paths --force
if errorlevel 1 goto :filterfailed

echo.
echo Re-adding origin remote (git filter-repo removes it as a safety step)...
git remote add origin https://github.com/captedge/tyohoon_npo.git

echo.
echo Force-pushing all branches...
git push origin --force --all
if errorlevel 1 goto :pushfailed

echo.
echo Force-pushing all tags...
git push origin --force --tags

echo.
echo Done. History rewritten and force-pushed to GitHub.
echo You can now rebuild the personal build (build_release_personal.bat /
echo build_apk_personal.bat) as usual; the output will stay untracked
echo thanks to the updated .gitignore.
pause
goto :eof

:cancelled
echo Cancelled. No changes were made.
pause
goto :eof

:nofilterrepo
echo git-filter-repo was not found on this machine.
echo Install it first, for example:
echo   pip install git-filter-repo
echo Then double-click this file again.
pause
goto :eof

:filterfailed
echo git filter-repo failed. See the error above. Nothing was pushed.
pause
goto :eof

:pushfailed
echo git push --force failed. See the error above.
echo Check your GitHub sign-in/connection, then try manually:
echo   git push origin --force --all
echo   git push origin --force --tags
pause
goto :eof
