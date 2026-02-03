#!/usr/bin/env node
/**
 * RCA CLI Tool
 * 
 * Command-line interface for analyzing sosreports and support bundles.
 * Uses the same parsers as the web tool.
 * 
 * Usage:
 *   node cli.js <file.tar.xz> [options]
 *   node cli.js --help
 * 
 * Options:
 *   --json           Output results as JSON
 *   --debug          Enable debug logging
 *   --parser <name>  Run only a specific parser
 *   --list-parsers   List available parsers
 *   --extract <dir>  Extract results to individual files
 */

import fs from 'fs';
import path from 'path';
import { loadParsers, SCC_RULES } from './parser-loader.js';
import { processArchive } from './archive-processor.js';

// Handle both ESM and CJS environments
const getDirname = () => {
    // For bundled CJS, use __dirname if available
    if (typeof __dirname !== 'undefined') {
        return __dirname;
    }
    // For ESM, derive from import.meta.url
    const { fileURLToPath } = require('url');
    return path.dirname(fileURLToPath(import.meta.url));
};

// Parse command line arguments
function parseArgs() {
    const args = process.argv.slice(2);
    const options = {
        file: null,
        json: false,
        debug: false,
        parser: null,
        listParsers: false,
        help: false,
        extract: null
    };

    for (let i = 0; i < args.length; i++) {
        const arg = args[i];
        if (arg === '--help' || arg === '-h') {
            options.help = true;
        } else if (arg === '--json' || arg === '-j') {
            options.json = true;
        } else if (arg === '--debug' || arg === '-d') {
            options.debug = true;
        } else if (arg === '--list-parsers' || arg === '-l') {
            options.listParsers = true;
        } else if (arg === '--parser' || arg === '-p') {
            options.parser = args[++i];
        } else if (arg === '--extract' || arg === '-e') {
            options.extract = args[++i] || './rca-output';
        } else if (!arg.startsWith('-')) {
            options.file = arg;
        }
    }

    return options;
}

function showHelp() {
    console.log(`
RCA CLI Tool - Analyze sosreports and support bundles

Usage:
  node cli.js <file.tar.xz> [options]
  npx rca-cli <file.tar.xz> [options]

Arguments:
  <file>              Path to a .tar.xz, .tar.gz, or .tar file

Options:
  -h, --help           Show this help message
  -j, --json           Output results as JSON
  -d, --debug          Enable debug logging
  -p, --parser <name>  Run only a specific parser
  -l, --list-parsers   List available parsers
  -e, --extract <dir>  Extract results to individual files in <dir>

Examples:
  node cli.js sosreport.tar.xz
  node cli.js sosreport.tar.xz --json > results.json
  node cli.js sosreport.tar.xz --parser rhuiErrors --debug
  node cli.js sosreport.tar.xz --extract ./output
`);
}

function listParsers() {
    console.log('\nAvailable parsers:\n');
    const parsers = Object.entries(SCC_RULES)
        .filter(([name, parser]) => parser.filePattern)
        .sort((a, b) => a[0].localeCompare(b[0]));

    for (const [name, parser] of parsers) {
        const pattern = parser.filePattern.toString();
        const multiFile = parser.processAllRotations ? ' [multi-file]' : '';
        console.log(`  ${name}${multiFile}`);
        console.log(`    Pattern: ${pattern}`);
    }
    console.log(`\nTotal: ${parsers.length} parsers\n`);
}

/**
 * Extract results to individual JSON files
 */
function extractResults(results, outputDir) {
    if (!fs.existsSync(outputDir)) {
        fs.mkdirSync(outputDir, { recursive: true });
    }

    // Write summary
    fs.writeFileSync(
        path.join(outputDir, 'summary.json'),
        JSON.stringify({
            fileCount: results.fileCount,
            directories: results.directories?.length || 0,
            fileTypes: results.fileTypes
        }, null, 2)
    );

    // Write each parser result
    const parserResults = {};
    for (const [key, value] of Object.entries(results)) {
        if (['fileCount', 'directories', 'files', 'fileTypes'].includes(key)) continue;
        if (value && typeof value === 'object') {
            const filename = `${key}.json`;
            fs.writeFileSync(
                path.join(outputDir, filename),
                JSON.stringify(value, null, 2)
            );
            parserResults[key] = filename;
        }
    }

    // Write index
    fs.writeFileSync(
        path.join(outputDir, 'index.json'),
        JSON.stringify({ generated: new Date().toISOString(), files: parserResults }, null, 2)
    );

    return Object.keys(parserResults).length;
}

