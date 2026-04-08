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

# === Автоматическая синхронизация изменений в репозитории ===
log_to_file "=== Начало автоматической синхронизации изменений ==="

sync_repositories() {
    local success_count=0
    local total_count=0
    
    # Синхронизируем все DS-* репозитории
    for repo in "$WORKSPACE_DIR"/DS-*; do
        if [ -d "$repo/.git" ]; then
            total_count=$((total_count + 1))
            local repo_name=$(basename "$repo")
            
            log_to_file "Синхронизация репозитория: $repo_name"
            
            cd "$repo"
            
            # Сохраняем текущее состояние на случай конфликта
            local stash_count_before=$(git stash list 2>/dev/null | wc -l)
            git stash -u --quiet 2>/dev/null || true
            local current_stash_count=$(git stash list 2>/dev/null | wc -l)
            
            # Пытаемся обновить локальный репозиторий
            if ! git pull --quiet 2>/dev/null; then
                if ! git pull --rebase --quiet 2>/dev/null; then
                    log_to_file "WARN: pull failed for $repo_name (offline? conflict?)"
                    # Восстанавливаем изменения при ошибке
                    if [ "$current_stash_count" -gt "$stash_count_before" ]; then
                        git stash pop --quiet 2>/dev/null || log_to_file "WARN: stash pop failed for $repo_name"
                    fi
                    continue
                fi
            fi
            
            # Восстанавливаем изменения из стэша
            local current_stash_count_after=$(git stash list 2>/dev/null | wc -l)
            if [ "$current_stash_count_after" -gt "$stash_count_before" ]; then
                git stash pop --quiet 2>/dev/null || log_to_file "WARN: stash pop failed for $repo_name"
            fi
            
            # Сбрасываем индекс и добавляем только наши изменения
            git reset --quiet 2>/dev/null || true
            
            # Добавляем все изменения
            git add -A 2>/dev/null || true
            
            # Проверяем, есть ли изменения для коммита
            if ! git diff --cached --quiet 2>/dev/null; then
                # Делаем коммит с автоматическим сообщением
                if git commit -m "auto: night-sync $(date +%Y-%m-%d) - day close procedures" --quiet 2>/dev/null; then
                    log_to_file "✓ Changes committed in $repo_name"
                    
                    # Пытаемся запушить изменения
                    if git push --quiet 2>/dev/null; then
                        log_to_file "✓ Changes pushed to $repo_name"
                        success_count=$((success_count + 1))
                    else
                        log_to_file "✗ Push failed for $repo_name (offline? permission denied?)"
                    fi
                else
                    log_to_file "✗ Commit failed for $repo_name (no changes or conflict?)"
                fi
            else
                log_to_file "• No changes to commit in $repo_name"
                success_count=$((success_count + 1))  # Считаем как успех если нет изменений
            fi
        fi
    done
    
    log_to_file "Синхронизация завершена: $success_count/$total_count репозиториев успешно синхронизировано"
}

# Выполняем синхронизацию только если были операции
if [ "$HAS_COMMITS_TODAY" = true ]; then
    sync_repositories
fi

log_to_file "=== Завершение автоматического выполнения Day Close скриптов ==="
