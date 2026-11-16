"""
KLNCE Transport - Tunnel Watchdog
Keeps localtunnel running continuously on port 5000 with subdomain 'klnce-transport-api'.
Automatically checks health and restarts the tunnel immediately if it disconnects or drops.
"""

import subprocess
import time
import sys
import threading
import urllib.request

SUBDOMAIN = "klnce-transport-api"
PORT = "5000"
EXPECTED_URL = f"https://{SUBDOMAIN}.loca.lt"

current_process = None

def health_checker():
    """Periodically check that the tunnel is actually routing requests."""
    global current_process
    time.sleep(10)
    failed_attempts = 0
    while True:
        try:
            req = urllib.request.Request(
                f"{EXPECTED_URL}/api/health",
                headers={"bypass-tunnel-reminder": "true", "User-Agent": "Watchdog"}
            )
            with urllib.request.urlopen(req, timeout=6) as res:
                if res.status == 200:
                    failed_attempts = 0
                else:
                    failed_attempts += 1
        except Exception:
            failed_attempts += 1

        if failed_attempts >= 2 and current_process:
            print("[Watchdog] Health check failed twice. Restarting tunnel process...")
            try:
                current_process.kill()
            except Exception:
                pass
            failed_attempts = 0

        time.sleep(15)

def run_tunnel():
    global current_process
    print(f"[Watchdog] Starting localtunnel on port {PORT} (subdomain: {SUBDOMAIN})...")
    
    checker_thread = threading.Thread(target=health_checker, daemon=True)
    checker_thread.start()

    while True:
        try:
            current_process = subprocess.Popen(
                ["npx.cmd", "--yes", "localtunnel", "--port", PORT, "--subdomain", SUBDOMAIN],
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                bufsize=1
            )
            print(f"[Watchdog] localtunnel process started (PID {current_process.pid})")

            for line in current_process.stdout:
                line_str = line.strip()
                if line_str:
                    print(f"[localtunnel] {line_str}")
                    sys.stdout.flush()
                    if "your url is:" in line_str and EXPECTED_URL not in line_str:
                        print(f"[Watchdog] Subdomain collision (got {line_str}). Retrying for {SUBDOMAIN}...")
                        current_process.kill()
                        break

            current_process.wait()
            print(f"[Watchdog] localtunnel process exited with code {current_process.returncode}. Restarting in 3 seconds...")
        except Exception as e:
            print(f"[Watchdog] Error running tunnel: {e}. Retrying in 5 seconds...")
            time.sleep(2)

        time.sleep(3)

if __name__ == "__main__":
    run_tunnel()
