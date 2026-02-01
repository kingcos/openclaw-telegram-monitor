# Telegram Monitor (Clawdbot 自检)

独立于 Clawdbot 源码的 Telegram 健康监控脚本。定期检查 Telegram 连接状态，异常时自动重启网关。

## 文件

- `telegram-monitor.sh` — 主脚本
- `telegram-monitor.plist.example` — macOS LaunchAgent 模板
- `README.md` — 本说明

## 环境变量

| 变量 | 默认值 | 说明 |
|------|--------|------|
| CHECK_INTERVAL | 60 | 检查间隔（秒） |
| FAIL_THRESHOLD | 3 | 连续失败多少次后重启 |
| RESTART_COOLDOWN | 120 | 重启后冷却时间（秒） |
| PROBE_TIMEOUT | 15000 | 探测超时（毫秒） |
| LOG_FILE | ~/.clawdbot/telegram-monitor.log | 日志路径 |
| CLAWDBOT_BIN | 自动检测 | clawdbot 可执行文件路径 |

## 运行方式

**前台运行：**
```bash
cd /path/to/telegram-monitor
./telegram-monitor.sh
```

**后台运行：**
```bash
nohup ./telegram-monitor.sh > /dev/null 2>&1 &
```

**tmux：**
```bash
tmux new-session -d -s telegram-monitor './telegram-monitor.sh'
```

**macOS 开机自启（LaunchAgent）：**
1. 复制 `telegram-monitor.plist.example` 到 `~/Library/LaunchAgents/com.clawdbot.telegram-monitor.plist`
2. 编辑 plist，将脚本路径改为本文件夹中的 `telegram-monitor.sh` 的绝对路径
3. 执行：`launchctl load ~/Library/LaunchAgents/com.clawdbot.telegram-monitor.plist`

## 依赖

- `clawdbot` 已安装且在 PATH 中，或通过 `CLAWDBOT_BIN` 指定
- `jq`（解析 JSON）

## 日志

默认日志：`~/.clawdbot/telegram-monitor.log`。可用 `tail -f ~/.clawdbot/telegram-monitor.log` 实时查看。
