@echo off
REM Apply the queued repo changes into the open Roblox Studio place.
REM Run this ON THE WINDOWS PC, with Studio open on "Backrooms: No Way Out".
REM Double-clicking is fine; the window stays open at the end.

setlocal
cd /d "%~dp0\.."

echo ============================================================
echo   Backrooms: No Way Out  --  apply repo changes to Studio
echo ============================================================
echo.

if not exist "%LOCALAPPDATA%\Roblox\mcp.bat" (
    echo [X] Roblox Studio MCP bridge not found:
    echo     %LOCALAPPDATA%\Roblox\mcp.bat
    echo     Install / enable the Roblox Studio MCP plugin first.
    goto :done
)

where git >nul 2>&1 || (echo [X] git is not on PATH & goto :done)

set PY=python
where python >nul 2>&1 || set PY=py
where %PY% >nul 2>&1 || (echo [X] python is not on PATH & goto :done)

echo [1/4] Fetching the audit branch...
git fetch origin claude/roblox-code-audit-di6qxi || goto :done

git diff --quiet && git diff --cached --quiet
if errorlevel 1 (
    echo.
    echo [!] You have uncommitted changes in this folder.
    echo     Commit or stash them first, then re-run. Nothing was changed.
    goto :done
)

echo [2/4] Checking out claude/roblox-code-audit-di6qxi ...
git checkout claude/roblox-code-audit-di6qxi || goto :done
git pull --ff-only origin claude/roblox-code-audit-di6qxi || goto :done

echo.
echo [3/4] Reading live Studio and classifying (nothing is written yet)...
echo.
%PY% tools\push_repo_to_studio.py --audit
set AUDIT=%ERRORLEVEL%
echo.
if not "%AUDIT%"=="0" (
    echo [!] The check above reported conflicts or errors.
    echo     Nothing has been written to Studio.
    echo     Send that output to Claude before pushing, or re-run with
    echo       %PY% tools\push_repo_to_studio.py --skip-conflicts
    goto :done
)

echo [4/4] Everything checks out. Apply the changes to Studio now?
choice /c YN /m "Press Y to apply, N to cancel"
if errorlevel 2 (
    echo Cancelled. Studio was not modified.
    goto :done
)

echo.
%PY% tools\push_repo_to_studio.py
echo.
if errorlevel 1 (
    echo [!] Finished with problems -- read the summary above.
) else (
    echo [OK] Done. Save the place in Studio to keep the changes.
    echo      Pre-push copies of every script are in .studio-push-backups\
)

:done
echo.
pause
endlocal
