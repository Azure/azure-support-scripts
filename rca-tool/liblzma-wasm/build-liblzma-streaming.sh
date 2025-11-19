#!/bin/bash
set -e

echo "=== Building Streaming liblzma WASM ==="

# Directories
SRC_DIR="xz-5.8.1"
BUILD_DIR="build-streaming"
DIST_DIR="dist-streaming"

# Clean previous build
rm -rf "$BUILD_DIR" "$DIST_DIR"
mkdir -p "$BUILD_DIR" "$DIST_DIR"

# Download and extract XZ Utils if needed
if [ ! -d "$SRC_DIR" ]; then
    echo "Downloading XZ Utils 5.8.1..."
    wget -q https://github.com/tukaani-project/xz/releases/download/v5.8.1/xz-5.8.1.tar.xz
    tar -xJf xz-5.8.1.tar.xz
    rm xz-5.8.1.tar.xz
fi

# Configure and build liblzma
echo "Configuring liblzma with emscripten..."
cd "$SRC_DIR"
emconfigure ./configure \
    --disable-shared \
    --enable-static \
    --disable-xz \
    --disable-xzdec \
    --disable-lzmadec \
    --disable-lzmainfo \
    --disable-lzma-links \
    --disable-scripts \
    --disable-doc \
    --prefix="$(pwd)/../$BUILD_DIR"

echo "Building liblzma..."
emmake make -j$(nproc)
emmake make install

cd ..

echo "Compiling streaming wrapper with emcc..."
emcc \
    -O3 \
    -s WASM=1 \
    -s MODULARIZE=1 \
    -s EXPORT_NAME='LZMA_XZ_Streaming_Module' \
    -s EXPORTED_FUNCTIONS='["_malloc","_free","_xz_stream_init","_xz_stream_process","_xz_stream_error","_xz_stream_free","_xz_decompress"]' \
    -s EXPORTED_RUNTIME_METHODS='["ccall","cwrap","getValue","setValue","UTF8ToString"]' \
    -s ALLOW_MEMORY_GROWTH=1 \
    -s INITIAL_MEMORY=16MB \
    -s MAXIMUM_MEMORY=2GB \
    -I"$BUILD_DIR/include" \
    xz_wrapper_streaming.c \
    "$BUILD_DIR/lib/liblzma.a" \
    -o "$DIST_DIR/liblzma-xz-streaming.js"

echo "=== Build Complete ==="
echo "Output files:"
ls -lh "$DIST_DIR/"
echo ""
echo "Streaming WASM module ready at: $DIST_DIR/liblzma-xz-streaming.{js,wasm}"
