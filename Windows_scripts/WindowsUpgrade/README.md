
# Windows In-Place Upgrade Assessment Script

## Overview

This PowerShell script is designed to assess the readiness of a Windows machine (desktop or server) for an **in-place OS upgrade**, with special considerations for **Azure VMs**. It evaluates OS version, supported upgrade paths, system disk space, and Azure security features like **Trusted Launch**, **Secure Boot**, and **vTPM**.

---

## Key Features

- ✅ Detects Windows version and distinguishes between desktop and server editions.
- ✅ Evaluates supported upgrade paths based on current Windows Server version.
- ✅ Checks system drive for required free space (minimum 64 GB).
- ✅ For Windows 10:
  - Identifies generation (Gen1 or Gen2).
  - Recommends upgrade options to Windows 11.
  - Checks Azure security features if run on a VM.
- ✅ For Windows 11:
  - Validates whether it's eligible for upgrades like 22H2 or newer based on **Trusted Launch**.
- ✅ Fetches Azure VM metadata to assess upgrade-blocking conditions (when applicable).

---

## Requirements

- PowerShell 5.1 or later.
- Script must be run with administrative privileges.
- To retrieve Azure instance metadata, script must be executed on an **Azure VM** with **instance metadata service** access enabled.

---
## Upgrade Matrix
| Current Version                              | Supported Upgrade Targets                                        |
| -------------------------------------------- | ---------------------------------------------------------------- |
| Windows Server 2008                          | Windows Server 2012                                              |
| Windows Server 2008 R2                       | Windows Server 2012                                              |
| Windows Server 2012                          | Windows Server 2016                                              |
| Windows Server 2012 R2                       | Windows Server 2016, Windows Server 2019, or Windows Server 2025 |
| Windows Server 2016                          | Windows Server 2019, Windows Server 2022, or Windows Server 2025 |
| Windows Server 2019                          | Windows Server 2022 or Windows Server 2025                       |
| Windows Server 2022                          | Windows Server 2025                                              |
| Windows Server 2022 Datacenter Azure Edition | ❌ No direct upgrade path – redeploy a new VM                     |
| Windows Server 2025 Datacenter Azure Edition | ❌ No direct upgrade path – redeploy a new VM                     |


| OS Version            | VM Generation | Trusted Launch | Secure Boot | vTPM  | Upgrade Possibility                                                                                                                 |
| --------------------- | ------------- | -------------- | ----------- | ----- | ----------------------------------------------------------------------------------------------------------------------------------- |
| **Windows 10**        | Gen1          | N/A            | N/A         | N/A   | ❌ Not supported for upgrade to Windows 11                                                                                           |
| **Windows 10**        | Gen2          | ❌              | ❌ / ✅       | ❌ / ✅ | ⚠️ Limited upgrade support; requirements missing                                                                                    |
| **Windows 10**        | Gen2          | ✅              | ✅           | ✅     | ✅ Upgrade to Windows 11 via feature update or [Installation Assistant](https://www.microsoft.com/en-us/software-download/windows11) |
| **Windows 11 ≤ 21H2** | N/A           | ❌              | N/A         | N/A   | ⚠️ Upgrade to 22H2+ requires Trusted Launch                                                                                         |
| **Windows 11 ≤ 21H2** | N/A           | ✅              | N/A         | N/A   | ✅ Eligible for upgrade to 22H2 and above                                                                                            |
| **Windows 11 ≥ 22H2** | N/A           | N/A            | N/A         | N/A   | ✅ Already up to date                                                                                                                |

## Usage

1. Open **PowerShell as Administrator**.
2. Run the script:

   ```powershell
   .\UpgradeAssessment.ps1
   ```

3. Review the output for upgrade recommendations and any potential blockers.

---

## Output Examples

Example output on a Windows Server 2016 VM:

```
The VM is running Windows Server 2016. The supported upgrade options are: Windows Server 2019, Windows Server 2022, or Windows Server 2025.

Please refer to the official documentation for more details: https://learn.microsoft.com/en-us/azure/virtual-machines/windows-in-place-upgrade
```

Example output on an Azure Gen2 Windows 10 VM:

```
The VM is running Windows 10 Gen2. you may upgrade it to Windows 11 via feature update, or using Windows 11 Installation Assistant. Confirm the upgrade eligibility using the PC Health Check App.
The VM has Trusted Launch, Secure Boot and Virtual TPM enabled. OK
PC Health Check App: https://support.microsoft.com/en-us/windows/how-to-use-the-pc-health-check-app-9c8abd9b-03ba-4e67-81ef-36f37caa7844
Windows 11 Installation Assistant: https://www.microsoft.com/en-us/software-download/windows11
```
---

## Troubleshooting

- **Azure Metadata Retrieval Errors:**  
  Ensure the script runs **within an Azure VM** and has access to `http://169.254.169.254`.

- **No output or partial output:**  
  Make sure all required registry keys and system information are accessible (no policy restrictions).

---

## Resources

- [PC Health Check App](https://support.microsoft.com/en-us/windows/how-to-use-the-pc-health-check-app-9c8abd9b-03ba-4e67-81ef-36f37caa7844)  
- [Windows 11 Installation Assistant](https://www.microsoft.com/en-us/software-download/windows11)
