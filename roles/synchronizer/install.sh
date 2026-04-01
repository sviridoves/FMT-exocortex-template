#!/bin/bash
# Synchronizer: установка центрального диспетчера (systemd timer)
# Заменяет отдельные планировщики единым scheduler
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SERVICE_NAME="exocortex-scheduler"
SERVICE_FILE="$HOME/.config/systemd/user/${SERVICE_NAME}.service"
TIMER_FILE="$HOME/.config/systemd/user/${SERVICE_NAME}.timer"

echo "Installing Synchronizer (central scheduler)..."

# Проверяем что scheduler.sh существует
if [ ! -f "$SCRIPT_DIR/scripts/scheduler.sh" ]; then
    echo "ERROR: $SCRIPT_DIR/scripts/scheduler.sh not found"
    exit 1
fi

# Делаем скрипты исполняемыми
chmod +x "$SCRIPT_DIR/scripts/"*.sh
chmod +x "$SCRIPT_DIR/scripts/templates/"*.sh 2>/dev/null || true

# Создаём директории состояния
mkdir -p "$HOME/.local/state/exocortex"
mkdir -p "$HOME/logs/synchronizer"

# Создаём директорию для unit-файлов
mkdir -p "$HOME/.config/systemd/user"

# Останавливаем и удаляем старый таймер (если есть)
systemctl --user stop "$SERVICE_NAME.timer" 2>/dev/null || true
systemctl --user disable "$SERVICE_NAME.timer" 2>/dev/null || true

# Создаём сервис
cat > "$SERVICE_FILE" << EOF
[Unit]
Description=Exocortex Central Scheduler
After=network-online.target

[Service]
Type=oneshot
ExecStart=$SCRIPT_DIR/scripts/scheduler.sh dispatch
StandardOutput=append:$HOME/logs/synchronizer/scheduler.log
StandardError=append:$HOME/logs/synchronizer/scheduler-error.log
Environment=HOME=$HOME
Environment=PATH=/usr/local/bin:/usr/bin:/bin
EOF

# Создаём таймер с расписанием (эквивалент StartCalendarInterval)
# Расписание: 0:00, 3:00, 5:00, 6:00, 9:00, 12:00, 15:00, 18:00, 21:00, 23:00
cat > "$TIMER_FILE" << EOF
[Unit]
Description=Exocortex Scheduler Dispatch Timer

[Timer]
Persistent=true
OnCalendar=*-*-* 00:00:00
OnCalendar=*-*-* 03:00:00
OnCalendar=*-*-* 05:00:00
OnCalendar=*-*-* 06:00:00
OnCalendar=*-*-* 09:00:00
OnCalendar=*-*-* 12:00:00
OnCalendar=*-*-* 15:00:00
OnCalendar=*-*-* 18:00:00
OnCalendar=*-*-* 21:00:00
OnCalendar=*-*-* 23:00:00

[Install]
WantedBy=timers.target
EOF

# Перезагружаем конфигурацию и активируем
systemctl --user daemon-reload
systemctl --user enable --now "$SERVICE_NAME.timer"

echo "  ✓ Installed: ${SERVICE_NAME}.timer"
echo "  ✓ Schedule: 10 dispatch points per day"
echo "  ✓ Manages: Strategist, Extractor, Code-Scan, Daily Report"
echo "  ✓ State: ~/.local/state/exocortex/"
echo "  ✓ Logs: ~/logs/synchronizer/"
echo ""
echo "Verify: systemctl --user status ${SERVICE_NAME}.timer"
echo "Logs: journalctl --user -u ${SERVICE_NAME} --since today"
echo ""
echo "Auto-wake (optional): wake system before dispatch times"
echo "  Linux: rtcwake or systemd timer with WakeSystem=true"
echo "  See docs/SETUP-GUIDE.md for details"
echo ""
echo "Telegram (optional): create ~/.config/aist/env with:"
echo "  export TELEGRAM_BOT_TOKEN=\"your-token\""
echo "  export TELEGRAM_CHAT_ID=\"your-id\""
echo ""
echo "Uninstall: systemctl --user disable --now ${SERVICE_NAME}.timer && rm ${SERVICE_FILE} ${TIMER_FILE}"