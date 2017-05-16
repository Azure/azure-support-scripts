There are two Azure VM Agents, one for Windows VMs and one for Linux VMs.  For an overview of these agents see [About the virtual machine agent and extensions](https://azure.microsoft.com/en-us/documentation/articles/virtual-machines-windows-classic-agents-and-extensions/)

## Azure Windows Agent 
The Windows VM agent is an optional component, however once installed it will automatically keep itself updated.  If a Windows VM is not auto-updating properly or you need to install the agent manually because it was never installed (e.g. if it was created from specialized VHD), you can run the [MSI installer](http://go.microsoft.com/fwlink/?LinkID=394789&clcid=0x409) to get on the latest version.


## Azure Linux Agent (waagent)
A wealth of information on the Azure Linux agent can be found in the [user guide](https://azure.microsoft.com/en-us/documentation/articles/virtual-machines-linux-agent-user-guide/). At this time the Linux guest agent does not auto-update.  Therefore, you are responsible for keeping the agent current.  Microsoft will periodically update the agent (waagent) in the various endorsed Linux distribution package repositories.  The recommended best practice is to update to the latest version available in the respective repositories for your distribution.  There are manual update steps available to move to the latest version of waagent on [GitHub](https://github.com/Azure/WALinuxAgent), but this should only be necessary to do under the direction of Microsoft support.


## Getting the agent version when logged on
### Windows Agent
When connected to the Windows guest, there are a couple ways to determine the version of the azure agent

The **Incarnation** REG_SZ value in **HKLM\SOFTWARE\Microsoft\GuestAgent** has the guest agent version on Windows VMs. 

**Reg.exe**
```
> reg query HKLM\SOFTWARE\Microsoft\GuestAgent /v Incarnation
HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\GuestAgent
    Incarnation    REG_SZ    2.7.1198.735
```

**PowerShell**
```
> (Get-ItemProperty -path HKLM:\SOFTWARE\Microsoft\GuestAgent).Incarnation
2.7.1198.735
```
or look in **C:\WindowsAzure\Logs\WaAppAgent.log** for the version logged at agent start-up

### Linux Agent
The easiest way to determine the current version of the Azure Linux agent when you are logged into the Linux guest is through the command: 
```
$ waagent -version
WALinuxAgent-2.1.3 running on ubuntu 15.10
Python: 3.4.3
```


##Retrieving Agent version remotely
To facilitate getting this information without connecting to the guest one can use either PowerShell or Azure Cli as shown below.  Note: the commands below assume that you have already logged in to PowerShell or Azure Cli, as well as configured the desired Azure Cli configuration mode.  The are designed as "Running script on a local computer" as described in [calling scripts](../documentation/callingscripts.md).

**Using Azure PowerShell to view guest agent version on classic VMs:**
```
> (Get-AzureVM -ServiceName ClassicWinVM -Name ClassicWinVM).GuestAgentStatus.GuestAgentVersion
2.7.1198.735
```
```
> (Get-AzureVM -ServiceName ClassicLinuxVM -Name ClassicLinuxVM).GuestAgentStatus.GuestAgentVersion
WALinuxAgent-2.0.14
```
**Using Azure PowerShell to view guest agent version on resource manager VMs:**
```
> (Get-AzureRmVM -ResourceGroupName ResourceGroup1 -Name WindowsVM -Status).VMAgent.VmAgentVersion
2.7.1198.735
```

```
> (Get-AzureRmVM -ResourceGroupName ResourceGroup2 -Name LinuxVM -Status).VMAgent.VmAgentVersion
WALinuxAgent-2.0.14
```
**Using Azure XPlat CLI to view guest agent version on classic VMs:**
```
$ azure vm show -d ClassicWinVM.cloudapp.net ClassicWinVM1 -vv

...
<GuestAgentVersion>2.7.1198.735</GuestAgentVersion>
...
```

```
$ azure vm show -d ClassicLinuxVM.cloudapp.net ClassicLinuxVM -vv

...
<GuestAgentVersion>2.1.3</GuestAgentVersion>
...
```

**Using Azure XPlat CLI to view guest agent version on resource manager VMs:**

```
$ azure vm get-instance-view -g ResourceGroup1 -n WindowsVM

...
data:    instanceView vmAgent vmAgentVersion "2.7.1198.766"
...
```

```
$ azure vm get-instance-view -g ResourceGroup2 -n LinuxVM

...
data:    instanceView vmAgent vmAgentVersion "WALinuxAgent-2.0.16"
...
```
