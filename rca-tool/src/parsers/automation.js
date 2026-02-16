/**
 * @module parsers/automation
 * @description Automation tools detection (Ansible, Puppet, Chef, SaltStack).
 *
 * Scans system log files for evidence of configuration-management tool
 * executions and returns a time-ordered list of events.
 *
 * ### Detected tools and patterns
 *
 * | Tool | Log patterns |
 * |------|--------------|
 * | Ansible | `ansible-command:`, `ansible-setup:` |
 * | Puppet  | `puppet-agent:`, `puppet apply`, `puppet-run:` |
 * | Chef    | `chef-client[PID]:`, `chef-solo[PID]:`, `chef-apply[PID]:` |
 *
 * Chef events include up to 5 lines of context for key phases
 * (Starting Chef, Converging, FATAL, ERROR, etc.).
 *
 * ### Input files
 *
 * Matches: `messages`, `localmessages`, `syslog`, `journalctl*` (with
 * optional date/number suffixes and `.txt` extension).
 *
 * ### Return value
 *
 * ```
 * { found: boolean, count: number, events: Array<{
 *     timestamp, lineNumber, toolType, patternType,
 *     command, rawLine, sourceFile
 * }> }
 * ```
 *
 * ### Factory
 *
 * Exported as `createAutomationParser(SCC_RULES)` -- the SCC_RULES object
 * provides `extractTimestamp()` and `stripAnsiCodes()` helpers.
 *
 * @see {@link module:worker} for registration in SCC_RULES
 */

// Debug logging - checks global DEBUG_CONFIG from worker.js
function debugLog(...args) {
    if (typeof DEBUG_CONFIG !== 'undefined' && DEBUG_CONFIG.automation) {
        console.log('[automation.js]', ...args);
    }
}

