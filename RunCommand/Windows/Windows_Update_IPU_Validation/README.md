
# **Azure VM - Windows Update IPU Validation Script**

This PowerShell script validates whether a Windows system requires an **In-Place Upgrade (IPU)**. It checks Windows Update components, servicing stack health, and disk space to detect update failures.

***

### **Features**

*   Validates Windows Update components and services.
*   Checks pending updates and servicing stack readiness.
*   Confirms disk space and OS build compatibility.
*   Generates a summary report for troubleshooting.

***

### **Prerequisites**

*   PowerShell 5.1 or later.
*   Must be executed with **Administrator privileges**.
*   Internet connectivity for Windows Update checks.
*   Supported OS: Windows Server 2016 or later, Windows 10/11.

***

### **Usage**

Run the script in PowerShell:

```powershell
Set-ExecutionPolicy Bypass -Force
.\Windows_Update_IPU_Validation.ps1
```

***

### **Awareness**

*   Validation time depends on system state and number of checks.
*   Ensure no other update operations are running during validation.

***

### **Liability**

As described in the [MIT license](..\..\..\LICENSE.txt), these scripts are provided as-is with no warranty or liability associated with their use.

***

### **Provide Feedback**

We value your input. If you encounter problems with the scripts or ideas on how they can be improved please file an issue in the [Issues](https://github.com/Azure/azure-support-scripts/issues) section of the project.

***

### **Known Issues**
