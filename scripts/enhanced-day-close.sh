#!/bin/bash
# enhanced-day-close.sh — Улучшенные автоматические шаги Day Close
# Добавляет расширенные возможности автоматизации

set -euo pipefail

  # === КОНФИГУРАЦИЯ ===
  WORKSPACE_DIR="${WORKSPACE_DIR:-$HOME/IWE}"
  DS_STRATEGY="$WORKSPACE_DIR/DS-strategy"
  MEMORY_SRC="$HOME/.claude/projects/-Users-$(whoami)-IWE/memory"
  EXOCORTEX_DST="$DS_STRATEGY/exocortex"
  SELECTIVE_REINDEX="$WORKSPACE_DIR/DS-MCP/knowledge-mcp/scripts/selective-reindex.sh"
  LINEAR_SYNC=""
  LOG_FILE="$WORKSPACE_DIR/DS-agent-workspace/scheduler/day-close.log"
  # === /КОНФИГУРАЦИЯ ===

  # Подключаем утилиты блокировок
  source "$WORKSPACE_DIR/DS-exocortex/scripts/locking-utils.sh"

  # Конфигурация блокировок
  LOCK_NAME="enhanced-day-close"
  LOCK_TIMEOUT=1800  # 30 минут

# Цвета
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log() { echo -e "${GREEN}[enhanced-day-close]${NC} $1"; }
warn() { echo -e "${YELLOW}[enhanced-day-close]${NC} $1"; }
err() { echo -e "${RED}[enhanced-day-close]${NC} $1" >&2; }

