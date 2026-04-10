#!/bin/bash
# enhanced-logging.sh — Улучшенное логирование для Day Close процедур

set -euo pipefail

  # === КОНФИГУРАЦИЯ ===
  WORKSPACE_DIR="${WORKSPACE_DIR:-$HOME/IWE}"
  DS_STRATEGY="$WORKSPACE_DIR/DS-strategy"
  LOGS_DIR="$WORKSPACE_DIR/DS-agent-workspace/scheduler/logs"
  MAIN_LOG="$LOGS_DIR/day-close-enhanced.log"
  ERROR_LOG="$LOGS_DIR/day-close-errors.log"
  METRICS_LOG="$LOGS_DIR/day-close-metrics.log"
  DAILY_SUMMARY="$LOGS_DIR/daily-summary-$(date +%Y-%m-%d).log"
  # === /КОНФИГУРАЦИЯ ===

   # Подключаем утилиты блокировок
   source "$WORKSPACE_DIR/DS-exocortex/scripts/locking-utils.sh" || {
     echo "Ошибка: не удалось подключить locking-utils.sh"
     exit 1
   }

  # Конфигурация блокировок
  LOCK_NAME="enhanced-logging"
  LOCK_TIMEOUT=1800  # 30 минут

# Создаем директорию для логов если не существует
mkdir -p "$LOGS_DIR"

# Цвета
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${GREEN}[log]${NC} $1"; }
warn() { echo -e "${YELLOW}[warn]${NC} $1"; }
err() { echo -e "${RED}[error]${NC} $1" >&2; }
debug() { echo -e "${BLUE}[debug]${NC} $1"; }

# --- Запись в основной лог ---
write_main_log() {
  local level="$1"
  local message="$2"
  local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
  local script_name=$(basename "$0")
  
  echo "[$timestamp] [$level] [$script_name] $message" >> "$MAIN_LOG"
}

# --- Запись в лог ошибок ---
write_error_log() {
  local error_message="$1"
  local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
  local script_name=$(basename "$0")
  
  echo "[$timestamp] [ERROR] [$script_name] $error_message" >> "$ERROR_LOG"
}

# --- Запись метрик ---
write_metrics() {
  local metric_name="$1"
  local metric_value="$2"
  local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
  
  echo "[$timestamp] $metric_name: $metric_value" >> "$METRICS_LOG"
}

# --- Сбор метрик за день ---
collect_daily_metrics() {
  local today=$(date +%Y-%m-%d)
  
  # Подсчет коммитов за день
  local total_commits=0
  for repo in "$WORKSPACE_DIR"/DS-* "$WORKSPACE_DIR"/PACK-*; do
    [ -d "$repo/.git" ] || continue
    local repo_commits=$(git -C "$repo" log --since="today 00:00" --oneline --no-merges 2>/dev/null | wc -l)
    total_commits=$((total_commits + repo_commits))
  done
  
  # Подсчет файлов
  local changed_files=$(find "$WORKSPACE_DIR" -name "*.md" -newermt "today 00:00" 2>/dev/null | wc -l)
  
  # Подсчет новых РП
  local new_wps=0
  local wp_registry="$DS_STRATEGY/docs/WP-REGISTRY.md"
  if [ -f "$wp_registry" ]; then
    # Считаем количество РП, добавленных сегодня (это приближенная оценка)
    new_wps=$(grep -c "$(date '+%m-%d')" "$wp_registry" 2>/dev/null || echo 0)
  fi
  
  # Записываем метрики
  write_metrics "daily_commits" "$total_commits"
  write_metrics "changed_files" "$changed_files"
  write_metrics "new_wps" "$new_wps"
  write_metrics "active_repos" "$(echo $WORKSPACE_DIR/DS-* $WORKSPACE_DIR/PACK-* | wc -w)"
  
  # Возвращаем собранные метрики
  echo "$total_commits|$changed_files|$new_wps"
}

