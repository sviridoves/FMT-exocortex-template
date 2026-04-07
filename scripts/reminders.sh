#!/bin/bash
# reminders.sh — Система напоминаний для Day Close процедур

set -euo pipefail

# === КОНФИГУРАЦИЯ ===
WORKSPACE_DIR="${WORKSPACE_DIR:-$HOME/IWE}"
DS_STRATEGY="$WORKSPACE_DIR/DS-strategy"
REMINDERS_LOG="$WORKSPACE_DIR/DS-agent-workspace/scheduler/reminders.log"
TELEGRAM_ENABLED=$(grep -q "telegram_notifications: true" "$WORKSPACE_DIR/DS-exocortex/params.yaml" && echo "true" || echo "false")
# === /КОНФИГУРАЦИЯ ===

# Цвета
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log() { echo -e "${GREEN}[reminders]${NC} $1"; }
warn() { echo -e "${YELLOW}[reminders]${NC} $1"; }
err() { echo -e "${RED}[reminders]${NC} $1" >&2; }

# --- Проверка необходимости Day Close ---
check_day_close_needed() {
  local today=$(date +%Y-%m-%d)
  local dayplan_file="$DS_STRATEGY/archive/day-plans/DayPlan_$today.md"
  
  # Проверяем, есть ли сегодняшний DayPlan файл
  if [ -f "$dayplan_file" ]; then
    # Проверяем, содержит ли он секцию "Итоги дня"
    if grep -q "## Итоги дня\|## Day Summary\|## Итоги за день" "$dayplan_file"; then
      return 1  # Day Close уже выполнен
    else
      return 0  # Day Close еще не выполнен
    fi
  else
    # Проверяем в current директории тоже
    dayplan_file="$DS_STRATEGY/current/DayPlan_$today.md"
    if [ -f "$dayplan_file" ]; then
      if grep -q "## Итоги дня\|## Day Summary\|## Итоги за день" "$dayplan_file"; then
        return 1  # Day Close уже выполнен
      else
        return 0  # Day Close еще не выполнен
      fi
    fi
  fi
  
  # Если файл не найден, проверяем по коммитам
  local has_commits_today=false
  for repo in "$WORKSPACE_DIR"/DS-* "$WORKSPACE_DIR"/PACK-*; do
    [ -d "$repo/.git" ] || continue
    if git -C "$repo" log --since="today 00:00" --oneline --no-merges 2>/dev/null | grep -q .; then
      has_commits_today=true
      break
    fi
  done
  
  [ "$has_commits_today" = true ]
}

# --- Проверка незавершенных задач ---
check_unfinished_tasks() {
  local unfinished_count=0
  
  # Проверяем WP-REGISTRY на незавершенные задачи
  local registry_file="$DS_STRATEGY/docs/WP-REGISTRY.md"
  if [ -f "$registry_file" ]; then
    # Подсчитываем количество незавершенных РП (без ✅ и done)
    unfinished_count=$(grep -c -E '\|.*🔄.*\||.*⏳.*\||.*📝.*\|' "$registry_file" 2>/dev/null || echo 0)
  fi
  
  echo $unfinished_count
}

# --- Проверка просроченных дедлайнов ---
check_overdue_deadlines() {
  local overdue_count=0
  local today=$(date +%Y-%m-%d)
  
  # Проверяем MEMORY.md на просроченные дедлайны
  local memory_file="$WORKSPACE_DIR/DS-exocortex/memory/MEMORY.md"
  if [ -f "$memory_file" ]; then
    # Ищем дедлайны в формате YYYY-MM-DD
    while IFS= read -r line; do
      if [[ "$line" =~ [0-9]{4}-[0-9]{2}-[0-9]{2} ]]; then
        local deadline=$(echo "$line" | grep -o '[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}' | head -1)
        if [[ "$deadline" < "$today" ]]; then
          overdue_count=$((overdue_count + 1))
        fi
      fi
    done < "$memory_file"
  fi
  
  echo $overdue_count
}

# --- Отправка напоминания ---
send_reminder() {
  local reminder_type="$1"
  local message="$2"
  
  log "Напоминание: $message"
  
  # Записываем в лог
  echo "$(date '+%Y-%m-%d %H:%M') | REMINDER | $reminder_type | $message" >> "$REMINDERS_LOG"
  
  # Отправляем через Telegram если включен
  if [ "$TELEGRAM_ENABLED" = "true" ]; then
    send_telegram_notification "$message"
  fi
}

# --- Отправка Telegram уведомления ---
send_telegram_notification() {
  local message="$1"
  # Заглушка для Telegram уведомлений
  log "Telegram: $message"
  # Здесь будет реализация отправки через Telegram API
}

