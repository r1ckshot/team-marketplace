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
echo "Attribution trailer — marker: the reason names Co-Authored-By."

# Той самий приклад, що й у гілкових кейсах: на фіче-гілці хук іде далі й падає на
# `npm test` (у fixture нема package.json), тож саме pass/deny нічого не розрізняє —
# звіряти треба ТЕКСТ причини. Заразом fixture тримає тест швидким: жоден кейс не
# доходить до справжнього прогону тестів цього репо.
trailer_case() {
  local name="$1" expected="$2" command="$3"
  local dir out verdict
  dir=$(mktemp -d)
  (cd "$dir" && git init -q -b feat/x . && git commit -q --allow-empty -m init) >/dev/null 2>&1
  out=$(cd "$dir" && printf '{"tool_name":"Bash","tool_input":{"command":%s}}' "$command" | node "$HOOK" 2>/dev/null)
  rm -rf "$dir"
  if printf '%s' "$out" | grep -q 'Co-Authored-By'; then verdict=deny-trailer; else verdict=passed-trailer-gate; fi
  if [ "$verdict" = "$expected" ]; then
    printf '  OK    %-52s %s\n' "$name" "$verdict"
  else
    printf '  FAIL  %-52s expected %s, got %s\n' "$name" "$expected" "$verdict"
    fails=$((fails + 1))
  fi
}

trailer_case "subject only, no trailer"    deny-trailer        '"git commit -m \"fix: x\""'
trailer_case "body but still no trailer"   deny-trailer        '"git commit -m \"fix: x\" -m \"why it broke\""'
trailer_case "trailer present"             passed-trailer-gate '"git commit -m \"fix: x\" -m \"Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>\""'
# Модель у трейлері міняється разом із /model — гейт не має її знати.
trailer_case "trailer names another model" passed-trailer-gate '"git commit -m \"fix: x\" -m \"Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\""'
# Повідомлення не в команді: редактор, --amend --no-edit, -C HEAD. Трейлера в
# рядку нема за побудовою, і гейт мусить мовчати, інакше блокує законні коміти.
trailer_case "editor commit"               passed-trailer-gate '"git commit"'
trailer_case "amend --no-edit"             passed-trailer-gate '"git commit --amend --no-edit"'
trailer_case "reuse message from HEAD"     passed-trailer-gate '"git commit -C HEAD"'

echo
echo "Branch gate — fixture repos, real HEAD (marker: the hint about checkout -b):"

# Гілку не підробити стабільно з поточного репо, тож кожен кейс отримує свій
# одноразовий репозиторій. Маркер у reason важливий: на фіче-гілці хук теж
# віддає deny (у fixture нема package.json, тож `npm test` падає) — і без звірки
# ТЕКСТУ причини кейс "гілковий чек пропустив" був би нерозрізненний від блоку.
branch_case() {
  local name="$1" expected="$2" branch="$3" seed="${4:-with-commit}"
  local dir out verdict
  dir=$(mktemp -d)
  if [ "$seed" = "unborn" ]; then
    (cd "$dir" && git init -q -b "$branch" .) >/dev/null 2>&1
    out=$(cd "$dir" && printf '{"tool_name":"Bash","tool_input":{"command":"git commit -m \\"fix: x\\""}}' | node "$HOOK" 2>/dev/null)
    rm -rf "$dir"
    if printf '%s' "$out" | grep -q 'checkout -b'; then verdict=deny-branch; else verdict=passed-branch-gate; fi
    if [ "$verdict" = "$expected" ]; then
      printf '  OK    %-52s %s\n' "$name" "$verdict"
    else
      printf '  FAIL  %-52s expected %s, got %s\n' "$name" "$expected" "$verdict"
      fails=$((fails + 1))
    fi
    return
  fi
  # Ідентичність — прапорцями, а не з глобального конфігу: у CI його нема, коміт
  # мовчки не створювався, гілка лишалась ненародженою, і кейс "коміт у master"
  # ставав зеленим через дірку в хуку, а не через справність. Знайдено релізом 1.1.0.
  (
    cd "$dir" || exit 1
    git init -q -b "$branch" .
    git -c user.email=ci@example.com -c user.name=ci commit -q --allow-empty -m init
  ) >/dev/null 2>&1
  out=$(cd "$dir" && printf '{"tool_name":"Bash","tool_input":{"command":"git commit -m \\"fix: x\\""}}' | node "$HOOK" 2>/dev/null)
  rm -rf "$dir"
  if printf '%s' "$out" | grep -q 'checkout -b'; then verdict=deny-branch; else verdict=passed-branch-gate; fi
  if [ "$verdict" = "$expected" ]; then
    printf '  OK    %-52s %s\n' "$name" "$verdict"
  else
    printf '  FAIL  %-52s expected %s, got %s\n' "$name" "$expected" "$verdict"
    fails=$((fails + 1))
  fi
}

branch_case "commit on master"             deny-branch         master
branch_case "commit on main"               deny-branch         main
branch_case "commit on feat/x"             passed-branch-gate  feat/x
branch_case "commit on docs/cleanup"       passed-branch-gate  docs/cleanup
branch_case "branch named masterpiece"     passed-branch-gate  masterpiece

# Репо без ЖОДНОГО коміта — гілка ненароджена, `rev-parse` падає. Саме цей стан
# ховав дірку в хуку до 2026-08-05: перший коміт у свіжому репо йшов повз гейт.
branch_case "first commit ever, on master" deny-branch         master       unborn
branch_case "first commit ever, on feat/x" passed-branch-gate  feat/x       unborn

echo
if [ "$fails" -eq 0 ]; then
  echo "All cases passed."
else
  echo "$fails case(s) failed."
  exit 1
fi
