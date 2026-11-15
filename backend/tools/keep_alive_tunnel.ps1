# ==============================================================================
# KLNCE Transport - Persistent Backend & Tunnel Watchdog
# Ensures 24/7 availability of both the Flask backend and public HTTPS tunnel.
# ==============================================================================

$Port = 5000
$Subdomain = "klnce-transport-api"
$BackendDir = "c:\Users\HP\Documents\2025 Project\KLNCE Transport\backend"

Write-Host ">>> Starting KLNCE Transport Watchdog Service..." -ForegroundColor Cyan

while ($true) {
    try {
        # 1. Verify Flask is listening
        $flaskRunning = (Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue)
        if (-not $flaskRunning) {
            Write-Host ">>> Flask is not running. Launching Flask backend on port $Port..." -ForegroundColor Yellow
            Start-Process python -ArgumentList "$BackendDir\app.py" -WindowStyle Hidden
            Start-Sleep -Seconds 3
        }

        # 2. Start localtunnel with fixed subdomain
        Write-Host ">>> Connecting public HTTPS tunnel (https://$Subdomain.loca.lt)..." -ForegroundColor Green
        npx --yes localtunnel --port $Port --subdomain $Subdomain
    }
    catch {
        Write-Host ">>> Error occurred in watchdog: $_" -ForegroundColor Red
    }

    Write-Host ">>> Tunnel disconnected. Auto-reconnecting in 5 seconds..." -ForegroundColor Yellow
    Start-Sleep -Seconds 5
}
