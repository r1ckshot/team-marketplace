# team-marketplace

## Що це

Публічний marketplace плагінів для Claude Code. Не курсовий контент (доки й
нотатки курсу лишаються приватними) — власні, незалежно написані інструменти,
які можна поставити в будь-який проєкт, будь-яким стеком.

## Як додати у Claude Code

```
/plugin marketplace add github:r1ckshot/team-marketplace
```

Потім інсталюй конкретний плагін зі списку нижче:

```
/plugin install block-env-writes@team-marketplace
```

Щоб плагін підхопився в усіх контриб'юторів проєкту автоматично — заком'ти
в `.claude/settings.json` проєкту:

```json
{
  "extraKnownMarketplaces": {
    "team-marketplace": {
      "type": "github",
      "repo": "r1ckshot/team-marketplace"
    }
  }
}
```

## Список плагінів

| Плагін | Що робить | Версія |
|---|---|---|
| [block-env-writes](./plugins/block-env-writes) | Блокує запис у `.env*` через шелл (redirect/tee/cp/sed-i/`$IFS`/inline-інтерпретатор) | 1.0.0 |
| [tax-navigator-toolkit](./plugins/tax-navigator-toolkit) | Тримає продукт, побудований на цифрах, чесним: цифра з джерела до тесту, наскрізний зріз через усі 10 місць реєстрації, еталони з мутаційною перевіркою, гейт перед комітом і межа шарів у момент запису файлу | 1.0.0 |

## Супровідники

`r1ckshot` — єдиний мейнтейнер, автор кожного плагіна в `author`-полі
`marketplace.json`.

## Як контриб'ютити

1. Прочитай [SECURITY.md](./SECURITY.md) до PR — плагін виконується з повними
   правами юзера, без sandbox.
2. Один плагін — одна тека в `plugins/<name>/`, зі своїм `README.md`.
3. Версія в `plugins/<name>/.claude-plugin/plugin.json` мусить збігатись із
   записом у корені `.claude-plugin/marketplace.json` — це перевіряє CI.
4. CI (`.github/workflows/validate-plugins.yml`) валідує кожен плагін через
   `claude plugin validate` на кожен PR.

## Контакти

`kapusticnyk.com@gmail.com` — питання, репорт вразливості, пропозиція плагіна.
