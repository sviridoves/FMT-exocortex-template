#!/bin/bash
# locking-utils.sh — Утилиты для координации между cron и планировщиком

set -euo pipefail

LOCK_DIR="${LOCK_DIR:-/tmp/iwe-locks}"
mkdir -p "$LOCK_DIR"

# Проверяем доступность директории для записи
if [ ! -w "$LOCK_DIR" ]; then
    echo "Ошибка: директория блокировок недоступна для записи: $LOCK_DIR" >&2
    exit 1
fi

# Функция получения блокировки
acquire_lock() {
    local lock_name="$1"
    local lock_timeout="${2:-3600}"  # 1 час по умолчанию
    
    local lock_file="$LOCK_DIR/$lock_name.lock"
    local lock_pid_file="$lock_file.pid"
    local current_time=$(date +%s)
    
    # Проверяем, существует ли старая блокировка
    if [ -f "$lock_pid_file" ]; then
        local old_pid
        old_pid=$(cat "$lock_pid_file" 2>/dev/null || echo "")
        
        if [ -n "$old_pid" ] && kill -0 "$old_pid" 2>/dev/null; then
            # Процесс все еще жив, проверяем время
            if [ -f "$lock_file" ]; then
                local lock_time
                lock_time=$(stat -c %Y "$lock_file" 2>/dev/null || stat -f %m "$lock_file" 2>/dev/null || echo "$current_time")
                
                if [ $((current_time - lock_time)) -lt $lock_timeout ]; then
                    # Блокировка все еще действует
                    echo "FAILED"  # Не удалось получить блокировку
                    return 1
                else
                    # Блокировка просрочена, освобождаем
                    rm -f "$lock_file" "$lock_pid_file" 2>/dev/null || true
                fi
            fi
        else
            # Процесс больше не существует, освобождаем блокировку
            rm -f "$lock_file" "$lock_pid_file" 2>/dev/null || true
        fi
    fi
    
    # Пробуем создать блокировку
    echo "$current_time" > "$lock_file" 2>/dev/null || {
        echo "FAILED"
        return 1
    }
    
    echo $$ > "$lock_pid_file" 2>/dev/null || {
        rm -f "$lock_file" 2>/dev/null || true
        echo "FAILED"
        return 1
    }
    
    echo "SUCCESS"  # Блокировка получена
    return 0
}

# Функция освобождения блокировки
release_lock() {
    local lock_name="$1"
    local lock_file="$LOCK_DIR/$lock_name.lock"
    local lock_pid_file="$lock_file.pid"
    
    # Проверяем, это наша ли блокировка
    if [ -f "$lock_pid_file" ]; then
        local pid
        pid=$(cat "$lock_pid_file" 2>/dev/null || echo "")
        if [ "$pid" = "$$" ]; then
            rm -f "$lock_file" "$lock_pid_file" 2>/dev/null || true
        fi
    fi
}

# Функция проверки, занята ли блокировка
is_locked() {
    local lock_name="$1"
    local lock_timeout="${2:-3600}"
    local lock_file="$LOCK_DIR/$lock_name.lock"
    local lock_pid_file="$lock_file.pid"
    
    if [ -f "$lock_pid_file" ]; then
        local pid
        pid=$(cat "$lock_pid_file" 2>/dev/null || echo "")
        
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            if [ -f "$lock_file" ]; then
                local current_time=$(date +%s)
                local lock_time
                lock_time=$(stat -c %Y "$lock_file" 2>/dev/null || stat -f %m "$lock_file" 2>/dev/null || echo "$current_time")
                
                if [ $((current_time - lock_time)) -lt $lock_timeout ]; then
                    return 0  # Занято
                fi
            fi
        fi
    fi
    
    return 1  # Свободно
}

# Использование:
# acquire_lock "scheduler-operation" 3600 && echo "Lock acquired" || echo "Lock failed"
# release_lock "scheduler-operation"
# is_locked "scheduler-operation" && echo "Busy" || echo "Free"