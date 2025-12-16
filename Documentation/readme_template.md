# Script Name

## Overview

Briefly describe the purpose of the script and the problem it solves.

## Prerequisites

- List required tools, modules, or dependencies (e.g., PowerShell, Az module, etc.)
- Mention any permissions or Azure roles needed

## Usage

```sh
# Example usage command
# Replace with actual script invocation
./ScriptName.ps1 -Parameter1 value1 -Parameter2 value2
```

### Parameters

| Name           | Description                            | Required | Default |
|----------------|----------------------------------------|----------|---------|
| `-Parameter1`  | What does this parameter do?           | Yes      | N/A     |
| `-Parameter2`  | Describe this parameter briefly        | No       | value2  |

## Examples

```sh
# Example 1: Short description
./ScriptName.ps1 -Parameter1 foo

# Example 2: Another usage scenario
./ScriptName.ps1 -Parameter1 bar -Parameter2 baz
```

## Output

Describe what output or artifacts (files, console output, logs, etc.) the script generates.

# Analyzing output

## 🧪 Script Output

* If writing anything locally or changing, please work with the working group to understand limitations
* Script output should be useful like a logfile
* Final results with external content link

### Windows:
The script provides detailed output using color-coded messages in the PowerShell console:

| Symbol | Color        | Meaning                                                                 |
|--------|--------------|-------------------------------------------------------------------------|
| ✅     | **Green**     | Successful operations (e.g., connection established, activation valid)   |
| ⚠️     | **Yellow**    | Warnings or non-critical issues (e.g., non-default KMS endpoint, certificates) |
| ❌     | **Red**       | Errors or failures (e.g., certificate chain issues, activation failure, IMDS not reachable) |

### Linux:

TBD 

If you open a support request, please include both of the above files to aid your support representative in helping you.


## License + Liability
As described in the [MIT license](..\LICENSE.txt), these scripts are provided as-is with no warranty or liability associated with their use.

## Provide Feedback
We value your input. If you encounter problems with the scripts or ideas on how they can be improved please file an issue in the [Issues](https://github.com/Azure/azure-support-scripts/issues) section of the project.


## Notes

- Add any caveats, additional info, or considerations here.
- Mention known limitations or troubleshooting steps.

