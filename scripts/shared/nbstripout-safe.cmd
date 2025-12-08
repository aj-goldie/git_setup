@echo off
REM ===========================================
REM nbstripout-safe.cmd: Fault-tolerant notebook filter for Windows
REM ===========================================
REM Wraps nbstripout-fast with graceful JSON validation.
REM If notebook JSON is malformed, passes through unchanged
REM instead of crashing git operations.
REM
REM Usage (git filter - reads from stdin, writes to stdout):
REM   git config filter.jupyter.clean nbstripout-safe
REM ===========================================

setlocal enabledelayedexpansion

REM Create temp file for input
set "tmpfile=%TEMP%\nbstripout-safe-%RANDOM%.ipynb"

REM Read stdin to temp file
copy con "%tmpfile%" > nul

REM Validate JSON using Python
python -c "import json; json.load(open(r'%tmpfile%'))" 2>nul
if %ERRORLEVEL% equ 0 (
    REM Valid JSON - run nbstripout-fast
    nbstripout-fast -t "%tmpfile%" 2>nul
    if !ERRORLEVEL! neq 0 (
        REM nbstripout-fast failed - fallback to passthrough
        echo [nbstripout-safe] Warning: nbstripout-fast failed, passing through unchanged >&2
        type "%tmpfile%"
    )
) else (
    REM Invalid JSON - pass through with warning
    echo [nbstripout-safe] Warning: Malformed notebook JSON detected, passing through unchanged >&2
    type "%tmpfile%"
)

REM Cleanup
del "%tmpfile%" 2>nul

exit /b 0

