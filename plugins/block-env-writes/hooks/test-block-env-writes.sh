#!/usr/bin/env bash
# Ізольований тест хука — до прив'язки в settings.json.
# Запуск: bash .claude/hooks/test-block-env-writes.sh
#
# Кожен кейс подає хуку JSON-payload у stdin і звіряє exit code:
#   2 = заблоковано, 0 = пропущено.
set -uo pipefail

HOOK="$(dirname "$0")/block-env-writes.mjs"
fails=0

check() {
  local name="$1" expected="$2" payload="$3"
  printf '%s' "$payload" | node "$HOOK" >/dev/null 2>&1
  local code=$?
  if [ "$code" = "$expected" ]; then
    printf '  OK    %-46s exit %s\n' "$name" "$code"
  else
    printf '  ПРОВАЛ %-45s очікував %s, отримав %s\n' "$name" "$expected" "$code"
    fails=$((fails + 1))
  fi
}

cmd_payload() { printf '{"tool_name":"Bash","tool_input":{"command":%s}}' "$1"; }
# Для команд зі складним цитуванням (вкладені " і ') — jq сам вважає екранування.
cmd_payload_raw() { jq -nc --arg c "$1" '{"tool_name":"Bash","tool_input":{"command":$c}}'; }

echo "Позитивні (мусить заблокувати, exit 2):"
check "редирект у .env"          2 "$(cmd_payload '"echo SECRET=1 > .env"')"
check "редирект без пробілу"     2 "$(cmd_payload '"echo x >.env.local"')"
check "дозапис heredoc"          2 "$(cmd_payload '"cat >> .env.production <<EOF"')"
check "tee"                      2 "$(cmd_payload '"echo K=V | tee .env.test"')"
check "копіювання поверх"        2 "$(cmd_payload '"cp /tmp/leak .env"')"
check "sed -i по .env"           2 "$(cmd_payload '"sed -i s/A/B/ .env.development"')"
check "у складеній команді"      2 "$(cmd_payload '"npm run build && echo TOKEN=1 > .env"')"
check "\$IFS замість пробілу"    2 "$(cmd_payload_raw 'echo${IFS}X=1${IFS}>${IFS}.env')"
check "node -e writeFileSync"    2 "$(cmd_payload_raw "node -e \"require('fs').writeFileSync('.env','X=1')\"")"
check "python3 -c open(...,'w')" 2 "$(cmd_payload_raw "python3 -c \"open('.env','w').write('X')\"")"

echo "Негативні (мусить пропустити, exit 0):"
check "читання .env"             0 "$(cmd_payload '"cat .env"')"
check "grep по .env"             0 "$(cmd_payload '"grep -n KEY .env.production"')"
check "запис у .env.example"     0 "$(cmd_payload '"echo KEY= > .env.example"')"
check "звичайна команда"         0 "$(cmd_payload '"npm test"')"
check "інший файл із env у назві" 0 "$(cmd_payload '"echo x > environment.md"')"
check "node -e читає .env"       0 "$(cmd_payload_raw "node -e \"console.log(require('fs').readFileSync('.env','utf8'))\"")"
check "звичайний node -e без .env" 0 "$(cmd_payload_raw 'node -e "console.log(1)"')"

echo "Межові (не має падати, exit 0):"
check "порожній payload"         0 '{}'
check "порожній stdin"           0 ''
check "битий JSON"               0 '{ це не json'
check "Bash без command"         0 '{"tool_name":"Bash","tool_input":{}}'

echo
if [ "$fails" = 0 ]; then
  echo "Усі кейси зелені."
else
  echo "Провалено кейсів: $fails"
  exit 1
fi
