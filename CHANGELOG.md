# Changelog

Формат — [Keep a Changelog](https://keepachangelog.com/), версії — [SemVer](https://semver.org/).

## [1.0.0] — 2026-07-31

### Added

- `block-env-writes` — `PreToolUse`-хук, блокує запис у `.env*` через шелл
  (redirect/tee/cp/sed-i/`$IFS`/inline-інтерпретатор).
