#!/bin/bash
# auto-archive.sh — Автоматическая архивация завершенных файлов

set -euo pipefail

  # === КОНФИГУРАЦИЯ ===
  WORKSPACE_DIR="${WORKSPACE_DIR:-$HOME/IWE}"
  DS_STRATEGY="$WORKSPACE_DIR/DS-strategy"
  ARCHIVE_DIR="$DS_STRATEGY/archive/wp-contexts"
  INBOX_DIR="$DS_STRATEGY/inbox"
  LOG_FILE="$WORKSPACE_DIR/DS-agent-workspace/scheduler/auto-archive.log"
  # === /КОНФИГУРАЦИЯ ===

   # Подключаем утилиты блокировок
   source "$WORKSPACE_DIR/DS-exocortex/scripts/locking-utils.sh" || {
     echo "Ошибка: не удалось подключить locking-utils.sh"
     exit 1
   }

  # Конфигурация блокировок
  LOCK_NAME="auto-archive"
  LOCK_TIMEOUT=1800  # 30 минут

# Цвета
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log() { echo -e "${GREEN}[auto-archive]${NC} $1"; }
warn() { echo -e "${YELLOW}[auto-archive]${NC} $1"; }
err() { echo -e "${RED}[auto-archive]${NC} $1" >&2; }

# --- Архивация завершенных WP context файлов ---
archive_completed_wp_contexts() {
  log "Архивация завершенных WP context файлов..."
  
  local archived_count=0
  local processed_count=0
  
  # Создаем директорию архива если не существует
  mkdir -p "$ARCHIVE_DIR"
  
  # Обрабатываем все WP файлы в inbox
  for wp_file in "$INBOX_DIR"/WP-*-*.md; do
    [ -f "$wp_file" ] || continue
    
    processed_count=$((processed_count + 1))
    local filename=$(basename "$wp_file")
    
    # Проверяем, завершен ли РП по различным признакам
    if is_wp_completed "$wp_file"; then
      # Архивируем файл
      local archive_path="$ARCHIVE_DIR/$filename"
      mv "$wp_file" "$archive_path"
      
      # Проверяем, успешно ли перемещено
      if [ -f "$archive_path" ]; then
        archived_count=$((archived_count + 1))
        log "  Архивирован: $filename"
        
        # Добавляем запись в лог архивации
        echo "$(date '+%Y-%m-%d %H:%M') | ARCHIVED | $filename | moved to $ARCHIVE_DIR" >> "$LOG_FILE"
      else
        warn "  Ошибка архивации: $filename"
      fi
    else
      log "  Пропущен (не завершен): $filename"
    fi
  done
  
  log "Обработано: $processed_count файлов, заархивировано: $archived_count"
}

# --- Проверка завершения РП ---
is_wp_completed() {
  local wp_file="$1"
  
   # Проверяем различные признаки завершения РП
   if grep -q "done\|заверш\|completed\|готов\|finished\|закрыт\|closed" "$wp_file"; then
     return 0
   fi
   
   # Проверяем YAML frontmatter на статус done
   if grep -q "^status:.*done" "$wp_file"; then
     return 0
   fi
  
  # Проверяем наличие специфичных строк, указывающих на завершение
  if grep -q "✅\|✓\|Готово\|Завершено\|Complete\|Done\|Closed" "$wp_file"; then
    return 0
  fi
  
  # Проверяем, есть ли в файле пометки о завершении
  if grep -qi "статус.*done\|status.*complete\|status.*closed\|результат.*готов" "$wp_file"; then
    return 0
  fi
  
  return 1
}

# --- Архивация старых DayPlan файлов ---
archive_old_dayplans() {
  log "Архивация старых DayPlan файлов..."
  
  local dayplans_archived=0
  
  # Находим DayPlan файлы старше 30 дней в current директории
  find "$DS_STRATEGY/current" -name "DayPlan*.md" -type f -mtime +30 | while read -r old_dayplan; do
    local filename=$(basename "$old_dayplan")
    local archive_path="$ARCHIVE_DIR/$filename"
    
    # Перемещаем в архив
    if mv "$old_dayplan" "$archive_path" 2>/dev/null; then
      dayplans_archived=$((dayplans_archived + 1))
      log "  Архивирован DayPlan: $filename"
      echo "$(date '+%Y-%m-%d %H:%M') | ARCHIVED_DAYPLAN | $filename | moved to $ARCHIVE_DIR" >> "$LOG_FILE"
    fi
  done
  
  log "Заархивировано DayPlan файлов: $dayplans_archived"
}

