/**
 * Event Parsers for RCA Tool
 * 
 * Contains kernel and system event analysis parsers:
 * - emergencyMode: Emergency mode detection
 * - kernelReboots: Linux kernel reboot detection
 * - oomKiller: Out of Memory killer event detection
 * - xfsErrors: XFS filesystem error detection
 * 
 * These parsers are exported for use in the main worker file.
 * They will be manually assigned to SCC_RULES after SCC_RULES is defined.
 */

// Debug logging - checks global DEBUG_CONFIG from worker.js
function debugLog(...args) {
    if (typeof DEBUG_CONFIG !== 'undefined' && DEBUG_CONFIG.events) {
        console.log('[events.js]', ...args);
    }
}

// Export system-related parsers
const emergencyModeParser = {
    // Target file path patterns - primarily console logs
    filePattern: /\/(messages|localmessages|journalctl[^\/]*|console.*\.log)(?:[.-]\d+)?(?:\.txt)?$/,
    
    // Parse function receives file content as string
    // Detects emergency mode events by finding the pattern:
    // - "You are in emergency mode."
    // Returns array of detected emergency mode events with timestamps
    parse: function(content, filename) {
        const lines = content.split('\n');
        const emergencyEvents = [];
        
        debugLog('[emergencyMode parser] Analyzing', lines.length, 'lines for emergency mode events');
        
        for (let i = 0; i < lines.length; i++) {
            const line = lines[i];
            
            // Pattern: "You are in emergency mode."
            if (line.match(/You are in emergency mode/i)) {
                const timestamp = SCC_RULES.extractTimestamp(line);
                
                emergencyEvents.push({
                    timestamp: timestamp || 'Date not detected',
                    lineNumber: i + 1,
                    rawLine: line.trim(),
                    sourceFile: filename
                });
                
                debugLog('[emergencyMode parser] ✓ Detected emergency mode at line', i + 1, ':', timestamp);
            }
        }
        
        debugLog('[emergencyMode parser] Found', emergencyEvents.length, 'emergency mode events');
        
        return {
            found: emergencyEvents.length > 0,
            count: emergencyEvents.length,
            events: emergencyEvents
        };
    }
};

const kernelRebootsParser = {
    // Target file path patterns (same as liveMigration)
    // supportconfig: */messages or */localmessages or */ha-log.txt (with optional suffixes)
    // sosreport: */var/log/messages or */sos_commands/logs/journalctl*
    filePattern: /\/(messages|localmessages|ha-log|journalctl[^\/]*)(?:[.-]\d+)?(?:\.txt)?$/,
    
    // Parse function receives file content as string
    // Detects kernel reboots by finding patterns:
    // - "Linux version" (kernel boot message)
    // - "Command line:" (kernel command line)
    // - System restart messages
    // Returns array of detected reboot events with timestamps and kernel versions
    parse: function(content) {
        const lines = content.split('\n');
        const reboots = [];
        
        debugLog('[kernelReboots parser] Analyzing', lines.length, 'lines for kernel reboots');
        
        for (let i = 0; i < lines.length; i++) {
            const line = lines[i];
            
            // Pattern 1: "Linux version X.Y.Z" - primary boot message
            // Match both formats:
            // - "kernel: Linux version 5.14.0"
            // - "kernel: [    0.000000][    T0] Linux version 5.14.21-150400.24.103-default"
            // - "[    0.000000] Linux version 5.15.0-1042-azure" (console log format)
            const kernelMatch = line.match(/(?:kernel:\s*)?(?:\[\s*[\d\.]+\]\s*(?:\[\s*T\d+\]\s*)?)?Linux version\s+([\d\.\-\w]+)/i);
            if (kernelMatch) {
                const timestamp = SCC_RULES.extractTimestamp(line);
                const kernelVersion = kernelMatch[1];
                
                reboots.push({
                    timestamp: timestamp || 'Unknown',
                    lineNumber: i + 1,
                    kernelVersion: kernelVersion,
                    type: 'kernel_boot',
                    rawLine: line.trim()
                });
                
                debugLog('[kernelReboots parser] ✓ Detected kernel boot at line', i + 1, ':', timestamp, 'version:', kernelVersion);
                continue;
            }
            
            // Pattern 2: systemd reboot messages
            if (line.match(/systemd.*Shutting down/i) || 
                line.match(/systemd.*Starting Reboot/i) ||
                line.match(/systemd.*Stopped target.*Shutdown/i)) {
                const timestamp = SCC_RULES.extractTimestamp(line);
                
                // Check if we already have a reboot event very close to this timestamp
                const isDuplicate = reboots.some(r => {
                    if (!timestamp || !r.timestamp) return false;
                    // Simple duplicate check - same line or very close
                    return Math.abs(r.lineNumber - (i + 1)) < 5;
                });
                
                if (!isDuplicate) {
                    reboots.push({
                        timestamp: timestamp || 'Unknown',
                        lineNumber: i + 1,
                        kernelVersion: null,
                        type: 'systemd_shutdown',
                        rawLine: line.trim()
                    });
                    
                    debugLog('[kernelReboots parser] ✓ Detected systemd shutdown at line', i + 1, ':', timestamp);
                }
                continue;
            }
            
            // Pattern 3: "reboot: " messages
            if (line.match(/kernel:\s*reboot:/i)) {
                const timestamp = SCC_RULES.extractTimestamp(line);
                
                reboots.push({
                    timestamp: timestamp || 'Unknown',
                    lineNumber: i + 1,
                    kernelVersion: null,
                    type: 'reboot_message',
                    rawLine: line.trim()
                });
                
                debugLog('[kernelReboots parser] ✓ Detected reboot message at line', i + 1, ':', timestamp);
                continue;
            }
        }
        
        debugLog('[kernelReboots parser] Found', reboots.length, 'reboot events');
        
        return {
            count: reboots.length,
            events: reboots
        };
    }
};

