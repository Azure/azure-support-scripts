#!/usr/bin/env node
/**
 * Build script to bundle the CLI into a single file using esbuild
 * 
 * The build process:
 * 1. Bundles all JS files into a single CJS file
 * 2. Reads all parsers from src/parsers/
 * 3. Post-processes the bundle to inject embedded parsers
 * 4. Creates a single .cjs file that can be run anywhere
 */

import * as esbuild from 'esbuild';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

// Load all parsers and return them as a JSON string for embedding
function loadParsersForBundle() {
    const parsersDir = path.join(__dirname, '..', 'src', 'parsers');
    const files = fs.readdirSync(parsersDir).filter(f => f.endsWith('.js'));
    
    const parsers = {};
    for (const file of files) {
        const filePath = path.join(parsersDir, file);
        const content = fs.readFileSync(filePath, 'utf8');
        parsers[file] = content;
    }
    
    return JSON.stringify(parsers);
}

// Load performance.js source for embedding
function loadPerformanceForBundle() {
    const perfPath = path.join(__dirname, '..', 'src', 'performance.js');
    return JSON.stringify(fs.readFileSync(perfPath, 'utf8'));
}

async function build() {
    console.log('Building CLI bundle...\n');

    try {
        // Ensure dist directory exists
        const distDir = path.join(__dirname, 'dist');
        if (!fs.existsSync(distDir)) {
            fs.mkdirSync(distDir, { recursive: true });
        }

        const tempFile = path.join(__dirname, 'dist', 'rca-cli.temp.js');
        const outfile = path.join(__dirname, 'dist', 'rca-cli.cjs');

        // Step 1: Bundle without minification (to allow post-processing)
        // Enable tree-shaking to remove unused code from libraries
        const result = await esbuild.build({
            entryPoints: [path.join(__dirname, 'cli.js')],
            bundle: true,
            platform: 'node',
            target: 'node18',
            outfile: tempFile,
            format: 'cjs',
            // Mark native modules as external (they can't be bundled)
            external: ['lzma-native'],
            minify: false, // Don't minify yet - we need to do post-processing
            treeShaking: true, // Enable tree-shaking to remove unused exports
            sourcemap: false,
            metafile: true,
            logOverride: {
                // Suppress import.meta warnings - the code has __dirname fallback for CJS
                'empty-import-meta': 'silent',
            },
        });

        // Step 2: Post-process to inject embedded parsers
        let content = fs.readFileSync(tempFile, 'utf8');
        
        // Load parsers and create the injection code
        const parsersJson = loadParsersForBundle();
        
        // Replace the placeholder with actual parser data
        const originalLength = content.length;
        content = content.replace(
            /EMBEDDED_PARSERS\s*=\s*null/,
            `EMBEDDED_PARSERS = ${parsersJson}`
        );
        
        // Also embed performance.js source
        const performanceJson = loadPerformanceForBundle();
        content = content.replace(
            /EMBEDDED_PERFORMANCE\s*=\s*null/,
            `EMBEDDED_PERFORMANCE = ${performanceJson}`
        );
        
        if (content.length === originalLength) {
            console.error('Warning: EMBEDDED_PARSERS replacement may have failed');
        } else {
            console.log(`  Injected parsers (added ${content.length - originalLength} bytes)`);
        }
        
        // Remove any existing shebang before writing (will be added in final step)
        content = content.replace(/^#!.*\n?/gm, '');
        
        // Write the post-processed content back
        fs.writeFileSync(tempFile, content);

        // Step 3: Re-bundle with full minification
        // This allows esbuild to properly minify all libraries including their internals
        await esbuild.build({
            entryPoints: [tempFile],
            bundle: false, // Already bundled, just minify
            platform: 'node',
            target: 'node18',
            outfile: outfile,
            format: 'cjs',
            minify: true,
            minifyWhitespace: true,
            minifyIdentifiers: true,
            minifySyntax: true,
            sourcemap: false,
            banner: {
                js: '#!/usr/bin/env node',
            },
        });

        // Clean up temp file
        fs.unlinkSync(tempFile);
        
        // Make the file executable
        fs.chmodSync(outfile, 0o755);

        // Get output file size
        const stats = fs.statSync(outfile);
        const sizeKB = (stats.size / 1024).toFixed(2);

        console.log(`Bundle created: dist/rca-cli.cjs (${sizeKB} KB)`);

        // Count embedded parsers
        const parsersCount = Object.keys(JSON.parse(parsersJson)).length;
        console.log(`  Embedded ${parsersCount} parsers`);

        // Analyze the bundle
        if (result.metafile) {
            const inputs = Object.keys(result.metafile.inputs);
            console.log(`  Bundled ${inputs.length} modules`);
        }

        console.log('\nTo use the bundled CLI:');
        console.log('  ./dist/rca-cli.cjs <file.tar.xz>');
        console.log('  node dist/rca-cli.cjs <file.tar.xz>');
        console.log('\nNote: lzma-native is external and must be installed separately.');
        console.log('  npm install lzma-native');

    } catch (error) {
        console.error('Build failed:', error);
        process.exit(1);
    }
}

build();
