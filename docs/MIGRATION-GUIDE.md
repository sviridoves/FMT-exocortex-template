# Перенос IWE на другое рабочее место

> **Принцип:** Все репозитории в GitHub (приватные) = source-of-truth. Перенос = git clone + копирование локальных файлов.
> **Время:** 30-60 мин (зависит от сети и количества репо).

---

## ЧАСТЬ 1: Старый компьютер — подготовка

### Шаг 1. Зафиксируй все репозитории

Выполни в терминале на **старом** компьютере:

```bash
cd ~/IWE

# Закоммить и запушь все изменения во всех репо
for repo in DS-exocortex DS-strategy DS-Jet DS-CB DS-Alrosa DS-ChIB DS-SelfMade DS-Severstal DS-RandD_IaC DS-TG_blog DS-ChIB; do
  if [ -d "$repo/.git" ]; then
    echo "=== $repo ==="
    cd ~/IWE/$repo
    git add -A
    git status --short
    echo "---"
    read -p "Закоммить? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
      git commit -m "chore: checkpoint before migration on $(date +%Y-%m-%d)"
      git push
      echo "✓ $repo запушен"
    fi
  fi
done
```

> Если нужно просто запушить всё без вопросов — убери блок `read -p` и `if`.

### Шаг 2. Проверь что всё на месте

```bash
cd ~/IWE
for repo in DS-exocortex DS-strategy DS-Jet DS-CB DS-Alrosa DS-ChIB DS-TG_blog; do
  if [ -d "$repo/.git" ]; then
    echo "$repo: $(git -C $repo log --oneline -1)"
  fi
done
```

Убедись что последний коммит — свежий.

### Шаг 3. Подготовь список локальных данных

Запиши себе (скопируй в файл или заметки):

```bash
# Проверь что существует
echo "--- Локальные файлы ---"
ls -la ~/.claude/projects/*/memory/MEMORY.md 2>/dev/null
ls -la ~/IWE/DS-exocortex/.exocortex.env 2>/dev/null
ls -la ~/IWE/DS-exocortex/.mcp.json 2>/dev/null
ls -la ~/IWE/DS-exocortex/.secrets/ 2>/dev/null
ls -la ~/.wakatime.cfg 2>/dev/null
launchctl list 2>/dev/null | grep -E "strategist|extractor|scheduler"
```

---

## ЧАСТЬ 2: Новый компьютер — установка

### Шаг 4. Установи базовые инструменты

На **новом** компьютере:

```bash
# 4.1 Homebrew (только macOS)
brew --version || /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# 4.2 Git
git --version || xcode-select --install  # macOS
# sudo apt install git  # Linux

# 4.3 Node.js (v18+)
node --version || brew install node  # macOS
# curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash - && sudo apt install -y nodejs  # Linux

# 4.4 GitHub CLI + авторизация
gh --version || brew install gh  # macOS
gh auth login  # выбери GitHub.com → HTTPS → Login with a web browser

# 4.5 Claude Code CLI
npm install -g @anthropic-ai/claude-code
claude --version

# 4.6 WakaTime CLI (опционально, для трекинга)
# См. SETUP-GUIDE.md §4 или скажи Claude Code: /setup-wakatime
```

### Шаг 5. Создай рабочую папку и клонируй шаблон

```bash
mkdir -p ~/IWE
cd ~/IWE

# Форкни шаблон и склонируй
gh repo fork TserenTserenov/FMT-exocortex-template --clone
cd FMT-exocortex-template
```

### Шаг 6. Запусти установку

```bash
bash setup.sh
```

Скрипт спросит:

| Вопрос | Что ввести |
|--------|-----------|
| GitHub username | Твой логин (sviridoves) |
| Workspace directory | Enter (определится автоматически) |
| Claude CLI path | Enter (определится автоматически) |
| Strategist launch hour (UTC) | 4 (если 7:00 MSK) |
| Timezone description | 7:00 MSK |

### Шаг 7. Клонируй свои репозитории

```bash
cd ~/IWE
gh repo clone sviridoves/DS-strategy
gh repo clone sviridoves/DS-Jet
gh repo clone sviridoves/DS-CB
gh repo clone sviridoves/DS-Alrosa
gh repo clone sviridoves/DS-ChIB
gh repo clone sviridoves/DS-TG_blog
# Добавь другие DS-репо по необходимости
```

---

## ЧАСТЬ 3: Перенос локальных данных

### Шаг 8. Скопируй MEMORY.md

MEMORY.md не хранится в Git — это оперативная память Claude Code.

**Вариант A — через scp (если оба компа в одной сети):**

```bash
# На НОВОМ компьютере:
mkdir -p ~/.claude/projects/-home-sviridov-IWE/memory
scp sviridov@OLD_IP:~/.claude/projects/-home-sviridov-IWE/memory/MEMORY.md ~/.claude/projects/-home-sviridov-IWE/memory/
```

**Вариант B — через флешку/облако:**

1. На старом: `cp ~/.claude/projects/*/memory/MEMORY.md ~/Desktop/`
2. Перенеси файл на новый компьютер
3. На новом: `cp ~/Desktop/MEMORY.md ~/.claude/projects/-home-sviridov-IWE/memory/`

**Вариант C — вручную:**

