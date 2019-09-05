# Enable or disable Automatic Updates in Windows Update
To enable or disable Automatic Windows Updates on a VM, you can run these via [RunCommand](https://docs.microsoft.com/en-us/azure/virtual-machines/windows/run-command) in the portal or through the Azure PowerShell cmdlet.

## PowerShell script to Disable Automatic Updates in Windows Update

```
Set-ItemProperty HKLM:\Software\Policies\Microsoft\Windows\WindowsUpdate\AU -Name NoAutoUpdate -Value 1
Set-ItemProperty HKLM:\Software\Policies\Microsoft\Windows\WindowsUpdate\AU -Name AUOptions -Value 3
```

## PowerShell script to Enable Automatic Updates in Windows Update
```
Set-ItemProperty HKLM:\Software\Policies\Microsoft\Windows\WindowsUpdate\AU -Name NoAutoUpdate -Value 0
Set-ItemProperty HKLM:\Software\Policies\Microsoft\Windows\WindowsUpdate\AU -Name AUOptions -Value 4
Set-ItemProperty "HKLM:\Software\Policies\Microsoft\Windows\Task Scheduler\Maintenance" -Name "Activation Boundary" -Value "2000-01-01T01:00:00"
Set-ItemProperty "HKLM:\Software\Policies\Microsoft\Windows\Task Scheduler\Maintenance" -Name Randomized -Value 1
Set-ItemProperty "HKLM:\Software\Policies\Microsoft\Windows\Task Scheduler\Maintenance" -Name "Random Delay" -Value "PT4H"
```
When **NoAutoUpdate** is **0** and **AUOptions** is 4, Windows automatically installs updates and reboots if any of the updates require a reboot.

The Azure VM property [EnableAutomaticUpdates](https://docs.microsoft.com/en-us/dotnet/api/microsoft.azure.management.compute.models.windowsconfiguration.enableautomaticupdates?view=azure-dotnet) determines if the Azure provisioning agent enables automatic updates when the VM is created. **EnableAutomaticUpdates** defaults to **True** if it is not explicitly defined. When **EnableAutomaticUpdates** is **True**, the Azure provisioning agent configures the Windows registry settings to enable automatic updates using the values referenced above. Note that for Windows VMs, the Azure provisioning agent is separate from the Azure VM agent. The Azure provisioning agent only runs once, when the VM is initially created, and it is not installed as a service.

The Azure VM agent, which does run as a service, is never expected to configure Windows Update settings. The exception was with Azure VM agent versions **2.7.41491.938** and **2.7.41491.940** which inadvertently did a one-time configuration to apply settings based on the **EnableAutomaticUpdates** value. Earlier versions of the Azure VM agent, as well as **2.7.41491.943** and later versions, never configure Windows Update settings.

For example, if you created a VM with the **EnableAutomaticUpdates** set to **True** (or left it undefined in which case it defaults to **True**), the Azure provisioning agent enabled automatic updates when the VM was created. If you later disabled automatic updates manually, and the VM was running Azure VM agent version **2.7.41491.938** or **2.7.41491.940**, the Azure VM agent reverted the automatic update settings back to being enabled. It would only revert the settings once. Versions **2.7.41491.943** and later correct that behavior so that the Azure VM agent never configures Windows Update settings, regardless of how the **EnableAutomaticUpdates** property is defined.
