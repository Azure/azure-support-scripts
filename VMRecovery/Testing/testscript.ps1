#My TESTING
#TEST CASE 1 Windows unmanaged
$resourceGroupName="rgvmrecotesting"
$vmName="UnManWin"
$password="Pa55w0rd!.?!"
$username= "Sujasd"
.\Create-TestVM.ps1 -resourceGroupName $resourceGroupName -vmName $vmName -windows -useManagedDisk:$false -username $username -password $password  -wait;
E:\git\GitHub-AzureSupportScripts\VMRecovery\ResourceManager\New-AzureRMRescueVM.ps1 -ResourceGroupName $resourceGroupName -VmName $vmName -userName $username -password $password  



#
#TEST CASE 2 Windows Managed
$resourceGroupName="rgvmrecotesting"
$vmName="ManWin"
$password="Pa55w0rd!.?!"
$username= "Sujasd"
.\Create-TestVM.ps1 -resourceGroupName $resourceGroupName -vmName $vmName -windows -useManagedDisk:$true -username $username -password $password  -wait;
E:\git\GitHub-AzureSupportScripts\VMRecovery\ResourceManager\New-AzureRMRescueVM.ps1 -ResourceGroupName $resourceGroupName -VmName $vmName -userName $username -password $password  


#TEST CASE 3 Linux unmanaged
$resourceGroupName="rgvmrecotesting"
$vmName="UnMANLinux"
$password="Pa55w0rd!.?!"
$username= "Sujasd"
#.\Create-TestVM.ps1 -resourceGroupName $resourceGroupName -vmName $vmName -windows -useManagedDisk:$false -username $username -password $password  -wait;
E:\git\GitHub-AzureSupportScripts\VMRecovery\ResourceManager\New-AzureRMRescueVM.ps1 -ResourceGroupName $resourceGroupName -VmName $vmName -userName $username -password $password  


#TEST CASE 4 Linux managed 
$resourceGroupName="rgvmrecotesting"
$vmName="MANLinux"
$password="Pa55w0rd!.?!"
$username= "Sujasd"
.\Create-TestVM.ps1 -resourceGroupName $resourceGroupName -vmName $vmName -windows -useManagedDisk:$True -username $username -password $password  -wait;
E:\git\GitHub-AzureSupportScripts\VMRecovery\ResourceManager\New-AzureRMRescueVM.ps1 -ResourceGroupName $resourceGroupName -VmName $vmName -userName $username -password $password  

