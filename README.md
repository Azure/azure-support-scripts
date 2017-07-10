# Azure Support Scripts
This repository contains scripts that are used by Microsoft Customer Service and Support (CSS) to aid in gaining better insight into, or troubleshooting issues with, deployments in Microsoft Azure.  A goal of this repository is provide transparency to Azure customers who want to better understand the scripts being used and to make these scripts accessible for self-help scenarios outside of Microsoft support.

These scripts are generally intended address a particular scenario and are not published as samples of best practices for inclusion in applications.  

- For code and scripting examples of best practice see [OneCode](http://aka.ms/onecodesamples), [OneScript](http://aka.ms/onescriptsamples), and the [Microsoft Azure Script Center](https://azure.microsoft.com/en-us/documentation/scripts/).  
- For documentation on how to build and deploy applications to Microsoft Azure, please see the [Microsoft Azure Documentation Center](https://azure.microsoft.com/en-us/documentation/).
-	For more information about support in Microsoft Azure see http://azure.microsoft.com/support 

# Requirements
Each script will describe its own dependencies for execution.  Generally, you will need an [Azure subscription](https://azure.microsoft.com/en-us/pricing/) as well as the script environments and any tools used by the script you wish to execute.  This may include:

- Azure PowerShell: 	[How to install and configure Azure PowerShell](https://azure.microsoft.com/en-us/documentation/articles/powershell-install-configure/)
- Azure Cli:	[How to install and configure Azure Command-Line Interface (Cli)](https://azure.microsoft.com/en-us/documentation/articles/xplat-cli-install/)
- Python:	[Azure Python Developer Center](https://azure.microsoft.com/en-us/develop/python/)

A great place to find such an environment is the [Azure Cloud Shell](https://azure.microsoft.com/en-us/features/cloud-shell/).

# Find Your Way
The repo is organized by support scenario and each contains a simple description of the script(s) in a readme.md.  Depending on the scenario, you will find one or more scripts written in common languages (e.g. PowerShell, Bash, Python) targeting various aspects of the Azure platform (e.g. Windows VM Guests, Linux VM Guests, Azure subscription settings).

# Liability
As described in the [MIT license](LICENSE.txt), these scripts are provided as-is with no warranty or liability associated with their use.

# Provide Feedback
We value your input.  If you encounter problems with the scripts or ideas on how they can be improved please file an issue in the [Issues](https://github.com/Azure/azure-support-scripts/issues) section of the project.

# Known Issues
