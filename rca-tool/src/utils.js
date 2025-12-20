// SCC Report Analysis Utilities
// Reusable helper functions for parsing SCC/supportconfig reports

// Simple XML parser for Web Workers (since DOMParser is not available)
// This is a minimal SAX-style parser for extracting elements and attributes
// Handles multi-line XML and properly parses opening tags with attributes
function parseXMLSimple(xmlString) {
    const elements = [];
    
    // Normalize whitespace: replace newlines and multiple spaces within tags
    // This allows tags to span multiple lines
    const normalizedXml = xmlString.replace(/\s+/g, ' ');
    
    // Match opening tags with attributes: <tagname attr="value" ...>
    // This simpler regex handles both regular and self-closing tags
    const tagRegex = /<(\w+)([^>]*)>/g;
    let match;
    
    while ((match = tagRegex.exec(normalizedXml)) !== null) {
        const tagName = match[1];
        const attrsString = match[2];
        
        // Parse attributes - handles both single and double quotes, and hyphenated attribute names
        const attributes = {};
        const attrRegex = /([\w-]+)=["']([^"']*)["']/g;
        let attrMatch;
        
        while ((attrMatch = attrRegex.exec(attrsString)) !== null) {
            attributes[attrMatch[1]] = attrMatch[2];
        }
        
        elements.push({
            tagName: tagName,
            attributes: attributes
        });
    }
    
    return elements;
}

// Query parsed XML elements by tag name
function querySelectorAll(elements, tagName) {
    return elements.filter(el => el.tagName === tagName);
}

// Query parsed XML elements by tag name and attribute match
function querySelectorAllWithAttr(elements, tagName, attrName, attrValue) {
    return elements.filter(el => {
        if (el.tagName !== tagName) return false;
        if (!attrName) return true;
        if (!attrValue) return el.attributes[attrName] !== undefined;
        return el.attributes[attrName] === attrValue;
    });
}

/**
 * Generic grep-like function to search content for pattern(s)
 * Searches line by line and returns match information
 * @param {string} content - File content to search
 * @param {RegExp|RegExp[]} patterns - Single regex or array of regexes
 * @param {Object} options - Search options
 * @param {boolean} options.firstMatchOnly - Return after first match (default: true)
 * @param {boolean} options.returnAllMatches - Return array of all matches (default: false)
 * @returns {Object} Match result with found, lineNumber, line, matchedPattern
 */
function grepLines(content, patterns, options = {}) {
    const {
        firstMatchOnly = true,
        returnAllMatches = false
    } = options;
    
    const lines = content.split('\n');
    const patternArray = Array.isArray(patterns) ? patterns : [patterns];
    const matches = [];
    
    for (let i = 0; i < lines.length; i++) {
        const line = lines[i];
        const trimmed = line.trim();
        if (!trimmed) continue;
        
        for (const pattern of patternArray) {
            if (pattern.test(trimmed)) {
                const match = {
                    found: true,
                    lineNumber: i + 1,  // 1-based line numbers
                    line: trimmed,
                    matchedPattern: pattern
                };
                
                if (firstMatchOnly) {
                    return match;
                }
                
                matches.push(match);
                break;  // Don't test other patterns for this line
            }
        }
    }
    
    return returnAllMatches 
        ? { found: matches.length > 0, matches }
        : { found: false };
}

/**
 * Extract timestamp from log line
 * Supports multiple common log timestamp formats
 * @param {string} line - Log line to extract timestamp from
 * @returns {string|null} Extracted timestamp or null if not found
 */
