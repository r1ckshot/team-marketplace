#!/usr/bin/env bash
# Ізольований тест хука layer-boundary.mjs.
# Запуск: bash .claude/hooks/test-layer-boundary.sh
#
# Рішення хука — JSON у stdout (як у pre-commit-gate), тож звіряємо його, не exit-код.
# Кейси дзеркалять п'ять правил із .dependency-cruiser.cjs плюс негативні: хук мусить
# мовчати там, де межа не порушена, інакше він просто заважає працювати.
set -uo pipefail

HOOK="$(cd "$(dirname "$0")" && pwd)/layer-boundary.mjs"
fails=0

# $1 name, $2 expected (deny|pass), $3 tool, $4 file_path, $5 code
check() {
  local name="$1" expected="$2" tool="$3" file="$4" code="$5"
  local payload out verdict field
  if [ "$tool" = "Write" ]; then field=content; else field=new_string; fi
  payload=$(FILE="$file" CODE="$code" TOOL="$tool" FIELD="$field" node -e '
    const {FILE, CODE, TOOL, FIELD} = process.env;
    process.stdout.write(JSON.stringify({tool_name: TOOL, tool_input: {file_path: FILE, [FIELD]: CODE}}));
  ')
  out=$(printf '%s' "$payload" | node "$HOOK" 2>/dev/null)
  if printf '%s' "$out" | grep -q '"permissionDecision":"deny"'; then verdict=deny; else verdict=pass; fi
  if [ "$verdict" = "$expected" ]; then
    printf '  OK    %-54s %s\n' "$name" "$verdict"
  else
    printf '  FAIL  %-54s expected %s, got %s\n' "$name" "$expected" "$verdict"
    fails=$((fails + 1))
  fi
}

echo "core-no-external (calc/ and rules/ must stay npm-free):"
check "react into calc"            deny Write app/lib/calc/scenarios/x.ts "import { useMemo } from 'react';"
check "type-only import of next"   deny Write app/lib/calc/x.ts           "import type { Metadata } from 'next';"
check "require() of lodash"        deny Edit  app/lib/calc/x.ts           "const _ = require('lodash');"
check "dynamic import of a pkg"    deny Edit  app/lib/calc/x.ts           "const m = await import('date-fns');"
check "npm into rules/"            deny Write app/lib/rules/types.ts      "import { z } from 'zod';"

echo
echo "rules-are-leaf (rules/ imports only itself):"
check "rules -> calc"              deny Write app/lib/rules/types.ts      "import { round2 } from '@/lib/calc/range';"
check "rules -> sibling file"      pass Write app/lib/rules/types.ts      "import data from './rules.2026.json';"
check "rules -> own alias path"    pass Write app/lib/rules/types.ts      "import { X } from '@/lib/rules/x';"
check "rules -> parent lib file"   deny Write app/lib/rules/types.ts      "import { fmt } from '../format';"

echo
echo "core-no-adapters (calc/ must not know about adapters):"
check "calc -> storage"            deny Write app/lib/calc/x.ts           "import { load } from '@/lib/storage';"
check "calc -> i18n"               deny Edit  app/lib/calc/scenarios/x.ts "import { t } from '@/lib/i18n/uk';"
check "calc -> questions schema"   deny Write app/lib/calc/x.ts           "import { schema } from '@/lib/questions/schema';"

echo
echo "lib-no-presentation (nothing in app/lib imports UI):"
check "calc -> component"          deny Write app/lib/calc/x.ts           "import { Card } from '@/components/ScenarioCard';"
check "adapter -> component"       deny Write app/lib/format.ts           "import { Card } from '@/components/ScenarioCard';"

echo
echo "ui-no-raw-rule-data (numbers reach the UI only through calc/):"
check "component -> rules json"    deny Write app/components/Table.tsx    "import rules from '@/lib/rules/rules.2026.json';"
check "page -> rules json"         deny Edit  app/questionnaire/page.tsx  "import rules from '../lib/rules/rules.2026.json';"
check "component -> calc"          pass Write app/components/Table.tsx    "import { compareScenarios } from '@/lib/calc/scenarios';"

echo
echo "Must stay out of the way:"
check "react in a component"       pass Write app/components/Table.tsx    "import { useState } from 'react';"
check "calc -> calc sibling"       pass Write app/lib/calc/scenarios/x.ts "import { toRange } from '../range';"
check "calc -> rules (allowed)"    pass Write app/lib/calc/x.ts           "import { getParams } from '@/lib/rules/types';"
check "test file may import react" pass Write app/lib/calc/__tests__/x.test.ts "import { render } from '@testing-library/react';"
check "file outside app/"          pass Write scripts/verify.mjs          "import { z } from 'zod';"
check "markdown, not code"         pass Write docs/STATE.md               "import { useState } from 'react';"
check "empty edit"                 pass Edit  app/lib/calc/x.ts           ""
check "word import inside a string" pass Write app/lib/calc/x.ts          "const msg = 'import from react';"

echo
if [ "$fails" -eq 0 ]; then
  echo "All cases passed."
else
  echo "$fails case(s) failed."
  exit 1
fi
