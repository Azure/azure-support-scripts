/**
 * @module tests/coverage-fixture
 * @description Playwright auto-fixture that collects V8 code coverage for both
 * the main thread and Web Worker threads.
 *
 * ### Main-thread coverage
 *
 * Uses Playwright's built-in `page.coverage` API (V8) to collect
 * per-byte JS and CSS coverage for the bundled UI code.
 *
 * ### Worker / parser coverage
 *
 * Source files loaded by the Web Worker (`worker.js`, `utils.js`,
 * `src/parsers/*.js`) are instrumented with Istanbul counters by
 * `instrument-coverage.sh`.  A postMessage hook in the instrumented
 * worker piggybacks the `__coverage__` object on every message sent
 * to the main thread.  This fixture captures that data, converts it
 * from Istanbul format to V8 `ScriptCoverage` entries, and feeds
 * everything to monocart-reporter as a single V8 data set.
 *
 * ### Usage
 *
 * Import `{ test, expect }` from this module instead of
 * `@playwright/test` in every spec file that exercises the web app.
 *
 * ```js
 * import { test, expect } from './coverage-fixture.js';
 * ```
 */

import { readFileSync } from 'fs';
import { test as baseTest, expect } from '@playwright/test';
import { addCoverageReport } from 'monocart-reporter';

// ─── Istanbul → V8 converter ──────────────────────────────────────────────────
/**
 * Convert an Istanbul `__coverage__` object into an array of V8
 * `ScriptCoverage` entries that monocart-reporter can process.
 *
 * For each file we read the original source from disk, translate
 * Istanbul's line:column locations to byte offsets, and produce
 * V8-style `functions` arrays with nested `ranges`.
 *
 * @param {Object} istanbulCoverage  The `__coverage__` global from the worker.
 * @returns {Array} V8-compatible coverage entries.
 */
function istanbulToV8(istanbulCoverage) {
  const entries = [];

  for (const [filePath, fileCov] of Object.entries(istanbulCoverage)) {
    let source;
    try {
      source = readFileSync(filePath, 'utf8');
    } catch {
      continue; // file not found (e.g. in CI with different absolute paths)
    }

    // Build a map of line number (1-based) → byte offset of line start.
    const lineOffsets = [0];
    for (let i = 0; i < source.length; i++) {
      if (source[i] === '\n') lineOffsets.push(i + 1);
    }

    /** Convert Istanbul {line, column} (1-based line, 0-based col) to byte offset. */
    const toOffset = (loc) => {
      const lineStart = lineOffsets[loc.line - 1] ?? 0;
      return Math.min(lineStart + loc.column, source.length);
    };

    // ── Build V8-style functions array ───────────────────────────────
    // Each function maps to a V8 "FunctionCoverage" with isBlockCoverage=true,
    // and nested ranges represent the function body blocks.
    const functions = [];

    // Top-level pseudo-function covering the entire file (required by V8 format)
    const topRanges = [{ startOffset: 0, endOffset: source.length, count: 1 }];
    // Add uncovered statements as count:0 ranges
    for (const [idx, loc] of Object.entries(fileCov.statementMap)) {
      const count = fileCov.s[idx] ?? 0;
      if (count === 0) {
        topRanges.push({
          startOffset: toOffset(loc.start),
          endOffset: toOffset(loc.end),
          count: 0
        });
      }
    }
    functions.push({
      functionName: '',
      isBlockCoverage: true,
      ranges: topRanges
    });

    // Named functions
    for (const [idx, fn] of Object.entries(fileCov.fnMap)) {
      const count = fileCov.f[idx] ?? 0;
      functions.push({
        functionName: fn.name || `(anonymous_${idx})`,
        isBlockCoverage: true,
        ranges: [{
          startOffset: toOffset(fn.loc.start),
          endOffset: toOffset(fn.loc.end),
          count
        }]
      });
    }

    entries.push({
      url: `file://${filePath}`,
      scriptId: String(entries.length + 1),
      source,
      functions
    });
  }

  return entries;
}

// ─── Test fixture ─────────────────────────────────────────────────────────────
const test = baseTest.extend({
  autoTestFixture: [async ({ page }, use) => {

    // V8 coverage API is Chromium-only (works with msedge)
    const isChromium = ['Desktop Edge', 'Desktop Chrome', 'Desktop Chromium']
      .some(name => test.info().project.name === 'local' || test.info().project.name === 'deployed');

    if (isChromium) {
      await Promise.all([
        page.coverage.startJSCoverage({ resetOnNavigation: false }),
        page.coverage.startCSSCoverage({ resetOnNavigation: false })
      ]);
    }

    // ── Istanbul Worker setup ──────────────────────────────────────────
    // Override the Worker constructor so that any message carrying
    // __istanbulCoverage (piggybacked by instrument-coverage.sh) is
    // captured on the main thread before the worker is terminated.
    await page.addInitScript(() => {
      window.__workerCoverages = [];
      const OrigWorker = window.Worker;
      window.Worker = function Worker(url, opts) {
        const w = new OrigWorker(url, opts);
        w.addEventListener('message', function(e) {
          if (e.data && e.data.__istanbulCoverage) {
            window.__workerCoverages.push(e.data.__istanbulCoverage);
          }
        });
        return w;
      };
      window.Worker.prototype = OrigWorker.prototype;
    });

    await use('autoTestFixture');

    // ── V8 coverage (main thread) ──────────────────────────────────────
    if (isChromium) {
      const [jsCoverage, cssCoverage] = await Promise.all([
        page.coverage.stopJSCoverage(),
        page.coverage.stopCSSCoverage()
      ]);
      const coverageList = [...jsCoverage, ...cssCoverage];
      await addCoverageReport(coverageList, test.info());
    }

    // ── Istanbul → V8 coverage (Web Workers) ───────────────────────────
    // Retrieve Istanbul data captured from worker postMessage calls,
    // convert to V8 ScriptCoverage format, and pass to monocart so
    // both main-thread and worker coverage appear in one report.
    const workerCoverages = await page.evaluate(
      () => window.__workerCoverages || []
    );
    if (workerCoverages.length > 0) {
      // Use the last snapshot — it has the most complete counters.
      const latest = workerCoverages[workerCoverages.length - 1];
      const v8Entries = istanbulToV8(latest);
      if (v8Entries.length > 0) {
        await addCoverageReport(v8Entries, test.info());
      }
    }

  }, {
    scope: 'test',
    auto: true
  }]
});

export { test, expect };
