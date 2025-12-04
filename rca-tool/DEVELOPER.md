# Developer documentation

How to build and contribute to rca-tool.

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

## Functionality

Currently, the tool manages:

|Function|Description|Mature|crm/hb|scc|sos|
|--------|-----------|------|------|---|---|
|Azure vm size|Extract Azure VM Size, from wireserver metadata|🗸|n.a.|🗸|🗸|
|Azure BYOS/PAYG|Licensing source for Azure, from wireserver metadata.|𐄂|n.a.|🗸|🗸|
|Distro detection|It finds distribution mayor and minor version from OS files or wireserver metadata|🗸|🗸|🗸|🗸|
|Cluster node detection and validation|Detects if a node name is declared in both cluster config and hosts file|🗸|🗸|🗸|🗸|
|Corosync configuration and validation|Azure best practices are compared. Needs improvement for non-Suse|𐄂|🗸|🗸|🗸|
|Cluster resource extraction|List resources, active node for each. Adding constains would be useful.|🗸|🗸|🗸|🗸|
|Corosync runtime status|Details which nodes are active, which is localhost|🗸|🗸|🗸|🗸|
|Fencing detection|Azure fencing or SDB. Needs warning if two are active at the same time.|🗸|🗸|🗸|🗸|
|Cluster events|Migrations are detected and listed|🗸|🗸|🗸|🗸|
|Live migration|Azure Live Migrations are detected and listed|🗸|🗸|🗸|🗸|
|Kernel reboot events|Shutdown, reboots and kernel starts are listed. Shows kernel version when boots|🗸|🗸|🗸|🗸|
|Out of memory/oomk events|If the system cannot allocate memory for processes or has out of memory events, they are detected and listed.|🗸|n.a.|🗸|🗸|
|Cluster packages|Validation of packages install in specific version ranges. Needs improvement for non-Suse.|||||
|AV Detection|MS Defender, Cloudstrike Falcon, Illumio, Trend Micro, Guardicore|||||
|DLM Service Detection|Detects if DLM (Distributed Lock Manager) service is enabled and alerts|🗸|n.a.|🗸|🗸|
|Kernel parameters and validation|It grabs kernel parameters (sysctl) and displays them raw. If SAP Hana is found, it also validates best practices.|🗸||||
|Raw fstab|It grab the raw fstab.|🗸||||
|Azure Site Recovery|It detects if the involflt_start service is enabled.|🗸||🗸||
|(WIP)||𐄂|n.a.|🗸|🗸|


Note: "n.a." in this table, means that some data is not present on all type of debug files.