function extractTimestamp(line) {
    // Try kernel timestamp format [time.microseconds] (with optional leading spaces)
    const kernelMatch = line.match(/\[\s*(\d+\.\d+)\]/);
    if (kernelMatch) return kernelMatch[1] + 's (kernel uptime)';
    
    // Try ISO timestamp
    const isoMatch = line.match(/(\d{4}-\d{2}-\d{2}[T\s]\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:[+-]\d{2}:\d{2})?)/);
    if (isoMatch) return isoMatch[1];
    
    // Try syslog format (Month Day Time) - normalize day to 2 digits with leading zero
    const syslogMatch = line.match(/((?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s+)(\d{1,2})(\s+\d{2}:\d{2}:\d{2})/);
    if (syslogMatch) {
        const month = syslogMatch[1].trim();
        const day = syslogMatch[2].padStart(2, '0');
        const time = syslogMatch[3].trim();
        return `${month} ${day} ${time}`;
    }
    
    // Try simple date format
    const simpleMatch = line.match(/(\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2})/);
    if (simpleMatch) return simpleMatch[1];
    
    return null;
}

/**
 * Generic systemd service detection helper
 * Detects if a systemd service is enabled using various systemctl output formats
 * @param {string} content - File content to search
 * @param {string} filename - Filename being analyzed
 * @param {string} serviceName - Service name without .service extension
 * @param {string} severity - Severity level ('info', 'warning', 'error')
 * @param {string} message - Message to return when service is detected
 * @param {function} debugLog - Debug logging function
 * @returns {Object} Detection result with found, enabled, severity, message, etc.
 */
function detectSystemdService(content, filename, serviceName, severity, message, debugLog) {
    // Combined pattern to match all systemctl output formats:
    // 1. systemctl list-unit-files (sosreport): service-name.service enabled
    // 2. systemctl list-unit-files (SCC): service-name.service; enabled
    // 3. systemctl status output: Loaded: loaded (/path/service-name.service; enabled; ...)
    const pattern = new RegExp(`(?:^|Loaded:.*)${serviceName}\\.service[;\\s]+enabled`, 'i');
    
    const result = grepLines(content, pattern, { firstMatchOnly: true });
    
    if (!result.found) {
        return { found: false };
    }
    
    if (debugLog) debugLog(`[detectSystemdService] Found ${serviceName}.service enabled at line ${result.lineNumber}`);
    
    return {
        found: true,
        enabled: true,
        severity: severity,
        message: message,
        detectionFile: filename,
        detectionLine: result.lineNumber,
        detectionContent: result.line
    };
}

/**
 * Check for SAP path exclusions in antivirus/security software config files
 * @param {string} content - Configuration file content
 * @param {string} parserName - Name of the parser for debug logging
 * @param {string[]} exclusionKeywords - Keywords to search for (e.g., ['exclude', 'exception'])
 * @param {function} debugLog - Debug logging function
 * @returns {Object} Result with found, exclusions, hasExclusions
 */
function checkSAPExclusions(content, parserName, exclusionKeywords = ['exclude', 'exclusion'], debugLog) {
    if (debugLog) debugLog(`[${parserName}] Checking config for SAP exclusions`);
    
    // Standard SAP paths that should be excluded
    const sapPaths = [
        '/usr/sap',
        '/hana/shared',
        '/hana/data',
        '/hana/log',
        '/sapmnt',
        '/usr/sap/*/SYS/exe'
    ];
    
    const foundExclusions = [];
    const lines = content.split('\n');
    
    for (const line of lines) {
        const lower = line.toLowerCase();
        
        // Check if line contains any exclusion keyword
        const hasExclusionKeyword = exclusionKeywords.some(keyword => lower.includes(keyword));
        
        if (hasExclusionKeyword) {
            // Check if any SAP paths are in this line
            for (const sapPath of sapPaths) {
                if (line.includes(sapPath)) {
                    foundExclusions.push(sapPath);
                    if (debugLog) debugLog(`[${parserName}] Found SAP exclusion:`, sapPath);
                }
            }
        }
    }
    
    return {
        found: true,
        exclusions: foundExclusions,
        hasExclusions: foundExclusions.length > 0
    };
}

