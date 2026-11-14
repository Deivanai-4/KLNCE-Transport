@echo off
title KLNCE Transport - Backend & Internet Tunnel
color 0A
echo ============================================================
echo   KLNCE Smart Transport System - Live Internet Backend
echo ============================================================
echo.
echo Starting Flask Backend Server (Port 5000)...
start "KLNCE Flask Backend" cmd /k "cd backend && python app.py"

timeout /t 3 >nul

echo Starting Cloudflare Secure Public Tunnel...
echo Any phone on cellular/mobile data (4G/5G) can access this!
echo.
backend\tools\cloudflared.exe tunnel --url http://127.0.0.1:5000 --protocol http2
pause

