/**
 * @module parsers/hana
 * @description SAP HANA trace-file parser shims delegated to
 * `supportfile_core` Rust.
 *
 * Currently exposes a single detector, `hanaSavepointsParser`, which scans
 * HANA `indexserver_*.trc` / `nameserver_*.trc` trace files for savepoint
 * activity (periodic flushes of changed pages to the data volume) and flags
 * slow savepoint callbacks and abnormal savepoint cadence.
 *
 * These traces are NOT part of a standard sosreport / supportconfig bundle —
 * they are collected separately (e.g. a HANA log ZIP). The parser is
 * content-driven, so feeding it unrelated `.trc` files is harmless.
 *
 * Rust-backed entrypoint: `parseHanaSavepoints`.
 */

function _hanaWasmCall(fnName, content, filename) {
    if (typeof WASM_BRIDGE === 'undefined' || !WASM_BRIDGE.isReady()) {
        return null;
    }
    try {
        return WASM_BRIDGE.parseJson(fnName, content, filename || '');
    } catch (err) {
        console.error('[hana.js]', fnName, 'WASM call failed:', err);
        return null;
    }
}

const hanaSavepointsParser = {
    // indexserver_*.trc / nameserver_*.trc HANA trace files.
    filePattern: /\/(indexserver|nameserver)[^/]*\.trc$/,

    parse: function(content, filename, _lines) {
        const result = _hanaWasmCall('parseHanaSavepoints', content, filename);
        if (!result) {
            return { found: false, count: 0, snapshotCount: 0, savepoints: [], warnings: [] };
        }
        return result;
    },

    // Multi-file: HANA spreads savepoint lines across several trace files.
    // Concatenate savepoint/warning records, sum the counts, and keep the
    // most recent timestamp plus the widest observed interval.
    mergeResults: function(existing, newResult) {
        if (!existing || !existing.found) return newResult;
        if (!newResult || !newResult.found) return existing;

        const spKey = (s) => `${(s && s.sourcePath) || ''}|${(s && s.sourceLine) || ''}|${(s && s.savepointVersion) || ''}`;
        const warnKey = (w) => `${(w && w.type) || ''}|${(w && w.sourcePath) || ''}|${(w && w.sourceLine) || ''}`;

        const seenSp = new Set((existing.savepoints || []).map(spKey));
        const mergedSp = (existing.savepoints || []).slice();
        for (const s of newResult.savepoints || []) {
            const key = spKey(s);
            if (!seenSp.has(key)) {
                seenSp.add(key);
                mergedSp.push(s);
            }
        }

        const seenWarn = new Set((existing.warnings || []).map(warnKey));
        const mergedWarn = (existing.warnings || []).slice();
        for (const w of newResult.warnings || []) {
            const key = warnKey(w);
            if (!seenWarn.has(key)) {
                seenWarn.add(key);
                mergedWarn.push(w);
            }
        }

        const count = (existing.count || 0) + (newResult.count || 0);
        const snapshotCount = (existing.snapshotCount || 0) + (newResult.snapshotCount || 0);

        // Count-weighted average interval; widest max interval.
        const ea = existing.avgIntervalS, na = newResult.avgIntervalS;
        const ec = existing.count || 0, nc = newResult.count || 0;
        let avg = null;
        if (ea != null && na != null && (ec + nc) > 0) {
            avg = (ea * ec + na * nc) / (ec + nc);
        } else {
            avg = ea != null ? ea : na;
        }
        const maxInterval = Math.max(existing.maxIntervalS || 0, newResult.maxIntervalS || 0) || null;

        const lastA = existing.lastSavepoint || '';
        const lastB = newResult.lastSavepoint || '';
        const last = lastB > lastA ? lastB : lastA;

        return {
            found: true,
            count: count,
            snapshotCount: snapshotCount,
            lastSavepoint: last || null,
            avgIntervalS: avg,
            maxIntervalS: maxInterval,
            savepoints: mergedSp,
            warnings: mergedWarn,
            sourcePath: existing.sourcePath || newResult.sourcePath,
        };
    },
};

