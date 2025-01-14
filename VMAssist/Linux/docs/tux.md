# Doc landing page

## Description
This will be a landing page for the potential issues found by using the VM assist scripts on a Linux VM running in Azure.  We will discuss or link to documentation discussing mitigations to potential problems affecting the Azure agent or general system stability

## General prerequesites and program flow
The VM assist troubleshooting scripts require very little in the way of prerequisites as it is intended to surface issues or present data for further scrutiny. The bare minimum is a functional `bash` shell and root-level access, either by directly becoming root or utilizing `sudo` in any form.  In order to run the python script properly, a workable python3 interpreter is required with only core or universally available modules.

~~~
**NOTE**
Regarding old distributions
All distributions in a standard supported state - excluding extended support offerings - use Python 3.  Conversely, all distributions using Python 2 as the primary version are into an "End of Life" status for general support.  This means that VM assist was built with python 3 conventions and modules.  While base checks may function in python 2, errors will occur and outputs may not be meaningful.  Similarly, `yum` is no longer the primary package manager, having been superseded by `dnf` in all current distribution families.

~~~

There are two scripts which comprise the 'tool', a bash script and a python script.  The bash script will perform some basic checks and determine if running the python script is possible and/or necessary.

The following checks are run in bash today
- OS family detection
- identify the Azure Agent service
- Identify the path of python called from the service - this will be used for running the python script
- Display the package, and repository for the package, for the agent and the python called from the agent
- Basic connectivity checks to the wire server and IMDS

If the bash script determines severe issues have been uncovered during the base OS checks, for whatever reason, the python script is not called and a brief report is presented.  Assuming that the python script is run, the bash report is suppressed unless the `-r` flag is used.

Python will run the following broad checks - which may be duplicates of the bash checks
- Find the source for the Azure agent and the python passed from bash
- optionally check any service or package statuses, which is currently a proof-of-concept inside the script
  - Only SSH is checked, as the PoC