const oomKillerParser = {
    // Target file path patterns (same as liveMigration and kernelReboots)
    // supportconfig: */messages or */localmessages (with optional suffixes)
    // sosreport: */var/log/messages or */sos_commands/logs/journalctl*
    filePattern: /\/(messages|localmessages|journalctl[^\/]*)(?:[.-]\d+)?(?:\.txt)?$/,
    
    // Parse function receives file content as string
    // Detects OOM killer events by finding patterns:
    // - "Out of memory: Kill process" or "Out of memory: Killed process"
    // - "oom-killer:" or "oom_reaper:"
    // - Memory statistics and killed process information
    // Returns array of detected OOM events with process details
    parse: function(content) {
        const lines = content.split('\n');
        const oomEvents = [];
        
        debugLog('[oomKiller parser] Analyzing', lines.length, 'lines for OOM killer events');
        
        for (let i = 0; i < lines.length; i++) {
            const line = lines[i];
            
            // Pattern 1: "Out of memory: Kill process" or "Out of memory: Killed process"
            const oomKillMatch = line.match(/Out of memory:.*Kill(?:ed)? process\s+(\d+)\s+\(([^)]+)\)/i);
            if (oomKillMatch) {
                const timestamp = SCC_RULES.extractTimestamp(line);
                const pid = oomKillMatch[1];
                const processName = oomKillMatch[2];
                
                // Try to find memory score on the same line or nearby lines
                let score = null;
                const scoreMatch = line.match(/score\s+(\d+)/i);
                if (scoreMatch) {
                    score = scoreMatch[1];
                }
                
                // Try to find total VM info
                let totalVM = null;
                const vmMatch = line.match(/total-vm:(\d+)kB/i);
                if (vmMatch) {
                    totalVM = vmMatch[1] + 'kB';
                }
                
                oomEvents.push({
                    timestamp: timestamp || 'Unknown',
                    lineNumber: i + 1,
                    pid: pid,
                    processName: processName,
                    score: score,
                    totalVM: totalVM,
                    type: 'oom_kill',
                    rawLine: line.trim()
                });
                
                debugLog('[oomKiller parser] ✓ Detected OOM kill at line', i + 1, ':', timestamp, 'process:', processName, 'pid:', pid);
                continue;
            }
            
            // Pattern 2: "oom-killer:" invocation (usually precedes the kill message)
            if (line.match(/invoked oom-killer:/i)) {
                const timestamp = SCC_RULES.extractTimestamp(line);
                
                // Extract the process that invoked OOM killer
                let invokedBy = null;
                const invokeMatch = line.match(/\]\s+([^\s]+)\s+invoked oom-killer:/i);
                if (invokeMatch) {
                    invokedBy = invokeMatch[1];
                }
                
                // Extract memory allocation info if present
                let order = null;
                const orderMatch = line.match(/order=(\d+)/i);
                if (orderMatch) {
                    order = orderMatch[1];
                }
                
                // Check if we already have an event very close to this
                const isDuplicate = oomEvents.some(e => {
                    return Math.abs(e.lineNumber - (i + 1)) < 3;
                });
                
                if (!isDuplicate) {
                    oomEvents.push({
                        timestamp: timestamp || 'Unknown',
                        lineNumber: i + 1,
                        pid: null,
                        processName: null,
                        invokedBy: invokedBy,
                        order: order,
                        type: 'oom_invoked',
                        rawLine: line.trim()
                    });
                    
                    debugLog('[oomKiller parser] ✓ Detected OOM invocation at line', i + 1, ':', timestamp, 'by:', invokedBy);
                }
                continue;
            }
            
            // Pattern 3: "oom_reaper:" messages (cleanup after OOM kill)
            if (line.match(/oom_reaper:/i)) {
                const timestamp = SCC_RULES.extractTimestamp(line);
                
                // Extract PID if present
                let pid = null;
                const pidMatch = line.match(/reaped process\s+(\d+)/i);
                if (pidMatch) {
                    pid = pidMatch[1];
                }
                
                // Check if we already have an event very close to this
                const isDuplicate = oomEvents.some(e => {
                    return Math.abs(e.lineNumber - (i + 1)) < 3;
                });
                
                if (!isDuplicate) {
                    oomEvents.push({
                        timestamp: timestamp || 'Unknown',
                        lineNumber: i + 1,
                        pid: pid,
                        processName: null,
                        type: 'oom_reaper',
                        rawLine: line.trim()
                    });
                    
                    debugLog('[oomKiller parser] ✓ Detected OOM reaper at line', i + 1, ':', timestamp);
                }
                continue;
            }
            
            // Pattern 4: "Cannot allocate memory" errors
            if (line.match(/Cannot allocate memory/i)) {
                const timestamp = SCC_RULES.extractTimestamp(line);
                
                // Extract process name if present
                let processName = null;
                const processMatch = line.match(/\]\s+([^\s:]+):/);
                if (processMatch) {
                    processName = processMatch[1];
                }
                
                // Check if we already have an event very close to this
                const isDuplicate = oomEvents.some(e => {
                    return Math.abs(e.lineNumber - (i + 1)) < 3;
                });
                
                if (!isDuplicate) {
                    oomEvents.push({
                        timestamp: timestamp || 'Unknown',
                        lineNumber: i + 1,
                        pid: null,
                        processName: processName,
                        type: 'alloc_failure',
                        rawLine: line.trim()
                    });
                    
                    debugLog('[oomKiller parser] ✓ Detected allocation failure at line', i + 1, ':', timestamp, 'process:', processName);
                }
                continue;
            }
        }
        
        debugLog('[oomKiller parser] Found', oomEvents.length, 'OOM killer events');
        
        return {
            count: oomEvents.length,
            events: oomEvents
        };
    }
};

