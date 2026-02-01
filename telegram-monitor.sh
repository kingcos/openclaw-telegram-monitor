#!/bin/bash
# Telegram Health Monitor
# Monitors clawdbot Telegram connection and restarts gateway on failure.
# Standalone folder: run from this directory or set paths accordingly.
#
# Usage:
#   ./telegram-monitor.sh                           # Run in foreground
#   nohup ./telegram-monitor.sh > /dev/null 2>&1 &  # Run in background
#   tmux new -d -s tg-mon './telegram-monitor.sh'   # tmux session
#
# Environment variables:
#   CHECK_INTERVAL    - Seconds between checks (default: 60)
#   FAIL_THRESHOLD    - Consecutive failures before restart (default: 3)
#   RESTART_COOLDOWN  - Seconds to wait after restart (default: 120)
#   PROBE_TIMEOUT     - Probe timeout in milliseconds (default: 15000)
#   LOG_FILE          - Log file path (default: ~/.clawdbot/telegram-monitor.log)
#   MAX_LOG_SIZE      - Max log size in bytes before rotation (default: 10485760 = 10MB)
#   CLAWDBOT_BIN      - Path to clawdbot binary (default: auto-detect)

set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# Configuration (via environment variables with defaults)
# ─────────────────────────────────────────────────────────────────────────────
CHECK_INTERVAL="${CHECK_INTERVAL:-60}"
FAIL_THRESHOLD="${FAIL_THRESHOLD:-3}"
RESTART_COOLDOWN="${RESTART_COOLDOWN:-120}"
PROBE_TIMEOUT="${PROBE_TIMEOUT:-15000}"
LOG_FILE="${LOG_FILE:-$HOME/.clawdbot/telegram-monitor.log}"
MAX_LOG_SIZE="${MAX_LOG_SIZE:-10485760}"

# Auto-detect clawdbot binary
if [ -n "${CLAWDBOT_BIN:-}" ]; then
  CLAWDBOT="$CLAWDBOT_BIN"
elif command -v clawdbot &>/dev/null; then
  CLAWDBOT="clawdbot"
else
  # Try common installation paths
  for path in "$HOME/.local/bin/clawdbot" "$HOME/Library/pnpm/clawdbot" "/usr/local/bin/clawdbot"; do
    if [ -x "$path" ]; then
      CLAWDBOT="$path"
      break
    fi
  done
fi

if [ -z "${CLAWDBOT:-}" ]; then
  echo "Error: clawdbot binary not found. Set CLAWDBOT_BIN environment variable." >&2
  exit 1
fi

# ─────────────────────────────────────────────────────────────────────────────
# State variables
# ─────────────────────────────────────────────────────────────────────────────
FAIL_COUNT=0
LAST_RESTART_TIME=0

# ─────────────────────────────────────────────────────────────────────────────
# Logging helpers
# ─────────────────────────────────────────────────────────────────────────────
setup_log() {
  local log_dir
  log_dir="$(dirname "$LOG_FILE")"
  mkdir -p "$log_dir"
  
  # Rotate log if too large
  if [ -f "$LOG_FILE" ] && [ "$(stat -f%z "$LOG_FILE" 2>/dev/null || stat -c%s "$LOG_FILE" 2>/dev/null || echo 0)" -gt "$MAX_LOG_SIZE" ]; then
    mv "$LOG_FILE" "${LOG_FILE}.old"
    log "INFO" "Log rotated (previous log saved as ${LOG_FILE}.old)"
  fi
}

log() {
  local level="$1"
  shift
  local timestamp
  timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
  echo "[$timestamp] [$level] $*" | tee -a "$LOG_FILE"
}