- Provide source information for all checked files and services
- Do configuration checks for the Azure agent
- Connectivity checks for requirements of the Azure agent
- [Basic system configuration and status checks](#Guest best practices)

Output for the python script will show the agent related checks, where status is always displayed, along with anything deemed critical.

All data will be logged in /var/log/azure/vmassist*

Example output
![BASH ](URL or file path)

## Mitigations

### Agent not ready
- The guest OS must be booting completely
  - many occurrances of the Azure Agent not being in a ready state are actually due to the VM not booting at all.
  - emergency or single user mode is not a valid troubleshooting state. The emergency shell is not a full OS and many services are not available.  Determine the cause for emergency mode and return the OS to a full booting state before focusing on the Azure Agent.
  - This tool should not be run in a rescue VM or chroot environment.
- Generally speaking, the Agent package should not be installed from GitHub on a distribution which provides a package for the Azure Agent
  - [Agent Installation instructions](https://learn.microsoft.com/azure/virtual-machines/extensions/agent-linux#installation)
- Azure Agent service config and status must be 'enabled' and 'Running' respectively
- The python called by the agent unit must be able to load `requests` and the `azurelinuxagent` module see [loading modules](#loading-modules)
- Connectivity checks to the wire server must pass in order for the agent to report status to Azure
- Communication to the Instance Metadata Service must be allowed.  This may not affect the agent post-provisioning, but can cause issues for configuration changes and certain licensing functions
  - [IMDS information](https://learn.microsoft.com/en-us/azure/virtual-machines/instance-metadata-service?tabs=linux)

### Python issues
Calling versions of python not properly integrated with the rest of the operating system can cause consistency issues
- Python environments not created to the same specifications as the versions packaged with the OS may not include standard modules
- While this guidance is inteded specifically for the Azure Agent, replacing python in any modern Linux distribution is dangerous given how much of the OS is reliant on a stable and known python environment.
- On RedHat 8 systems there is a version of python to be used for all services located at `/usr/bin/platform-python` and the standard python3 usually links to it.  Note that the standard agent package references platform-python directly so it should be possible to alter the `/usr/bin/python3` link without breaking the Azure Agent, provided the agent is built by RedHat or to their convention
- In distributions other than RedHat 8, if there are multiple versions of python3 installed, the default python3 (/usr/bin/python3) should be one from the distribution publisher for the purpose of loading all the required modules.
- While it is possible to make any python3 work with the Azure Agent, it is out of scope for support as we only support the distribution python 3
- The correct path for anything needing a specific version of python 3 is to direct that software to the specific needed version and leave the OS-provided python, including keeping `/usr/bin/python3` linked to it.
- There may be other "distribution provided" python versions, but these packages will also indicate a minor version, such as `python3.12`, in the name where the "default" version is just `python3`, these python versions should not be linked to `/usr/bin/python3`

#### Loading modules
- Custom modules created as part of the Azure Agent are installed for the system python and other python versions will have their own library paths
- The scripts will check if the called python version can load the `azurelinuxagent` and `requests` python modules, both of which are necessary for proper functionaility
- If either module fails to load, the agent will not function properly, as the `azurelinuxagent` module is the actual agent class and `requests` is used for I/O operations with the wire server and IMDS.  Remember that `requests` is part of the base python3 installation and while not directly a dependency of the Azure Agent package, is needed for many other system functions.
- In a truly custom python3 build it is possible that even base modules are not present, which places the burden back on the systems administrator to fix any issues.

### Repositories
Installing packages that duplicate or replace system functions can cause issues, especially if these are done outside of the package manager mechanisms

When examining the output of the VM assist scripts, the repository listings are provided to surface this data for examination.  There are some base strings which are treated as "distribution provided" for validation purposes.  This includes, but may not be limited to, the following and will vary based on the distribution present
- azurelinux
- Origin: Ubuntu
- @System
- anaconda
- rhui
- AppStream
- SLE-Module

Certain other outputs in the "repository" output should be considered cause for investigation
- 3rd party websites
- custom "in-house" repositories or mirrors
- other versions or variations of the distribution in question, for example: CentOS on a RedHat VM, OpenSuSE on SuSE Enterprise, Debian on Ubuntu, and so on
- The string "@commandline" meaning the package was installed from a downloaded file, and will not have source information.
- No output (blank)

VM assist may flag unknown repositories as 'findings' even though they are the distribution publisher.  This is simply because the list of "safe" repositories is a static entity and not all distributions are handled - regardless of their ["endorsed"](https://learn.microsoft.com/azure/virtual-machines/linux/endorsed-distros) status.

#### Custom sources
The following scenarios are unsupported for anything which may affect the Azure Agent
- Using 3rd party repositories
- Mirroring the official repositories to a basic web server or any community driven repository tool.  Vendor tools such as SuSE Manager, RedHat Satellite, or similar, have controls on the packages contained within and would need careful evaluation to determine that the package is still Vendor built 
- Installing the scripts from the github repository when a distribution package is available
- Compiling the package from the github sources

### Connectivity
- Once VM has been verified to boot successfully, work through this guide
  (Linux guest agent)[https://learn.microsoft.com/troubleshoot/azure/virtual-machines/linux/linux-azure-guest-agent]
- All 3 network checks must pass, if an HTTP response is given it must be 200 (OK)
- No proxy redirection is allowed
  - https://learn.microsoft.com/azure/virtual-machines/instance-metadata-service?tabs=linux

### Agent configurations
- If the agent service is not set to 'enabled' this will be called out.  Note that the 'preset' for the systemd unit is disabled, but packages may manually enable it in their post-install or in the marketplace image configuration
- For best functionality the `AutoUpdate.Enabled` flag in the waagent.conf should be set to True, this allows the extension handler to upgrade to match the Azure infrastructure.  The base Agent package is not altered when the extension handler is updated
- Most Azure features that touch the guest OS operate as an extension.  If the `Extensions.Enabled` flag in the waagent.conf is disabled it will be flagged.

#### Auto Upgrade
The Azure agent consists of two parts 
- the provisioning agent and wrapper daemon
- Extension handler or "goalstate"

For best handling of Azure extensions, the goalstate should automatically pull updates from Azure.  The ability to do so is controlled by the `AutoUpdate.Enabled` flag.  If the wire server is found to have a newer version than is present on the VM, this will be flagged.  See the following FAQ for more discussion: [https://github.com/Azure/WALinuxAgent/wiki/FAQ]

#### Extensions

### Guest best practices

#### Disk space
While not strictly causing the Agent to fail, a full disk can cause unpredictable behavior.  One behavior is the inability for extensions to deploy or in some cases update, as a small download to `/var` will be needed.

VM assist contains a reasonable warning threshold, where disk utilization will be called out on a per-filesystem basis.

#### OpenSSL
Generally speaking, openssl does not apply to the starting of the Azure Agent, or communication to either the wireserver or IMDS as these are http endpoints.  However openssl issues can cause problems with anything else that communicates to an SSL website. SSL communications in Azure often include, but are not limited to 
- Azure platform API endpoints
- Other Azure services other than the management API 
- EntraID SSH authentication
- OS vendor repository and licensing servers

Altering the base OpenSSL binary either by installing 3rd party packages or rebuilding from source, is unsupported in all forms.

#### Networking
While deviations from networking best practices do not strictly cause the agent to not be online, all communication may fail if the networking of the guest is misconfigured
- IPs should not be statically defined, as stated in [Networking best practices](https://learn.microsoft.com/azure/virtual-network/ip-services/virtual-network-network-interface-addresses?tabs=nic-address-portal#address-types)
- MAC address definitions in network configurations should match the Azure NICs.  This data is usually updated by `cloud-init` in most distributions, however there are instances where where the Azure Agent is used for provisioning - usually in absence of `cloud-init`.
- Proxies should not be defined, or there need to be exclusions for the wire server and IMDS IPs at a minimum.  VM assist will check for proxy definitions in well-known, system-wide configurations, however there are countless ways to define proxy addresses.