const xfsErrorsParser = {
    // Target file path patterns (same as oomKiller)
    // supportconfig: */messages or */localmessages (with optional suffixes)
    // sosreport: */var/log/messages or */sos_commands/logs/journalctl*
    filePattern: /\/(messages|localmessages|journalctl[^\/]*)(?:[.-]\d+)?(?:\.txt)?$/,
    
    // Parse function receives file content as string
    // Detects XFS filesystem errors that require unmounting and repair
    // Example: [1814128.610637] XFS (sdd1): Please unmount the filesystem and rectify the problem(s)
    parse: function(content) {
        debugLog('[xfsErrors parser] Analyzing for XFS filesystem errors');
        
        // Pattern to match XFS error messages
        const xfsPattern = /XFS\s+\(([^)]+)\):\s*(.+)/i;
        
        // Use grepLines to find all XFS messages
        const result = SCC_RULES.grepLines(content, xfsPattern, { 
            firstMatchOnly: false, 
            returnAllMatches: true 
        });
        
        if (!result.found) {
            debugLog('[xfsErrors parser] No XFS messages found');
            return {
                count: 0,
                events: []
            };
        }
        
        const xfsErrors = [];
        
        // Filter for critical errors only
        for (const match of result.matches) {
            const fullMatch = match.line.match(xfsPattern);
            if (!fullMatch) continue;
            
            const device = fullMatch[1];
            const message = fullMatch[2].trim();
            
            // Focus on critical errors that require repair
            const isCritical = /please unmount.*rectify/i.test(message) ||
                             /metadata.*corruption/i.test(message) ||
                             /corruption.*detected/i.test(message) ||
                             /corruption warning/i.test(message) ||
                             /internal error/i.test(message) ||
                             /shutting down filesystem/i.test(message) ||
                             /filesystem has been shut down/i.test(message) ||
                             /duplicate UUID.*can't mount/i.test(message);
            
            if (isCritical) {
                const timestamp = SCC_RULES.extractTimestamp(match.line);
                
                xfsErrors.push({
                    timestamp: timestamp || 'Unknown',
                    lineNumber: match.lineNumber,
                    device: device,
                    message: message,
                    rawLine: match.line
                });
                
                debugLog('[xfsErrors parser] ✓ Detected XFS error at line', match.lineNumber, ':', timestamp, 'device:', device);
            }
        }
        
        debugLog('[xfsErrors parser] Found', xfsErrors.length, 'critical XFS filesystem errors');
        
        return {
            count: xfsErrors.length,
            events: xfsErrors
        };
    }
};


// More event parsers can be added here as needed
