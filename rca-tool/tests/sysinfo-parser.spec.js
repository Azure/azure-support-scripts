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

test('sysinfo parser extracts Distribution line from worker', async () => {
  // osRelease parser is now in external module, so load from there
  const parserPath = path.join(__dirname, '..', 'src', 'parsers', 'unix.js');
  const code = fs.readFileSync(parserPath, 'utf8');

  // Extract the parseSysinfo helper function from osReleaseParser
  const parseSysinfoMarker = 'parseSysinfo: function(content, filename)';
  const parseSysinfoIdx = code.indexOf(parseSysinfoMarker);
  if (parseSysinfoIdx === -1) throw new Error('parseSysinfo helper not found');

  const funcStart = code.indexOf('function', parseSysinfoIdx);
  if (funcStart === -1) throw new Error('parseSysinfo function keyword not found');
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
  if (bodyEnd === -1) throw new Error('Could not locate end of parseSysinfo function body');

  const fnBody = code.substring(bodyStart + 1, bodyEnd);
  // Create a function with debugLog stub in scope
  const parseFn = new Function('content', 'filename', 'debugLog', fnBody);

  const sample = `#####Cluster info:
Corosync Cluster Engine, version '2.4.6'

#####System info:
Platform: Linux
Kernel release: 5.14.21-150500.55.83-default
Architecture: x86_64
Distribution: SUSE Linux Enterprise Server 15 SP5`;
  
  const result = parseFn(sample, 'sysinfo.txt', function(){});

  expect(result).toBeTruthy();
  expect(result.found).toBe(true);
  expect(result.prettyName).toBe('SUSE Linux Enterprise Server 15 SP5');
});
