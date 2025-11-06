
# Windows In-Place Upgrade Assessment Script

## Overview

This PowerShell script is designed to assess the readiness of a Windows machine (desktop or server) for an **in-place OS upgrade**, with special considerations for **Azure VMs**. It evaluates OS version, supported upgrade paths, system disk space, and Azure security features like **Trusted Launch**, **Secure Boot**, and **vTPM**.

---

## Key Features

- **OS Version Detection**
  - Identifies whether the system is Windows 10, 11, or a Windows Server edition.
- **Server Upgrade Path Check**
  - Matches current server version to supported upgrade targets.
- **Hardware Validation**
  - Disk space (≥ 64 GB)
  - Physical memory (≥ 4 GB)
- **Azure VM Security Feature Verification**
  - Trusted Launch
  - Secure Boot
  - Virtual TPM
- **Azure Virtual Desktop (AVD) Detection**
  - Flags unsupported pooled host pool configurations.
- **Upgrade Recommendations**
  - Outputs supported upgrade paths or relevant upgrade guidance.

---

## Requirements

- PowerShell 5.1 or later.
- Script must be run with administrative privileges.
- To retrieve Azure instance metadata, script must be executed on an **Azure VM** with **instance metadata service** access enabled.

---
## Upgrade Matrix
**Windows Server**
| Current Version                              | Supported Upgrade Targets                                        |
| -------------------------------------------- | ---------------------------------------------------------------- |
| Windows Server 2008                          | Windows Server 2012                                              |
| Windows Server 2008 R2                       | Windows Server 2012                                              |
| Windows Server 2012                          | Windows Server 2016                                              |
| Windows Server 2012 R2                       | Windows Server 2016, Windows Server 2019, or Windows Server 2025 |
| Windows Server 2016                          | Windows Server 2019, Windows Server 2022, or Windows Server 2025 |
| Windows Server 2019                          | Windows Server 2022 or Windows Server 2025                       |
| Windows Server 2022                          | Windows Server 2025                                              |
| Windows Server 2025                          | ❌ No direct upgrade path – redeploy a new VM                     |
| Windows Server 2022 Datacenter Azure Edition | ❌ No direct upgrade path – redeploy a new VM                     |
| Windows Server 2025 Datacenter Azure Edition | ❌ No direct upgrade path – redeploy a new VM                     |

**Windows Client**
| OS Version            | VM Generation | Trusted Launch | Secure Boot | vTPM  | Upgrade Possibility                                                                                                                 |
| --------------------- | ------------- | -------------- | ----------- | ----- | ----------------------------------------------------------------------------------------------------------------------------------- |
| **Windows 10**        | Gen1          | N/A            | N/A         | N/A   | ❌ Not supported for upgrade to Windows 11                                                                                           |
| **Windows 10**        | Gen2          | ❌              | ❌ / ✅       | ❌ / ✅ | ⚠️ Limited upgrade support; requirements missing                                                                                    |
| **Windows 10**        | Gen2          | ✅              | ✅           | ✅     | ✅ Upgrade to Windows 11 via feature update or [Installation Assistant](https://www.microsoft.com/en-us/software-download/windows11) |
| **Windows 10(AVD Pooled Host Pool)**        | Any         | N/A             | N/A          | N/A     | ❌ Not supported for In-place-upgrade |
| **Windows 11 ≤ 21H2** | Gen2           | ❌              | N/A         | N/A   | ⚠️ Upgrade to 22H2+ requires Trusted Launch                                                                                         |
| **Windows 11 ≤ 21H2** | Gen2           | ✅              | N/A         | N/A   | ✅ Eligible for upgrade to 22H2 and above                                                                                            |
| **Windows 11 ≥ 22H2** | Gen2           | N/A            | N/A         | N/A   | ✅ Already up to date                                                                                                                |

## Usage

1. Open **PowerShell as Administrator**.
2. Run the script:

   ```powershell
   .\Windows_OSUpgrade_Assessment_Validation.ps1
   ```

3. Review the output for upgrade recommendations and any potential blockers.

---

## Output Examples

Example output on a Windows Server 2016 VM:

```
Windows Version: Windows Server 2019 Datacenter

[Passed] Disk Space (Free: 128 GB)
[Passed] Physical Memory (Total: 8 GB)
[Passed] VM Generation: Gen2
[Passed] Trusted Launch
[Passed] Secure Boot
[Passed] TPM Enabled

The VM is running Windows Server 2019 Datacenter. 
The supported upgrade options are: Windows Server 2022 or Windows Server 2025.
Please refer to the official documentation for more details: 
https://learn.microsoft.com/azure/virtual-machines/windows-in-place-upgrade
```

Example output on an Azure Gen1 Windows 10 VM:

```
Windows Version: Windows 10 Pro

[Passed] Disk Space (Free: 105.71 GB)
[Passed] Physical Memory (Total: 8 GB)
[Failed] VM Generation: Gen2 required for upgrade
[Failed] Unable to retrieve Azure metadata. Ensure the script is running on an Azure VM with access to instance metadata.
IMDS Errors and debugging: https://learn.microsoft.com/azure/virtual-machines/instance-metadata-service?tabs=windows#errors-and-debugging

FAILED: The VM is running Windows 10 Gen1. Upgrade to Windows 11 is only supported for Gen2 VMs

```
---

## References

- [PC Health Check App](https://support.microsoft.com/en-us/windows/how-to-use-the-pc-health-check-app-9c8abd9b-03ba-4e67-81ef-36f37caa7844)  
- [Windows 11 Installation Assistant](https://www.microsoft.com/software-download/windows11)

## Liability
As described in the [MIT license](..\..\..\LICENSE.txt), these scripts are provided as-is with no warranty or liability associated with their use.

## Provide Feedback
We value your input. If you encounter problems with the scripts or ideas on how they can be improved please file an issue in the [Issues](https://github.com/Azure/azure-support-scripts/issues) section of the project.

## Known Issues