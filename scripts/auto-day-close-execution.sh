#!/bin/bash
# auto-day-close-execution.sh — Автоматическое выполнение скриптов Day Close

set -euo pipefail

# === КОНФИГУРАЦИЯ ===
WORKSPACE_DIR="/home/vps/IWE"
SCRIPTS_DIR="$WORKSPACE_DIR/DS-exocortex/scripts"
LOGS_DIR="$WORKSPACE_DIR/DS-agent-workspace/scheduler/logs"
AUTO_LOG="$LOGS_DIR/auto-day-close-$(date +%Y-%m-%d).log"
LOCK_NAME="auto-day-close"
LOCK_TIMEOUT=3600  # 1 час
# === /КОНФИГУРАЦИЯ ===

# Подключаем утилиты блокировки
source "$SCRIPTS_DIR/locking-utils.sh"

# Создаем директорию для логов
mkdir -p "$LOGS_DIR"

# Логирование функция
log_to_file() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$AUTO_LOG"
}

log_to_file "=== Запуск автоматического выполнения Day Close скриптов ==="

# Проверяем, занята ли блокировка планировщиком
if is_locked "scheduler-operation"; then
    log_to_file "Планировщик занят, откладываем выполнение Day Close"
    exit 0
fi

# Пытаемся получить блокировку для выполнения
if ! acquire_lock "$LOCK_NAME" "$LOCK_TIMEOUT"; then
    log_to_file "Не удалось получить блокировку, возможно другой процесс уже работает"
    exit 0
fi

# Завершение работы - освобождение блокировки
trap 'release_lock "$LOCK_NAME"; log_to_file "Блокировка освобождена"' EXIT

# Проверяем, есть ли сегодня коммиты (чтобы не запускать в выходные/тихие дни)
HAS_COMMITS_TODAY=false
for repo in "$WORKSPACE_DIR"/DS-* "$WORKSPACE_DIR"/PACK-*; do
    if [ -d "$repo/.git" ]; then
        if git -C "$repo" log --since="today 00:00" --oneline --no-merges 2>/dev/null | grep -q .; then
            HAS_COMMITS_TODAY=true
            break
        fi
    fi
done

if [ "$HAS_COMMITS_TODAY" = true ]; then
    log_to_file "Найдены коммиты за сегодня, запускаем процедуры Day Close..."

    # 1. Запускаем статус обновления
    log_to_file "Запуск: status-update.sh"
    if "$SCRIPTS_DIR/status-update.sh"; then
        log_to_file "✓ status-update.sh успешно завершен"
    else
        log_to_file "✗ status-update.sh завершился с ошибкой"
    fi

    # 2. Запускаем архивацию
    log_to_file "Запуск: auto-archive.sh"
    if "$SCRIPTS_DIR/auto-archive.sh"; then
        log_to_file "✓ auto-archive.sh успешно завершен"
    else
        log_to_file "✗ auto-archive.sh завершился с ошибкой"
    fi

    # 3. Запускаем улучшенное логирование
    log_to_file "Запуск: enhanced-logging.sh daily"
    if "$SCRIPTS_DIR/enhanced-logging.sh" daily; then
        log_to_file "✓ enhanced-logging.sh успешно завершен"
    else
        log_to_file "✗ enhanced-logging.sh завершился с ошибкой"
    fi

    # 4. Запускаем проверку напоминаний
    log_to_file "Запуск: reminders.sh check-all"
    if "$SCRIPTS_DIR/reminders.sh" check-all; then
        log_to_file "✓ reminders.sh успешно завершен"
    else
        log_to_file "✗ reminders.sh завершился с ошибкой"
    fi

    # 5. Запускаем улучшенный day-close (только автоматические части)
    log_to_file "Запуск: enhanced-day-close.sh"
    if "$SCRIPTS_DIR/enhanced-day-close.sh"; then
        log_to_file "✓ enhanced-day-close.sh успешно завершен"
    else
        log_to_file "✗ enhanced-day-close.sh завершился с ошибкой"
    fi

else
    log_to_file "Нет коммитов за сегодня, пропускаем выполнение процедур Day Close"
fi

log_to_file "=== Завершение автоматического выполнения Day Close скриптов ==="
