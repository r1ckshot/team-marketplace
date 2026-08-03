#!/usr/bin/env node
/**
 * PreToolUse + matcher Bash + if: git commit* — гейт перед комітом.
 *
 * Замінює інлайн `npm test` у settings.json. Два чеки, обидва мають ловити
 * проблему ДО коміту, не після: кирилиця в message (правило CLAUDE.md
 * "коміти англійською" один раз протекло в subject — 2026-07-31) і
 * `npm test` + `npm run verify` (той самий клас, що й check-docs.mjs, лишень
 * рівнем раніше).
 */
import { spawnSync } from 'node:child_process';

let raw = '';
process.stdin.on('data', (d) => (raw += d));
process.stdin.on('end', () => {
  let command = '';
  try {
    command = (JSON.parse(raw || '{}').tool_input || {}).command || '';
  } catch {
    process.exit(0);
  }
  if (!command) process.exit(0);

  // Власний гейт замість покладання на `if: Bash(git commit*)` у settings.json:
  // поле `if` фактично не фільтрує — хук отримував КОЖНУ Bash-команду і ганяв на
  // ній повний `npm test` + `verify`, а кирилиця в будь-якому echo читалась як
  // кирилиця в commit message. Перевірено 2026-08-03 живими викликами.
  if (!isGitCommit(command)) process.exit(0);

  const CYRILLIC = /[Ѐ-ӿ]/;
  if (CYRILLIC.test(command)) {
    deny('Кирилиця в git commit — коміти строго англійською (CLAUDE.md, розділ Git).');
    return;
  }

  const test = spawnSync('npm', ['test', '--silent'], { encoding: 'utf8' });
  if (test.status !== 0) {
    deny(`npm test впав — коміт заблоковано.\n${tail(test.stdout + test.stderr)}`);
    return;
  }

  const verify = spawnSync('npm', ['run', 'verify', '--silent'], { encoding: 'utf8' });
  if (verify.status !== 0) {
    deny(`npm run verify впав — коміт заблоковано.\n${tail(verify.stdout + verify.stderr)}`);
    return;
  }

  process.exit(0);
});

/**
 * Чи є в команді справжній `git commit`. Регексом це не робиться надійно: між
 * `git` і підкомандою стоять глобальні опції, і частина з них має ОКРЕМИМ токеном
 * значення (`git -c user.name=x commit`). Тому — розбір токенів: пропускаємо
 * прапорці, перший непрапорцевий токен і є підкоманда. Так `git commit-tree` і
 * `grep commit` лишаються поза гейтом, а `npm test && git commit -m …` — усередині.
 */
function isGitCommit(command) {
  const OPTIONS_WITH_VALUE = new Set(['-c', '-C', '--git-dir', '--work-tree', '--namespace', '--exec-path']);

  for (const segment of command.split(/&&|\|\||;|\||\n/)) {
    const tokens = segment.trim().split(/\s+/).filter(Boolean);
    const gitAt = tokens.findIndex((t) => t === 'git' || t.endsWith('/git'));
    if (gitAt === -1) continue;

    for (let i = gitAt + 1; i < tokens.length; i++) {
      const token = tokens[i];
      if (!token.startsWith('-')) return token === 'commit';
      if (OPTIONS_WITH_VALUE.has(token)) i++;
    }
  }
  return false;
}

function tail(s, n = 20) {
  return s.trim().split('\n').slice(-n).join('\n');
}

function deny(reason) {
  console.log(JSON.stringify({
    hookSpecificOutput: {
      hookEventName: 'PreToolUse',
      permissionDecision: 'deny',
      permissionDecisionReason: reason,
    },
  }));
  process.exit(0);
}
