You can run **Get-AzVMImageDeprecationStatus.ps1** to show if any VMs in a subscription were created from VM images that are scheduled for deprecation.

See [https://aka.ms/DeprecatedImagesFAQ](https://aka.ms/DeprecatedImagesFAQ) for more information about VM image deprecation.

To run **Get-AzVMImageDeprecationStatus.ps1** in Azure Cloud Shell:

1. Open Cloud Shell in Azure Portal, or by navigating to [https://shell.azure.com](https://shell.azure.com)
2. Click **Switch to PowerShell** at the top left. If it says **Switch to Bash** you're already in PowerShell.
3. Run the following command to download **Get-AzVMImageDeprecationStatus.ps1** into cloud shell:
```
Invoke-WebRequest https://raw.githubusercontent.com/craiglandis/ps/master/Get-AzVMImageDeprecationStatus.ps1 -OutFile Get-AzVMImageDeprecationStatus.ps1
```
4. To check all VMs in the subscription, run **Get-AzVMImageDeprecationStatus.ps1** with no parameters:
```
./Get-AzVMImageDeprecationStatus.ps1
```
5. To only check VMs in a specific resource group, run **Get-AzVMImageDeprecationStatus.ps1** with the **-resourceGroupName** parameter:
```
./Get-AzVMImageDeprecationStatus.ps1 -resourceGroupName myRG
```
6. To only check one specific VM, run **Get-AzVMImageDeprecationStatus.ps1** with both the **-resourceGroupName** and **-vmName** parameters:
```
./Get-AzVMImageDeprecationStatus.ps1 -resourceGroupName myRG -vmName myVM
```

If any VMs were created from images scheduled for deprecation, their details will be output to the screen as well as to CSV, JSON, and text output files which are zipped into **imagestate.zip**.

To download **imagestate.zip** from cloud shell, select **Manage Files** on the Cloud Shell toolbar, then **Download**, enter **imagestate.zip** in the required field, then click **Download**.