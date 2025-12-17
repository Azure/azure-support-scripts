# Developer documentation

How to build and contribute to rca-tool.

## Functionality

Currently, the tool manages:

|Function|Description|Mature code?|crm/hb|scc|sos|console /messages / syslog / plain text files|
|--------|-----------|------|------|---|---|-----------|
|Azure vm size|Extract Azure VM Size, from wireserver metadata|🗸|n.a.|🗸|🗸||
|Azure BYOS/PAYG|Licensing source for Azure, from wireserver metadata.|𐄂|n.a.|🗸|🗸||
|Distro detection|It finds distribution mayor and minor version from OS files or wireserver metadata|🗸|🗸|🗸|🗸||
|Cluster node detection and validation|Detects if a node name is declared in both cluster config and hosts file|🗸|🗸|🗸|🗸||
|Corosync configuration and validation|Azure best practices are compared. Needs improvement for non-Suse|𐄂|🗸|🗸|🗸||
|Cluster resource extraction|List resources, active node for each. Adding constains would be useful.|🗸|🗸|🗸|🗸||
|Corosync runtime status|Details which nodes are active, which is localhost|🗸|🗸|🗸|🗸||
|Fencing detection|Azure fencing or SDB. Needs warning if two are active at the same time.|🗸|🗸|🗸|🗸||
|Cluster events|Migrations are detected and listed|🗸|🗸|🗸|🗸||
|Live migration|Azure Live Migrations are detected and listed|🗸|🗸|🗸|🗸|🗸|
|Kernel reboot events|Shutdown, reboots and kernel starts are listed. Shows kernel version when boots|🗸|🗸|🗸|🗸|🗸|
|Out of memory/oomk events|If the system cannot allocate memory for processes or has out of memory events, they are detected and listed.|🗸|n.a.|🗸|🗸|🗸|
|Cluster packages|Validation of packages install in specific version ranges. Needs improvement for non-Suse.||||||
|AV Detection|MS Defender, Cloudstrike Falcon, Illumio, Trend Micro, Guardicore|🗸|n.a.|🗸|🗸||
|DLM Service Detection|Detects if DLM (Distributed Lock Manager) service is enabled and alerts|🗸|n.a.|🗸|🗸||
|Kernel parameters and validation|It grabs kernel parameters (sysctl) and displays them raw. If SAP Hana is found, it also validates best practices.|🗸|||🗸||
|Raw fstab|It grab the raw fstab.|🗸|n.a.|🗸|🗸||
|Azure Site Recovery|It detects if the involflt_start service is enabled.|🗸|n.a.|🗸|||
|XFS corruption|If we see a message about xfs corruption, it is listed as an event.|🗸||🗸|🗸||
|XFS duplicate UUID|If the is a kernel message about a duplicate UUID XFS mount, it is listed as an event.|🗸||🗸|🗸|🗸|
|NVME Detection|If NVME disks are found, they are listed.|🗸|n.a.||🗸||
|Network Kernel Parameters|Recommended and optional kernel parameters for network are verified on the collected sysctl.|🗸|n.a.|🗸|🗸||
|Raw list of distro packages|Shows a raw list of packages from dpkg -l, and dnf list|🗸|n.a.||🗸||
|Azure Storage Type Detection|Standard SSD, Premium SSDv2, Ultradisk, etc.|🗸|n.a.|n.a.|🗸||
|SSH error detection|Failed to start and permission errors|𐄂|n.a.|🗸|🗸|🗸|
|(WIP)||𐄂|n.a.|🗸|🗸||


Note: "n.a." in this table, means that some data is not present on all type of debug files.

## Quick Start

1. **Build the project:**
   ```bash
   cd rca-tool
   sudo apt install -y emscripten
   ( cd liblzma-wasm && chmod +x build-liblzma-streaming.sh && \
   ./build-liblzma-streaming.sh )
   ```

2. **Serve the files:**
   ```bash
   # Using Python
   python3 -m http.server 8000
   ```

**Important**: No python is used in this application. The http.server module in python is just an easy way to server a web page. It should work with any web server of your choise. The same would apply for the port used.

