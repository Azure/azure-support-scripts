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

// Handle both ESM and CJS environments for __dirname
const getDirname = () => {
    // For bundled CJS, use __dirname if available
    if (typeof __dirname !== 'undefined') {
        return __dirname;
    }
    // For ESM, derive from import.meta.url
    return path.dirname(fileURLToPath(import.meta.url));
};

// Placeholder for embedded performance code - will be replaced by build script
// In development, this remains null and performance.js is loaded from filesystem
let EMBEDDED_PERFORMANCE = null;

// Load performance code from either embedded or filesystem source
function loadPerformanceCode() {
    if (EMBEDDED_PERFORMANCE) {
        return EMBEDDED_PERFORMANCE;
    }
    // Development mode: load from filesystem
    const currentDir = getDirname();
    const perfPath = path.join(currentDir, '..', 'src', 'performance.js');
    return fs.readFileSync(perfPath, 'utf8');
}

const perfCode = loadPerformanceCode();

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
