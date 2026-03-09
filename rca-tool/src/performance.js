/**
 * @module performance
 * @description Shared performance tracking and reporting for RCA Tool.
 *
 * Used by both the CLI (Node.js) and the web worker to produce
 * identical timing reports.  The module is environment-agnostic:
 *   - In a Web Worker it is loaded via importScripts().
 *   - In Node/CLI it is imported as an ES module.
 *
 * Usage:
 *   const tracker = new PerformanceTracker();   // call at start
 *   tracker.startFile(filename);                // before processing a file
 *   tracker.recordDecode(ms);                   // after content decode
 *   tracker.recordParser(parserName, ms, result, accumulated);
 *   tracker.endFile(filename, contentLength, parserCount);
 *   ...
 *   const report = tracker.getReport();         // raw data object
 *   const text   = formatPerformanceReport(report, memoryMB);
 */

// ---------------------------------------------------------------------------
// PerformanceTracker – collects raw timing entries
// ---------------------------------------------------------------------------

class PerformanceTracker {
    constructor() {
        this.fileEntries = [];     // { file, size, parsers, totalMs, decodeMs }
        this.parserEntries = [];   // { file, parser, parseMs, events, accumulated }
        this.startTime = performance.now();
        this.totalBytes = 0;
        this.totalFiles = 0;

        // Per-file transient state
        this._fileStart = 0;
        this._decodeMs = 0;
    }

    /** Call before processing each file */
    startFile() {
        this._fileStart = performance.now();
        this._decodeMs = 0;
    }

    /** Record content-decode time for the current file */
    recordDecode(ms) {
        this._decodeMs = ms;
    }

    /**
     * Record one parser invocation for the current file.
     * @param {string} file      – canonical filename
     * @param {string} parser    – parser/rule name
     * @param {number} parseMs   – wall-clock ms for the parse call
     * @param {object} result    – the parser's return value (used to count events)
     * @param {object} [accumulatedResult] – the merged result so far (for accumulated count)
     */
    recordParser(file, parser, parseMs, result, accumulatedResult) {
        this.parserEntries.push({
            file,
            parser,
            parseMs,
            events: countEvents(result),
            accumulated: accumulatedResult ? countEvents(accumulatedResult) : 0
        });
    }

    /**
     * Finalise tracking for one file.
     * @param {string} file         – canonical filename
     * @param {number} contentLen   – byte length of the decoded content
     * @param {number} parserCount  – how many parsers matched this file
     */
    endFile(file, contentLen, parserCount) {
        this.totalBytes += contentLen;
        this.totalFiles++;
        this.fileEntries.push({
            file,
            size: contentLen,
            parsers: parserCount,
            totalMs: performance.now() - this._fileStart,
            decodeMs: this._decodeMs
        });
    }

    /** Return the raw performance data object */
    getReport() {
        return {
            fileEntries: this.fileEntries,
            parserEntries: this.parserEntries,
            totalTimeMs: performance.now() - this.startTime,
            totalFiles: this.totalFiles,
            totalBytes: this.totalBytes
        };
    }
}

// ---------------------------------------------------------------------------
// countEvents – derive an event count from a heterogeneous parser result
// ---------------------------------------------------------------------------

function countEvents(result) {
    if (!result) return 0;
    if (typeof result.count === 'number') return result.count;
    if (Array.isArray(result.events)) return result.events.length;
    // clusterEvents style
    const migrations = result.resourceMigrations?.length || 0;
    const fencing = result.fencingEvents?.length || 0;
    if (migrations || fencing) return migrations + fencing;
    if (Array.isArray(result.errors)) return result.errors.length;
    return 0;
}

// ---------------------------------------------------------------------------
// formatPerformanceReport – produces the human-readable + TSV report text
// ---------------------------------------------------------------------------

/**
 * Build the full performance report as a single string.
 *
 * @param {object} perfData   – from PerformanceTracker.getReport()
 * @param {number} [memoryMB] – optional peak heap in MB (caller supplies;
 *                               Node uses process.memoryUsage(), browser
 *                               uses performance.memory)
 * @returns {string} multi-line report
 */
