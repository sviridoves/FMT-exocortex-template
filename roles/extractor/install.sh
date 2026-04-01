#!/bin/bash
# Extractor: установка systemd timer для inbox-check
# Запускает inbox-check каждые 3 часа
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SERVICE_NAME="extractor-inbox-check"
SERVICE_FILE="$HOME/.config/systemd/user/${SERVICE_NAME}.service"
TIMER_FILE="$HOME/.config/systemd/user/${SERVICE_NAME}.timer"

echo "Installing Extractor systemd timer..."

# Проверяем что extractor.sh существует
if [ ! -f "$SCRIPT_DIR/scripts/extractor.sh" ]; then
    echo "ERROR: $SCRIPT_DIR/scripts/extractor.sh not found"
    exit 1
fi

# Делаем скрипт исполняемым
chmod +x "$SCRIPT_DIR/scripts/extractor.sh"

# Создаём директорию для логов
LOG_DIR="$HOME/logs/extractor"
mkdir -p "$LOG_DIR"

# Останавливаем и удаляем старый таймер (если есть)
systemctl --user stop "$SERVICE_NAME.timer" 2>/dev/null || true
systemctl --user disable "$SERVICE_NAME.timer" 2>/dev/null || true

# Создаём директорию для unit-файлов
mkdir -p "$HOME/.config/systemd/user"

# Создаём сервис
cat > "$SERVICE_FILE" << EOF
[Unit]
Description=Extractor Inbox Check
After=network-online.target

[Service]
Type=oneshot
ExecStart=$SCRIPT_DIR/scripts/extractor.sh inbox-check
StandardOutput=append:$LOG_DIR/inbox-check.log
StandardError=append:$LOG_DIR/inbox-check-error.log
Environment=HOME=$HOME
Environment=PATH=/usr/local/bin:/usr/bin:/bin
EOF

# Создаём таймер (каждые 3 часа)
cat > "$TIMER_FILE" << EOF
[Unit]
Description=Run inbox check every 3 hours

[Timer]
OnBootSec=10min
OnUnitActiveSec=3h
Persistent=true

[Install]
WantedBy=timers.target
EOF

# Перезагружаем конфигурацию и активируем
systemctl --user daemon-reload
systemctl --user enable --now "$SERVICE_NAME.timer"

echo "  ✓ Installed: ${SERVICE_NAME}.timer"
echo "  ✓ Interval: every 3 hours"
echo "  ✓ Logs: $LOG_DIR/"
echo ""
echo "Verify: systemctl --user status ${SERVICE_NAME}.timer"
echo "Logs: journalctl --user -u ${SERVICE_NAME} --since today"
echo "Uninstall: systemctl --user disable --now ${SERVICE_NAME}.timer && rm ${SERVICE_FILE} ${TIMER_FILE}"