#!/usr/bin/env bash
# Ізольований тест хука pre-commit-gate.mjs.
# Запуск: bash .claude/hooks/test-pre-commit-gate.sh
#
# На відміну від решти хуків, цей віддає рішення не exit-кодом, а JSON-ом
# (permissionDecision), тож звіряємо stdout. Перевіряється РОУТИНГ (чи хук взагалі
# бере команду) і кирилична перевірка — обидві спрацьовують до запуску `npm test`,
# тож тест лишається швидким і не залежить від стану репо.
#
# Привід: до 2026-08-03 хук покладався на `if: Bash(git commit*)` у settings.json.
# Поле не фільтрує — хук отримував КОЖНУ Bash-команду, ганяв на ній повний
# `npm test` + `npm run verify` і блокував будь-який рядок із кирилицею.
set -uo pipefail

HOOK="$(cd "$(dirname "$0")" && pwd)/pre-commit-gate.mjs"
fails=0

# «pass» = хук нічого не сказав (команда не його справа або гейт зелений);
# «deny» = у stdout є permissionDecision deny.
check() {
  local name="$1" expected="$2" command="$3"
  local out verdict
  out=$(printf '{"tool_name":"Bash","tool_input":{"command":%s}}' "$command" | node "$HOOK" 2>/dev/null)
  if printf '%s' "$out" | grep -q '"permissionDecision":"deny"'; then verdict=deny; else verdict=pass; fi
  if [ "$verdict" = "$expected" ]; then
    printf '  OK    %-52s %s\n' "$name" "$verdict"
  else
    printf '  FAIL  %-52s expected %s, got %s\n' "$name" "$expected" "$verdict"
    fails=$((fails + 1))
  fi
}

echo "Not a commit at all — hook must stay out of the way (pass):"
check "echo with Cyrillic text"            pass '"echo тест"'
check "vitest run"                         pass '"npx vitest run"'
check "git log"                            pass '"git log --oneline -5"'
check "git push"                           pass '"git push origin feat/x"'
check "grep for the word commit"           pass '"grep -rn commit docs/"'
check "git commit-tree (plumbing)"         pass '"git commit-tree abc123"'
check "word commit inside a string"        pass '"echo \"commit later\""'

echo
echo "Real commit with Cyrillic in the message — must deny:"
check "subject in Ukrainian"               deny '"git commit -m \"виправлення\""'
check "flags between git and commit"       deny '"git -c user.name=x commit -m \"тест\""'
check "compound command"                   deny '"npm test && git commit -m \"тест\""'
check "Cyrillic in heredoc body"           deny '"git commit -F- <<EOF\nтіло\nEOF"'
check "amend with Cyrillic"                deny '"git commit --amend -m \"тест\""'

echo
if [ "$fails" -eq 0 ]; then
  echo "All cases passed."
else
  echo "$fails case(s) failed."
  exit 1
fi
