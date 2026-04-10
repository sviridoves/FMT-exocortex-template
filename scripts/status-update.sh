#!/bin/bash
# status-update.sh — Автоматическое обновление статусов в системе управления

set -euo pipefail

  # === КОНФИГУРАЦИЯ ===
  WORKSPACE_DIR="${WORKSPACE_DIR:-$HOME/IWE}"
  DS_STRATEGY="$WORKSPACE_DIR/DS-strategy"
  LOG_FILE="$WORKSPACE_DIR/DS-agent-workspace/scheduler/status-update.log"
  # === /КОНФИГУРАЦИЯ ===

   # Подключаем утилиты блокировок
   source "$WORKSPACE_DIR/DS-exocortex/scripts/locking-utils.sh" || {
     echo "Ошибка: не удалось подключить locking-utils.sh"
     exit 1
   }

  # Конфигурация блокировок
  LOCK_NAME="status-update"
  LOCK_TIMEOUT=1800  # 30 минут

# Цвета
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log() { echo -e "${GREEN}[status-update]${NC} $1"; }
warn() { echo -e "${YELLOW}[status-update]${NC} $1"; }
err() { echo -e "${RED}[status-update]${NC} $1" >&2; }

# --- Обновление статусов в WeekPlan ---
update_weekplan_statuses() {
  log "Обновление статусов в WeekPlan..."
  
  # Находим текущий WeekPlan файл
  local weekplan_file=""
  for file in "$DS_STRATEGY/current"/WeekPlan*.md; do
    if [[ -f "$file" ]]; then
      weekplan_file="$file"
      break
    fi
  done
  
  if [ -z "$weekplan_file" ]; then
    warn "WeekPlan файл не найден"
    return 0
  fi
  
  log "Обновляем: $(basename "$weekplan_file")"
  
  # Создаем временный файл для обновления
  local temp_file=$(mktemp)
  cp "$weekplan_file" "$temp_file"
  
  # Здесь будет логика обновления статусов РП в WeekPlan
  # Пока что просто добавляем временную метку обновления
  sed -i.bak '/^---$/,$ { /#.*Итоги.*понедельника\|#.*Итоги.*вторника\|#.*Итоги.*среды\|#.*Итоги.*четверга\|#.*Итоги.*пятницы\|#.*Итоги.*субботы\|#.*Итоги.*воскресенья/!b; :a; n; ba; }; $a\\n<!-- Статусы обновлены: '"$(date)"' -->' "$temp_file"
  
  mv "$temp_file" "$weekplan_file"
  rm -f "$temp_file.bak"
  
  log "WeekPlan обновлен"
}

# --- Обновление статусов в WP-REGISTRY ---
update_registry_statuses() {
  log "Обновление статусов в WP-REGISTRY..."
  
  local registry_file="$DS_STRATEGY/docs/WP-REGISTRY.md"
  if [ ! -f "$registry_file" ]; then
    warn "WP-REGISTRY файл не найден: $registry_file"
    return 0
  fi
  
  # Создаем резервную копию
  cp "$registry_file" "${registry_file}.bak"
  
  # Здесь будет логика обновления статусов в реестре
  # Пока что просто добавляем временную метку
  sed -i.bak '1i\
<!-- Последнее обновление статусов: '"$(date)"' -->' "$registry_file"
  
  rm -f "${registry_file}.bak"
  log "WP-REGISTRY обновлен"
}