const createAutomationParser = function(SCC_RULES) {
    return {
        // Target file path patterns - messages, syslog, journalctl
        filePattern: /\/(messages|localmessages|syslog|journalctl[^\/]*)(?:[.-]\d+)?(?:\.txt)?$/,
        
        // Parse function receives file content as string
        // Detects automation tool usage:
        // - "ansible-command: " (Ansible command executions)
        // - "ansible-setup: " (Ansible setup/facts gathering)
        // - "puppet-agent: " (Puppet agent executions)
        // - "puppet apply" (Puppet apply commands)
        // - "puppet-run: " (Puppet run executions)
        // - "chef-client: " (Chef client executions)
        // - "chef-solo: " (Chef solo executions)
        // - "chef-apply: " (Chef apply executions)
        // Future: SaltStack, etc.
        // Returns array of detected automation events with timestamps and full command lines
        parse: function(content, filename) {
            const lines = content.split('\n');
            const automationEvents = [];
            
            debugLog('[automation parser] Analyzing', lines.length, 'lines for automation tool usage');
            
            for (let i = 0; i < lines.length; i++) {
                const line = lines[i];
                
                let toolType = null;
                let patternType = null;
                let command = null;
                
                // Pattern 1: Ansible command execution
                if (line.includes('ansible-command:')) {
                    toolType = 'ansible';
                    patternType = 'command';
                    const ansibleMatch = line.match(/ansible-command:\s*(.+)/);
                    if (ansibleMatch) {
                        command = ansibleMatch[1].trim();
                    }
                }
                
                // Pattern 2: Ansible setup/facts gathering
                if (line.includes('ansible-setup:')) {
                    toolType = 'ansible';
                    patternType = 'setup';
                    const ansibleMatch = line.match(/ansible-setup:\s*(.+)/);
                    if (ansibleMatch) {
                        command = ansibleMatch[1].trim();
                    }
                }
                
                // Pattern 3: Puppet agent execution
                if (line.includes('puppet-agent:')) {
                    toolType = 'puppet';
                    patternType = 'agent';
                    const puppetMatch = line.match(/puppet-agent:\s*(.+)/);
                    if (puppetMatch) {
                        command = puppetMatch[1].trim();
                    }
                }
                
                // Pattern 4: Puppet apply
                if (line.includes('puppet apply')) {
                    toolType = 'puppet';
                    patternType = 'apply';
                    const puppetMatch = line.match(/(puppet apply.+)/);
                    if (puppetMatch) {
                        command = puppetMatch[1].trim();
                    }
                }
                
                // Pattern 5: Puppet run
                if (line.includes('puppet-run:')) {
                    toolType = 'puppet';
                    patternType = 'run';
                    const puppetMatch = line.match(/puppet-run:\s*(.+)/);
                    if (puppetMatch) {
                        command = puppetMatch[1].trim();
                    }
                }
                
                // Pattern 6: Chef client execution (format: chef-client[PID]: message)
                // Capture important events and include next 5 lines for context
                if (line.includes('chef-client[')) {
                    const chefMatch = line.match(/chef-client\[\d+\]:\s*(.+)/);
                    if (chefMatch) {
                        const message = SCC_RULES.stripAnsiCodes(chefMatch[1].trim());
                        // Capture important events with context
                        if (message.includes('Starting Chef') || 
                            message.includes('Chef Infra Client finished') ||
                            message.includes('Chef Run complete') ||
                            message.includes('Chef Client finished') ||
                            message.includes('Synchronizing Cookbooks') ||
                            message.includes('Installing Cookbook Gems') ||
                            message.includes('Compiling Cookbooks') ||
                            message.includes('Converging') ||
                            message.includes('FATAL:') ||
                            message.includes('ERROR:')) {
                            toolType = 'chef';
                            patternType = 'client';
                            
                            // Capture the current line plus next 5 lines for context
                            const contextLines = [message];
                            for (let j = 1; j <= 5 && (i + j) < lines.length; j++) {
                                const nextLine = lines[i + j];
                                const nextMatch = nextLine.match(/chef-client\[\d+\]:\s*(.+)/);
                                if (nextMatch) {
                                    contextLines.push(SCC_RULES.stripAnsiCodes(nextMatch[1].trim()));
                                } else {
                                    break;
                                }
                            }
                            command = contextLines.join(' | ');
                        }
                    }
                }
                
                // Pattern 7: Chef solo (format: chef-solo[PID]: message)
                if (line.includes('chef-solo[')) {
                    const chefMatch = line.match(/chef-solo\[\d+\]:\s*(.+)/);
                    if (chefMatch) {
                        const message = SCC_RULES.stripAnsiCodes(chefMatch[1].trim());
                        // Capture important events with context
                        if (message.includes('Starting Chef') || 
                            message.includes('Chef Solo finished') ||
                            message.includes('Chef Run complete') ||
                            message.includes('Synchronizing Cookbooks') ||
                            message.includes('Compiling Cookbooks') ||
                            message.includes('Converging') ||
                            message.includes('FATAL:') ||
                            message.includes('ERROR:')) {
                            toolType = 'chef';
                            patternType = 'solo';
                            
                            // Capture the current line plus next 5 lines for context
                            const contextLines = [message];
                            for (let j = 1; j <= 5 && (i + j) < lines.length; j++) {
                                const nextLine = lines[i + j];
                                const nextMatch = nextLine.match(/chef-solo\[\d+\]:\s*(.+)/);
                                if (nextMatch) {
                                    contextLines.push(SCC_RULES.stripAnsiCodes(nextMatch[1].trim()));
                                } else {
                                    break;
                                }
                            }
                            command = contextLines.join(' | ');
                        }
                    }
                }
                
                // Pattern 8: Chef apply (format: chef-apply[PID]: message)
                if (line.includes('chef-apply[')) {
                    const chefMatch = line.match(/chef-apply\[\d+\]:\s*(.+)/);
                    if (chefMatch) {
                        const message = SCC_RULES.stripAnsiCodes(chefMatch[1].trim());
                        // Capture important events with context
                        if (message.includes('Starting Chef') || 
                            message.includes('Chef Apply finished') ||
                            message.includes('Chef Run complete') ||
                            message.includes('Compiling Cookbooks') ||
                            message.includes('Converging') ||
                            message.includes('FATAL:') ||
                            message.includes('ERROR:')) {
                            toolType = 'chef';
                            patternType = 'apply';
                            
                            // Capture the current line plus next 5 lines for context
                            const contextLines = [message];
                            for (let j = 1; j <= 5 && (i + j) < lines.length; j++) {
                                const nextLine = lines[i + j];
                                const nextMatch = nextLine.match(/chef-apply\[\d+\]:\s*(.+)/);
                                if (nextMatch) {
                                    contextLines.push(SCC_RULES.stripAnsiCodes(nextMatch[1].trim()));
                                } else {
                                    break;
                                }
                            }
                            command = contextLines.join(' | ');
                        }
                    }
                }
                
                if (toolType) {
                    const timestamp = SCC_RULES.extractTimestamp(line);
                    
                    automationEvents.push({
                        timestamp: timestamp || 'Date not detected',
                        lineNumber: i + 1,
                        toolType: toolType,
                        patternType: patternType,
                        command: command,
                        rawLine: line.trim(),
                        sourceFile: filename
                    });
                    
                    debugLog('[automation parser] ✓ Detected', toolType, 'at line', i + 1, ':', timestamp);
                }
            }
            
            debugLog('[automation parser] Found', automationEvents.length, 'automation events');
            
            return {
                found: automationEvents.length > 0,
                count: automationEvents.length,
                events: automationEvents
            };
        }
    };
}
