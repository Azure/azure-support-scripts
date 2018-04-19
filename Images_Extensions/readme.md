The scripts in this folder will list the VM images and extensions in Azure by using the Resource Manager endpoints.  Images and extensions are published to a particular location or datacenter.  These scripts will accept a location paramenter (e.g. westus), if no default parameter is passed a default location will be used.

## Usage
These scripts are designed to run [on a local computer](../Documentation/CallingScripts.md).

## Known Issues
Due to the interative nature of looping through each publisher and version of the images/extensions, these scripts may take several minutes to execute. 
