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