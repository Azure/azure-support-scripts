# **Azure VM - Windows WUA Update Reset Script**

This PowerShell script resets Windows Update components to resolve issues where Windows Update fails or becomes stuck. It clears update caches, re-registers services, and restores default configurations to ensure updates can be downloaded and installed successfully.

***

### **Features**

*   Stops Windows Update-related services.
*   Clears **SoftwareDistribution** and **Catroot2** folders.
*   Re-registers critical Windows Update DLLs.
*   Restarts services and resets update configuration.

***

### **Prerequisites**

*   **PowerShell 5.1 or later**.
*   Must be executed with **Administrator privileges**.
*   Supported OS: Windows Server 2016 or later, Windows 10/11.

***

### **Usage**

Run the script in PowerShell:

```powershell
Set-ExecutionPolicy Bypass -Force
.\Windows_WUA_Update_Reset.ps1
```

***

### **Awareness**

*   Resetting Windows Update components will remove cached update files.
*   After running the script, Windows Update may take longer initially as it rebuilds its cache.
*   Ensure no other update operations are running during execution.

***

## Liability
As described in the [MIT license](..\..\..\LICENSE.txt), these scripts are provided as-is with no warranty or liability associated with their use.

## Provide Feedback
We value your input. If you encounter problems with the scripts or ideas on how they can be improved please file an issue in the [Issues](https://github.com/Azure/azure-support-scripts/issues) section of the project.

## Known Issues

