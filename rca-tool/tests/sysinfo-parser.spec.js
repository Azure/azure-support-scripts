import { test, expect } from '@playwright/test';

// Lightweight sysinfo parser (extracted for unit testing)
function parseSysinfo(text) {
  if (!text || typeof text !== 'string') return { found: false };
  const lines = text.split(/\r?\n/);
  for (const raw of lines) {
    const line = (raw || '').trim();
    const m = /^Distribution:\s*(.+)$/i.exec(line);
    if (m) {
      return { found: true, distribution: m[1].trim() };
    }
  }
  return { found: false };
}

test('extracts Distribution from sysinfo.txt', async () => {
  const sample = `System Summary\nDistribution: Ubuntu 20.04.6 LTS\nKernel: 5.15.0-1034`;
  const res = parseSysinfo(sample);
  expect(res.found).toBe(true);
  expect(res.distribution).toBe('Ubuntu 20.04.6 LTS');
});

test('returns not found when Distribution line is missing', async () => {
  const sample = `Some header\nNo relevant data here\nAnother line`;
  const res = parseSysinfo(sample);
  expect(res.found).toBe(false);
});
import fs from 'fs';
import path from 'path';
import vm from 'vm';

test('sysinfo parser extracts Distribution line', async () => {
  const workerPath = path.join(__dirname, '..', 'liblzma-streaming-worker.js');
  const code = fs.readFileSync(workerPath, 'utf8');

  // Evaluate the worker file in a fresh VM context so we can access SCC_RULES
  // Provide stubs for worker-specific globals to avoid runtime errors
  const context = {
    console,
    setTimeout,
    clearTimeout,
    importScripts: () => {},
    postMessage: () => {},
    self: {},
    navigator: {},
    // Stubs for streaming/wasm helpers used in the worker file
    LZMA_XZ_Streaming_Module: () => Promise.resolve({}),
    Module: {},
    WebAssembly: {},
    fetch: async () => ({ ok: true }),
    TextDecoder: global.TextDecoder || function() { this.decode = (b) => Buffer.from(b).toString(); }
  };
  vm.createContext(context);

  // Instead of executing the entire worker (which triggers wasm/worker init),
  // extract the SCC_RULES object literal and evaluate only that portion.
  const marker = 'const SCC_RULES =';
  const markerIdx = code.indexOf(marker);
  if (markerIdx === -1) throw new Error('SCC_RULES marker not found in worker file');
  const braceStart = code.indexOf('{', markerIdx);
  if (braceStart === -1) throw new Error('Could not find start of SCC_RULES object');

  // Find matching closing brace for the SCC_RULES object literal
  let depth = 0;
  let endPos = -1;
  for (let i = braceStart; i < code.length; i++) {
    const ch = code[i];
    if (ch === '{') depth++;
    else if (ch === '}') {
      depth--;
      if (depth === 0) { endPos = i; break; }
    }
  }
  if (endPos === -1) throw new Error('Failed to locate end of SCC_RULES object');

  // Evaluate all top-of-file setup up through the end of SCC_RULES so helper
  // functions (e.g. debugLog) are available, but avoid the rest of the file
  // Extract only the `parse` function body for the sysinfo rule and create a callable function
  const sysinfoIdx = code.indexOf('sysinfo:', markerIdx);
  if (sysinfoIdx === -1) throw new Error('sysinfo rule not found');

  const parseIdx = code.indexOf('parse:', sysinfoIdx);
  if (parseIdx === -1) throw new Error('parse function for sysinfo not found');

  const funcStart = code.indexOf('function', parseIdx);
  if (funcStart === -1) throw new Error('parse function keyword not found');
  const bodyStart = code.indexOf('{', funcStart);
  // Find matching closing brace for the function body
  let d = 0;
  let bodyEnd = -1;
  for (let i = bodyStart; i < code.length; i++) {
    if (code[i] === '{') d++;
    else if (code[i] === '}') {
      d--;
      if (d === 0) { bodyEnd = i; break; }
    }
  }
  if (bodyEnd === -1) throw new Error('Could not locate end of parse function body');

  const fnBody = code.substring(bodyStart + 1, bodyEnd);
  // Create a function with debugLog stub in scope
  const parseFn = new Function('content', 'filename', 'debugLog', fnBody + '\nreturn undefined;');

  const sample = `Some header\nDistribution: SUSE Linux Enterprise Server 12 SP3\nOther: value`;
  const result = parseFn(sample, 'sysinfo.txt', function(){});

  expect(result).toBeTruthy();
  expect(result.found).toBe(true);
  expect(result.distribution).toBe('SUSE Linux Enterprise Server 12 SP3');
});