3. **Open in browser:**
   Navigate to `http://localhost:8000`

## Browser Compatibility

This project uses modern web APIs and requires a recent browser with:
- WebAssembly support
- File API support
- Drag and Drop API support

Currently all testing is done with MS Edge via Playwright

## Adding rules

It's important that in order to push code to GitHub all of the tests must pass, and you should add testing if you add more rules, or adjust the testing if you modify the current rules or web rendering.

1. Start a rule in ```liblzma-streaming-worker.js```by adding a rule name: ```osRelease```, add a ```filePattern``` to define the files where the data can be found, trying to make the rule work on ```hb_reports```, ```crm_reports```, ```supportconfig``` and ```sosreports```, depending on where the data is available.

   ```js
    // Rule: Extract OS release information from /etc/os-release
    osRelease: {
        filePattern: /\/(etc|usr\/lib)\/os-release$/,
   ```


2. Create a ```parse``` function, ```Log``` to the console the ```filename``` where the match was found, and use Javascript with ```trim()```, ```match()```, ```split()``` and other ways to filter the content that you wish to extract.

   ```js
        parse: function(content, filename) {
            debugLog('[osRelease parser] Analyzing OS release information in:', filename);
   ```

3. Once you have located and extracted the data required, ```return``` 

   ```js           
        return {
            found: true,
            name: name,
            version: version,
            versionId: versionId,
            prettyName: prettyName,
            majorVersion: majorVersion,
            minorVersion: minorVersion
        };
    
   ```

4. Render the data in index.html by making CSS sections visible, and adding alerts and color changes as needed.

### Special parsers

The codebase includes utility functions to simplify common parsing tasks. Here are some practical examples:

#### Extract sections from supportconfig .txt files

Use `extractSection` to extract embedded configuration files from supportconfig .txt files (e.g., network.txt, ha.txt). It automatically handles both supportconfig embedded sections and direct files (sosreport).

```js
// Example: Extract /etc/hosts from network.txt (supportconfig) or /etc/hosts (sosreport)
hostsFile: {
    filePattern: /\/(network\.txt|\/etc\/hosts)$/,
    
    parse: function(content, filename) {
        // Extract section - works for both formats automatically
        const section = SCC_RULES.extractSection(
            content,
            filename,
            '# /etc/hosts',        // Section marker in supportconfig
            '/etc/hosts'           // Direct file pattern for sosreport
        );
        
        if (!section.found) {
            return { entries: [], allHostnames: [] };
        }
        
        // Now process the extracted lines
        const hosts = [];
        for (const line of section.lines) {
            const trimmed = line.trim();
            if (!trimmed || trimmed.startsWith('#')) continue;
            
            const parts = trimmed.split(/\s+/);
            if (parts.length >= 2) {
                hosts.push({
                    ip: parts[0],
                    hostnames: parts.slice(1)
                });
            }
        }
        
        return { entries: hosts };
    }
}
```

#### Detect a systemd service

Use `detectSystemdService` to check if a service is enabled. It handles multiple file formats automatically.

```js
// Example: Detect Azure Site Recovery service
azureSiteRecovery: {
    filePattern: /(?:sos_commands\/systemd\/systemctl_list-unit-files|systemd-status\.txt)$/,
    
    parse: function(content, filename) {
        return SCC_RULES.detectSystemdService(
            content,
            filename,
            'involflt_start',  // Service name without .service extension
            'info',            // Severity: 'info', 'warning', or 'error'
            'Azure Site Recovery (ASR) is enabled on this system.'
        );
    }
}
```

#### Search for a pattern in file content

Use `grepLines` to search for text patterns, similar to the Unix `grep` command.

```js
// Example: Detect Illumio software
illumio: {
    filePattern: /sos_commands\/systemd\/systemctl_list-units_--all$/,
    
    parse: function(content) {
        const result = SCC_RULES.grepLines(content, /illumio/i, { firstMatchOnly: true });
        
        if (!result.found) {
            return { found: false };
        }
        
        return {
            found: true,
            message: 'Illumio detected. SAP exclusions should be verified.'
        };
    }
}
```

