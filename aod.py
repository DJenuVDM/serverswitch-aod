#!/usr/bin/env python3
"""
ServerSwitch AOD (Always-On Device) Server
Runs on your always-on machine (Pi, NAS, Linux PC, etc.)
Exposes endpoints to wake up other machines on the same LAN.
"""

import subprocess
import os
import logging
import struct
import socket
import time
from flask import Flask, jsonify, request
from functools import wraps
from collections import defaultdict

app = Flask(__name__)

CONFIG_FILE = os.path.join(os.path.dirname(__file__), "config.env")
SCRIPTS_DIR = os.path.join(os.path.dirname(__file__), "scripts")

# ── Logging ───────────────────────────────────────────────────────────────────
logging.basicConfig(
    filename=os.path.join(os.path.dirname(__file__), "serverswitch-aod.log"),
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s"
)
log = logging.getLogger("serverswitch-aod")

# ── Config ────────────────────────────────────────────────────────────────────
def load_config():
    config = {}
    if os.path.exists(CONFIG_FILE):
        with open(CONFIG_FILE) as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith("#") and "=" in line:
                    k, v = line.split("=", 1)
                    config[k.strip()] = v.strip()
    return config

# ── Rate limiting ─────────────────────────────────────────────────────────────
request_counts = defaultdict(list)

def rate_limit(max_per_minute=10):
    def decorator(f):
        @wraps(f)
        def wrapper(*args, **kwargs):
            ip = request.remote_addr
            now = time.time()
            request_counts[ip] = [t for t in request_counts[ip] if now - t < 60]
            if len(request_counts[ip]) >= max_per_minute:
                log.warning(f"Rate limit hit from {ip}")
                return jsonify({"error": "rate_limited"}), 429
            request_counts[ip].append(now)
            return f(*args, **kwargs)
        return wrapper
    return decorator

def require_token(f):
    @wraps(f)
    def wrapper(*args, **kwargs):
        config = load_config()
        token = config.get("AUTH_TOKEN", "")
        provided = request.headers.get("X-Token", "")
        if not token or provided != token:
            log.warning(f"Unauthorized from {request.remote_addr}")
            return jsonify({"error": "unauthorized"}), 401
        return f(*args, **kwargs)
    return wrapper

# ── WoL magic packet ──────────────────────────────────────────────────────────
def send_wol(mac: str, broadcast: str = "255.255.255.255", port: int = 9):
    """Send a Wake-on-LAN magic packet to the given MAC address."""
    mac_clean = mac.replace(":", "").replace("-", "").replace(".", "")
    if len(mac_clean) != 12:
        raise ValueError(f"Invalid MAC address: {mac}")
    mac_bytes = bytes.fromhex(mac_clean)
    magic = b"\xff" * 6 + mac_bytes * 16
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
        sock.sendto(magic, (broadcast, port))
    log.info(f"WoL sent to {mac} via {broadcast}:{port}")

# ── Routes ────────────────────────────────────────────────────────────────────

@app.route("/ping", methods=["GET"])
@rate_limit(60)
def ping():
    return jsonify({"status": "on", "role": "aod"})

@app.route("/wake/wol", methods=["POST"])
@rate_limit(10)
@require_token
def wake_wol():
    """
    Wake a device using WoL.
    Body: { "mac": "aa:bb:cc:dd:ee:ff", "broadcast": "192.168.1.255" }
    broadcast is optional, defaults to 255.255.255.255
    """
    data = request.get_json(silent=True) or {}
    mac = data.get("mac", "").strip()
    broadcast = data.get("broadcast", "255.255.255.255").strip()

    if not mac:
        return jsonify({"error": "mac address required"}), 400

    try:
        send_wol(mac, broadcast)
        log.info(f"WoL sent for {mac} from {request.remote_addr}")
        return jsonify({"status": "wol_sent", "mac": mac})
    except Exception as e:
        log.error(f"WoL failed for {mac}: {e}")
        return jsonify({"error": str(e)}), 500

@app.route("/wake/script/<script_name>", methods=["POST"])
@rate_limit(10)
@require_token
def wake_script(script_name):
    """
    Run a custom wake script from the scripts/ directory.
    Script name must be alphanumeric + underscores only (security).
    Request body can include:
    {
        "args": ["arg1", "arg2"],  # positional arguments passed to script
        "env": {"VAR1": "value1"}   # environment variables passed to script
    }
    """
    # Sanitize script name — only allow safe characters
    safe = "".join(c for c in script_name if c.isalnum() or c in "_-")
    if safe != script_name:
        return jsonify({"error": "invalid script name"}), 400

    script_path = os.path.join(SCRIPTS_DIR, safe + ".sh")
    if not os.path.exists(script_path):
        return jsonify({"error": f"script '{safe}.sh' not found in scripts/"}), 404

    try:
        # Parse request body for optional args and env vars
        data = request.get_json(silent=True) or {}
        script_args = data.get("args", [])
        script_env_vars = data.get("env", {})
        
        # Validate args are strings
        if not isinstance(script_args, list) or not all(isinstance(arg, str) for arg in script_args):
            return jsonify({"error": "args must be a list of strings"}), 400
        
        # Validate env vars are strings
        if not isinstance(script_env_vars, dict) or not all(isinstance(k, str) and isinstance(v, str) for k, v in script_env_vars.items()):
            return jsonify({"error": "env must be a dict of string key-value pairs"}), 400
        
        # Prepare environment with custom vars
        env = os.environ.copy()
        env.update(script_env_vars)
        
        # Build command with args
        cmd = ["bash", script_path] + script_args
        
        result = subprocess.run(
            cmd,
            capture_output=True, text=True, timeout=30, env=env
        )
        log.info(f"Script {safe}.sh ran for {request.remote_addr} with {len(script_args)} args, exit={result.returncode}")
        return jsonify({
            "status": "script_ran",
            "script": safe,
            "exit_code": result.returncode,
            "stdout": result.stdout.strip(),
            "stderr": result.stderr.strip()
        })
    except subprocess.TimeoutExpired:
        return jsonify({"error": "script timed out after 30s"}), 500
    except Exception as e:
        log.error(f"Script {safe}.sh failed: {e}")
        return jsonify({"error": str(e)}), 500

@app.route("/scripts", methods=["GET"])
@rate_limit(30)
@require_token
def list_scripts():
    """List available wake scripts."""
    try:
        scripts = [
            f.replace(".sh", "")
            for f in os.listdir(SCRIPTS_DIR)
            if f.endswith(".sh")
        ]
        return jsonify({"scripts": scripts})
    except Exception:
        return jsonify({"scripts": []})

if __name__ == "__main__":
    os.makedirs(SCRIPTS_DIR, exist_ok=True)
    config = load_config()
    port = int(config.get("PORT", 5051))
    log.info(f"ServerSwitch AOD starting on port {port}")
    app.run(host="0.0.0.0", port=port)
