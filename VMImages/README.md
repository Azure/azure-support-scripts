You can run **Get-AzVMImageDeprecationStatus.ps1** to show if any VMs in a subscription were created from VM images that are scheduled for deprecation. This script does not support VMSS.

See [https://aka.ms/DeprecatedImagesFAQ](https://aka.ms/DeprecatedImagesFAQ) for more information about VM image deprecation.

To run **Get-AzVMImageDeprecationStatus.ps1** in Azure Cloud Shell:

1. Open Cloud Shell in Azure Portal, or by navigating to [https://shell.azure.com](https://shell.azure.com)
2. Click **Switch to PowerShell** at the top left. If it says **Switch to Bash** you're already in PowerShell.
3. Run the following command to download **Get-AzVMImageDeprecationStatus.ps1** into cloud shell:
```
Invoke-WebRequest https://raw.githubusercontent.com/Azure/azure-support-scripts/master/VMImages/Get-AzVMImageDeprecationStatus.ps1 -OutFile Get-AzVMImageDeprecationStatus.ps1
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

Sample output:

```
PS /home/craig> ./Get-AzVMImageDeprecationStatus.ps1

5 of 19 VMs were created from images scheduled for deprecation

Showing VMs from images scheduled for deprecation (use -all to show all VMs):

VM            RG ImageState              ScheduledDeprecationTime ImageUrn                                                                          AlternativeOption
--            -- ----------              ------------------------ --------                                                                          -----------------
sles15        RG ScheduledForDeprecation 2024-11-07T00:00:00Z     suse:sles-15-sp5-byos:gen2:2023.12.14
win10-ent-cpc RG ScheduledForDeprecation 2024-11-18T00:00:00Z     microsoftwindowsdesktop:windows-ent-cpc:win10-22h2-ent-cpc-m365:19045.4046.240213
win11-ent-cpc RG ScheduledForDeprecation 2024-11-18T00:00:00Z     microsoftwindowsdesktop:windows-ent-cpc:win10-22h2-ent-cpc-m365:19045.4046.240213
ub20          RG ScheduledForDeprecation 2024-11-22T00:00:00Z     canonical:0001-com-ubuntu-server-focal:20_04-lts:20.04.202105130
ws19          RG ScheduledForDeprecation 2024-12-10T00:00:00Z     microsoftwindowsserver:windowsserver:2019-datacenter:17763.4645.230707

Writing output to /home/craig

 CSV: /home/craig\Get-AzVMImageDeprecationStatus-351d4bb3-5fd0-40ef-88fe-3ca10c783275.csv
JSON: /home/craig\Get-AzVMImageDeprecationStatus-351d4bb3-5fd0-40ef-88fe-3ca10c783275.json
 TXT: /home/craig\Get-AzVMImageDeprecationStatus-351d4bb3-5fd0-40ef-88fe-3ca10c783275.txt

 ZIP: /home/craig\imagestate.zip

To download 'imagestate.zip' from cloud shell, select 'Manage Files', 'Download', then enter 'imagestate.zip' in the required field, then click 'Download'

6.2s
```