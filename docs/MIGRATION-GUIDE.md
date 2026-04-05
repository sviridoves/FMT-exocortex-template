# Перенос IWE на другое рабочее место (Ubuntu 24 + Cline + OpenRouter)

> **Принцип:** Все репозитории в GitHub (приватные) = source-of-truth. Перенос = git clone + копирование локальных файлов.
> **Платформа:** Ubuntu 24.04 LTS
> **IDE:** VS Code + расширение Cline (не Claude Code CLI)
> **LLM:** OpenRouter (универсальный API-шлюз к моделям: Claude, GPT, Gemini и др.)
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
ls -la ~/IWE/memory/MEMORY.md 2>/dev/null
ls -la ~/IWE/.claude/projects/*/memory/MEMORY.md 2>/dev/null
ls -la ~/IWE/DS-exocortex/.exocortex.env 2>/dev/null
ls -la ~/IWE/DS-exocortex/.mcp.json 2>/dev/null
ls -la ~/IWE/DS-exocortex/.secrets/ 2>/dev/null
ls -la ~/.wakatime.cfg 2>/dev/null
ls -la ~/.config/Cline/MCP/settings.json 2>/dev/null
crontab -l 2>/dev/null
```

---

## ЧАСТЬ 2: Новый компьютер (Ubuntu 24) — установка

### Шаг 4. Установи базовые инструменты

На **новом** компьютере (Ubuntu 24.04):

```bash
# Обновись
sudo apt update && sudo apt upgrade -y

# 4.1 Git
sudo apt install -y git

# 4.4 GitHub CLI
(type -p wget >/dev/null || (sudo apt update && sudo apt-get install wget -y)) \
  && sudo mkdir -p -m 755 /etc/apt/keyrings \
  && out=$(mktemp) && wget -nv -O"$out" https://keyserver.ubuntu.com/pks/lookup?op=get\&search=0x23F3D4EA75716059 \
  && cat "$out" | sudo gpg --dearmor -o /etc/apt/keyrings/cli-asc-keyring.gpg \
  && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/cli-asc-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
  && sudo apt update \
  && sudo apt install -y gh

# Авторизация
gh auth login  # выбери GitHub.com → HTTPS → Login with a web browser

# 4.5 Node.js (v20 LTS)
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt install -y nodejs

# 4.6 npm пакеты
sudo npm install -g wakatime-cli
```

### Шаг 4b. Установка VS Code + Cline

```bash
# VS Code
sudo apt install -y wget gpg
wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > packages.microsoft.gpg
sudo install -D -o root -g root -m 644 packages.microsoft.gpg /etc/apt/keyrings/packages.microsoft.gpg
echo "deb [arch=amd64,arm64,armhf signed-by=/etc/apt/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" | sudo tee /etc/apt/sources.list.d/vscode.list > /dev/null
sudo apt update
sudo apt install -y code

# Открой VS Code
code

# Установка Cline
# 1. В VS Code: `Ctrl+Shift+X` (Extensions)
# 2. Поиск: "Cline"
# 3. Установи расширение "Cline" (cline.cline)
```

### Шаг 4c. Настройка OpenRouter

1. **Получи API ключ:**
   - Открой https://openrouter.ai/
   - Зарегистрируйся / войди
   - Перейди на https://openrouter.ai/keys
   - Создай новый ключ → скопируй

2. **Настрой Cline:**
   - Открой VS Code → Cline (иконка в сайдбаре или `Ctrl+Shift+P` → "Cline: Open")
   - **Provider:** выбери **OpenRouter**
   - **API Key:** вставь ключ из OpenRouter
   - **Model:** выбери модель по умолчанию:
     - `anthropic/claude-3.5-sonnet` — баланс цена/качество
     - `anthropic/claude-3-opus` — сложные архитектурные задачи
     - `anthropic/claude-3-haiku` — тривиальные задачи, экономия
   - Нажми Save

3. **Проверь:**
   - В Cline напиши: «Привет, тест связи»
   - Должен прийти ответ от модели через OpenRouter

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
cd ~/IWE/FMT-exocortex-template
bash setup.sh
```

Скрипт спросит:

| Вопрос | Что ввести |
|--------|-----------|
| GitHub username | Твой логин (sviridoves) |
| Workspace directory | Enter (определится автоматически) |
| Claude CLI path | `/usr/bin/cline` или оставь пустым если нет CLI (у тебя Cline расширение) |
| Strategist launch hour (UTC) | 4 (если 7:00 MSK) |
| Timezone description | 7:00 MSK |

> **Примечание:** Так как ты используешь **Cline (VS Code расширение)**, а не Claude Code CLI, некоторые CLI-функции могут быть недоступны. Это нормально — Cline всё читает через workspace, но launchd/systemd-агенты нужно запускать отдельно (см. Шаг 12).

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

### Шаг 8. Скопируй MEMORY.md (или настрой Cline)

> **Важно:** При использовании Cline (VS Code расширение) memory-файлы хранятся не в `~/.claude/projects/`, а зависят от конфигурации.
> Cline может читать память из workspace — поэтому проще всего скопировать MEMORY.md прямо в `~/IWE/memory/`.

**Вариант A — через scp:**

```bash
# На НОВОМ:
mkdir -p ~/IWE/memory
scp sviridov@OLD_IP:~/IWE/memory/MEMORY.md ~/IWE/memory/
```

**Вариант B — через флешку:**

1. На старом: скопируй `~/IWE/memory/MEMORY.md`
2. На новом: вставь в `~/IWE/memory/MEMORY.md`

**Вариант C — через Cline:**

Напиши в Cline: «Восстанови MEMORY.md из последнего коммита в DS-exocortex» — он вычитает историю.

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

### Шаг 12. Переустанови агентов (systemd/cron)

На Ubuntu вместо launchd используются **systemd timers** или **cron**.

```bash
cd ~/IWE/DS-exocortex

# Про установку systemd-юнитов скажи в Cline:
# «Установи агентов как systemd timers на Ubuntu 24»
```

**Альтернатива — через crontab (проще):**

```bash
# Открой crontab
crontab -e

# Добавь строки:
# Утренний план (7:00 MSK = 4:00 UTC), Вт-Вс
0 4 * * 1-6 bash ~/IWE/DS-exocortex/roles/strategist/scripts/strategist.sh day-plan

# Недельный обзор (Вс 22:00 MSK = 19:00 UTC)
0 19 * * 0 bash ~/IWE/DS-exocortex/roles/strategist/scripts/strategist.sh week-review

# Note-Review (23:00 MSK = 20:00 UTC ежедневно)
0 20 * * * bash ~/IWE/DS-exocortex/roles/strategist/scripts/strategist.sh note-review

# Проверка:
crontab -l
```

### Шаг 13. Настрой MCP-серверы для Cline

Cline поддерживает MCP через настройку `.mcp.json` или в настройках расширения.

**Вариант A — через файл настроек:**

```bash
mkdir -p ~/.config/Cline/MCP

# Скажи Cline в чате:
# «Настрой MCP серверы: knowledge-mcp и digital-twin-mcp»
```

Cline создаст конфигурацию и подключит серверы.

**Вариант B — проверить вручную:**

В VS Code → Cline → Settings → MCP Servers → добавь:
- `knowledge-mcp`: `https://knowledge-mcp.aisystant.workers.dev/mcp`
- `digital-twin-mcp`: `https://digital-twin-mcp.aisystant.workers.dev/mcp`

**Проверка:**
Напиши Cline: «Найди в knowledge-mcp документы про протоколы» — должен найти через search.

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

### Шаг 16. Тестовая сессия в Cline

1. Открой VS Code
2. `File → Open Folder` → выбери `~/IWE`
3. Открой Cline (`Ctrl+Shift+P` → "Cline: Open" или иконка в сайдбаре)
4. Напиши в чат:

> «Проведи проверку после переноса: проверь все репо, MEMORY.md, MCP-серверы, статус крона, настройки OpenRouter»

Cline должен:
- Прочитать все репозитории (через workspace)
- Проверить MEMORY.md
- Проверить MCP-подключение
- Проверить crontab
- Показать статус OpenRouter (через API)

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
| Cline не видит файлы | Открой папку `~/IWE` через `File → Open Folder` |
| MCP не подключается | Проверь интернет, перезапусти VS Code |
| systemd timer не запускается | `systemctl --user status strategist.timer` |
| Cron не работает | `grep CRON /var/log/syslog` — проверь логи |
| OpenRouter 402 error | Пополни баланс на openrouter.ai/credits |
| OpenRouter 401 error | API ключ неверный — проверь на openrouter.ai/keys |
| MEMORY.md пустой | Попроси Cline: «Восстанови MEMORY.md из последнего commit'а» |
| Репозиторий не клонируется | `gh repo list sviridoves` — проверь имя |
| setup.sh падает | `bash setup.sh --dry-run` — покажет что происходит |

---

*Документ создан: 2026-04-05*
*Следующее обновление: при изменении структуры миграции*