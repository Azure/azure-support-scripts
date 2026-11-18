/**
 * Parser Loader for CLI
 * 
 * Loads the parsers from src/parsers/ and makes them available for use.
 * Handles the browser-style parser definitions for Node.js compatibility.
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

// Global debug function
global.debugLog = (...args) => {
    if (global.DEBUG_MODE) {
        console.error('[DEBUG]', ...args);
    }
};

// Parser rules container with utility functions
export const SCC_RULES = {
    // Utility function for deduplication (from worker.js)
    deduplicateEvents: function(existingEvents, newEvents, comparisonFields) {
        const addedEvents = [];
        let duplicateCount = 0;
        
        for (const newEvent of newEvents) {
            const isDuplicate = existingEvents.some(existing => {
                return comparisonFields.every(field => {
                    const existVal = existing[field];
                    const newVal = newEvent[field];
                    if (existVal === undefined && newVal === undefined) return true;
                    if (existVal === undefined || newVal === undefined) return false;
                    return String(existVal).trim() === String(newVal).trim();
                });
            });
            
            if (!isDuplicate) {
                addedEvents.push(newEvent);
            } else {
                duplicateCount++;
            }
        }
        
        return { addedEvents, duplicateCount };
    },
    
    // Extract raw file content (simple passthrough)
    extractRawFile: function(content, filename) {
        return {
            found: true,
            content: content,
            filename: filename
        };
    },
    
    // Extract a specific section from supportconfig/sosreport files
    // Returns: { found: boolean, content: string, lines: array }
    extractSection: function(content, filename, sectionMarker, directFilePattern) {
        // If filename matches direct pattern, return content as-is
        if (directFilePattern && filename.includes(directFilePattern)) {
            return {
                found: true,
                content: content,
                lines: content.split('\n')
            };
        }
        
        // Look for section marker in supportconfig format
        const lines = content.split('\n');
        let inSection = false;
        const sectionLines = [];
        
        for (let i = 0; i < lines.length; i++) {
            const line = lines[i];
            
            // Check for section end marker - SCC files use various section types
            // #==[ Configuration File ]===, #==[ Command ]===, #==[ Log File ]===, etc.
            if (inSection && line.trim().startsWith('#==[ ')) {
                break;
            }
            
            if (!inSection && line.includes(sectionMarker)) {
                inSection = true;
                continue;
            }
            
            if (inSection) {
                sectionLines.push(line);
            }
        }
        
        if (sectionLines.length === 0) {
            return {
                found: false,
                content: '',
                lines: []
            };
        }
        
        return {
            found: true,
            content: sectionLines.join('\n'),
            lines: sectionLines
        };
    },
    
    // Extract timestamp from log line
    extractTimestamp: function(line) {
        if (!line) return null;
        
        // ISO format: 2025-11-11T10:30:45.123456+00:00
        const isoMatch = line.match(/(\d{4}-\d{2}-\d{2}[T\s]\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:[+-]\d{2}:\d{2})?)/);
        if (isoMatch) return isoMatch[1];
        
        // Syslog format: Aug 23 14:31:48
        const syslogMatch = line.match(/(\w{3}\s+\d{1,2}\s+\d{2}:\d{2}:\d{2}(?:\.\d+)?)/);
        if (syslogMatch) return syslogMatch[1];
        
        return null;
    },
    
    // Parse key=value file format
    parseKeyValueFile: function(content, options = {}) {
        const result = {};
        const separator = options.separator || '=';
        const lines = content.split('\n');
        
        for (const line of lines) {
            const trimmed = line.trim();
            if (!trimmed || trimmed.startsWith('#')) continue;
            
            const sepIndex = trimmed.indexOf(separator);
            if (sepIndex === -1) continue;
            
            const key = trimmed.substring(0, sepIndex).trim();
            const value = trimmed.substring(sepIndex + 1).trim();
            result[key] = value;
        }
        
        return result;
    },
    
    // Strip ANSI escape codes
    stripAnsiCodes: function(text) {
        if (!text) return text;
        return text.replace(/\x1B\[[0-9;]*[a-zA-Z]/g, '');
    },
    
    // Compare version strings
    compareVersion: function(actual, expected, operator) {
        if (!actual || !expected) return false;
        
        const parseVersion = (v) => {
            return v.split(/[.-]/).map(p => {
                const num = parseInt(p, 10);
                return isNaN(num) ? 0 : num;
            });
        };
        
        const actualParts = parseVersion(actual);
        const expectedParts = parseVersion(expected);
        const maxLen = Math.max(actualParts.length, expectedParts.length);
        
        let comparison = 0;
        for (let i = 0; i < maxLen; i++) {
            const a = actualParts[i] || 0;
            const e = expectedParts[i] || 0;
            if (a < e) { comparison = -1; break; }
            if (a > e) { comparison = 1; break; }
        }
        
        switch (operator) {
            case 'gt': return comparison > 0;
            case 'gte': return comparison >= 0;
            case 'lt': return comparison < 0;
            case 'lte': return comparison <= 0;
            case 'eq': return comparison === 0;
            default: return false;
        }
    },
    
    // Grep-like search in content
    grepLines: function(content, patterns, options = {}) {
        const lines = content.split('\n');
        const matches = [];
        const patternArray = Array.isArray(patterns) ? patterns : [patterns];
        
        for (let i = 0; i < lines.length; i++) {
            const line = lines[i];
            for (const pattern of patternArray) {
                const regex = pattern instanceof RegExp ? pattern : new RegExp(pattern, 'i');
                if (regex.test(line)) {
                    matches.push({
                        line: line,
                        lineNumber: i + 1,
                        match: line.match(regex)
                    });
                    if (options.firstMatchOnly) return { found: true, matches };
                    break;
                }
            }
        }
        
        return { found: matches.length > 0, matches };
    },
    
    // Detect systemd service status
    detectSystemdService: function(content, filename, serviceName, severity, message) {
        const lines = content.split('\n');
        for (const line of lines) {
            if (line.includes(serviceName)) {
                const isEnabled = line.includes('enabled');
                const isActive = line.includes('active') && !line.includes('inactive');
                return {
                    found: true,
                    enabled: isEnabled,
                    active: isActive,
                    severity: severity,
                    message: message,
                    sourceLine: line.trim()
                };
            }
        }
        return { found: false };
    },
    
    // Detect security software
    detectSecuritySoftware: function(content, parserName, packagePrefix, processIndicators, displayName, message) {
        // Check for package
        const lines = content.split('\n');
        for (const line of lines) {
            if (packagePrefix && line.includes(packagePrefix)) {
                return {
                    found: true,
                    type: 'package',
                    name: displayName,
                    message: message,
                    sourceLine: line.trim()
                };
            }
            if (processIndicators) {
                for (const indicator of processIndicators) {
                    if (line.includes(indicator)) {
                        return {
                            found: true,
                            type: 'process',
                            name: displayName,
                            message: message,
                            sourceLine: line.trim()
                        };
                    }
                }
            }
        }
        return { found: false };
    },
    
    // Check SAP exclusions
    checkSAPExclusions: function(content, parserName, exclusionKeywords) {
        // Placeholder - implement if needed
        return { found: false, excluded: false };
    }
};

// Placeholder for embedded parsers - will be replaced by esbuild plugin during build
// In development, this remains null and parsers are loaded from filesystem
let EMBEDDED_PARSERS = null;

// This will be replaced by the esbuild plugin with actual parser content
// DO NOT MODIFY THIS LINE - it's a build marker
// @EMBEDDED_PARSERS_PLACEHOLDER@

// Silent console - only logs when DEBUG_MODE is true
const silentConsole = {
    log: (...args) => { if (global.DEBUG_MODE) console.error('[parser]', ...args); },
    error: (...args) => console.error(...args),
    warn: (...args) => { if (global.DEBUG_MODE) console.error('[parser warn]', ...args); },
    info: (...args) => { if (global.DEBUG_MODE) console.error('[parser]', ...args); },
    debug: (...args) => { if (global.DEBUG_MODE) console.error('[parser debug]', ...args); },
};

/**
 * Load a parser from its source content
 */
