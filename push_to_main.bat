@echo off
echo ========================================
echo Merging dev into main and pushing...
echo ========================================

cd /d "%~dp0"

echo.
echo Switching to main branch...
git checkout main

echo.
echo Merging dev into main...
git merge dev

echo.
echo Pushing to GitHub (main)...
git push origin main

echo.
echo Switching back to dev branch...
git checkout dev

echo.
echo ========================================
echo Done! Check https://github.com/sKarreku/KIF-Multiplayer/tree/main/updates
echo ========================================
pause
