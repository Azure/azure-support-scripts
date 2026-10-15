/**
 * @module tests/hana-fixtures.global-setup
 * @description Playwright global setup that (re)generates the SAP HANA `.zip`
 * test fixtures from the `fixtures-gen` Rust crate.
 *
 * The fixtures live under the gitignored `tests/fixtures/` directory and are
 * never committed. Generating them here — rather than checking in binaries —
 * keeps the repository free of prebuilt archives while guaranteeing the HANA
 * specs have their inputs in both local and CI runs. The crate's own
 * `cargo test` round-trips the generated traces through the real parsers, so a
 * format regression fails fast there too.
 */
import { execFileSync } from 'child_process';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const manifest = path.resolve(__dirname, '../fixtures-gen/Cargo.toml');
const fixturesDir = path.join(__dirname, 'fixtures');

export default function globalSetup() {
  execFileSync(
    'cargo',
    ['run', '--quiet', '--manifest-path', manifest, '--', '--out', fixturesDir],
    { stdio: 'inherit' },
  );
}
