# Azure Support Scripts

This repository contains scripts that are used by Microsoft Customer Service and Support (CSS) to aid in gaining better insight into, or troubleshooting issues with, deployments in Microsoft Azure. A goal of this repository is provide transparency to Azure customers who want to better understand the scripts being used and to make these scripts accessible for self-help scenarios outside of Microsoft support.

These scripts are generally intended to address a particular scenario and are not published as samples of best practices for inclusion in applications.

* For code and scripting examples of best practice see [OneCode](https://learn.microsoft.com/samples/browse/?expanded=azure&products=azure-resource-manager), [OneScript](https://learn.microsoft.com/shows/onescript), and the [Microsoft Azure Script Center](https://azure.microsoft.com/en-us/documentation/scripts).
* For documentation on building and deploying applications for Microsoft Azure, please see the [Microsoft Azure Documentation Center](https://learn.microsoft.com/azure).
* For more information about support in Microsoft Azure see http://azure.microsoft.com/support

# 

# Requirements

Each script will describe its own dependencies for execution. Generally, you will need an [Azure subscription](https://azure.microsoft.com/pricing) as well as the script environments and any tools used by the script you wish to execute. This may include:

* Azure PowerShell: [How to install Azure PowerShell](https://learn.microsoft.com//powershell/azure/install-azure-powershell)
* Azure CLI: [How to install the Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli)
* Python: [Python on Azure](https://azure.microsoft.com/resources/developers/python)

A great place to find such an environment is the [Azure Cloud Shell](https://aka.ms/cloudshell).

# 

# Find Your Way

The repo is organized by support scenario and each contains a simple description of the script(s) in a readme.md. Depending on the scenario, you will find one or more scripts written in common languages (e.g. PowerShell, Bash, Python) targeting various aspects of the Azure platform (e.g. Windows VM Guests, Linux VM Guests, Azure subscription settings).

# 

-----

## How To Contribute


	1.	Clone github repo locally
		 $ git clone https://github.com/Azure/azure-support-scripts <local_path>
	
	2.	Create a new branch from master
		 $ cd <local_path>
		 $ git checkout -b <new_branch>

	4.	Apply your changes in the branch

	5.	Push changes to your remote branch by following below sequesnce of commands
		$ git add <file_changed>
		$ git commit -m "<Commit_message>"
		$ git push --set-upstream origin <new_branch> 

	6.	Raise PR to merge into master for review

-----

# 

# Liability

As described in the [MIT license](LICENSE.txt), these scripts are provided as-is with no warranty or liability associated with their use.

# 

# Provide Feedback

We value your input. If you encounter problems with the scripts or ideas on how they can be improved please file an issue in the [Issues](https://github.com/Azure/azure-support-scripts/issues) section of the project.

# 

# Known Issues

