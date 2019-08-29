# Enable or disable Automatic Updates in Windows Update
To enable or disable Automatic Windows Updates on a VM, you can run these through via [RunCommand](https://docs.microsoft.com/en-us/azure/virtual-machines/windows/run-command) in the portal or through the Azure PowerShell cmdlet.

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