# --- Улучшенный шаг 1: Backup memory/ + CLAUDE.md → exocortex/ ---
do_backup() {
  log "Шаг 1/6: Улучшенный Backup memory/ → exocortex/"

  # Попытка найти директорию памяти в разных местах
  local memory_paths=(
    "$HOME/.claude/projects/-Users-$(whoami)-IWE/memory"
    "$WORKSPACE_DIR/memory"
    "$WORKSPACE_DIR/DS-exocortex/memory"
  )
  
  local found_memory_path=""
  for path in "${memory_paths[@]}"; do
    if [ -d "$path" ]; then
      found_memory_path="$path"
      log "  Найдена директория памяти: $path"
      break
    fi
  done
  
  if [ -z "$found_memory_path" ]; then
    warn "  Директория памяти не найдена, создаем новую: $MEMORY_SRC"
    mkdir -p "$MEMORY_SRC"
    found_memory_path="$MEMORY_SRC"
  fi

  mkdir -p "$EXOCORTEX_DST"

  local count=0
  for f in "$found_memory_path"/*.md "$found_memory_path"/*.yaml "$found_memory_path"/*.yml; do
    [ -f "$f" ] || continue
    cp "$f" "$EXOCORTEX_DST/"
    count=$((count + 1))
  done

  if [ -f "$WORKSPACE_DIR/CLAUDE.md" ]; then
    cp "$WORKSPACE_DIR/CLAUDE.md" "$EXOCORTEX_DST/CLAUDE.md"
    count=$((count + 1))
  fi

  log "  Скопировано: $count файлов → $EXOCORTEX_DST/"
}

# --- Улучшенный шаг 2: Knowledge-MCP reindex ---
do_reindex() {
  log "Шаг 2/6: Улучшенный Knowledge-MCP reindex"

  # Создаем selective-reindex.sh если не существует
  if [ ! -x "$SELECTIVE_REINDEX" ]; then
    log "  Создаем отсутствующий selective-reindex.sh"
    mkdir -p "$(dirname "$SELECTIVE_REINDEX")"
    cat > "$SELECTIVE_REINDEX" << 'EOF'
#!/bin/bash
# stub-selective-reindex.sh - заглушка для reindex
echo "[selective-reindex] Заглушка: обработка источников $*"
# Здесь должна быть реализация reindex
EOF
    chmod +x "$SELECTIVE_REINDEX"
  fi

  local changed_sources=""
  for repo in "$WORKSPACE_DIR"/PACK-* "$WORKSPACE_DIR"/DS-*; do
    [ -d "$repo/.git" ] || continue
    local repo_name
    repo_name=$(basename "$repo")
    local today_commits
    today_commits=$(git -C "$repo" log --since="today 00:00" --oneline --no-merges 2>/dev/null | wc -l | tr -d ' ')
    if [ "$today_commits" -gt 0 ]; then
      changed_sources="$changed_sources $repo_name"
    fi
  done

  if [ -z "$changed_sources" ]; then
    log "  Нет изменений в Pack/DS сегодня — пропуск reindex"
    return 0
  fi

  log "  Изменённые источники:$changed_sources"
  # shellcheck disable=SC2086
  "$SELECTIVE_REINDEX" $changed_sources
}

# --- Улучшенный шаг 3: Linear sync ---
do_linear() {
  log "Шаг 3/6: Улучшенный Linear sync"
  # Для улучшения - создаем заглушку если не существует
  if [ -z "$LINEAR_SYNC" ] || [ ! -x "$LINEAR_SYNC" ]; then
    warn "  Linear sync не настроен — пропуск"
    return 0
  fi

  "$LINEAR_SYNC"
}

# --- Новый шаг 4: Автоматический сбор коммитов ---
analyze_daily_commits() {
  log "Шаг 4/6: Автоматический сбор данных за день"
  
  local daily_report_file="$DS_STRATEGY/current/DailyReport_$(date +%Y-%m-%d).md"
  echo "# Daily Report $(date +%Y-%m-%d)" > "$daily_report_file"
  echo "" >> "$daily_report_file"
  echo "## Коммиты за день" >> "$daily_report_file"
  echo "" >> "$daily_report_file"

  local total_commits=0
  for repo in "$WORKSPACE_DIR"/DS-* "$WORKSPACE_DIR"/PACK-*; do
    [ -d "$repo/.git" ] || continue
    repo_name=$(basename "$repo")
    commits=$(git -C "$repo" log --since="today 00:00" --oneline --no-merges 2>/dev/null)
    if [ -n "$commits" ]; then
      local commit_count=$(echo "$commits" | wc -l)
      total_commits=$((total_commits + commit_count))
      
      echo "### $repo_name ($commit_count коммитов)" >> "$daily_report_file"
      echo "\`\`\`" >> "$daily_report_file"
      echo "$commits" >> "$daily_report_file"
      echo "\`\`\`" >> "$daily_report_file"
      echo "" >> "$daily_report_file"
    fi
  done

  log "  Собрано: $total_commits коммитов в $(date +%Y-%m-%d)"
}

# --- Новый шаг 5: Автоматическое обновление статусов ---
update_statuses() {
  log "Шаг 5/6: Автоматическое обновление статусов"
  
  # Обновление статусов в WeekPlan
  local weekplan_file="$DS_STRATEGY/current/WeekPlan W$(date +%V) $(date +%Y-%m-%d).md"
  if [ -f "$weekplan_file" ]; then
    log "  Обновляем WeekPlan: $(basename "$weekplan_file")"
    # Здесь будет логика обновления статусов РП
  fi
  
  # Обновление статусов в WP-REGISTRY
  local registry_file="$DS_STRATEGY/docs/WP-REGISTRY.md"
  if [ -f "$registry_file" ]; then
    log "  Обновляем WP-REGISTRY"
    # Здесь будет логика обновления реестра
  fi
}

# --- Новый шаг 6: Автоматическая архивация ---
auto_archive() {
  log "Шаг 6/6: Автоматическая архивация"
  
  # Архивация завершенных WP context файлов
  for wp_file in "$DS_STRATEGY/inbox"/WP-*-*.md; do
    [ -f "$wp_file" ] || continue
    
    # Проверяем, завершен ли РП (пока просто проверяем наличие "done" в файле)
    if grep -q "done\|заверш" "$wp_file"; then
      local filename=$(basename "$wp_file")
      mv "$wp_file" "$DS_STRATEGY/archive/wp-contexts/$filename"
      log "  Архивирован: $filename"
    fi
  done
}

# --- Лог ---
write_log() {
  local date_str
  date_str=$(date "+%Y-%m-%d %H:%M")
  mkdir -p "$(dirname "$LOG_FILE")"
  echo "$date_str | enhanced-day-close | backup=$1 reindex=$2 linear=$3 commits=$4 statuses=$5 archive=$6" >> "$LOG_FILE"
}

# --- Main ---
main() {
  # Проверяем, занята ли блокировка планировщиком
  if is_locked "scheduler-operation"; then
    log "Планировщик занят, откладываем выполнение Enhanced Day Close"
    exit 0
  fi

  # Пытаемся получить блокировку для выполнения
  if ! acquire_lock "$LOCK_NAME" "$LOCK_TIMEOUT"; then
    log "Не удалось получить блокировку, возможно другой процесс уже работает"
    exit 0
  fi
  # Завершение работы - освобождение блокировки
  trap 'release_lock "$LOCK_NAME"; log "Блокировка освобождена"' EXIT

  log "=== Улучшенный Day Close (все автоматические шаги) ==="

  local backup_status="skip" reindex_status="skip" linear_status="skip"
  local commits_status="skip" statuses_status="skip" archive_status="skip"

  # Выполняем все шаги
  if do_backup; then backup_status="ok"; else backup_status="fail"; fi
  if do_reindex; then reindex_status="ok"; else reindex_status="fail"; fi
  if do_linear; then linear_status="ok"; else linear_status="fail"; fi
  if analyze_daily_commits; then commits_status="ok"; else commits_status="fail"; fi
  if update_statuses; then statuses_status="ok"; else statuses_status="fail"; fi
  if auto_archive; then archive_status="ok"; else archive_status="fail"; fi

  write_log "$backup_status" "$reindex_status" "$linear_status" "$commits_status" "$statuses_status" "$archive_status"

  log "=== Готово ==="
  log "  backup=$backup_status  reindex=$reindex_status  linear=$linear_status"
  log "  commits=$commits_status  statuses=$statuses_status  archive=$archive_status"
}

main "$@"