// ---------------------------------------------------------------------------
// Shared merge helpers for the aggregate HANA detectors (deadlocks, OOM,
// merge errors). The WASM bridge has already converted snake_case keys to
// camelCase by the time `mergeResults` runs.
// ---------------------------------------------------------------------------

const _HANA_TOP_N = 10;
const _HANA_MAX_RECORDS = 1000;

// Match `indexserver_*.trc` / `nameserver_*.trc` HANA trace files.
const _HANA_TRC_PATTERN = /\/(indexserver|nameserver)[^/]*\.trc$/;

// Merge two `[{name, count}]` tallies by summing counts per name, then keep
// the top-N (count desc, name asc) — mirrors the Rust `top_counts`.
function _hanaMergeTopCounts(a, b) {
    const m = new Map();
    for (const list of [a || [], b || []]) {
        for (const c of list) {
            if (!c || !c.name) continue;
            m.set(c.name, (m.get(c.name) || 0) + (c.count || 0));
        }
    }
    return [...m.entries()]
        .map(([name, count]) => ({ name, count }))
        .sort((x, y) => y.count - x.count || (x.name < y.name ? -1 : x.name > y.name ? 1 : 0))
        .slice(0, _HANA_TOP_N);
}

function _hanaCapConcat(a, b, cap) {
    const out = (a || []).slice();
    for (const x of b || []) {
        if (out.length >= cap) break;
        out.push(x);
    }
    return out;
}

function _hanaMaxTs(a, b) {
    a = a || '';
    b = b || '';
    return (b > a ? b : a) || null;
}

const hanaDeadlocksParser = {
    filePattern: _HANA_TRC_PATTERN,

    parse: function(content, filename, _lines) {
        const result = _hanaWasmCall('parseHanaDeadlocks', content, filename);
        if (!result) {
            return { found: false, count: 0, topObjects: [], topStatements: [], deadlocks: [], warnings: [] };
        }
        return result;
    },

    mergeResults: function(existing, newResult) {
        if (!existing || !existing.found) return newResult;
        if (!newResult || !newResult.found) return existing;

        const count = (existing.count || 0) + (newResult.count || 0);
        const topObjects = _hanaMergeTopCounts(existing.topObjects, newResult.topObjects);
        const topStatements = _hanaMergeTopCounts(existing.topStatements, newResult.topStatements);
        const deadlocks = _hanaCapConcat(existing.deadlocks, newResult.deadlocks, _HANA_MAX_RECORDS);
        const last = _hanaMaxTs(existing.lastDeadlock, newResult.lastDeadlock);

        const severity = count >= 25 ? 'error' : 'warning';
        const topObj = topObjects.length
            ? `${topObjects[0].name} (${topObjects[0].count} deadlocks)`
            : 'unknown';
        const first = deadlocks[0] || {};
        const lastD = deadlocks[deadlocks.length - 1] || {};
        const warning = {
            type: 'hana_deadlocks_detected',
            message: `${count} deadlock(s) detected; HANA rolled back a victim transaction each time`,
            details: `Most contended object: ${topObj}`,
            severity: severity,
            recommendation: "Recurring deadlocks usually mean concurrent transactions update the same rows in different orders. Review the contended table/statement and the application's update ordering, batch size, and commit frequency.",
            sourcePath: existing.sourcePath || newResult.sourcePath,
            sourceLine: first.sourceLine,
            sourceLineEnd: lastD.sourceLineEnd,
        };

        return {
            found: true,
            count: count,
            lastDeadlock: last,
            topObjects: topObjects,
            topStatements: topStatements,
            deadlocks: deadlocks,
            warnings: [warning],
            sourcePath: existing.sourcePath || newResult.sourcePath,
        };
    },
};