/**
 * Detect RPM package and extract version information
 * @param {string} content - File content (rpm.txt, installed-rpms, etc.)
 * @param {string} packagePrefix - RPM package name prefix (e.g., 'falcon-sensor', 'mdatp')
 * @param {string} parserName - Name of the parser for debug logging (optional)
 * @param {function} debugLog - Debug logging function
 * @returns {Object} Detection result with found, version, packageName, line
 */
function detectRPMPackage(content, packagePrefix, parserName = '', debugLog) {
    const rpmPattern = new RegExp(`^${packagePrefix}-([\\.\\d.]+)`);
    const result = grepLines(content, rpmPattern, { firstMatchOnly: true });
    
    if (!result.found) {
        if (parserName && debugLog) debugLog(`[${parserName}] RPM package ${packagePrefix} not found`);
        return { found: false };
    }
    
    const match = result.line.match(rpmPattern);
    if (match) {
        const version = match[1];
        if (parserName && debugLog) debugLog(`[${parserName}] Found RPM package ${packagePrefix}:`, version);
        return {
            found: true,
            version: version,
            packageName: packagePrefix,
            line: result.line,
            lineNumber: result.lineNumber
        };
    }
    
    return { found: false };
}

/**
 * Detect running process by name or path
 * @param {string} content - File content (ps.txt or process list)
 * @param {string|string[]} processIndicators - String or array of strings to search for
 * @param {string} parserName - Name of the parser for debug logging (optional)
 * @param {function} debugLog - Debug logging function
 * @returns {Object} Detection result with found, line, lineNumber
 */
