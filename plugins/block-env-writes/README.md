# block-env-writes

## Purpose

`PreToolUse` hook на `Bash`: блокує запис у `.env*` через шелл (редирект,
`tee`, `cp`/`mv`, `sed -i`, `truncate`/`dd`), включно з `$IFS`-обходом пробілу
й записом через `node -e`/`python3 -c` inline-код. Permission `deny` на
`Write`/`Edit` не бачить файл, який створює сам шелл — цей хук закриває саме
цю діру.

**Що НЕ робить:** це sanity-net проти необережності агента, не security-межа
проти свідомого обходу (quote-fragmentation, base64/XOR-обфускація regex не
ловить — для цього потрібен парсинг шелу, не текстовий патерн).

## Install

```bash
claude --plugin-dir ./plugins/block-env-writes
```

## Commands

—

## Skills

—

## Hooks

| Event | Що робить |
|---|---|
| `PreToolUse` (matcher `Bash`) | `${CLAUDE_PLUGIN_ROOT}/hooks/block-env-writes.mjs` — exit 2 і пояснення в stderr, якщо команда пише в `.env*` (крім `.env.example`/`.sample`/`.template`/`.dist`) |

## Як перевірити

Без LLM, найшвидше — прогнати ізольований тест (21 кейс: позитивні, негативні,
межові):

```bash
bash ./hooks/test-block-env-writes.sh
```

Наскрізно, в реальній сесії з інстальованим плагіном — попроси Claude
`echo X=1 > .env` і подивись на `ЗАБЛОКОВАНО:` у відповіді.