function formatPerformanceReport(perfData, memoryMB) {
    const { fileEntries, parserEntries, totalTimeMs, totalFiles, totalBytes } = perfData;
    const lines = [];
    const push = (s) => lines.push(s);

    push('');
    push('='.repeat(70));
    push('  PERFORMANCE REPORT');
    push('='.repeat(70));
    push(`  Total time: ${(totalTimeMs / 1000).toFixed(2)}s`);
    push(`  Files processed: ${totalFiles}`);
    push(`  Files parsed: ${fileEntries.length}`);
    push(`  Total content size: ${(totalBytes / (1024 * 1024)).toFixed(1)} MB`);
    if (memoryMB != null) {
        push(`  Memory peak: ${memoryMB.toFixed(1)} MB`);
    }
    push('');

    // Top 20 slowest files
    const sortedFiles = [...fileEntries].sort((a, b) => b.totalMs - a.totalMs);
    push('  Top 20 slowest files:');
    push(`  ${'File'.padEnd(60)} ${'Size'.padStart(10)} ${'Parsers'.padStart(8)} ${'Time(ms)'.padStart(10)} ${'Decode(ms)'.padStart(11)}`);
    push(`  ${'-'.repeat(60)} ${'-'.repeat(10)} ${'-'.repeat(8)} ${'-'.repeat(10)} ${'-'.repeat(11)}`);
    for (const f of sortedFiles.slice(0, 20)) {
        const shortName = f.file.length > 58 ? '...' + f.file.slice(-55) : f.file;
        const sizeStr = f.size >= 1024 * 1024
            ? `${(f.size / (1024 * 1024)).toFixed(1)}MB`
            : `${(f.size / 1024).toFixed(1)}KB`;
        push(`  ${shortName.padEnd(60)} ${sizeStr.padStart(10)} ${String(f.parsers).padStart(8)} ${f.totalMs.toFixed(1).padStart(10)} ${f.decodeMs.toFixed(1).padStart(11)}`);
    }

    // Top 20 slowest parser invocations
    const sortedParsers = [...parserEntries].sort((a, b) => b.parseMs - a.parseMs);
    push('');
    push('  Top 20 slowest parser calls:');
    push(`  ${'Parser'.padEnd(25)} ${'File'.padEnd(40)} ${'Time(ms)'.padStart(10)} ${'Events'.padStart(8)} ${'Accum'.padStart(8)}`);
    push(`  ${'-'.repeat(25)} ${'-'.repeat(40)} ${'-'.repeat(10)} ${'-'.repeat(8)} ${'-'.repeat(8)}`);
    for (const p of sortedParsers.slice(0, 20)) {
        const shortFile = p.file.length > 38 ? '...' + p.file.slice(-35) : p.file;
        push(`  ${p.parser.padEnd(25)} ${shortFile.padEnd(40)} ${p.parseMs.toFixed(1).padStart(10)} ${String(p.events).padStart(8)} ${String(p.accumulated).padStart(8)}`);
    }

    // Per-parser aggregate
    const parserAgg = {};
    for (const p of parserEntries) {
        if (!parserAgg[p.parser]) parserAgg[p.parser] = { calls: 0, totalMs: 0, totalEvents: 0 };
        parserAgg[p.parser].calls++;
        parserAgg[p.parser].totalMs += p.parseMs;
        parserAgg[p.parser].totalEvents += p.events;
    }
    const sortedAgg = Object.entries(parserAgg).sort((a, b) => b[1].totalMs - a[1].totalMs);
    push('');
    push('  Parser aggregate (all files):');
    push(`  ${'Parser'.padEnd(30)} ${'Calls'.padStart(6)} ${'Total(ms)'.padStart(10)} ${'Avg(ms)'.padStart(10)} ${'Events'.padStart(8)}`);
    push(`  ${'-'.repeat(30)} ${'-'.repeat(6)} ${'-'.repeat(10)} ${'-'.repeat(10)} ${'-'.repeat(8)}`);
    for (const [name, agg] of sortedAgg) {
        push(`  ${name.padEnd(30)} ${String(agg.calls).padStart(6)} ${agg.totalMs.toFixed(1).padStart(10)} ${(agg.totalMs / agg.calls).toFixed(1).padStart(10)} ${String(agg.totalEvents).padStart(8)}`);
    }

    // TSV section for machine parsing
    push('');
    push('  --- TSV DATA (pipe stderr to file for processing) ---');
    push('FILE\tsize\tparsers\ttotal_ms\tdecode_ms');
    for (const f of sortedFiles) {
        push(`FILE\t${f.file}\t${f.size}\t${f.parsers}\t${f.totalMs.toFixed(1)}\t${f.decodeMs.toFixed(1)}`);
    }
    push('PARSER\tfile\tparser\tparse_ms\tevents\taccumulated');
    for (const p of parserEntries) {
        push(`PARSER\t${p.file}\t${p.parser}\t${p.parseMs.toFixed(1)}\t${p.events}\t${p.accumulated}`);
    }
    push('');

    return lines.join('\n');
}

// ---------------------------------------------------------------------------
// Export for Web Worker (importScripts) and CLI (vm.Script sandbox)
// ---------------------------------------------------------------------------

// In a Web Worker, attach to global scope so worker.js can use them.
// In the CLI, the parser-loader sandbox context will also pick these up.
if (typeof self !== 'undefined') {
    self.PerformanceTracker = PerformanceTracker;
    self.countEvents = countEvents;
    self.formatPerformanceReport = formatPerformanceReport;
}