#### Detect installed RPM packages and processes

Use `detectRPMPackage` to find installed packages, `detectProcess` to check for running processes, or `detectSecuritySoftware` to check both.

```js
// Example 1: Check if a package is installed
const rpmResult = SCC_RULES.detectRPMPackage(content, 'mdatp', 'myParser');
if (rpmResult.found) {
    console.log(`Found version: ${rpmResult.version}`);
}

// Example 2: Check for running process
const processResult = SCC_RULES.detectProcess(content, ['mdatp', 'wdavdaemon'], 'myParser');
if (processResult.found) {
    console.log(`Process found: ${processResult.line}`);
}

// Example 3: Detect Microsoft Defender (RPM + process combined)
msDefender: {
    filePattern: /\/(rpm\.txt|installed-rpms|ps\.txt)$/,
    
    parse: function(content) {
        return SCC_RULES.detectSecuritySoftware(
            content,
            'msDefender parser',     // Parser name for logging
            'mdatp',                 // RPM package name prefix
            ['mdatp', 'wdavdaemon'], // Process names to search for
            'MS Defender',           // Display name
            'Microsoft Defender detected. SAP exclusions should be verified.'
        );
    }
}
```

#### Parse key-value configuration files

Use `parseKeyValueFile` to parse configuration files with key-value pairs (e.g., sysctl output, kernel parameters).

```js
// Example: Parse sysctl kernel parameters
kernelTuning: {
    filePattern: /sos_commands\/kernel\/sysctl_-a$/,
    
    parse: function(content, filename) {
        // Parse sysctl output
        const parsed = SCC_RULES.parseKeyValueFile(content, {
            pattern: /^([^\s=]+)\s*=\s*(.+)$/,  // Match "key = value"
            skipComments: true,
            skipEmpty: true
        });
        
        // Now validate specific parameters
        const parameters = parsed.parameters;
        const warnings = [];
        
        if (parameters['vm.swappiness'] !== '10') {
            warnings.push({
                parameter: 'vm.swappiness',
                expected: '10',
                actual: parameters['vm.swappiness']
            });
        }
        
        return {
            found: true,
            parameters: parameters,
            warnings: warnings
        };
    }
}
```

#### Extract raw configuration files

Use `extractRawFile` to extract full file content for later analysis or display.

```js
// Example: Extract fstab for display
fstab: {
    filePattern: /\/etc\/fstab$/,
    
    parse: function(content, filename) {
        // Simply extract the raw file content
        return SCC_RULES.extractRawFile(content, filename);
        // Returns: { found: true, content: "...", filename: "/etc/fstab" }
    }
}
```

## Debug mode

For reviewing the rules, you can run the web page with the following parameters, so that more data is logged into the browser console, which you can view using Developer Tools in MS Edge.

   ```
   http://localhost:8000/?debug=cluster
   ```

Useful modes are ```cluster```, ```app``` and ```all```.

## Testing

After each change in the source code, it's a good idea to run automated testing of rca-tool to verify that no new change has introduced breaks in the previous code. It is a good idea as well to add testing for new code.

   ```bash
   cd rca-tool/tests
   npm ci
   chmod +x create-fixtures.sh && ./create-fixtures.sh
   npx playwright install --with-deps msedge
   npm test
   # Accessibility testing
   node accessibility-check.js
   ```

## TODO

If you want to contribute to the project, the current priority is not to add more functionality, but to have parity and testing of the 4 supported type of files, since they contain different information, packaged in different ways, it is possible that (as an example, this used to happen but is not fixed) you are able to find a kernel reboot on an sos report, but not on an scc file from the same server.

1. Parity for all types of files, with testing
2. Adding detection from cases or from cluster specialist's recommendations
3. Adding more detectors: automation platforms, better cluster resources and events, package history, others

If possible, moving the rules to a rust WASM code would make the analysis of the files even faster. (see Limitations)

## Limitations

Due to the need to run with streaming, we currently support only gzip and xz files, using a C library compiled for WASM.

If other mature libraries for compression can be compiled and used with streaming, it should be possible to support other types for files like ZIP, or zstd.