# --- Очистка MEMORY.md от завершенных РП ---
cleanup_memory_md() {
  log "Очистка MEMORY.md от завершенных РП..."
  
  local memory_file="$WORKSPACE_DIR/DS-exocortex/memory/MEMORY.md"
  if [ ! -f "$memory_file" ]; then
    warn "MEMORY.md не найден: $memory_file"
    return 0
  fi
  
  local original_lines=$(wc -l < "$memory_file")
  local temp_file=$(mktemp)
  
  # Флаг для отслеживания секции РП
  local in_wp_section=false
  local removed_count=0
  local line_num=0
  
  while IFS= read -r line || [[ -n "$line" ]]; do
    line_num=$((line_num + 1))
    
    # Проверяем начало секции РП текущей недели
    if [[ "$line" =~ ^##.*РП.*текущей.недели ]]; then
      in_wp_section=true
      echo "$line" >> "$temp_file"
    # Проверяем конец секции РП (до следующего заголовка второго уровня)
    elif [[ "$line" =~ ^##\ [^#] ]] && [ "$in_wp_section" = true ]; then
      in_wp_section=false
      echo "$line" >> "$temp_file"
    # Внутри секции РП - проверяем строки с РП
    elif [ "$in_wp_section" = true ] && [[ "$line" =~ ^\|\ [0-9]+.*\| ]]; then
  # Проверяем, содержит ли строка статус done
  if [[ "$line" =~ \|.*done.*\| ]] || [[ "$line" =~ \|.*✅.*\| ]] || [[ "$line" =~ \|.*closed.*\| ]]; then
        # Пропускаем строку (не добавляем в новый файл)
        removed_count=$((removed_count + 1))
        log "  Удален завершенный РП из MEMORY.md: $(echo "$line" | cut -d'|' -f3 | xargs)"
      else
        # Добавляем строку в новый файл
        echo "$line" >> "$temp_file"
      fi
    else
      # Все остальные строки добавляем как есть
      echo "$line" >> "$temp_file"
    fi
  done < "$memory_file"
  
  # Только если были удаления, заменяем оригинальный файл
  if [ $removed_count -gt 0 ]; then
    mv "$temp_file" "$memory_file"
    local new_lines=$(wc -l < "$memory_file")
    log "MEMORY.md очищен - удалено $removed_count завершенных РП, строк: $original_lines -> $new_lines"
    
    # Добавляем запись в лог
    echo "$(date '+%Y-%m-%d %H:%M') | CLEANUP_MEMORY | removed $removed_count completed WPs | lines: $original_lines -> $new_lines" >> "$LOG_FILE"
  else
    rm "$temp_file"
    log "MEMORY.md не изменен - не найдено завершенных РП для удаления"
  fi
}

# --- Лог ---
write_log() {
  local date_str
  date_str=$(date "+%Y-%m-%d %H:%M")
  mkdir -p "$(dirname "$LOG_FILE")"
  echo "$date_str | auto-archive | contexts_archived=$1 dayplans_archived=$2 memory_cleaned=$3" >> "$LOG_FILE"
}

# --- Main ---
main() {
  # Проверяем, занята ли блокировка планировщиком
  if is_locked "scheduler-operation"; then
    log "Планировщик занят, откладываем выполнение архивации"
    exit 0
  fi

  # Пытаемся получить блокировку для выполнения
  if ! acquire_lock "$LOCK_NAME" "$LOCK_TIMEOUT"; then
    log "Не удалось получить блокировку, возможно другой процесс уже работает"
    exit 0
  fi
  # Завершение работы - освобождение блокировки
  trap 'release_lock "$LOCK_NAME"; log "Блокировка освобождена"' EXIT

  log "=== Автоматическая архивация ==="

  local contexts_archived=0 dayplans_archived=0 memory_cleaned=0

  # Запускаем архивацию в фоне и сохраняем PID
  archive_completed_wp_contexts &
  local contexts_pid=$!
  
  # Архивация старых DayPlan файлов
  archive_old_dayplans &
  local dayplans_pid=$!
  
  # Ждем завершения архивации WP контекстов
  wait "$contexts_pid"
  contexts_archived=$(grep -c "ARCHIVED |" "$LOG_FILE" 2>/dev/null | tail -1 || echo 0)
  
  # Ждем завершения архивации DayPlan файлов
  wait "$dayplans_pid"
  dayplans_archived=$(grep -c "ARCHIVED_DAYPLAN |" "$LOG_FILE" 2>/dev/null | tail -1 || echo 0)
  
  # Очистка MEMORY.md
  cleanup_memory_md
  memory_cleaned=1

  write_log "$contexts_archived" "$dayplans_archived" "$memory_cleaned"

  log "=== Готово ==="
  log "  wp_contexts_archived=$contexts_archived  dayplans_archived=$dayplans_archived  memory_cleaned=$memory_cleaned"
}

main "$@"