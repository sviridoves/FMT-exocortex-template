#!/bin/bash
# Synchronizer: установка центрального диспетчера (systemd) для Linux
# Заменяет отдельные launchd-агенты единым scheduler

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCHEDULER_SCRIPT="$SCRIPT_DIR/scripts/scheduler.sh"
SERVICE_NAME="exocortex-scheduler"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
TIMER_FILE="/etc/systemd/system/${SERVICE_NAME}.timer"

echo "Installing Synchronizer (central scheduler) for Linux..."

# Проверяем что основной скрипт существует
if [ ! -f "$SCHEDULER_SCRIPT" ]; then
    echo "ERROR: $SCHEDULER_SCRIPT not found"
    exit 1
fi

# Делаем скрипты исполняемыми
chmod +x "$SCRIPT_DIR/scripts/"*.sh
chmod +x "$SCRIPT_DIR/scripts/templates/"*.sh 2>/dev/null || true

# Создаём директории состояния и логов
mkdir -p "$HOME/.local/state/exocortex"
mkdir -p "$HOME/logs/synchronizer"

# Создаем systemd service файл
cat > "$SERVICE_FILE" << 'EOF'
[Unit]
Description=Exocortex Central Scheduler Service
After=network.target

[Service]
Type=oneshot
User=vps
WorkingDirectory=/home/vps/IWE
ExecStart=/home/vps/IWE/DS-exocortex/roles/synchronizer/scripts/scheduler.sh dispatch
Environment=PATH=/usr/local/bin:/usr/bin:/bin:/opt/homebrew/bin
Environment=HOME=/home/vps
TimeoutSec=3600

[Install]
WantedBy=multi-user.target
EOF

# Создаем systemd timer файл с расписанием (соответствует StartCalendarInterval из plist)
cat > "$TIMER_FILE" << 'EOF'
[Unit]
Description=Timer for Exocortex Central Scheduler
Requires=exocortex-scheduler.service

[Timer]
# Расписание соответствует StartCalendarInterval из оригинального plist:
# 0:00  — week-review (Пн) + code-scan
# 3:00  — extractor inbox-check
# 5:00  — strategist morning
# 6:00  — extractor + daily-report
# 9:00  — extractor
# 12:00 — extractor
# 15:00 — extractor
# 18:00 — extractor
# 21:00 — extractor
# 23:00 — strategist note-review
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

# Перезагружаем systemd конфигурацию
systemctl daemon-reload

# Останавливаем старый таймер если он был (для безопасности)
systemctl stop "${SERVICE_NAME}.timer" 2>/dev/null || true

# Включаем и запускаем таймер
systemctl enable "${SERVICE_NAME}.timer"
systemctl start "${SERVICE_NAME}.timer"

echo "  ✓ Installed: ${SERVICE_NAME} systemd service and timer"
echo "  ✓ Schedule: 10 dispatch points per day (00:00, 03:00, 05:00, 06:00, 09:00, 12:00, 15:00, 18:00, 21:00, 23:00)"
echo "  ✓ Manages: Strategist, Extractor, Code-Scan, Daily Report"
echo "  ✓ State: ~/.local/state/exocortex/"
echo "  ✓ Logs: ~/logs/synchronizer/"
echo ""
echo "Verify: systemctl status exocortex-scheduler.timer"
echo "Check logs: journalctl -u exocortex-scheduler.service -f"
echo "Status: bash $SCRIPT_DIR/scripts/scheduler.sh status"
echo ""
echo "Disable: systemctl stop exocortex-scheduler.timer && systemctl disable exocortex-scheduler.timer"