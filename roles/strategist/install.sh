#!/bin/bash
# Install Strategist Agent systemd timers
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MORNING_SERVICE="strategist-morning"
WEEKLY_SERVICE="strategist-weekly"
USER_SYSTEMD="$HOME/.config/systemd/user"

echo "Installing Strategist Agent systemd timers..."

# Создаём директорию
mkdir -p "$USER_SYSTEMD"
mkdir -p "$HOME/logs/strategist"

# Делаем скрипт исполняемым
chmod +x "$SCRIPT_DIR/scripts/strategist.sh"

# Останавливаем старые таймеры (если есть)
systemctl --user stop "${MORNING_SERVICE}.timer" 2>/dev/null || true
systemctl --user disable "${MORNING_SERVICE}.timer" 2>/dev/null || true
systemctl --user stop "${WEEKLY_SERVICE}.timer" 2>/dev/null || true
systemctl --user disable "${WEEKLY_SERVICE}.timer" 2>/dev/null || true

# Morning: ежедневно в 5:00
cat > "$USER_SYSTEMD/${MORNING_SERVICE}.service" << EOF
[Unit]
Description=Strategist Morning Routine
After=network-online.target

[Service]
Type=oneshot
ExecStart=$SCRIPT_DIR/scripts/strategist.sh morning
StandardOutput=append:$HOME/logs/strategist/morning.log
StandardError=append:$HOME/logs/strategist/morning-error.log
Environment=HOME=$HOME
Environment=PATH=/usr/local/bin:/usr/bin:/bin
EOF

cat > "$USER_SYSTEMD/${MORNING_SERVICE}.timer" << EOF
[Unit]
Description=Strategist Morning Timer

[Timer]
OnCalendar=*-*-* 05:00:00
Persistent=true

[Install]
WantedBy=timers.target
EOF

# Week Review: каждый понедельник в 0:00
cat > "$USER_SYSTEMD/${WEEKLY_SERVICE}.service" << EOF
[Unit]
Description=Strategist Week Review
After=network-online.target

[Service]
Type=oneshot
ExecStart=$SCRIPT_DIR/scripts/strategist.sh week-review
StandardOutput=append:$HOME/logs/strategist/week-review.log
StandardError=append:$HOME/logs/strategist/week-review-error.log
Environment=HOME=$HOME
Environment=PATH=/usr/local/bin:/usr/bin:/bin
EOF

cat > "$USER_SYSTEMD/${WEEKLY_SERVICE}.timer" << EOF
[Unit]
Description=Strategist Week Review Timer

[Timer]
OnCalendar=Mon *-*-* 00:00:00
Persistent=true

[Install]
WantedBy=timers.target
EOF

# Активируем
systemctl --user daemon-reload
systemctl --user enable --now "${MORNING_SERVICE}.timer"
systemctl --user enable --now "${WEEKLY_SERVICE}.timer"

echo "Done. Timers loaded:"
systemctl --user list-timers | grep strategist
echo ""
echo "Logs:"
echo "  Morning: journalctl --user -u ${MORNING_SERVICE} --since today"
echo "  Week Review: journalctl --user -u ${WEEKLY_SERVICE} --since today"
echo ""
echo "Uninstall:"
echo "  systemctl --user disable --now ${MORNING_SERVICE}.timer ${WEEKLY_SERVICE}.timer"
echo "  rm $USER_SYSTEMD/${MORNING_SERVICE}.{service,timer}"
echo "  rm $USER_SYSTEMD/${WEEKLY_SERVICE}.{service,timer}"