import * as vscode from 'vscode';
import * as fs from 'fs';
import * as path from 'path';

const PROVIDER_ID = 'rca-tool';

/** Append `.exe` on Windows. */
function exe(name: string): string {
  return process.platform === 'win32' ? `${name}.exe` : name;
}

/**
 * Resolve a binary path: prefer the user-configured override, otherwise fall
 * back to the binary bundled under the extension's `bin/` directory.
 */
function resolveBinary(
  context: vscode.ExtensionContext,
  configKey: string,
  binName: string,
): string {
  const override = vscode.workspace
    .getConfiguration('rcaTool')
    .get<string>(configKey, '')
    .trim();
  if (override) {
    return override;
  }
  return path.join(context.extensionPath, 'bin', exe(binName));
}

/**
 * Ensure the bundled binary is executable. VSIX packaging does not preserve the
 * Unix executable bit, so restore it on activation. No-op on Windows.
 */
function ensureExecutable(binPath: string): void {
  if (process.platform === 'win32') {
    return;
  }
  try {
    fs.chmodSync(binPath, 0o755);
  } catch {
    // Non-fatal: an override path the user owns may already be executable, or
    // the file may not exist yet (surfaced later when the server fails to start).
  }
}

export function activate(context: vscode.ExtensionContext): void {
  const didChange = new vscode.EventEmitter<void>();
  context.subscriptions.push(didChange);

  const provider: vscode.McpServerDefinitionProvider = {
    onDidChangeMcpServerDefinitions: didChange.event,
    provideMcpServerDefinitions: () => {
      const serverBin = resolveBinary(context, 'mcpServerPath', 'supportfile_mcp');
      const rcaCliBin = resolveBinary(context, 'rcaCliPath', 'rca_cli');

      ensureExecutable(serverBin);
      ensureExecutable(rcaCliBin);

      return [
        new vscode.McpStdioServerDefinition(
          'RCA Tool',
          serverBin,
          [],
          { RCA_CLI_BIN: rcaCliBin },
        ),
      ];
    },
  };

  context.subscriptions.push(
    vscode.lm.registerMcpServerDefinitionProvider(PROVIDER_ID, provider),
  );

  // Re-resolve server definitions when the user changes the override paths.
  context.subscriptions.push(
    vscode.workspace.onDidChangeConfiguration((e) => {
      if (
        e.affectsConfiguration('rcaTool.mcpServerPath') ||
        e.affectsConfiguration('rcaTool.rcaCliPath')
      ) {
        didChange.fire();
      }
    }),
  );
}

export function deactivate(): void {
  // Subscriptions are disposed automatically by VS Code.
}