function detectProcess(content, processIndicators, parserName = '', debugLog) {
    const processArray = Array.isArray(processIndicators) ? processIndicators : [processIndicators];
    const processPattern = new RegExp(processArray.map(p => p.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')).join('|'));
    const result = grepLines(content, processPattern, { firstMatchOnly: true });
    
    if (!result.found) {
        if (parserName && debugLog) debugLog(`[${parserName}] Process not found:`, processIndicators);
        return { found: false };
    }
    
    if (parserName && debugLog) debugLog(`[${parserName}] Found process:`, result.line);
    return {
        found: true,
        line: result.line,
        lineNumber: result.lineNumber
    };
}

/**
 * Detect software by checking for both RPM package and running process
 * Combines detectRPMPackage and detectProcess for convenience
 * @param {string} content - File content (rpm.txt or ps output)
 * @param {string} parserName - Name of the parser for debug logging
 * @param {string} packagePrefix - RPM package name prefix (e.g., 'falcon-sensor', 'mdatp')
 * @param {string|string[]} processIndicators - String or array of strings to search in process list
 * @param {string} displayName - Display name for the software
 * @param {string} message - Message to return when software is detected
 * @param {function} debugLog - Debug logging function
 * @returns {Object} Detection result with found, version, runningProcess, message
 */
function detectSecuritySoftware(content, parserName, packagePrefix, processIndicators, displayName, message, debugLog) {
    if (debugLog) debugLog(`[${parserName}] Analyzing for ${displayName}`);
    
    // Check for RPM package with version
    const rpmResult = detectRPMPackage(content, packagePrefix, parserName, debugLog);
    
    // Check for running process
    const processResult = detectProcess(content, processIndicators, parserName, debugLog);
    
    if (!rpmResult.found) {
        if (debugLog) debugLog(`[${parserName}] ${displayName} not detected`);
        return { found: false };
    }
    
    if (debugLog) debugLog(`[${parserName}] ${displayName} detected, version:`, rpmResult.version);
    
    return {
        found: true,
        version: rpmResult.version,
        runningProcess: processResult.found,
        sapExceptionsConfigured: null, // null = unknown, needs config file check
        message: message
    };
}

/**
 * Extract a section from supportconfig .txt files or return entire content for direct files
 * Supportconfig embeds multiple config files in single .txt files with section markers:
 * - Section start: # /path/to/config/file
 * - Section end: #==[ Configuration File ]===
 * 
 * @param {string} content - Full file content
 * @param {string} filename - Filename being analyzed (used to detect direct vs embedded)
 * @param {string} sectionMarker - Section start marker (e.g., '# /etc/hosts', '# /etc/corosync/corosync.conf')
 * @param {string} directFilePattern - Pattern to detect if this is a direct file (e.g., '/etc/hosts', 'corosync.conf')
 * @param {function} debugLog - Debug logging function (optional)
 * @returns {Object} Result with found, lines (array), content (string)
 */
function extractSection(content, filename, sectionMarker, directFilePattern, debugLog) {
    const lines = content.split('\n');
    const extractedLines = [];
    
    // Check if this is a direct file (e.g., sosreport /etc/hosts) or embedded (e.g., supportconfig network.txt)
    const isDirectFile = filename && filename.includes(directFilePattern);
    
    if (isDirectFile) {
        // Direct file - return all content
        if (debugLog) debugLog(`[extractSection] Direct file detected (${directFilePattern}), returning full content`);
        return {
            found: true,
            lines: lines,
            content: content
        };
    }
    
    // Embedded file in supportconfig - extract section
    let inSection = false;
    
    for (let i = 0; i < lines.length; i++) {
        const line = lines[i];
        
        // Check for section end marker
        if (inSection && line.trim().startsWith('#==[ Configuration File ]===')) {
            if (debugLog) debugLog(`[extractSection] Found section end marker at line ${i + 1}`);
            break;
        }
        
        // Check for section start marker
        if (!inSection && line.includes(sectionMarker)) {
            inSection = true;
            if (debugLog) debugLog(`[extractSection] Found section start marker at line ${i + 1}: ${sectionMarker}`);
            continue; // Skip the marker line itself
        }
        
        // If we're in the section, collect the line
        if (inSection) {
            extractedLines.push(line);
        }
    }
    
    if (extractedLines.length === 0) {
        if (debugLog) debugLog(`[extractSection] Section not found: ${sectionMarker}`);
        return {
            found: false,
            lines: [],
            content: ''
        };
    }
    
    if (debugLog) debugLog(`[extractSection] Extracted ${extractedLines.length} lines from section: ${sectionMarker}`);
    
    return {
        found: true,
        lines: extractedLines,
        content: extractedLines.join('\n')
    };
}

/**
 * Parse key-value configuration files (e.g., sysctl output, kernel parameters)
 * Handles common formats like "key = value" or "key: value"
 * 
 * @param {string} content - File content to parse
 * @param {Object} options - Parsing options
 * @param {RegExp} options.pattern - Regex to match key-value pairs (default: /^([^\s=:]+)\s*[=:]\s*(.+)$/)
 * @param {boolean} options.skipComments - Skip lines starting with # (default: true)
 * @param {boolean} options.skipEmpty - Skip empty lines (default: true)
 * @param {function} debugLog - Debug logging function (optional)
 * @returns {Object} Result with found, parameters (object), raw (original content)
 */
function parseKeyValueFile(content, options = {}, debugLog) {
    const {
        pattern = /^([^\s=:]+)\s*[=:]\s*(.+)$/,
        skipComments = true,
        skipEmpty = true
    } = options;
    
    const lines = content.split('\n');
    const parameters = {};
    let parsedCount = 0;
    
    for (const line of lines) {
        const trimmed = line.trim();
        
        // Skip empty lines
        if (skipEmpty && !trimmed) continue;
        
        // Skip comment lines
        if (skipComments && trimmed.startsWith('#')) continue;
        
        // Parse key-value pair
        const match = trimmed.match(pattern);
        if (match && match.length >= 3) {
            const key = match[1].trim();
            const value = match[2].trim();
            parameters[key] = value;
            parsedCount++;
        }
    }
    
    if (debugLog) debugLog(`[parseKeyValueFile] Parsed ${parsedCount} key-value pairs`);
    
    return {
        found: true,
        parameters: parameters,
        raw: content,
        count: parsedCount
    };
}

/**
 * Extract raw configuration file content
 * Simple wrapper that returns the full content with metadata
 * Useful for files that will be analyzed later or displayed as-is
 * 
 * @param {string} content - File content
 * @param {string} filename - Filename being analyzed
 * @param {function} debugLog - Debug logging function (optional)
 * @returns {Object} Result with found, content, filename
 */
function extractRawFile(content, filename, debugLog) {
    if (debugLog) debugLog(`[extractRawFile] Extracted raw file: ${filename}`);
    
    return {
        found: true,
        content: content,
        filename: filename
    };
}

/**
 * Deduplicate events based on specified comparison fields
 * @param {Array} existingEvents - Array of existing events
 * @param {Array} newEvents - Array of new events to add
 * @param {Array} comparisonFields - Array of field names to compare for deduplication
 * @param {Function} debugLog - Optional debug logging function
 * @returns {Object} Object with addedEvents array and duplicateCount
 */
function deduplicateEvents(existingEvents, newEvents, comparisonFields, debugLog) {
    const addedEvents = [];
    let duplicateCount = 0;
    
    newEvents.forEach(newEvent => {
        // Check if this event already exists by comparing specified fields
        const isDuplicate = existingEvents.some(existingEvent => {
            return comparisonFields.every(field => existingEvent[field] === newEvent[field]);
        });
        
        if (!isDuplicate) {
            addedEvents.push(newEvent);
        } else {
            duplicateCount++;
        }
    });
    
    if (debugLog) {
        debugLog(`[deduplicateEvents] Added ${addedEvents.length} new events, skipped ${duplicateCount} duplicates`);
    }
    
    return {
        addedEvents,
        duplicateCount
    };
}

/**
 * Compare semantic versions
 * @param {string} actual - Actual version string (e.g., "5.14.21")
 * @param {string} expected - Expected version string (e.g., "5.14.0")
 * @param {string} operator - Comparison operator: 'exact', 'gte', 'lte'
 * @returns {boolean} True if comparison matches
 */
function compareVersion(actual, expected, operator) {
    const parseVersion = (v) => {
        const parts = v.split('.').map(p => parseInt(p, 10));
        return {
            major: parts[0] || 0,
            minor: parts[1] || 0,
            patch: parts[2] || 0
        };
    };
    
    const actualParts = parseVersion(actual);
    const expectedParts = parseVersion(expected);
    
    switch (operator) {
        case 'exact':
            return actualParts.major === expectedParts.major && 
                   actualParts.minor === expectedParts.minor;
                   
        case 'gte': // greater than or equal
            if (actualParts.major > expectedParts.major) return true;
            if (actualParts.major < expectedParts.major) return false;
            if (actualParts.minor > expectedParts.minor) return true;
            if (actualParts.minor < expectedParts.minor) return false;
            return actualParts.patch >= expectedParts.patch;
            
        case 'lte': // less than or equal
            if (actualParts.major < expectedParts.major) return true;
            if (actualParts.major > expectedParts.major) return false;
            if (actualParts.minor < expectedParts.minor) return true;
            if (actualParts.minor > expectedParts.minor) return false;
            return actualParts.patch <= expectedParts.patch;
            
        default:
            return false;
    }
}

/**
 * Strip ANSI escape codes (terminal color codes) from text
 * @param {string} text - Text containing ANSI codes
 * @returns {string} Clean text without ANSI codes
 */
function stripAnsiCodes(text) {
    if (!text) return text;
    // Remove ANSI escape sequences: \033[...m or \x1b[...m or #033[...m
    return text.replace(/(?:\033|\x1b|#033)\[[0-9;]*m/g, '');
}

// Export utilities object for use in Web Worker
const RCA_UTILITIES = {
    grepLines,
    extractTimestamp,
    deduplicateEvents,
    compareVersion,
    detectSystemdService,
    checkSAPExclusions,
    detectRPMPackage,
    detectProcess,
    detectSecuritySoftware,
    extractSection,
    parseKeyValueFile,
    extractRawFile,
    stripAnsiCodes
};
