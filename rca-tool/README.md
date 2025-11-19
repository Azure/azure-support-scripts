# RCA Tool

A Root Cause Analysis (RCA) tool that analyzes cluster diagnostic files (hb_report and supportconfig) from .tar.gz and .tar.xz archives, with special support for SCC (Supportconfig) reports including cluster node detection and validation.

## Features

- **Client-Side Processing**: All decompression and analysis happens in your browser
- **Dual Format Support**: Handles both .tar.gz (gzip) and .tar.xz (LZMA) files
- **Streaming Decompression**: Memory-efficient processing of large files (>50MB) using liblzma
- **SCC Report Analysis**: Automatic detection and analysis of supportconfig reports
- **Cluster Node Detection**: Extracts cluster node names from ha.txt
- **Hosts File Validation**: Cross-validates cluster nodes against /etc/hosts entries
- **File Listing**: Shows complete contents of archives
- **No Server Dependencies**: Everything runs in the browser
- **Privacy-First**: No files sent to servers
- **Fast Performance**: Native WASM speed via Emscripten and Rust

## Architecture

### Decompression Engines
- **GZIP**: Rust flate2 library compiled to WASM
- **XZ/LZMA**: C library (liblzma from XZ Utils 5.4.6) compiled via Emscripten
  - Streaming mode with 256KB chunks for large files
  - Memory-efficient processing
  - Located in: `liblzma-wasm/dist-streaming/`

### UI Components
- **Drag-and-Drop**: Rust WASM (`pkg/`)  
- **TAR Parsing & SCC Analysis**: JavaScript worker (`liblzma-streaming-worker.js`)
- **Rule-Based Analysis**: Extensible rule system for SCC report extraction

## Prerequisites

- Rust (install from [rustup.rs](https://rustup.rs/))
- wasm-pack (will be installed automatically by the build script)
- Emscripten SDK (for rebuilding liblzma if needed)

## Quick Start

1. **Build the project:**
   ```bash
   ./build.sh
   ```

2. **Serve the files:**
   ```bash
   # Using Python
   python3 -m http.server 8000
   ```

3. **Open in browser:**
   Navigate to `http://localhost:8000`

## How to Use

1. Open the web page in your browser
2. Drag a cluster diagnostic file (.tar.gz or .tar.xz) onto the drop zone
3. For SCC reports, view detected cluster nodes and validation results
3. The application will analyze the archive and display:
   - File type detected (hb_report or supportconfig)
   - Complete list of files in the archive
   - Key diagnostic information

## Supported File Types

The application handles cluster diagnostic files:
- `.tar.gz` - Gzip compressed cluster files
- `.tar.xz` - XZ compressed cluster files
- **hb_report**: Heartbeat report files from cluster analysis
- **supportconfig**: SUSE support configuration files

## Project Structure

```
wasm-hello/
├── src/
│   └── lib.rs          # Main Rust code with WASM bindings and XZ/TAR processing  
├── pkg/                # Generated WASM files (after build)
├── Cargo.toml          # Rust dependencies and configuration
├── index.html          # Web interface
├── build.sh           # Build script
├── test-file.txt      # Sample test file
└── README.md          # This file
```

## How It Works

1. **Rust WASM**: The `src/lib.rs` file contains:
   - WASM bindings using `wasm-bindgen`
   - Web API interactions through `web-sys`
   - Dual compression support: XZ (lzma-rs) and Gzip (flate2)
   - Custom TAR archive parsing and analysis
   - Cluster file type detection (hb_report vs supportconfig)
   - Drag and drop event handlers
   - Complete client-side file processing

2. **Pure Browser Solution**: Everything runs in the browser:
   - No server-side dependencies
   - No external JavaScript libraries
   - No network requests for processing
   - All decompression and analysis in WASM

3. **Cluster File Detection**: Automatically identifies:
   - **hb_report**: Heartbeat cluster reports
   - **supportconfig**: SUSE support configuration files
   - Complete file listing for diagnostics

4. **Web Interface**: Clean, responsive interface for cluster file analysis

## Dependencies

- `wasm-bindgen`: Rust/WASM bindings
- `js-sys`: JavaScript API bindings
- `web-sys`: Web API bindings for DOM manipulation
- `lzma-rs`: Pure Rust XZ/LZMA decompression (WASM compatible)
- `flate2`: Gzip decompression support
- `wasm-bindgen-futures`: Async operations support

## Building Manually

If you prefer to build manually without the script:

```bash
# Install wasm-pack if not already installed
curl https://rustwasm.github.io/wasm-pack/installer/init.sh -sSf | sh

# Build the WASM package
wasm-pack build --target web --out-dir pkg
```

## Browser Compatibility

This project uses modern web APIs and requires a recent browser with:
- WebAssembly support
- File API support
- Drag and Drop API support

## License

This project is open source and available under the MIT License.