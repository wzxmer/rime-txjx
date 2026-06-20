@echo off
setlocal
set PYTHONDONTWRITEBYTECODE=1
cd /d "%~dp0\.."
where py >nul 2>nul
if %errorlevel%==0 (
  py -3 "zzc\gen_char_parts.py"
  exit /b %errorlevel%
)
where python >nul 2>nul
if %errorlevel%==0 (
  python "zzc\gen_char_parts.py"
  exit /b %errorlevel%
)
echo Python 3 not found. Run: python3 zzc/gen_char_parts.py
exit /b 1