# --- Создание ежедневного дайджеста ---
create_daily_summary() {
  local metrics_data=$(collect_daily_metrics)
  local commits=$(echo "$metrics_data" | cut -d'|' -f1)
  local files=$(echo "$metrics_data" | cut -d'|' -f2)
  local wps=$(echo "$metrics_data" | cut -d'|' -f3)
  
  local today=$(date "+%Y-%m-%d")
  local summary_header="=== Ежедневный дайджест: $today ==="
  
  echo "$summary_header" > "$DAILY_SUMMARY"
  echo "Дата: $today" >> "$DAILY_SUMMARY"
  echo "Коммиты: $commits" >> "$DAILY_SUMMARY"
  echo "Измененных файлов: $files" >> "$DAILY_SUMMARY"
  echo "Новых РП: $wps" >> "$DAILY_SUMMARY"
  echo "Активных репозиториев: $(echo $WORKSPACE_DIR/DS-* $WORKSPACE_DIR/PACK-* | wc -w)" >> "$DAILY_SUMMARY"
  echo "" >> "$DAILY_SUMMARY"
  
  # Добавляем информацию о статусах РП
  echo "=== Статусы РП ===" >> "$DAILY_SUMMARY"
  local wp_registry="$DS_STRATEGY/docs/WP-REGISTRY.md"
  if [ -f "$wp_registry" ]; then
    grep -E "^\|.*\|.*\|.*\|.*\|.*\|$" "$wp_registry" | head -10 >> "$DAILY_SUMMARY"
  fi
  echo "" >> "$DAILY_SUMMARY"
  
  # Добавляем последние логи
  echo "=== Последние действия ===" >> "$DAILY_SUMMARY"
  tail -20 "$MAIN_LOG" >> "$DAILY_SUMMARY"
  
  write_main_log "INFO" "Создан дайджест за $today"
}

# --- Анализ логов за период ---
analyze_logs_period() {
  local days_back="${1:-7}"  # По умолчанию за 7 дней
  local analysis_file="$LOGS_DIR/log-analysis-$(date +%Y-%m-%d).txt"
  
  echo "=== Анализ логов за последние $days_back дней ===" > "$analysis_file"
  echo "Дата генерации: $(date)" >> "$analysis_file"
  echo "" >> "$analysis_file"
  
  # Анализ ошибок
  echo "=== Ошибки ===" >> "$analysis_file"
  grep -i "error\|fail\|critical" "$MAIN_LOG" | tail -20 >> "$analysis_file"
  echo "" >> "$analysis_file"
  
  # Анализ активности
  echo "=== Активность ===" >> "$analysis_file"
  grep "$(date -d "$days_back days ago" +%Y-%m-%d)" "$MAIN_LOG" | wc -l >> "$analysis_file"
  echo " записей за последние $days_back дней" >> "$analysis_file"
  echo "" >> "$analysis_file"
  
  # Анализ метрик
  echo "=== Метрики за период ===" >> "$analysis_file"
  tail -50 "$METRICS_LOG" >> "$analysis_file"
  
  write_main_log "INFO" "Проведен анализ логов за $days_back дней"
}

# --- Ротация логов ---
rotate_logs() {
  local max_size_mb=10
  local log_files=("$MAIN_LOG" "$ERROR_LOG" "$METRICS_LOG")
  
  for log_file in "${log_files[@]}"; do
    if [ -f "$log_file" ]; then
      local size_kb=$(du -k "$log_file" | cut -f1)
      local size_mb=$((size_kb / 1024))
      
      if [ "$size_mb" -gt "$max_size_mb" ]; then
        local backup_file="${log_file}.backup.$(date +%Y%m%d_%H%M%S)"
        mv "$log_file" "$backup_file"
        touch "$log_file"  # Создаем новый пустой файл
        write_main_log "INFO" "Ротация лога: $log_file -> $backup_file"
      fi
    fi
  done
}

# --- Мониторинг выполнения чеклиста ---
monitor_checklist_completion() {
  local checklist_file="$WORKSPACE_DIR/memory/protocol-close.md"
  if [ -f "$checklist_file" ]; then
    local total_items=$(grep -c "^[[:space:]]*-[[:space:]]*\[\]" "$checklist_file" 2>/dev/null || echo 0)
    local completed_items=$(grep -c "^[[:space:]]*-[[:space:]]*\[x\]" "$checklist_file" 2>/dev/null || echo 0)
    
    local completion_percent=0
    if [ "$total_items" -gt 0 ]; then
      completion_percent=$((completed_items * 100 / total_items))
    fi
    
    write_metrics "checklist_completion_percent" "$completion_percent"
    write_metrics "checklist_completed" "$completed_items"
    write_metrics "checklist_total" "$total_items"
    
    # Логируем, если выполнение чеклиста низкое
    if [ "$completion_percent" -lt 50 ]; then
      write_main_log "WARNING" "Низкое выполнение чеклиста Day Close: $completion_percent% ($completed_items/$total_items)"
    fi
  fi
}

