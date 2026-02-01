# Telegram Monitor (Clawdbot Health Check)

**[中文](README.zh-CN.md)**

Standalone Telegram health monitor for Clawdbot. Periodically checks Telegram connection status and restarts the gateway when it becomes unhealthy.

## Files

- `telegram-monitor.sh` — Main script
- `telegram-monitor.plist.example` — macOS LaunchAgent template
- `README.md` — This documentation (English)
- `README.zh-CN.md` — 中文说明

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| CHECK_INTERVAL | 60 | Interval between checks (seconds) |
| FAIL_THRESHOLD | 3 | Consecutive failures before restart |
| RESTART_COOLDOWN | 120 | Cooldown after restart (seconds) |
| PROBE_TIMEOUT | 15000 | Probe timeout (milliseconds) |
| LOG_FILE | ~/.clawdbot/telegram-monitor.log | Log file path |
| MAX_LOG_SIZE | 10485760 (10MB) | Max log size in bytes before rotation |
| CLAWDBOT_BIN | auto-detect | Path to clawdbot executable |

## How to Run

**Foreground:**
```bash
cd /path/to/telegram-monitor
./telegram-monitor.sh
```

**Background:**
```bash
nohup ./telegram-monitor.sh > /dev/null 2>&1 &
```

**tmux:**
```bash
tmux new-session -d -s telegram-monitor './telegram-monitor.sh'
```

**macOS auto-start (LaunchAgent):**
1. Copy `telegram-monitor.plist.example` to `~/Library/LaunchAgents/com.clawdbot.telegram-monitor.plist`
2. Edit the plist and set the script path to the absolute path of `telegram-monitor.sh` in this folder
3. Run: `launchctl load ~/Library/LaunchAgents/com.clawdbot.telegram-monitor.plist`

## Dependencies

- `clawdbot` installed and on PATH, or set via `CLAWDBOT_BIN`
- `jq` (for JSON parsing)

## Logs

Default log file: `~/.clawdbot/telegram-monitor.log`. Use `tail -f ~/.clawdbot/telegram-monitor.log` to watch in real time.