Скажи Claude Code на новом компьютере: «Восстанови MEMORY.md из последнего состояния» — он может прочитать историю коммитов.

### Шаг 9. Перенеси конфиг экзокортекса

```bash
# Вариант A — scp:
scp sviridov@OLD_IP:~/IWE/DS-exocortex/.exocortex.env ~/IWE/DS-exocortex/
scp sviridov@OLD_IP:~/IWE/DS-exocortex/.mcp.json ~/IWE/DS-exocortex/

# Вариант B — пересоздать:
cd ~/IWE/DS-exocortex
bash setup.sh --validate  # подскажет что нужно заполнить
```

### Шаг 10. Перенеси secrets

```bash
# Вариант A — scp:
scp -r sviridov@OLD_IP:~/IWE/DS-exocortex/.secrets/ ~/IWE/DS-exocortex/

# Вариант B — перегенерировать OAuth:
bash ~/IWE/DS-exocortex/setup/optional/setup-calendar.sh  # Google Calendar
# MCP-серверы добавить через claude.ai/settings/connectors
```

### Шаг 11. Перенеси personal файлы

```bash
# Для каждого DS-репо:
for repo in DS-strategy DS-Jet DS-CB DS-Alrosa DS-ChIB DS-TG_blog; do
  if [ -d "$repo/.git" ]; then
    scp -r sviridov@OLD_IP:~/IWE/$repo/personal/ ~/IWE/$repo/personal/ 2>/dev/null
  fi
done
```

---

## ЧАСТЬ 4: Настройка агентов

### Шаг 12. Переустанови агентов (launchd/cron)

```bash
cd ~/IWE/DS-exocortex

# Стратег (утренние планы + ревью)
bash roles/strategist/install.sh

# Экстрактор (опционально)
bash roles/extractor/install.sh

# Синхронизатор (опционально)
bash roles/synchronizer/install.sh
```

Проверь:

```bash
# macOS
launchctl list | grep -E "strategist|extractor|scheduler"

# Linux
crontab -l | grep -E "strategist|extractor|scheduler"
```

### Шаг 13. Подключи MCP-серверы

1. Открой https://claude.ai/settings/connectors
2. Добавь: `https://knowledge-mcp.aisystant.workers.dev/mcp`
3. Добавь: `https://digital-twin-mcp.aisystant.workers.dev/mcp`
4. Перезапусти Claude Code

Проверь: в Claude Code набери `/mcp` — оба сервера должны быть Connected.

### Шаг 14. Настрой WakaTime (если использовал)

```bash
# Установить CLI
# См. SETUP-GUIDE.md §4

# Или скопировать конфиг
scp sviridov@OLD_IP:~/.wakatime.cfg ~/.wakatime.cfg

# Или получить новый API key: https://wakatime.com/settings/api-key
```

---

## ЧАСТЬ 5: Проверка

### Шаг 15. Валидация установки

```bash
cd ~/IWE/DS-exocortex
bash setup.sh --validate
```

Должно показать всё OK. Если есть ошибки — следуй подсказкам.

### Шаг 16. Тестовая сессия

```bash
cd ~/IWE
claude
```

Скажи:

> «Проведи проверку после переноса: проверяй все репо, MEMORY.md, MCP-серверы, агентов»

Claude должен:
- Прочитать все репозитории
- Проверить MEMORY.md
- Проверить MCP-подключение
- Проверить статус агентов

### Шаг 17. Тестовый DayPlan

```bash
# Ручной запуск Стратега:
bash ~/IWE/DS-exocortex/roles/strategist/scripts/strategist.sh day-plan
```

Проверь что создался `DS-strategy/current/DayPlan YYYY-MM-DD.md`.

---

## Чек-лист миграции

| Шаг | Что | Статус |
|-----|-----|--------|
| 1 | Все репо закоммичены на старом | ☐ |
| 2 | Все репо запушены | ☐ |
| 3 | Список локальных данных записан | ☐ |
| 4 | Базовые инструменты установлены | ☐ |
| 5 | Шаблон склонирован | ☐ |
| 6 | setup.sh выполнен | ☐ |
| 7 | Все DS-репо склонированы | ☐ |
| 8 | MEMORY.md перенесён | ☐ |
| 9 | .exocortex.env перенесён | ☐ |
| 10 | .secrets/ перенесены | ☐ |
| 11 | personal/ файлы перенесены | ☐ |
| 12 | Агенты переустановлены | ☐ |
| 13 | MCP-серверы подключены | ☐ |
| 14 | WakaTime настроен | ☐ |
| 15 | setup.sh --validate = OK | ☐ |
| 16 | Тестовая сессия прошла | ☐ |
| 17 | DayPlan создан | ☐ |

---

## Если что-то пошло не так

| Проблема | Решение |
|----------|---------|
| `gh auth` не работает | `gh auth logout && gh auth login` |
| MCP не подключается | Проверь интернет, перезапусти Claude Code |
| launchd агент не запускается | `bash roles/strategist/install.sh` переустановит |
| MEMORY.md пустой | Попроси Claude: «Восстанови MEMORY.md из последнего commit'а» |
| Репозиторий не клонируется | `gh repo list sviridoves` — проверь имя |
| setup.sh падает | `bash setup.sh --dry-run` — покажет что происходит |

---

*Документ создан: 2026-04-05*
*Следующее обновление: при изменении структуры миграции*