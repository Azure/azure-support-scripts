/**
 * Performance module loader for CLI
 * 
 * Loads the shared src/performance.js (which is a plain script, not ESM)
 * and re-exports its classes and functions for use in CLI ESM code.
 */

import fs from 'fs';
import path from 'path';
import vm from 'vm';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

// Read the shared performance module
const perfPath = path.join(__dirname, '..', 'src', 'performance.js');
const perfCode = fs.readFileSync(perfPath, 'utf8');

// Evaluate in a sandbox that mimics the global scope
const sandbox = {
    performance: globalThis.performance,
    self: {},           // captures the exported symbols
    console: console,
};
const script = new vm.Script(perfCode, { filename: 'performance.js' });
const context = vm.createContext(sandbox);
script.runInContext(context);

// Re-export
export const PerformanceTracker = sandbox.self.PerformanceTracker;
export const countEvents = sandbox.self.countEvents;
export const formatPerformanceReport = sandbox.self.formatPerformanceReport;
