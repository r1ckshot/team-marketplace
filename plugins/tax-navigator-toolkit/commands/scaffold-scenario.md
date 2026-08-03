---
description: Провести новий сценарій порівняння наскрізь — правила, модуль calc/, реєстрація в 10 місцях, i18n, тести
allowed-tools: Read, Write, Edit, Grep, Glob, Bash(date:*), Bash(grep:*), Bash(npm test:*), Bash(npx vitest:*), Bash(npx tsc:*), Bash(npm run:*)
---

# Сценарій `$ARGUMENTS`

Сьогодні: !`date -I`

Наявні сценарії: !`grep -o "^export type ScenarioId = .*" app/lib/calc/types.ts`

Ця команда веде ОДИН сценарій порівняння через увесь зріз: дані → розрахунок →
реєстрація → текст → тести. Вона існує, бо ланцюг реєстрації довгий і забувається
не в цікавих місцях, а в нудних: у F1 (`zlecenie`, 2026-08-03) новий сценарій
довелось прописати в **десяти** місцях, і чотири з них — суто механічні
(`app/page.tsx`, README, ARCHITECTURE, карта архітектури). Забутий пункт не валить
тести — він просто лишає в продукті документ, який бреше.

## Крок 0 — аргумент і розмір

`$ARGUMENTS` порожній → зупинись і спитай `<slug>` латиницею (`zlecenie`,
`nierejestrowana`) — він стане `ScenarioId`, ключем i18n та іменем файлу.

Slug уже є в `ScenarioId` → це не новий сценарій, а правка наявного. Зупинись і
спитай Mike, що саме змінюється: додати підформу — не те саме, що додати сценарій.

## Крок 1 — цифри, до будь-якого коду

**Жодного рядка коду, поки числа не звірені.** Кожна ставка, поріг і ліміт
проходить `/scaffold-rule <rule_id>` — тобто джерело з allowlist, рядок
«Верифіковано» в `docs/EVIDENCE.md`, запис у `rules.2026.json` із `source_url` +
`verified_at`.

Прикидати «десь 12%» заборонено (`.claude/rules/evidence-numbers.md`). Джерело
недоступне → сценарій показується **без числа** з поясненням, як `fop`.

Що зазвичай стає окремими `rule_id`: складки (хто платить і скільки), витрати
(KUP чи їх аналог), пороги й ліміти, а також норми, що дають **ризик** — саме
вони стають `riskReasonKey`.

## Крок 2 — модуль розрахунку

`app/lib/calc/scenarios/<slug>.ts`, за формою наявних (`uop.ts` — найближчий, якщо
сценарій про найм; `incubator.ts` — якщо є підформи):

```ts
export function calc<Slug>(answers: Answers, base: Base = 'employerCost'): ScenarioResult
```

Тверді межі шару, їх стереже хук `layer-boundary` і `npm run test:arch`:

- імпорти лише з `@/lib/rules/*` і сусідів по `calc/`; ні react, ні next, нічого з npm;
- жодного тексту для UI — тільки `noteKeys` / `riskReasonKey` / `unavailableReasonKey`;
- жодної нової арифметики там, де вже є спільна: `toRange`, `round2`, `UNCERTAINTY`
  (`../range`), `skalaAnnualTax`, `spanOf`, `expenseRate` (`./shared`),
  `getParams`, `sourcesOf` (`@/lib/rules/types`).

Число, якого немає підстав показати, — це `rangeMonthly: null` + `noRangeReasonKey`,
а не правдоподібна оцінка.

## Крок 3 — реєстрація: усі десять місць

Пройди список зверху вниз і **звітуй по кожному пункту**, а не «зареєстрував».

| # | Файл | Що саме |
|---|---|---|
| 1 | `app/lib/calc/types.ts` | `ScenarioId` += `'<slug>'` |
| 2 | `app/lib/calc/scenarios/index.ts` | виклик у `compareScenarios` + реекспорт `calc<Slug>` |
| 3 | `app/lib/i18n/uk.ts` | `scenario.<slug>`, `risk.<slug>.*`, усі `noteKeys` і `unavailableReasonKey` |
| 4 | `app/lib/i18n/uk.ts` | `app.description` і `app.intro` — там названа КІЛЬКІСТЬ варіантів |
| 5 | `app/page.tsx` | масив `SCENARIOS` лендингу — той самий порядок, що в `compareScenarios` |
| 6 | `docs/EVIDENCE.md` | §Сценарій `<Літера>` — що це, три відмінності від найближчого сусіда, ризик |
| 7 | `SPEC.md` | Goal 2 (кількість сценаріїв) + новий рядок в Acceptance criteria |
| 8 | `README.md` | «порівняння N сценаріїв» |
| 9 | `ARCHITECTURE.md` | рядок таблиці шарів згадує кількість сценаріїв |
| 10 | `docs/architecture-map.md` | контейнер `calc` — та сама кількість |

Порядок у `compareScenarios` — продуктове рішення, не алфавіт: сусідні сценарії
стоять поруч, щоб різницю було видно очима. Сортування «за вигодою» заборонене —
воно читається як порада.

## Крок 4 — тести

Веде скіл `scenario-tests`. Коротко, що він зробить: гілки логіки, еталон із
ручного виведення в `benchmark.test.ts` (звірка з **центром** смуги, не
`rangeContains`), рядок у `flow.test.tsx`, і мутаційна перевірка — навмисно
зламати арифметику й переконатись, що тест падає.

Не пропускай мутаційну перевірку: у F1 три з п'яти навмисних поломок пройшли
зеленими, і без цього кроку сценарій виглядав би покритим.

## Крок 5 — прогін

```
npx tsc --noEmit && npm test && npm run test:ui && npm run verify
```

`npm run verify` тут не формальність: він звіряє кількість тестів у `docs/STATE.md`
з фактичною і ловить биті посилання в документах, які ти щойно правив.

Звітуй фактом: «N node + M UI зелені». Червоне — зупинка.

## Крок 6 — очі Mike

Сценарій додає рядок у таблицю порівняння й картку — це візуальна зміна.
`.claude/rules/visual-review.md`: не називати готовим, поки Mike не подивився.
Дай точний URL (`/questionnaire` → екран результату) і скажи, на що дивитись.

## Крок 7 — коміти

Три коміти, у порядку кроків, subject англійською:

1. `docs(evidence): verify <тема> against <джерело>` (якщо EVIDENCE окремо)
2. `feat(calc): add <slug> scenario with verified <рік> rates`
3. `docs: record <slug> in spec and architecture docs`

**Не комітити без явного підтвердження Mike.**
