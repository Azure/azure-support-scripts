#!/bin/bash
# Instrument source files with Istanbul for coverage collection in Web Workers.
#
# This script instruments src/parsers/, src/utils.js, and src/worker.js
# with Istanbul counters and copies the instrumented files into web/dist/
# (overwriting the un-instrumented copies produced by the Vite build).
#
# Run AFTER `bash build.sh` and BEFORE `npx playwright test`.
#
# Istanbul writes per-file coverage counters to `self.__coverage__` in the
# worker scope.  The coverage-fixture.js auto-fixture collects this data
# after each test and feeds it to monocart-reporter.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR/.."
DIST_DIR="$PROJECT_ROOT/web/dist"
TMPDIR=$(mktemp -d)

trap 'rm -rf "$TMPDIR"' EXIT

echo "Instrumenting source files for coverage..."

# nyc requires the files to be inside its project root, so run from rca-tool/
cd "$PROJECT_ROOT"

# Instrument parser files (paths in __coverage__ will reference src/parsers/)
npx --prefix tests nyc instrument src/parsers "$TMPDIR/parsers" --compact false
cp "$TMPDIR/parsers"/*.js "$DIST_DIR/parsers/"
echo "  ✓ parsers/"

# Instrument utils.js
npx --prefix tests nyc instrument src/utils.js "$TMPDIR" --compact false
cp "$TMPDIR/src/utils.js" "$DIST_DIR/utils.js"
echo "  ✓ utils.js"

# Instrument worker.js (renamed to liblzma-streaming-worker.js in the build)
npx --prefix tests nyc instrument src/worker.js "$TMPDIR" --compact false
cp "$TMPDIR/src/worker.js" "$DIST_DIR/liblzma-streaming-worker.js"
echo "  ✓ worker.js → liblzma-streaming-worker.js"

# Inject a postMessage hook into the instrumented worker so that __coverage__
# data piggybacks on every message sent back to the main thread.  This lets the
# test fixture capture coverage even though the worker is terminated right after
# sending results.
#
# Also define DEBUG_CONFIG so that parser debugLog() bodies are exercised,
# covering the otherwise-untestable console.log branches.
WORKER="$DIST_DIR/liblzma-streaming-worker.js"

cat >> "$WORKER" << 'COVERAGE_HOOK'

// --- Istanbul Coverage Hook (injected by instrument-coverage.sh) ---
// Piggybacks __coverage__ data onto every postMessage from the worker so the
// main-thread test fixture can capture it before the worker is terminated.
(function() {
  var _origPost = self.postMessage;
  self.postMessage = function(data) {
    if (typeof __coverage__ !== 'undefined' && data && typeof data === 'object') {
      data.__istanbulCoverage = __coverage__;
    }
    return _origPost.apply(self, arguments);
  };
})();
COVERAGE_HOOK
echo "  ✓ coverage hook injected into worker"

# Enable debug logging for all parsers so debugLog() console.log branches
# are exercised during tests, covering those otherwise-untestable lines.
# DEBUG_CONFIG is a const object in the worker — its properties are mutable.
cat >> "$WORKER" << 'DEBUG_HOOK'

// --- Debug Config Enablement (injected by instrument-coverage.sh) ---
// Turns on debugLog() for every parser so coverage captures the console.log body.
if (typeof DEBUG_CONFIG !== 'undefined') {
  Object.keys(DEBUG_CONFIG).forEach(function(k) { DEBUG_CONFIG[k] = true; });
}
DEBUG_HOOK
echo "  ✓ debug config enablement injected"

echo "Instrumentation complete."
