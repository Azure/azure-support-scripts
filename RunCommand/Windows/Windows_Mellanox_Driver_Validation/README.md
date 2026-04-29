# Azure VM - Windows Mellanox Driver Validation Script

This PowerShell script validates the Mellanox mlx5 network adapter driver version on
Azure Windows VMs and checks for evidence of `DRIVER_IRQL_NOT_LESS_OR_EQUAL`
(bugcheck **0x000000D1**) events — a common crash signature caused by outdated
Mellanox mlx5 drivers.

Use this script as the **first stop** when handling Mellanox mlx5 driver-related crash
cases, before escalation.

## Related Documentation

- [Troubleshoot Mellanox mlx5 Driver Crashes on Azure Windows VMs](https://learn.microsoft.com/en-us/troubleshoot/azure/virtual-machines/windows/windows-virtual-machine-mellanox-network-driver-crash-troubleshooting)
- [Azure VM Mellanox Driver Validation Tool](https://learn.microsoft.com/en-us/troubleshoot/azure/virtual-machines/windows/windows-virtual-machine-mellanox-network-driver-validation-tool)

## Features

- Detects installed Mellanox / NVIDIA ConnectX network adapters
- Reports driver version, date, and provider
- Flags drivers that appear outdated (> 1 year) for TSG review
- Checks Windows Event Log for recent `0x000000D1` bug check events (last 30 days)
- Reports adapter link status

## Prerequisites

- PowerShell 5.1 or later
- Must be executed within an Azure Windows VM
- Elevated (Administrator) privileges recommended for full event log access

## Usage

Run the script in PowerShell **within an Azure Windows VM**:

```powershell
Set-ExecutionPolicy Bypass -Force
.\Windows_Mellanox_Driver_Validation.ps1
```

Or run via the Azure portal **Run Command** feature:
1. Navigate to the VM in the Azure portal.
2. Select **Operations** > **Run Command** > **RunPowerShellScript**.
3. Paste the script contents and select **Run**.

### What to look for in the output

| Section | Look for |
|---------|----------|
| Adapter Detection | Confirms whether a Mellanox adapter is present |
| Driver Version | Compare version against TSG minimum — flag if > 1 year old |
| Bugcheck Events | Any `0x000000D1` events in the last 30 days |
| Link Status | Adapter status `Up` vs. error/disabled state |

### Related TSG

**Mellanox mlx5 Driver Crash – Outdated Driver (Windows)**
`https://dev.azure.com/Supportability/AzureIaaSVM/_wiki/wikis/AzureIaaSVM/2539440/`

Use the TSG to:
- Validate the driver version reported by this script
- Walk the customer through the supported driver update process

### Awareness

- This script is **detection only** — it makes no changes to the system.
- On VMs with multiple Mellanox adapters, output is generated per adapter.
- Event log lookback is 30 days by default.
- Adapter age warning threshold is 365 days; > 730 days shows a higher-severity warning.

## Known Issues

- On some VM SKUs, `Get-PnpDevice` may not enumerate the Mellanox adapter even when
  present. If the adapter is visible in Device Manager but not detected by the script,
  run `Get-WmiObject Win32_PnPSignedDriver | Where-Object { $_.DeviceName -match 'Mellanox' }`
  directly to confirm.

## Liability

As described in the [MIT license](../../../LICENSE.txt), these scripts are provided
as-is with no warranty or liability associated with their use.

## Provide Feedback

We value your input. If you encounter problems with the script or have ideas on how it
can be improved, please file an issue in the
[Issues](https://github.com/Azure/azure-support-scripts/issues) section of the project.
