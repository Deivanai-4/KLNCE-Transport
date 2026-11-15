"""
KLNCE Transport - Tunnel Watchdog
Keeps localtunnel running continuously on port 5000 with subdomain 'klnce-transport-api'.
Automatically restarts the tunnel immediately if it disconnects or drops.
"""

import subprocess
import time
import sys

SUBDOMAIN = "klnce-transport-api"
PORT = "5000"

def run_tunnel():
    print(f"[Watchdog] Starting localtunnel on port {PORT} (subdomain: {SUBDOMAIN})...")
    while True:
        try:
            # Run localtunnel via npx
            process = subprocess.Popen(
                ["npx.cmd", "--yes", "localtunnel", "--port", PORT, "--subdomain", SUBDOMAIN],
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                bufsize=1
            )
            print(f"[Watchdog] localtunnel process started (PID {process.pid})")

            for line in process.stdout:
                line_str = line.strip()
                if line_str:
                    print(f"[localtunnel] {line_str}")
                    sys.stdout.flush()

            process.wait()
            print(f"[Watchdog] localtunnel process exited with code {process.returncode}. Restarting in 3 seconds...")
        except Exception as e:
            print(f"[Watchdog] Error running tunnel: {e}. Retrying in 5 seconds...")
            time.sleep(2)

        time.sleep(3)

if __name__ == "__main__":
    run_tunnel()