# --- Основная проверка напоминаний ---
run_reminders_check() {
  log "Проверка напоминаний..."
  
  # Проверяем необходимость Day Close
  if check_day_close_needed; then
    send_reminder "DAY_CLOSE" "⚠️ Необходимо выполнить Day Close за сегодня ($TODAY)"
  fi
  
  # Проверяем незавершенные задачи
  local unfinished_tasks=$(check_unfinished_tasks)
  if [ "$unfinished_tasks" -gt 5 ]; then  # Если больше 5 незавершенных задач
    send_reminder "UNFINISHED_TASKS" "📊 Незавершенных задач: $unfinished_tasks - рекомендуется приоритизация"
  fi
  
  # Проверяем просроченные дедлайны
  local overdue_deadlines=$(check_overdue_deadlines)
  if [ "$overdue_deadlines" -gt 0 ]; then
    send_reminder "OVERDUE_DEADLINES" "🚨 Просроченных дедлайнов: $overdue_deadlines - требуется срочное внимание"
  fi
  
  # Проверяем файлы в inbox, которые давно не обрабатываются
  check_inbox_files
  
  log "Проверка напоминаний завершена"
}

# --- Проверка файлов в inbox ---
check_inbox_files() {
  local inbox_dir="$DS_STRATEGY/inbox"
  if [ -d "$inbox_dir" ]; then
    # Находим файлы старше 7 дней
    local old_files=$(find "$inbox_dir" -name "*.md" -type f -mtime +7 2>/dev/null | wc -l)
    if [ "$old_files" -gt 0 ]; then
      send_reminder "INBOX_FILES" "📁 Файлов в inbox старше 7 дней: $old_files - требуется обработка"
    fi
  fi
}

# --- Настройка cron для регулярных напоминаний ---
setup_cron_reminders() {
  log "Настройка cron напоминаний..."
  
  # Создаем cron entry для ежедневных напоминаний
  local cron_job="0 18 * * * $WORKSPACE_DIR/DS-exocortex/scripts/reminders.sh check-day-close"
  local current_crontab=$(crontab -l 2>/dev/null | grep -v "reminders.sh" || true)
  
  # Добавляем нашу задачу
  echo "$current_crontab" | grep -q "$cron_job" || {
    echo "$current_crontab" > /tmp/crontab.tmp
    echo "$cron_job" >> /tmp/crontab.tmp
    crontab /tmp/crontab.tmp
    rm /tmp/crontab.tmp
    log "Cron задача добавлена: $cron_job"
  }
}

# --- Проверка чеклиста Day Close ---
check_day_close_checklist() {
  local checklist_file="$WORKSPACE_DIR/memory/protocol-close.md"
  if [ -f "$checklist_file" ]; then
    # Проверяем, все ли шаги выполнены
    local total_steps=$(grep -c "#### \|[0-9]\." "$checklist_file" 2>/dev/null || echo 0)
    local completed_steps=$(grep -c "✅\|done\|completed\|заверш" "$checklist_file" 2>/dev/null || echo 0)
    
    if [ "$total_steps" -gt 0 ] && [ "$completed_steps" -lt $((total_steps / 2)) ]; then
      send_reminder "CHECKLIST_PROGRESS" "📋 Прогресс Day Close чеклиста: $completed_steps/$total_steps - требуется завершение"
    fi
  fi
}

# --- Main ---
main() {
  # Проверяем, занята ли блокировка планировщиком
  if [ -f "$LOCK_UTILS" ] && is_locked "scheduler-operation"; then
    log "Планировщик занят, откладываем выполнение проверки напоминаний"
    exit 0
  fi

  # Пытаемся получить блокировку для выполнения
  if [ -f "$LOCK_UTILS" ]; then
    if ! acquire_lock "$LOCK_NAME" "$LOCK_TIMEOUT"; then
      log "Не удалось получить блокировку, возможно другой процесс уже работает"
      exit 0
    fi
    # Завершение работы - освобождение блокировки
    trap 'release_lock "$LOCK_NAME"; log "Блокировка освобождена"' EXIT
  fi

  local action="${1:-check}"

  case "$action" in
    "check"|"check-day-close")
      run_reminders_check
      ;;
    "setup-cron")
      setup_cron_reminders
      ;;
    "check-all")
      run_reminders_check
      check_day_close_checklist
      ;;
    *)
      echo "Использование: $0 [check|setup-cron|check-all]"
      echo "  check        - проверить напоминания"
      echo "  setup-cron   - настроить cron задачи"
      echo "  check-all    - полная проверка всех напоминаний"
      exit 1
      ;;
  esac
}

main "$@"