# ─────────────────────────────────────────────────────────────────────────────
# Health check function
# ─────────────────────────────────────────────────────────────────────────────
check_telegram_health() {
  local output
  local exit_code=0
  
  # Run probe with timeout
  output=$("$CLAWDBOT" channels status --probe --json --timeout "$PROBE_TIMEOUT" 2>&1) || exit_code=$?
  
  # If command failed entirely, return failure
  if [ $exit_code -ne 0 ]; then
    log "WARN" "channels status command failed (exit=$exit_code): $output"
    return 1
  fi
  
  # Check if output is valid JSON (gateway reachable)
  if ! echo "$output" | jq -e '.ts' &>/dev/null; then
    log "WARN" "Gateway not reachable or invalid JSON output"
    return 1
  fi
  
  # Log raw JSON for debugging (full response to log file)
  log "DEBUG" "--- Raw status JSON ---"
  echo "$output" >> "$LOG_FILE"
  log "DEBUG" "--- End raw status ---"

  # JSON structure:
  #   .channelAccounts.telegram[] - array of account snapshots
  #   .channels.telegram - channel summary
  # Get the first telegram account from channelAccounts
  local telegram_account
  telegram_account=$(echo "$output" | jq -r '
    .channelAccounts.telegram // empty |
    .[0] // empty
  ' 2>/dev/null) || true
  
  if [ -z "$telegram_account" ] || [ "$telegram_account" = "null" ]; then
    log "WARN" "Telegram channel not found in status output"
    return 1
  fi
  
  # Check key health indicators (API may not include "connected"; use running + probe.ok)
  local running probe_ok enabled
  running=$(echo "$telegram_account" | jq -r '.running // false' 2>/dev/null)
  probe_ok=$(echo "$telegram_account" | jq -r '.probe.ok // false' 2>/dev/null)
  enabled=$(echo "$telegram_account" | jq -r '.enabled // true' 2>/dev/null)
  
  # Log current status
  local bot_username
  bot_username=$(echo "$telegram_account" | jq -r '.probe.bot.username // .bot.username // "unknown"' 2>/dev/null)
  
  # Check if channel is disabled (not an error)
  if [ "$enabled" = "false" ]; then
    log "INFO" "Telegram channel is disabled - skipping health check"
    return 0
  fi
  
  # Healthy: running and probe ok (connected is not always present in API response)
  if [ "$running" = "true" ] && [ "$probe_ok" = "true" ]; then
    log "INFO" "Telegram healthy: running=$running, probe=$probe_ok, bot=$bot_username"
    return 0
  else
    log "WARN" "Telegram unhealthy: running=$running, probe=$probe_ok, bot=$bot_username"
    return 1
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Restart gateway function
# ─────────────────────────────────────────────────────────────────────────────
restart_gateway() {
  log "INFO" "Attempting gateway restart..."
  
  local output
  local exit_code=0
  output=$("$CLAWDBOT" gateway restart 2>&1) || exit_code=$?
  
  if [ $exit_code -eq 0 ]; then
    log "INFO" "Gateway restart initiated successfully"
    LAST_RESTART_TIME=$(date +%s)
    return 0
  else
    log "ERROR" "Gateway restart failed (exit=$exit_code): $output"
    return 1
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Main monitoring loop
# ─────────────────────────────────────────────────────────────────────────────
main() {
  setup_log
  
  log "INFO" "=========================================="
  log "INFO" "Telegram Monitor started"
  log "INFO" "  CHECK_INTERVAL:   ${CHECK_INTERVAL}s"
  log "INFO" "  FAIL_THRESHOLD:   ${FAIL_THRESHOLD}"
  log "INFO" "  RESTART_COOLDOWN: ${RESTART_COOLDOWN}s"
  log "INFO" "  PROBE_TIMEOUT:    ${PROBE_TIMEOUT}ms"
  log "INFO" "  CLAWDBOT:         ${CLAWDBOT}"
  log "INFO" "  LOG_FILE:         ${LOG_FILE}"
  log "INFO" "=========================================="
  
  # Trap SIGINT/SIGTERM for graceful shutdown
  trap 'log "INFO" "Monitor stopped by signal"; exit 0' INT TERM
  
  while true; do
    # Check if we're still in cooldown period after restart
    local now
    now=$(date +%s)
    local time_since_restart=$((now - LAST_RESTART_TIME))
    
    if [ "$LAST_RESTART_TIME" -gt 0 ] && [ "$time_since_restart" -lt "$RESTART_COOLDOWN" ]; then
      local remaining=$((RESTART_COOLDOWN - time_since_restart))
      log "INFO" "In cooldown period, waiting ${remaining}s before next check..."
      sleep "$remaining"
      continue
    fi
    
    # Perform health check
    if check_telegram_health; then
      # Health check passed - reset failure counter
      if [ "$FAIL_COUNT" -gt 0 ]; then
        log "INFO" "Health restored after $FAIL_COUNT failed check(s)"
      fi
      FAIL_COUNT=0
    else
      # Health check failed - increment counter
      FAIL_COUNT=$((FAIL_COUNT + 1))
      log "WARN" "Health check failed ($FAIL_COUNT/$FAIL_THRESHOLD)"
      
      # Check if we should restart
      if [ "$FAIL_COUNT" -ge "$FAIL_THRESHOLD" ]; then
        log "WARN" "Failure threshold reached, triggering restart..."
        
        if restart_gateway; then
          FAIL_COUNT=0
          log "INFO" "Entering cooldown period (${RESTART_COOLDOWN}s)..."
          sleep "$RESTART_COOLDOWN"
          continue
        else
          # Restart failed - wait a bit and try again
          log "ERROR" "Restart failed, will retry after next check interval"
        fi
      fi
    fi
    
    # Wait for next check
    sleep "$CHECK_INTERVAL"
  done
}

# ─────────────────────────────────────────────────────────────────────────────
# Entry point
# ─────────────────────────────────────────────────────────────────────────────
main "$@"