# --- Обновление статусов в MEMORY.md ---
update_memory_statuses() {
  log "Обновление статусов в MEMORY.md..."
  
  local memory_file="$WORKSPACE_DIR/DS-exocortex/memory/MEMORY.md"
  if [ ! -f "$memory_file" ]; then
    warn "MEMORY.md файл не найден: $memory_file"
    return 0
  fi
  
  # Создаем резервную копию
  cp "$memory_file" "${memory_file}.bak"
  
  # Удаляем завершенные РП из MEMORY.md
  local temp_file=$(mktemp)
  local in_wp_section=false
  local removed_count=0
  
  while IFS= read -r line; do
    if [[ "$line" =~ ^##.*РП.*текущей.недели ]]; then
      in_wp_section=true
      echo "$line" >> "$temp_file"
    elif [[ "$line" =~ ^\|.*\|.*done.*\| ]] && [ "$in_wp_section" = true ]; then
      # Пропускаем строки с done РП
      removed_count=$((removed_count + 1))
      continue
    elif [[ "$line" =~ ^\|.*\#.*\| ]] && [[ "$line" != "| # | РП | Бюджет | Статус | Дедлайн | Проект |" ]]; then
      # Проверяем, есть ли в строке статус done
      if [[ "$line" =~ \|.*done.*\| ]]; then
        removed_count=$((removed_count + 1))
        continue
      fi
    elif [[ "$line" =~ ^--- ]] && [ "$in_wp_section" = true ]; then
      in_wp_section=false
    fi
    echo "$line" >> "$temp_file"
  done < "$memory_file"
  
  mv "$temp_file" "$memory_file"
  rm -f "${memory_file}.bak"
  
  log "MEMORY.md обновлен - удалено $removed_count завершенных РП"
}

# --- Обновление статусов в DayPlan ---
update_dayplan_statuses() {
  log "Обновление статусов в DayPlan..."
  
  # Находим текущий DayPlan файл
  local dayplan_file=""
  for file in "$DS_STRATEGY/current"/DayPlan*.md "$DS_STRATEGY/archive/day-plans"/DayPlan*.md; do
    if [[ -f "$file" ]]; then
      # Проверяем, является ли файл сегодняшним
      local file_date=$(basename "$file" | grep -o '[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}')
      local today=$(date +%Y-%m-%d)
      if [[ "$file_date" == "$today" ]]; then
        dayplan_file="$file"
        break
      fi
    fi
  done
  
  if [ -z "$dayplan_file" ]; then
    warn "Текущий DayPlan файл не найден"
    return 0
  fi
  
  log "Обновляем DayPlan: $(basename "$dayplan_file")"
  
  # Создаем резервную копию
  cp "$dayplan_file" "${dayplan_file}.bak"
  
  # Добавляем временную метку обновления
  sed -i.bak '1i\
<!-- Статусы обновлены: '"$(date)"' -->' "$dayplan_file"
  
  rm -f "${dayplan_file}.bak"
  log "DayPlan обновлен"
}

# --- Лог ---
write_log() {
  local date_str
  date_str=$(date "+%Y-%m-%d %H:%M")
  mkdir -p "$(dirname "$LOG_FILE")"
  echo "$date_str | status-update | weekplan=$1 registry=$2 memory=$3 dayplan=$4" >> "$LOG_FILE"
}

# --- Main ---
main() {
  # Проверяем, занята ли блокировка планировщиком
  if is_locked "scheduler-operation"; then
    log "Планировщик занят, откладываем выполнение обновления статусов"
    exit 0
  fi

  # Пытаемся получить блокировку для выполнения
  if ! acquire_lock "$LOCK_NAME" "$LOCK_TIMEOUT"; then
    log "Не удалось получить блокировку, возможно другой процесс уже работает"
    exit 0
  fi
  # Завершение работы - освобождение блокировки
  trap 'release_lock "$LOCK_NAME"; log "Блокировка освобождена"' EXIT

  log "=== Автоматическое обновление статусов ==="

  local weekplan_status="skip" registry_status="skip" memory_status="skip" dayplan_status="skip"

  if update_weekplan_statuses; then weekplan_status="ok"; else weekplan_status="fail"; fi
  if update_registry_statuses; then registry_status="ok"; else registry_status="fail"; fi
  if update_memory_statuses; then memory_status="ok"; else memory_status="fail"; fi
  if update_dayplan_statuses; then dayplan_status="ok"; else dayplan_status="fail"; fi

  write_log "$weekplan_status" "$registry_status" "$memory_status" "$dayplan_status"

  log "=== Готово ==="
  log "  weekplan=$weekplan_status  registry=$registry_status  memory=$memory_status  dayplan=$dayplan_status"
}

main "$@"