function formatResults(results, options) {
    if (options.json) {
        return JSON.stringify(results, null, 2);
    }

    let output = '\n';
    output += '='.repeat(70) + '\n';
    output += '  RCA Analysis Results\n';
    output += '='.repeat(70) + '\n\n';

    output += `Files processed: ${results.fileCount}\n`;
    output += `Directories: ${results.directories?.length || 0}\n\n`;

    // AZURE VM PROPERTIES
    if (results.azureVMProperties?.found || results.osRelease?.found) {
        output += '-'.repeat(70) + '\n';
        output += 'AZURE VM PROPERTIES\n';
        output += '-'.repeat(70) + '\n';
        const vm = results.azureVMProperties || {};
        if (vm.vmSize) output += `  VM Size: ${vm.vmSize}\n`;
        if (vm.publisher) output += `  Publisher: ${vm.publisher}\n`;
        if (vm.offer) output += `  Offer: ${vm.offer}\n`;
        if (vm.sku) output += `  SKU: ${vm.sku}\n`;
        if (vm.billingModel) output += `  Billing Model: ${vm.billingModel}\n`;
        if (vm.osDiskType) output += `  OS Disk Type: ${vm.osDiskType}\n`;
        if (vm.dataDisks?.length > 0) {
            output += `  Data Disks: ${vm.dataDisks.length}\n`;
            vm.dataDisks.forEach(d => output += `    - LUN ${d.lun}: ${d.storageAccountType} (${d.diskSizeGB} GB)\n`);
        }
        if (results.osRelease?.found) {
            output += '  Operating System:\n';
            if (results.osRelease.prettyName) output += `    Distribution: ${results.osRelease.prettyName}\n`;
            else if (results.osRelease.name) output += `    Distribution: ${results.osRelease.name}\n`;
            if (results.osRelease.versionId) output += `    Version: ${results.osRelease.versionId}\n`;
        }
        output += '\n';
    }

    // CLUSTER CONFIGURATION
    const hasCluster = results.corosyncConfig?.found || results.clusterNodes?.found || results.pacemakerResources?.found || results.fencingConfig?.found || results.clusterDaemonStatus?.found || (results.azureScheduledEvents?.found && results.azureScheduledEvents?.warnings?.length > 0);
    if (hasCluster) {
        output += '-'.repeat(70) + '\n';
        output += 'CLUSTER CONFIGURATION\n';
        output += '-'.repeat(70) + '\n';
        if (results.corosyncConfig?.found) {
            output += '  Corosync:\n';
            if (results.corosyncConfig.totemToken) output += `    Token: ${results.corosyncConfig.totemToken}\n`;
            if (results.corosyncConfig.totemConsensus) output += `    Consensus: ${results.corosyncConfig.totemConsensus}\n`;
            if (results.corosyncConfig.totemTransport) output += `    Transport: ${results.corosyncConfig.totemTransport}\n`;
            results.corosyncConfig.warnings?.forEach(w => output += `    [WARN] ${w.message}\n`);
        }
        if (results.clusterNodes?.found && results.clusterNodes.nodes?.length > 0) {
            output += `  Cluster Nodes (${results.clusterNodes.nodes.length}):\n`;
            results.clusterNodes.nodes.forEach(n => output += `    - ${n.name || n.id}${n.state ? ' (' + n.state + ')' : ''}\n`);
        }
        if (results.pacemakerResources?.found && results.pacemakerResources.resources?.length > 0) {
            output += `  Pacemaker Resources (${results.pacemakerResources.resources.length}):\n`;
            results.pacemakerResources.resources.slice(0, 15).forEach(r => output += `    - ${r.name}: ${r.type}${r.state ? ' [' + r.state + ']' : ''}\n`);
            if (results.pacemakerResources.resources.length > 15) output += `    ... and ${results.pacemakerResources.resources.length - 15} more\n`;
        }
        if (results.fencingConfig?.found) {
            output += '  Fencing:\n';
            if (results.fencingConfig.fenceAgents?.length > 0) output += `    Agents: ${results.fencingConfig.fenceAgents.join(', ')}\n`;
            results.fencingConfig.warnings?.forEach(w => output += `    [WARN] ${w.message}\n`);
        }
        // Cluster daemon status (corosync/pacemaker enabled/disabled)
        if (results.clusterDaemonStatus?.found) {
            output += '  Daemon Status:\n';
            const daemons = results.clusterDaemonStatus.daemons;
            ['corosync', 'pacemaker', 'pcsd'].forEach(daemon => {
                const d = daemons[daemon];
                if (d && d.active !== null) {
                    const status = `${d.active ? 'active' : 'inactive'}/${d.enabled ? 'enabled' : 'disabled'}`;
                    const marker = (!d.active || !d.enabled) ? '[!]' : '   ';
                    output += `    ${marker} ${daemon}: ${status}\n`;
                }
            });
            // Show warnings/errors
            results.clusterDaemonStatus.warnings?.forEach(w => {
                const prefix = w.severity === 'error' ? '[ERROR]' : '[WARN]';
                output += `    ${prefix} ${w.message}\n`;
                if (w.recommendation) output += `            Recommendation: ${w.recommendation}\n`;
            });
        }
        // Azure Scheduled Events (health-azure) configuration
        if (results.azureScheduledEvents?.found && results.azureScheduledEvents.warnings?.length > 0) {
            output += '  Azure Scheduled Events:\n';
            results.azureScheduledEvents.warnings.forEach(w => {
                const prefix = w.severity === 'error' ? '[ERROR]' : '[WARN]';
                output += `    ${prefix} ${w.message}\n`;
                if (w.stoppedResources?.length > 0) {
                    output += `            Stopped resources: ${w.stoppedResources.slice(0, 5).join(', ')}`;
                    if (w.stoppedResources.length > 5) output += ` (and ${w.stoppedResources.length - 5} more)`;
                    output += '\n';
                }
                if (w.recommendation) output += `            Recommendation: ${w.recommendation}\n`;
            });
        }
        output += '\n';
    }

    // DISTRIBUTION
    const hasDistro = results.rhuiConfig?.found || results.eusVersionLock?.found || results.rhelRhuiCheck?.found || results.cryptoPolicies?.found || results.rhuiErrors?.found || results.distroPackages?.found;
    if (hasDistro) {
        output += '-'.repeat(70) + '\n';
        output += 'DISTRIBUTION\n';
        output += '-'.repeat(70) + '\n';
        if (results.rhelRhuiCheck?.found) {
            output += '  RHUI Package: ';
            if (results.rhelRhuiCheck.hasRhuiPackage) {
                output += `${results.rhelRhuiCheck.rhuiPackages?.join(', ') || 'installed'}`;
                if (results.rhelRhuiCheck.rhuiType) output += ` (${results.rhelRhuiCheck.rhuiType})`;
            } else output += '[WARN] Not found';
            output += '\n';
        }
        if (results.eusVersionLock?.found) {
            output += '  EUS Version Lock: ';
            if (results.eusVersionLock.hasReleaseverFile) output += `${results.eusVersionLock.releasever} (from ${results.eusVersionLock.source})`;
            else output += 'Not locked';
            output += '\n';
        }
        if (results.cryptoPolicies?.found) {
            output += `  Crypto Policy: ${results.cryptoPolicies.policy}`;
            if (!results.cryptoPolicies.isDefault) output += ' (non-default)';
            output += '\n';
        }
        if (results.rhuiConfig?.found && results.rhuiConfig.repos?.length > 0) {
            const enabled = results.rhuiConfig.repos.filter(r => r.enabled);
            const eus = enabled.filter(r => r.isEus);
            output += `  RHUI Repositories: ${enabled.length} enabled`;
            if (eus.length > 0) output += ` (${eus.length} EUS)`;
            output += '\n';
        }
        if (results.rhuiErrors?.found) {
            output += '  RHUI Connectivity:\n';
            if (results.rhuiErrors.hasCertExpiration) output += '    [ERROR] Certificate Expiration Detected\n';
            if (results.rhuiErrors.hasHttp403) output += '    [ERROR] HTTP 403 Errors (likely expired certificate)\n';
            if (results.rhuiErrors.hasHttp400) output += '    [WARN] HTTP 400 Errors (EUS version may be unavailable)\n';
            if (results.rhuiErrors.hasConnectionError) output += '    [WARN] Connection Errors\n';
            if (results.rhuiErrors.affectedRepos?.length > 0) output += `    Affected repos: ${results.rhuiErrors.affectedRepos.join(', ')}\n`;
            if (results.rhuiErrors.errors?.length > 0) output += `    Total errors: ${results.rhuiErrors.errors.length}\n`;
            results.rhuiErrors.warnings?.forEach(w => {
                output += `    [WARN] ${w.message}\n`;
                if (w.recommendation) output += `           Recommendation: ${w.recommendation}\n`;
            });
        }
        if (results.distroPackages?.found) {
            output += `  Packages: ${results.distroPackages.packageCount || Object.keys(results.distroPackages.packages || {}).length} installed\n`;
            results.distroPackages.warnings?.forEach(w => output += `    [WARN] ${w.package}: ${w.message}\n`);
        }
        output += '\n';
    }

    // STORAGE
    const hasStorage = results.lvmConfig?.found || results.raidConfig?.found || results.btrfsConfig?.found || results.fstab?.found || results.blockDevices?.found || results.storageCorrelation?.found;
    if (hasStorage) {
        output += '-'.repeat(70) + '\n';
        output += 'STORAGE\n';
        output += '-'.repeat(70) + '\n';
        
        // Block Devices
        if (results.blockDevices?.found) {
            const disks = results.blockDevices.disks || [];
            const parts = results.blockDevices.partitions || [];
            if (disks.length > 0 || parts.length > 0) {
                output += `  Block Devices: ${disks.length} disk(s), ${parts.length} partition(s)\n`;
                disks.forEach(d => {
                    output += `    - ${d.name}: ${d.size || 'unknown size'}`;
                    if (d.model) output += ` (${d.model})`;
                    output += '\n';
                });
            }
        }
        
        if (results.lvmConfig?.found) {
            output += '  LVM:\n';
            if (results.lvmConfig.pvs?.length > 0) output += `    Physical Volumes: ${results.lvmConfig.pvs.length}\n`;
            if (results.lvmConfig.vgs?.length > 0) output += `    Volume Groups: ${results.lvmConfig.vgs.length}\n`;
            if (results.lvmConfig.lvs?.length > 0) output += `    Logical Volumes: ${results.lvmConfig.lvs.length}\n`;
        }
        if (results.raidConfig?.found && results.raidConfig.arrays?.length > 0) {
            output += `  RAID Arrays (${results.raidConfig.arrays.length}):\n`;
            results.raidConfig.arrays.forEach(a => output += `    - ${a.device}: ${a.level} (${a.state})\n`);
            results.raidConfig.warnings?.forEach(w => output += `    [WARN] ${w.message}\n`);
        }
        if (results.btrfsConfig?.found) {
            if (results.btrfsConfig.filesystems?.length > 0) output += `  BTRFS Filesystems: ${results.btrfsConfig.filesystems.length}\n`;
            if (results.btrfsConfig.subvolumes?.length > 0) output += `  BTRFS Subvolumes: ${results.btrfsConfig.subvolumes.length}\n`;
        }
        if (results.fstab?.found && results.fstab.entries?.length > 0) {
            output += `  Fstab Entries: ${results.fstab.entries.length}\n`;
            results.fstab.warnings?.forEach(w => output += `    [WARN] ${w.message}\n`);
        }
        
        // Storage Correlation (UUID checks)
        if (results.storageCorrelation?.found) {
            const errors = results.storageCorrelation.errors || [];
            const warnings = results.storageCorrelation.warnings || [];
            if (errors.length > 0 || warnings.length > 0) {
                output += '  Fstab/UUID Correlation:\n';
                errors.forEach(e => {
                    output += `    [ERROR] ${e.mountpoint}: UUID ${e.uuid} not found on any device\n`;
                    if (e.expectedFstype) output += `            Expected filesystem: ${e.expectedFstype}\n`;
                });
                warnings.forEach(w => {
                    output += `    [WARN] ${w.mountpoint}: ${w.message}\n`;
                });
            }
        }
        output += '\n';
    }

    // EVENTS
    const hasEvents = results.liveMigration?.count > 0 || results.kernelReboots?.count > 0 || results.oomKiller?.count > 0 || results.xfsErrors?.count > 0 || results.clusterEvents?.count > 0 || results.emergencyMode?.found;
    if (hasEvents) {
        output += '-'.repeat(70) + '\n';
        output += 'EVENTS\n';
        output += '-'.repeat(70) + '\n';
        if (results.liveMigration?.count > 0) {
            output += `  Live Migration: ${results.liveMigration.count} event(s)\n`;
            results.liveMigration.events?.slice(0, 5).forEach(e => output += `    - ${e.timestamp}: ${e.type || 'migration'}\n`);
            if (results.liveMigration.events?.length > 5) output += `    ... and ${results.liveMigration.events.length - 5} more\n`;
        }
        if (results.kernelReboots?.count > 0) {
            output += `  Kernel Reboots: ${results.kernelReboots.count} event(s)\n`;
            results.kernelReboots.events?.slice(0, 5).forEach(e => output += `    - ${e.timestamp}: ${e.type || 'reboot'}\n`);
            if (results.kernelReboots.events?.length > 5) output += `    ... and ${results.kernelReboots.events.length - 5} more\n`;
        }
        if (results.oomKiller?.count > 0) {
            output += `  [WARN] OOM Killer: ${results.oomKiller.count} event(s)\n`;
            results.oomKiller.events?.slice(0, 5).forEach(e => output += `    - ${e.timestamp}: ${e.process || 'killed'}\n`);
        }
        if (results.xfsErrors?.count > 0) {
            output += `  [ERROR] XFS Errors: ${results.xfsErrors.count} event(s)\n`;
            results.xfsErrors.events?.slice(0, 5).forEach(e => output += `    - ${e.timestamp}: ${e.message || e.type || 'error'}\n`);
        }
        if (results.clusterEvents?.count > 0) output += `  Cluster Events: ${results.clusterEvents.count} event(s)\n`;
        if (results.emergencyMode?.found) {
            output += '  [WARN] Emergency Mode: Detected\n';
            if (results.emergencyMode.reason) output += `    Reason: ${results.emergencyMode.reason}\n`;
        }
        output += '\n';
    }

    // KERNEL AND SYSTEM
    const hasKernel = results.kernelTuning?.found || results.hugePages?.found;
    if (hasKernel) {
        output += '-'.repeat(70) + '\n';
        output += 'KERNEL AND SYSTEM\n';
        output += '-'.repeat(70) + '\n';
        if (results.kernelTuning?.found) {
            if (results.kernelTuning.params && Object.keys(results.kernelTuning.params).length > 0) {
                output += '  Kernel Parameters:\n';
                ['vm.swappiness', 'net.ipv4.tcp_keepalive_time', 'kernel.sched_migration_cost_ns'].forEach(p => {
                    if (results.kernelTuning.params[p] !== undefined) output += `    ${p} = ${results.kernelTuning.params[p]}\n`;
                });
            }
            results.kernelTuning.warnings?.forEach(w => output += `    [WARN] ${w.message}\n`);
        }
        if (results.hugePages?.found) {
            output += '  Huge Pages:\n';
            if (results.hugePages.staticHugePages) output += `    Static: ${results.hugePages.staticHugePages.total_mb || 0} MB\n`;
            if (results.hugePages.transparentHugePages?.anon_mb > 0) output += `    Transparent: ${results.hugePages.transparentHugePages.anon_mb} MB\n`;
            results.hugePages.recommendations?.forEach(r => output += `    [INFO] ${r.message}\n`);
        }
        output += '\n';
    }

    // SECURITY
    const hasSecurity = results.falconSensor?.found || results.msDefender?.found || results.trendMicro?.found || results.illumio?.found || results.guardicoreAgent?.found;
    if (hasSecurity) {
        output += '-'.repeat(70) + '\n';
        output += 'SECURITY\n';
        output += '-'.repeat(70) + '\n';
        if (results.falconSensor?.found) {
            output += `  CrowdStrike Falcon: ${results.falconSensor.installed ? 'Installed' : 'Detected'}`;
            if (results.falconSensor.version) output += ` (v${results.falconSensor.version})`;
            output += '\n';
        }
        if (results.msDefender?.found) {
            output += `  Microsoft Defender: ${results.msDefender.installed ? 'Installed' : 'Detected'}`;
            if (results.msDefender.version) output += ` (v${results.msDefender.version})`;
            output += '\n';
        }
        if (results.trendMicro?.found) output += '  Trend Micro: Detected\n';
        if (results.illumio?.found) output += '  Illumio: Detected\n';
        if (results.guardicoreAgent?.found) output += '  Guardicore: Detected\n';
        output += '\n';
    }

    // AZURE SITE RECOVERY
    if (results.azureSiteRecovery?.found || results.involfltVersion?.found) {
        output += '-'.repeat(70) + '\n';
        output += 'AZURE SITE RECOVERY\n';
        output += '-'.repeat(70) + '\n';
        if (results.azureSiteRecovery?.found) {
            output += `  ASR Agent: ${results.azureSiteRecovery.installed ? 'Installed' : 'Detected'}`;
            if (results.azureSiteRecovery.status) output += ` (${results.azureSiteRecovery.status})`;
            output += '\n';
        }
        if (results.involfltVersion?.found) output += `  InMage/Involflt: ${results.involfltVersion.version || 'Detected'}\n`;
        if (results.involfltKernelVersion?.found) output += `  Involflt Kernel: ${results.involfltKernelVersion.version || 'Detected'}\n`;
        output += '\n';
    }

    // NETWORKING
    if (results.hostsFile?.found || results.sshService?.found) {
        output += '-'.repeat(70) + '\n';
        output += 'NETWORKING\n';
        output += '-'.repeat(70) + '\n';
        if (results.hostsFile?.found && results.hostsFile.entries?.length > 0) output += `  Hosts File: ${results.hostsFile.entries.length} entries\n`;
        if (results.sshService?.found) {
            output += `  SSH Service: ${results.sshService.status || 'Detected'}\n`;
            results.sshService.warnings?.forEach(w => output += `    [WARN] ${w.message}\n`);
        }
        output += '\n';
    }

    // APPLICATIONS (SAP)
    if (results.basicEnvironment?.found && (results.basicEnvironment.sapProductDetected || results.basicEnvironment.epicProductDetected)) {
        output += '-'.repeat(70) + '\n';
        output += 'APPLICATIONS\n';
        output += '-'.repeat(70) + '\n';
        if (results.basicEnvironment.sapProductDetected) output += '  SAP: Detected\n';
        if (results.basicEnvironment.epicProductDetected) output += '  SAP EPIC: Detected\n';
        output += '\n';
    }

    output += '='.repeat(70) + '\n';
    return output;
}

async function main() {
    const options = parseArgs();

    // Enable debug mode globally
    if (options.debug) {
        global.DEBUG_MODE = true;
    }

    // Load parsers
    await loadParsers();

    if (options.help) {
        showHelp();
        process.exit(0);
    }

    if (options.listParsers) {
        listParsers();
        process.exit(0);
    }

    if (!options.file) {
        console.error('Error: No input file specified\n');
        showHelp();
        process.exit(1);
    }

    // Check file exists
    if (!fs.existsSync(options.file)) {
        console.error(`Error: File not found: ${options.file}`);
        process.exit(1);
    }

    try {
        console.error(`\nAnalyzing: ${options.file}\n`);
        
        const results = await processArchive(options.file, {
            debug: options.debug,
            parserFilter: options.parser
        });

        // Extract to files if requested
        if (options.extract) {
            const count = extractResults(results, options.extract);
            console.error(`Extracted ${count} result files to: ${options.extract}\n`);
        }

        const output = formatResults(results, options);
        console.log(output);

    } catch (error) {
        console.error(`Error processing file: ${error.message}`);
        if (options.debug) {
            console.error(error.stack);
        }
        process.exit(1);
    }
}

main();
