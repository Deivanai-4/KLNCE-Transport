@echo off
title KLNCE Transport - Server Startup
color 0A

echo ============================================================
echo   KLNCE Smart Transport System - Server Startup
echo ============================================================
echo.

REM --- Detect current directory (should be project root) ---
set "PROJECT_ROOT=%~dp0"
set "BACKEND_DIR=%PROJECT_ROOT%backend"

echo [INFO] Project Root: %PROJECT_ROOT%
echo [INFO] Backend Dir : %BACKEND_DIR%
echo.

REM --- Step 1: Check Python ---
where python >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERROR] Python not found in PATH.
    echo         Install Python 3.11 from https://python.org and re-run.
    pause
    exit /b 1
)
for /f "tokens=*" %%i in ('python --version 2^>^&1') do set PYVER=%%i
echo [OK] %PYVER%
echo.

REM --- Step 2: Verify Flask dependencies ---
python -c "import flask, pymongo, flask_jwt_extended, bcrypt, openpyxl" >nul 2>&1
if %errorlevel% neq 0 (
    echo [INSTALLING] Some packages are missing. Installing now...
    pip install flask flask-cors flask-jwt-extended pymongo dnspython python-dotenv bcrypt openpyxl requests werkzeug --quiet
    if %errorlevel% neq 0 (
        echo [ERROR] Package installation failed. Run manually:
        echo         pip install flask flask-cors flask-jwt-extended pymongo dnspython python-dotenv bcrypt openpyxl
        pause
        exit /b 1
    )
    echo [OK] Packages installed.
) else (
    echo [OK] Python packages: flask, pymongo, bcrypt, openpyxl - all ready.
)
echo.

REM --- Step 3: Get LAN IP for reference ---
echo [INFO] Your PC IP addresses (use the 192.168.x.x one for Wi-Fi):
ipconfig | findstr /i "IPv4"
echo.

REM --- Step 4: Start Flask backend ---
echo [STARTING] Flask backend on http://localhost:5000 ...
start "KLNCE Flask Backend" cmd /k "cd /d "%BACKEND_DIR%" && python app.py"
echo [WAIT] Giving Flask 5 seconds to initialize...
timeout /t 5 /nobreak >nul

REM --- Step 5: Test Flask is up ---
python -c "import urllib.request; urllib.request.urlopen('http://localhost:5000/api/health', timeout=5); print('[OK] Flask is running!')" 2>nul
if %errorlevel% neq 0 (
    echo [WARNING] Flask might still be starting. Check the Flask window for errors.
) else (
    echo [OK] Flask backend is live at http://localhost:5000/api
)
echo.

REM --- Step 6: Check for localtunnel (lt) ---
where lt >nul 2>&1
if %errorlevel% neq 0 (
    echo [INFO] localtunnel (lt) not found in PATH.
    echo.
    echo   Option A - Install localtunnel (requires Node.js):
    echo     npm install -g localtunnel
    echo     lt --port 5000 --subdomain klnce-transport-api
    echo.
    echo   Option B - Use your LAN IP instead (no tunnel needed):
    echo     The app will auto-detect http://YOUR_PC_IP:5000/api over Wi-Fi.
    echo     Your PC and phone must be on the SAME Wi-Fi network.
    echo.
    echo [SKIPPING] Tunnel not started. The app will fall back to LAN IP.
    goto :show_summary_no_tunnel
)

REM --- Step 7: Start localtunnel ---
echo [STARTING] localtunnel at https://klnce-transport-api.loca.lt ...
start "KLNCE Localtunnel" cmd /k "lt --port 5000 --subdomain klnce-transport-api"
timeout /t 3 /nobreak >nul

echo.
echo ============================================================
echo   SERVER IS RUNNING
echo ============================================================
echo.
echo   Flask Backend : http://localhost:5000
echo   Health Check  : http://localhost:5000/api/health
echo   Tunnel URL    : https://klnce-transport-api.loca.lt/api
echo.
echo   The Flutter app (Android debug) will auto-connect to:
echo     1. https://klnce-transport-api.loca.lt/api  (tunnel)
echo     2. http://YOUR_LAN_IP:5000/api              (Wi-Fi fallback)
echo.
echo   Keep BOTH windows open while the app is running.
echo   Close this window to shut down everything.
echo ============================================================
pause
goto :eof

:show_summary_no_tunnel
echo.
echo ============================================================
echo   SERVER IS RUNNING (LAN mode only)
echo ============================================================
echo.
echo   Flask Backend : http://localhost:5000
echo   Health Check  : http://localhost:5000/api/health
echo.
echo   The Flutter app will auto-connect via your LAN IP.
echo   Make sure your phone and PC are on the SAME Wi-Fi.
echo.
echo   To install localtunnel for public HTTPS access, run:
echo     npm install -g localtunnel
echo     lt --port 5000 --subdomain klnce-transport-api
echo ============================================================
pause
