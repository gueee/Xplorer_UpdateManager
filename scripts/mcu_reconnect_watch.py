#!/usr/bin/env python3
"""Auto FIRMWARE_RESTART after a mainboard power cycle.

Polls Moonraker. When Klipper is in shutdown/error because an MCU went away
(power cycle, USB re-enumeration) and every serial path referenced in the
config exists again, it issues a firmware_restart. Never reacts to a user
emergency stop ("webhooks request") or to config errors.

Sudo-free: run from the user crontab (@reboot). Log: ~/mcu_reconnect_watch.log
"""
import glob, json, os, re, time, urllib.request

MOONRAKER = "http://127.0.0.1:7125"
CONFIG_DIR = os.path.expanduser("~/printer_data/config")
LOG = os.path.expanduser("~/mcu_reconnect_watch.log")
POLL = 5            # seconds between checks
SETTLE = 8          # seconds all devices must be present before restart
MIN_GAP = 60        # min seconds between restart attempts
MAX_ATTEMPTS = 3    # then back off
BACKOFF = 600

TRIGGER = re.compile(r"Lost communication with MCU|Unable to connect|Timeout on connect|"
                     r"could not open port|Unable to open serial|MCU '[^']+' shutdown: Timer too close|"
                     r"Serial connection closed", re.I)
IGNORE = re.compile(r"webhooks request|Config error|Option '|Section '|Unable to parse|Unknown pin", re.I)

def log(msg):
    with open(LOG, "a") as f:
        f.write(time.strftime("%Y-%m-%d %H:%M:%S ") + msg + "\n")

def api(path, method="GET"):
    req = urllib.request.Request(MOONRAKER + path, method=method)
    with urllib.request.urlopen(req, timeout=10) as r:
        return json.load(r)["result"]

def serial_paths():
    """Serial devices of all configured MCUs.

    Prefer the config Klipper last loaded (Moonraker configfile object); fall
    back to scanning cfg files, ignoring template placeholders.
    """
    paths = set()
    try:
        settings = api("/printer/objects/query?configfile")["status"]["configfile"]["settings"]
        for sec, val in settings.items():
            if sec == "mcu" or sec.startswith("mcu ") or sec in ("cartographer", "scanner"):
                ser = val.get("serial") if isinstance(val, dict) else None
                if ser and ser.startswith("/dev/serial/by-id/"):
                    paths.add(ser)
    except Exception:
        pass
    if paths:
        return paths
    for root, _, files in os.walk(CONFIG_DIR):
        if "/0_Xplorer" in root or root.endswith("/.git"):
            continue
        for fn in files:
            if not fn.endswith(".cfg"):
                continue
            try:
                txt = open(os.path.join(root, fn), errors="ignore").read()
            except OSError:
                continue
            for m in re.finditer(r"^\s*serial\s*[:=]\s*(/dev/serial/by-id/\S+)", txt, re.M):
                if "REPLACE" not in m.group(1).upper():
                    paths.add(m.group(1))
    return paths

def main():
    log("watcher started")
    present_since = None
    last_attempt = 0.0
    attempts = 0
    while True:
        time.sleep(POLL)
        try:
            info = api("/printer/info")
        except Exception:
            present_since = None
            continue
        state, msg = info.get("state"), info.get("state_message", "")
        if state not in ("shutdown", "error") or IGNORE.search(msg) or not TRIGGER.search(msg):
            present_since = None
            attempts = 0
            continue
        paths = serial_paths()
        missing = [p for p in paths if not os.path.exists(p)]
        if missing or not paths:
            present_since = None
            continue
        now = time.time()
        if present_since is None:
            present_since = now
            log(f"MCU loss detected ({msg.splitlines()[0][:80]}); all {len(paths)} serial devices back, settling")
            continue
        if now - present_since < SETTLE:
            continue
        if attempts >= MAX_ATTEMPTS and now - last_attempt < BACKOFF:
            continue
        if now - last_attempt < MIN_GAP:
            continue
        if attempts >= MAX_ATTEMPTS:
            attempts = 0
        try:
            api("/printer/firmware_restart", "POST")
            attempts += 1
            last_attempt = now
            log(f"issued FIRMWARE_RESTART (attempt {attempts})")
        except Exception as e:
            log(f"firmware_restart failed: {e}")
        present_since = None

if __name__ == "__main__":
    main()
