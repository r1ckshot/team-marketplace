#!/usr/bin/env node
/**
 * PreToolUse + matcher Bash + if: git commit* — гейт перед комітом.
 *
 * Замінює інлайн `npm test` у settings.json. Три чеки, всі мають ловити проблему
 * ДО коміту, не після: гілка (правило "у master напряму не комітимо" протекло
 * 2026-08-04 — вісім файлів були застейджені просто в master), кирилиця в message
 * (правило CLAUDE.md "коміти англійською" протекло в subject 2026-07-31) і
 * `npm test` + `npm run verify` (той самий клас, що й check-docs.mjs, лишень
 * рівнем раніше).
 *
 * Порядок чеків = від найдешевшого: обидва перші відповідають миттєво, тож на
 * заблокованому коміті не витрачається півхвилини на тести.
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

  const branch = currentBranch();
  if (branch === 'master' || branch === 'main') {
    deny(
      `Коміт напряму в \`${branch}\` — CLAUDE.md, розділ Git: гілка на фічу, ` +
        'у master тільки merge після підтвердження Mike.\n' +
        'Застейджене нікуди не дінеться: git checkout -b <type>/<slug> і комітити там.'
    );
    return;
  }

  const CYRILLIC = /[Ѐ-ӿ]/;
  if (CYRILLIC.test(command)) {
    deny('Кирилиця в git commit — коміти строго англійською (CLAUDE.md, розділ Git).');
    return;
  }

  // Трейлер атрибуції. Ключ `attribution` у settings.json цього НЕ гарантує: він
  // лише кладе інструкцію в контекст, а інструкцію можна проґавити — 2026-08-05
  // два коміти пішли без трейлера саме так. Перевіряється сам ФАКТ трейлера, не
  // імʼя моделі: Mike перемикає Opus/Sonnet/Fable під задачу, і дефолтний текст
  // щоразу інший.
  if (messageIsInCommand(command) && !/Co-Authored-By:\s*\S+.*@anthropic\.com/i.test(command)) {
    deny(
      'Коміт без трейлера Co-Authored-By — CLAUDE.md, розділ Git.\n' +
        'Дописати останнім рядком тіла: Co-Authored-By: Claude <модель> <noreply@anthropic.com>'
    );
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

/**
 * Чи видно текст повідомлення прямо в команді. `git commit` без прапорця відкриває
 * редактор, `--amend --no-edit` і `-C HEAD` переносять старе повідомлення — у всіх
 * трьох трейлера в команді нема ЗА ПОБУДОВОЮ, і блокувати їх означало б ловити не
 * те. Гейт спрацьовує лише там, де повідомлення справді складається зараз.
 */
function messageIsInCommand(command) {
  return /(^|\s)(-m\b|--message\b|-F\s*-|--file[= ]-)/.test(command);
}

/**
 * Гілка, на якій стоїть HEAD. Відірваний HEAD (`rebase`, `cherry-pick`, `bisect`)
 * віддає рядок "HEAD" — і це свідомо НЕ блокується: лінеаризація власної історії
 * перед вливанням у master дозволена (DECISIONS 2026-07-29), а коміти всередині
 * rebase взагалі не проходять через цей хук.
 */
function currentBranch() {
  const r = spawnSync('git', ['rev-parse', '--abbrev-ref', 'HEAD'], { encoding: 'utf8' });
  return r.status === 0 ? r.stdout.trim() : '';
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