const hanaOomParser = {
    filePattern: _HANA_TRC_PATTERN,

    parse: function(content, filename, _lines) {
        const result = _hanaWasmCall('parseHanaOom', content, filename);
        if (!result) {
            return { found: false, count: 0, events: [], warnings: [] };
        }
        return result;
    },

    mergeResults: function(existing, newResult) {
        if (!existing || !existing.found) return newResult;
        if (!newResult || !newResult.found) return existing;

        const count = (existing.count || 0) + (newResult.count || 0);
        const events = _hanaCapConcat(existing.events, newResult.events, _HANA_MAX_RECORDS);
        const last = _hanaMaxTs(existing.lastOom, newResult.lastOom);

        const e0 = events[0] || {};
        const eLast = events[events.length - 1] || {};
        const ft = e0.failureType || 'unknown';
        const host = e0.host || '?';
        const warning = {
            type: 'hana_out_of_memory',
            message: `${count} HANA out-of-memory event(s) — an allocation hit the global allocation limit`,
            details: `First OOM on ${host}: allocation failure type ${ft}`,
            severity: 'error',
            recommendation: 'OOM means HANA could not allocate within its global allocation limit. Check the largest memory consumers (column-store tables, statement memory, heap allocators), reduce statement_memory_limit offenders, and verify the host has enough physical RAM for the configured limit.',
            sourcePath: existing.sourcePath || newResult.sourcePath,
            sourceLine: e0.sourceLine,
            sourceLineEnd: eLast.sourceLineEnd,
        };

        return {
            found: true,
            count: count,
            lastOom: last,
            events: events,
            warnings: [warning],
            sourcePath: existing.sourcePath || newResult.sourcePath,
        };
    },
};

const hanaMergeErrorsParser = {
    filePattern: _HANA_TRC_PATTERN,

    parse: function(content, filename, _lines) {
        const result = _hanaWasmCall('parseHanaMergeErrors', content, filename);
        if (!result) {
            return { found: false, count: 0, mergeErrorCount: 0, compressionErrorCount: 0, tokenExhaustionCount: 0, topTables: [], errors: [], warnings: [] };
        }
        return result;
    },

    mergeResults: function(existing, newResult) {
        if (!existing || !existing.found) return newResult;
        if (!newResult || !newResult.found) return existing;

        const count = (existing.count || 0) + (newResult.count || 0);
        const mergeErrorCount = (existing.mergeErrorCount || 0) + (newResult.mergeErrorCount || 0);
        const compressionErrorCount = (existing.compressionErrorCount || 0) + (newResult.compressionErrorCount || 0);
        const tokenExhaustionCount = (existing.tokenExhaustionCount || 0) + (newResult.tokenExhaustionCount || 0);
        const topTables = _hanaMergeTopCounts(existing.topTables, newResult.topTables);
        const errors = _hanaCapConcat(existing.errors, newResult.errors, _HANA_MAX_RECORDS);
        const last = _hanaMaxTs(existing.lastError, newResult.lastError);

        const severity = count >= 50 ? 'error' : 'warning';
        let message, recommendation;
        if (tokenExhaustionCount > 0) {
            message = `${count} delta-merge / compression failure(s); ${tokenExhaustionCount} due to merge-token exhaustion (rc=2465)`;
            recommendation = 'Merge-token exhaustion (rc=2465) means too many merges were requested at once, often a symptom of memory pressure or a merge backlog. Check for concurrent OOM events, the mergedog configuration, and whether large tables need manual / smart merge tuning.';
        } else {
            message = `${count} delta-merge / optimize-compression failure(s) in HANA`;
            recommendation = 'Failed merges leave tables with an oversized delta storage, hurting query performance and memory. Review the affected tables and the indexserver alert trace for the underlying cause.';
        }
        const e0 = errors[0] || {};
        const eLast = errors[errors.length - 1] || {};
        const warning = {
            type: 'hana_merge_failures',
            message: message,
            details: topTables.length ? `Most affected table: ${topTables[0].name} (${topTables[0].count} failures)` : null,
            severity: severity,
            recommendation: recommendation,
            sourcePath: existing.sourcePath || newResult.sourcePath,
            sourceLine: e0.sourceLine,
            sourceLineEnd: eLast.sourceLineEnd,
        };

        return {
            found: true,
            count: count,
            mergeErrorCount: mergeErrorCount,
            compressionErrorCount: compressionErrorCount,
            tokenExhaustionCount: tokenExhaustionCount,
            lastError: last,
            topTables: topTables,
            errors: errors,
            warnings: [warning],
            sourcePath: existing.sourcePath || newResult.sourcePath,
        };
    },
};