function loadParserFromContent(content, filename) {
    // Create a sandbox context with debugLog and SCC_RULES available
    const sandbox = {
        debugLog: global.debugLog,
        console: silentConsole,
        SCC_RULES: SCC_RULES,  // Make utility functions available to parsers
        // Export parsers will be captured here
        module: { exports: {} },
        exports: {}
    };
    
    // Execute the parser file in the sandbox
    try {
        const script = new vm.Script(content, { filename });
        const context = vm.createContext(sandbox);
        script.runInContext(context);
        
        // Extract parser variables from the sandbox
        // Look for variables ending in 'Parser'
        const parserNames = content.match(/const\s+(\w+Parser)\s*=/g) || [];
        
        for (const match of parserNames) {
            const parserName = match.replace(/const\s+/, '').replace(/\s*=/, '');
            
            // Try to get the parser from sandbox
            const evalScript = new vm.Script(parserName, { filename });
            try {
                const parser = evalScript.runInContext(context);
                if (parser && parser.filePattern && typeof parser.parse === 'function') {
                    // Convert parser name to rule name (remove 'Parser' suffix)
                    let ruleName = parserName.replace(/Parser$/, '');
                    // First letter lowercase
                    ruleName = ruleName.charAt(0).toLowerCase() + ruleName.slice(1);
                    
                    SCC_RULES[ruleName] = parser;
                    debugLog(`Loaded parser: ${ruleName} from ${filename}`);
                }
            } catch (e) {
                // Parser might not be defined in global scope
            }
        }
    } catch (error) {
        console.error(`Error loading parser ${filename}:`, error.message);
    }
}

/**
 * Load all parsers - either from embedded (bundled) or filesystem (development)
 */
export async function loadParsers() {
    if (EMBEDDED_PARSERS) {
        // Bundled mode: load from embedded parsers
        debugLog('Loading embedded parsers...');
        for (const [filename, content] of Object.entries(EMBEDDED_PARSERS)) {
            loadParserFromContent(content, filename);
        }
    } else {
        // Development mode: load from filesystem
        const currentDir = getDirname();
        const parsersDir = path.join(currentDir, '..', 'src', 'parsers');
        
        debugLog(`Loading parsers from ${parsersDir}...`);
        
        // Read all JS files in the parsers directory
        const files = fs.readdirSync(parsersDir).filter(f => f.endsWith('.js'));
        
        for (const file of files) {
            const filePath = path.join(parsersDir, file);
            const content = fs.readFileSync(filePath, 'utf8');
            loadParserFromContent(content, filePath);
        }
    }
    
    debugLog(`Loaded ${Object.keys(SCC_RULES).filter(k => SCC_RULES[k]?.filePattern).length} parsers`);
}

export default { loadParsers, SCC_RULES };
