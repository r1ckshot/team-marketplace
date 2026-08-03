#!/usr/bin/env node
/**
 * PreToolUse + matcher Write|Edit — межа шарів у момент запису файлу.
 *
 * Ті самі п'ять правил, що в `.dependency-cruiser.cjs` (`npm run test:arch`), але
 * на крок раніше: depcruise бачить порушення лише після того, як файл записано,
 * тести прогнано і час витрачено. Хук зупиняє на спробі запису й називає те саме
 * правило тим самим іменем — щоб два механізми не розповідали різні історії.
 *
 * Хук НЕ замінює depcruise: він дивиться на текст однієї правки й не бачить графа
 * цілком (транзитивні залежності, цикли). Тому `test:arch` лишається джерелом
 * правди, а це — швидкий фільтр найчастіших помилок.
 */

const CORE = /^app\/lib\/(rules|calc)\//;
const RULES_DIR = /^app\/lib\/rules\//;
const LIB = /^app\/lib\//;
const PRESENTATION = /^app\/components\/|^app\/[^/]*\.tsx$|^app\/.*\/page\.tsx$/;
const TESTS = /__tests__|\.test\.[tj]sx?$/;

const ADAPTER_SPECIFIER = /^@\/lib\/(storage|share|format)(\.ts)?$|^@\/lib\/(questions|i18n)\//;
const PRESENTATION_SPECIFIER = /^@\/components\/|\/page$|^@\/app\//;
const RAW_RULE_DATA = /rules\.\d{4}\.json$/;

let raw = '';
process.stdin.on('data', (d) => (raw += d));
process.stdin.on('end', () => {
  let payload;
  try {
    payload = JSON.parse(raw || '{}');
  } catch {
    process.exit(0);
  }

  const input = payload.tool_input || {};
  const filePath = normalize(input.file_path || '');
  if (!filePath.startsWith('app/') || TESTS.test(filePath)) process.exit(0);

  // Write несе весь файл, Edit — лише новий фрагмент. Перевіряти достатньо те, що
  // саме зараз з'явиться в файлі: правило порушує новий імпорт, не старі рядки.
  const text = input.content ?? input.new_string ?? '';
  if (!text) process.exit(0);

  for (const specifier of importSpecifiers(text)) {
    const violation = check(filePath, specifier);
    if (violation) {
      deny(
        `${violation.rule}: ${violation.why}\n\n` +
          `Файл:    ${filePath}\n` +
          `Імпорт:  ${specifier}\n\n` +
          'Межа описана в ARCHITECTURE.md і тримається `npm run test:arch`. ' +
          'Якщо межа справді має змінитись — це рішення для DECISIONS.md, а не правка нашвидкуруч.'
      );
      return;
    }
  }

  process.exit(0);
});

/** Абсолютний шлях → відносний до кореня репо; зворотні слеші → прямі. */
function normalize(filePath) {
  return filePath.replace(/\\/g, '/').replace(`${process.cwd().replace(/\\/g, '/')}/`, '');
}

/**
 * Специфікатори з `import ... from 'x'`, голого `import 'x'`, динамічного
 * `import('x')` і `require('x')`. Регексом, а не парсером: хук має бути миттєвим
 * і без залежностей, а всі чотири форми в цьому репо пишуться однорядково.
 */
function importSpecifiers(text) {
  const found = new Set();
  const patterns = [
    /\bimport\s+[^;'"]*\bfrom\s*['"]([^'"]+)['"]/g,
    /\bimport\s*['"]([^'"]+)['"]/g,
    /\bimport\s*\(\s*['"]([^'"]+)['"]\s*\)/g,
    /\brequire\s*\(\s*['"]([^'"]+)['"]\s*\)/g,
  ];
  for (const pattern of patterns) {
    for (const match of text.matchAll(pattern)) found.add(match[1]);
  }
  return found;
}

/** Голий специфікатор = npm-пакет. `@/` — наш аліас на app/, не scope-пакет. */
function isNpm(specifier) {
  return !specifier.startsWith('.') && !specifier.startsWith('/') && !specifier.startsWith('@/');
}

function check(filePath, specifier) {
  if (CORE.test(filePath) && isNpm(specifier)) {
    return {
      rule: 'core-no-external',
      why: 'ядро (rules/, calc/) не має npm-залежностей — ні react, ні next, ні будь-чого ще: розрахунок мусить рахуватись у голому Node.',
    };
  }

  if (RULES_DIR.test(filePath) && !isNpm(specifier) && !isWithinRules(filePath, specifier)) {
    return {
      rule: 'rules-are-leaf',
      why: 'rules/ — найнижчий шар: дані й типи. Він не імпортує нічого, крім самого себе.',
    };
  }

  if (CORE.test(filePath) && ADAPTER_SPECIFIER.test(specifier)) {
    return {
      rule: 'core-no-adapters',
      why: 'ядро не знає про адаптери (storage, share, format, questions, i18n) — залежність іде в інший бік.',
    };
  }

  if (LIB.test(filePath) && PRESENTATION_SPECIFIER.test(specifier)) {
    return {
      rule: 'lib-no-presentation',
      why: 'жоден файл app/lib/** не імпортує компоненти чи сторінки — інакше логіка почне залежати від UI.',
    };
  }

  if (PRESENTATION.test(filePath) && RAW_RULE_DATA.test(specifier)) {
    return {
      rule: 'ui-no-raw-rule-data',
      why: 'цифри доходять до UI лише через calc/, ніколи прямим читанням rules.2026.json — інакше показане число обійде розрахунок і власні тести.',
    };
  }

  return null;
}

/** Усередині rules/ дозволені лише сусіди: `./x`, `@/lib/rules/x`. */
function isWithinRules(filePath, specifier) {
  if (specifier.startsWith('@/')) return specifier.startsWith('@/lib/rules/');
  if (!specifier.startsWith('.')) return false;
  const dir = filePath.slice(0, filePath.lastIndexOf('/'));
  const resolved = new URL(specifier, `file:///${dir}/`).pathname.slice(1);
  return RULES_DIR.test(resolved);
}

function deny(reason) {
  console.log(
    JSON.stringify({
      hookSpecificOutput: {
        hookEventName: 'PreToolUse',
        permissionDecision: 'deny',
        permissionDecisionReason: reason,
      },
    })
  );
  process.exit(0);
}
