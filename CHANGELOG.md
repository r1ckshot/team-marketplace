# Changelog

Формат — [Keep a Changelog](https://keepachangelog.com/), версії — [SemVer](https://semver.org/).

## [1.1.0] — 2026-08-03

### Added

- `tax-navigator-toolkit@1.0.0` — два command-и (`scaffold-rule`,
  `scaffold-scenario`), три скіли (`add-source-domain`, `scenario-tests`,
  `feature-ship`) і три хуки (`layer-boundary`, `pre-commit-gate`,
  `block-env-writes`). Витягнутий не з уяви, а з заміру: спершу та сама фіча
  зроблена руками, і в плагін пішло рівно те, що виявилось повторюваним.

### Changed

- CI ганяє **всі** `hooks/test-*.sh` кожного плагіна, а не одне зашите імʼя.
  Доти набір із трьох сюїт мовчки не запускався б, і бейдж усе одно був би
  зелений — це гірше за плагін узагалі без тестів.

### Added

- `block-env-writes` — `PreToolUse`-хук, блокує запис у `.env*` через шелл
  (redirect/tee/cp/sed-i/`$IFS`/inline-інтерпретатор).
