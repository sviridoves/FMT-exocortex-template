#!/bin/bash
# Extractor: установка systemd-сервиса для inbox-check на Linux
# Запускает inbox-check каждые 3 часа

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
EXTRACTOR_SCRIPT="$SCRIPT_DIR/scripts/extractor.sh"
SERVICE_NAME="extractor-inbox-check"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
TIMER_FILE="/etc/systemd/system/${SERVICE_NAME}.timer"

echo "Installing Extractor systemd service and timer..."

# Проверяем что основной скрипт существует
if [ ! -f "$EXTRACTOR_SCRIPT" ]; then
    echo "ERROR: $EXTRACTOR_SCRIPT not found"
    exit 1
fi

# Делаем скрипт исполняемым
chmod +x "$EXTRACTOR_SCRIPT"

# Создаем директорию для логов
mkdir -p /home/vps/logs/extractor

# Создаем systemd service файл
cat > "$SERVICE_FILE" << 'EOF'
[Unit]
Description=Extractor Inbox Check Service
After=network.target

[Service]
Type=oneshot
User=vps
WorkingDirectory=/home/vps/IWE
ExecStart=/home/vps/IWE/DS-exocortex/roles/extractor/scripts/extractor.sh inbox-check
Environment=PATH=/usr/local/bin:/usr/bin:/bin:/opt/homebrew/bin
Environment=HOME=/home/vps

[Install]
WantedBy=multi-user.target
EOF

# Создаем systemd timer файл
cat > "$TIMER_FILE" << 'EOF'
[Unit]
Description=Timer for Extractor Inbox Check
Requires=extractor-inbox-check.service

[Timer]
OnBootSec=5min
OnUnitActiveSec=3h

[Install]
WantedBy=timers.target
EOF

# Перезагружаем systemd конфигурацию
systemctl daemon-reload

# Останавливаем старый таймер если он запущен
systemctl stop "${SERVICE_NAME}.timer" 2>/dev/null || true

# Включаем и запускаем таймер
systemctl enable "${SERVICE_NAME}.timer"
systemctl start "${SERVICE_NAME}.timer"

echo "  ✓ Installed: ${SERVICE_NAME} systemd service and timer"
echo "  ✓ Interval: every 3 hours"
echo "  ✓ Logs: ~/logs/extractor/"
echo ""
echo "Verify: systemctl status extractor-inbox-check.timer"
echo "Check logs: journalctl -u extractor-inbox-check.service -f"
echo "Disable: systemctl stop extractor-inbox-check.timer && systemctl disable extractor-inbox-check.timer"