# --- Отчет о производительности ---
generate_performance_report() {
  local report_file="$LOGS_DIR/performance-report-$(date +%Y-%m-%d).csv"
  
  # Заголовки CSV
  echo "timestamp,total_commits,changed_files,new_wps,checklist_completion,errors_count,warnings_count" > "$report_file"
  
  # Собираем данные
  local metrics_data=$(collect_daily_metrics)
  local commits=$(echo "$metrics_data" | cut -d'|' -f1)
  local files=$(echo "$metrics_data" | cut -d'|' -f2)
  local wps=$(echo "$metrics_data" | cut -d'|' -f3)
  
  # Получаем процент выполнения чеклиста
  local checklist_file="$WORKSPACE_DIR/memory/protocol-close.md"
  local total_items=$(grep -c "^[[:space:]]*-[[:space:]]*\[\]" "$checklist_file" 2>/dev/null || echo 0)
  local completed_items=$(grep -c "^[[:space:]]*-[[:space:]]*\[x\]" "$checklist_file" 2>/dev/null || echo 0)
  local completion_percent=0
  if [ "$total_items" -gt 0 ]; then
    completion_percent=$((completed_items * 100 / total_items))
  fi
  
  # Подсчет ошибок и предупреждений
  local errors_count=$(grep -c "ERROR\|FAIL\|CRITICAL" "$MAIN_LOG" 2>/dev/null || echo 0)
  local warnings_count=$(grep -c "WARNING\|WARN" "$MAIN_LOG" 2>/dev/null || echo 0)
  
  # Записываем строку отчета
  echo "$(date +%Y-%m-%d_%H:%M:%S),$commits,$files,$wps,$completion_percent,$errors_count,$warnings_count" >> "$report_file"
  
  write_main_log "INFO" "Сгенерирован отчет о производительности: $report_file"
}

# --- Main ---
main() {
  # Проверяем, занята ли блокировка планировщиком
  if is_locked "scheduler-operation"; then
    log "Планировщик занят, откладываем выполнение логирования"
    exit 0
  fi

  # Пытаемся получить блокировку для выполнения
  if ! acquire_lock "$LOCK_NAME" "$LOCK_TIMEOUT"; then
    log "Не удалось получить блокировку, возможно другой процесс уже работает"
    exit 0
  fi
  # Завершение работы - освобождение блокировки
  trap 'release_lock "$LOCK_NAME"; log "Блокировка освобождена"' EXIT

  local action="${1:-all}"

  case "$action" in
    "init")
      # Инициализация системы логирования
      rotate_logs
      write_main_log "INFO" "Система логирования инициализирована"
      ;;
    "daily")
      # Ежедневные операции
      rotate_logs
      create_daily_summary
      monitor_checklist_completion
      generate_performance_report
      write_main_log "INFO" "Ежедневные операции логирования завершены"
      ;;
    "analyze")
      # Анализ за период
      local days="${2:-7}"
      analyze_logs_period "$days"
      ;;
    "metrics")
      # Сбор метрик
      collect_daily_metrics
      ;;
    "all")
      # Все операции
      rotate_logs
      collect_daily_metrics
      create_daily_summary
      monitor_checklist_completion
      generate_performance_report
      local days="${2:-7}"
      analyze_logs_period "$days"
      write_main_log "INFO" "Все операции логирования завершены"
      ;;
    *)
      echo "Использование: $0 [init|daily|analyze|metrics|all]"
      echo "  init     - инициализация системы логирования"
      echo "  daily    - ежедневные операции"
      echo "  analyze  - анализ логов (дней, по умолчанию 7)"
      echo "  metrics  - сбор метрик"
      echo "  all      - все операции"
      exit 1
      ;;
  esac
}

main "$@"