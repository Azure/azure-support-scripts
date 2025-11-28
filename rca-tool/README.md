# RCA Tool

A Root Cause Analysis (RCA) tool that analyzes support and diagnostic files (hb_report, crm_report, supportconfig and sosreport) from .tar.gz and .tar.xz archives, and summarizes Azure VM, distribution, OS, kernel and cluster resources and parameters, with validation of cluster best practices and event detection (live migration, reboots, oom killer).

## Features

- Streaming Decompression: Memory-efficient processing of large files using liblzma
- File Listing: Shows complete contents of archives
- No Server Dependencies: Everything runs in the browser
- Privacy-First: No files sent to servers
- Fast Performance: Native WASM speed via Emscripten
- Zero install: No need to download files, specific OS, dependency install
- IBM Colorblind-safe palette and web accesiblity: To make this a diverse and inclusive tool
- CI testing: Uses playright to verify code and help developers
- GitHub Pages: Serverless and easy deployment via GitHub actions

## How to Use

1. Open the [web page](https://azure.github.io/azure-support-scripts/) in your browser
   - Note: Change GitHub user in URL, if using a fork for development
2. Drag a cluster diagnostic file (.tar.gz or .tar.xz) onto the drop zone
3. The application will analyze the archive and display:
   - File type detected (hb_report, crm_report, supportconfig or sosreport)
   - Complete list of files in the archive
   - Key diagnostic information

## Architecture

```Mermaid
flowchart TD
A(File stream to local browser) -->|stream decompression with wasm| B(Multiple patterns)
B --> C{if file is fstab}
B --> D{if file is ha.txt}
B --> K{if file is ha.txt}
B --> E{if file is instance metadata json}
C --> F(extract raw) --> I
D --> G(extract cluster config) --> I
K --> L(extract cluster nodes) --> I
E --> H(extract Azure VM properties) --> I

I(data structure) --> J(Web render)
```

### Components

- libzmla is compiled for WASM with Emscripten SDK
- Patterns and rules are run in javascript
- Rendering is HTML with CSS
- Unit testing and accesibility testing is done with Playwright and MS Edge browser


## License

This project is open source and available under the MIT License.