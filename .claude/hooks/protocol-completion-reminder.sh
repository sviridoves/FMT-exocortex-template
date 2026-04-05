#!/bin/bash
# Protocol Completion Reminder Hook
# Event: PostToolUse (matcher: tool_name = Read, input.file_path contains "protocol-")
# После чтения протокола напоминает: выполни ВСЕ шаги включая верификацию.
# Read-only: только возвращает JSON.

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty')
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# Срабатываем только на чтение протоколов
if [ "$TOOL" = "Read" ] && echo "$FILE_PATH" | grep -q "protocol-"; then
  PROTOCOL_NAME=$(basename "$FILE_PATH" .md)
  cat <<EOF
{"additionalContext": "\ud83d\udcdd \u051f\u0520\u051e\u0522\u051e\u051a\u051e\u051b \u0517\u0510\u0513\u0520\u0523\u0516\u0515\u051d: $PROTOCOL_NAME. \u051e\u0511\u052f\u0517\u0510\u0522\u0515\u051b\u052c\u051d\u051e: (1) \u0512\u055b\u053f\u053e\u053b\u053d\u0538 \u0512\u0521\u0515 \u0558\u0530\u0533\u0538 \u0530\u053b\u0533\u053e\u0550\u0538\u0552\u053c\u0530. (2) \u051f\u053e\u0551\u053b\u0535 \u0537\u0530\u0532\u0535\u0550\u0558\u0535\u053d\u0538\u055f \u0537\u0530\u053f\u0553\u0551\u0552\u0538 /verify \u0535\u053b\u055f \u0532\u0535\u0550\u0538\u0555\u0538\u053a\u0530\u0556\u0538\u0538 \u053f\u053e \u0557\u0535\u053a\u053b\u0538\u0551\u0552\u0553 (Haiku R23). \u051d\u0515 \u053f\u0550\u053e\u053f\u0553\u0551\u053a\u0530\u0539 \u0532\u0535\u0550\u0538\u0555\u0538\u053a\u0530\u0556\u0538\u055e."}
EOF
else
  echo '{}'
fi
exit 0
