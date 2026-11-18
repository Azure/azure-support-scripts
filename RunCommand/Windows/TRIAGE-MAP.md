# Windows VM Diagnostic Scripts — Find the Right Script for Your Problem

You have a problem with your Azure Windows VM. This page helps you find the right diagnostic script fast — no need to browse through dozens of folders.

**Pick the problem you're seeing**, run the scripts in order, and check the output. Each script tells you what's wrong and links to a fix.

## I can't connect to my VM with Remote Desktop (RDP)

| Run | Script | What it checks |
|---|---|---|
| 1 | [RDP_Health_Snapshot](Windows_RDP_Health_Snapshot/) | Remote Desktop service running, port 3389 open, firewall allows RDP |
| 2 | [TLS_Cipher_RDP_Compatibility_Audit](Windows_TLS_Cipher_RDP_Compatibility_Audit/) | TLS settings compatible with your RDP client |
| 3 | [RDP_Certificate_Binding_Check](Windows_RDP_Certificate_Binding_Check/) | RDP certificate present and not expired |
| 4 | [Firewall_Profile_Baseline_Check](Windows_Firewall_Profile_Baseline_Check/) | Windows Firewall isn't blocking Remote Desktop |
| 5 | [Network_IMDS_Reachability](Windows_Network_IMDS_Reachability/) | VM can communicate with Azure (network adapter, default route, Azure endpoints) |

**If your VM is domain-joined and you can't sign in:** also run [Domain_Trust_SecureChannel_Check](Windows_Domain_Trust_SecureChannel_Check/) → [TimeSync_Kerberos_Health](Windows_TimeSync_Kerberos_Health/) → [UserProfileService_Health](Windows_UserProfileService_Health/).

## My VM won't start or is stuck during boot

| Run | Script | What it checks |
|---|---|---|
| 1 | [Service_Boot_Audit](Windows_Service_Boot_Audit/) | Boot mode (Safe Mode, recovery), event log accessibility |
| 2 | [Service_Dependency_Break_Check](Windows_Service_Dependency_Break_Check/) | Core Windows services that must start (RPC, DCOM, Service Control Manager) |
| 3 | [GroupPolicy_Processing_Health](Windows_GroupPolicy_Processing_Health/) | Group Policy processing — common cause of startup hangs |
| 4 | [ServiceStartupTimeout_Check](Windows_ServiceStartupTimeout_Check/) | Services taking too long to start |
| 5 | [BootPolicy_Drift_Check](Windows_BootPolicy_Drift_Check/) | Boot configuration (BCD) entries haven't been altered |

**Stuck at "Applying Group Policy"?** Start at step 3.
**Blue screen or unexpected restart?** Jump to [My VM crashed (blue screen) or keeps restarting](#my-vm-crashed-blue-screen-or-keeps-restarting).

## Windows services are failing or won't start

| Run | Script | What it checks |
|---|---|---|
| 1 | [Service_Dependency_Break_Check](Windows_Service_Dependency_Break_Check/) | Core services (RPC, DCOM) that other services depend on |
| 2 | [RPC_EndpointMapper_Check](Windows_RPC_EndpointMapper_Check/) | RPC endpoint mapper on port 135 — many services need this |
| 3 | [ServiceStartupTimeout_Check](Windows_ServiceStartupTimeout_Check/) | Services that are hung or timing out during startup |
| 4 | [TaskScheduler_Health](Windows_TaskScheduler_Health/) | Task Scheduler service and any failed scheduled tasks |
| 5 | [EventLog_Channel_Health](Windows_EventLog_Channel_Health/) | Event Log service working — needed to diagnose service failures |

## Azure VM Agent shows "Not Ready" in the portal

The VM Agent coordinates all extensions. If it's not working, no extensions will work.

| Run | Script | What it checks |
|---|---|---|
| 1 | [VM_Agent_Health_Dump](Windows_VM_Agent_Health_Dump/) | VM Agent and RdAgent services running, heartbeat recent, error log |
| 2 | [Network_IMDS_Reachability](Windows_Network_IMDS_Reachability/) | VM can reach Azure endpoints (168.63.129.16 and 169.254.169.254) |
| 3 | [Service_Dependency_Break_Check](Windows_Service_Dependency_Break_Check/) | Core Windows services the agent depends on |
| 4 | [Firewall_Profile_Baseline_Check](Windows_Firewall_Profile_Baseline_Check/) | Firewall not blocking Azure endpoints |
| 5 | [RouteTable_Anomaly_Check](Windows_RouteTable_Anomaly_Check/) | Custom routes not overriding Azure communication paths |

## An extension is failing — start here (applies to all extensions)

Before troubleshooting a specific extension, confirm the extension platform itself is healthy. Run these first regardless of which extension is failing.

| Run | Script | What it checks |
|---|---|---|
| 1 | [VM_Agent_Health_Dump](Windows_VM_Agent_Health_Dump/) | VM Agent working, shows status of every installed extension |
| 2 | [Extension_Install_Chain_Health](Windows_Extension_Install_Chain_Health/) | Extension installation pipeline: registry entries, plugin folder, Azure endpoint reachable, agent log errors |
| 3 | [Network_IMDS_Reachability](Windows_Network_IMDS_Reachability/) | VM can reach Azure — extensions need this to download and report status |
| 4 | [Disk_Filesystem_Audit](Windows_Disk_Filesystem_Audit/) | Enough disk space on C: — extensions can't install if the disk is full |
| 5 | [Proxy_WinHTTP_WinINET_Check](Windows_Proxy_WinHTTP_WinINET_Check/) | Proxy not blocking extension downloads |
| 6 | [SChannel_CertStore_Health](Windows_SChannel_CertStore_Health/) | No expired certificates blocking secure connections |

If everything above passes, find your specific extension below.

---

### Custom Script Extension won't run or is stuck "Transitioning"

Extension name: `Microsoft.Compute.CustomScriptExtension`

| Run | Script | What it checks |
|---|---|---|
| 1–6 | **[Run the shared baseline above](#an-extension-is-failing--start-here-applies-to-all-extensions)** | Covers the most common blockers: disk full, proxy, certificates |
| 7 | [Firewall_Profile_Baseline_Check](Windows_Firewall_Profile_Baseline_Check/) | Outbound connections to your storage account (port 443) not blocked |
| 8 | [DNS_NameResolution_Health](Windows_DNS_NameResolution_Health/) | DNS can resolve your storage account URL |
| 9 | [EventLog_Channel_Health](Windows_EventLog_Channel_Health/) | Application event log for errors |

**Where to find logs:** `C:\Packages\Plugins\Microsoft.Compute.CustomScriptExtension\<version>\Status\` for status, `...\Downloads\` for downloaded script files. Check the output file to see if it's a script error vs. a platform error.

---

### Azure Disk Encryption (ADE) failed to enable or decrypt

Extension name: `Microsoft.Azure.Security.AzureDiskEncryption`

| Run | Script | What it checks |
|---|---|---|
| 1–6 | **[Run the shared baseline above](#an-extension-is-failing--start-here-applies-to-all-extensions)** | Extension platform healthy |
| 7 | [Encryption_State_Check](Windows_Encryption_State_Check/) | Current BitLocker state, ADE settings, which drives are encrypted |
| 8 | [BitLocker_KeyProtector_Audit](Windows_BitLocker_KeyProtector_Audit/) | Encryption key protectors, TPM status, recovery key available |
| 9 | [Disk_Filesystem_Audit](Windows_Disk_Filesystem_Audit/) | Dirty volumes — encryption can't start on a volume with pending repairs |
| 10 | [GroupPolicy_Processing_Health](Windows_GroupPolicy_Processing_Health/) | Group Policy may enforce conflicting BitLocker settings |

**Where to find logs:** `C:\Packages\Plugins\Microsoft.Azure.Security.AzureDiskEncryption\<version>\Status\`. If the extension shows "Succeeded" but the disk isn't encrypted, it's a BitLocker configuration issue — start at step 7.

---

### Monitoring agent not reporting data (MMA, AMA, or Azure Diagnostics)

Extension names:
- `Microsoft.EnterpriseCloud.Monitoring.MicrosoftMonitoringAgent` (Log Analytics agent / MMA)
- `Microsoft.Azure.Monitor.AzureMonitorWindowsAgent` (Azure Monitor Agent / AMA)
- `Microsoft.Azure.Diagnostics.IaaSDiagnostics` (Windows Azure Diagnostics / WAD)

| Run | Script | What it checks |
|---|---|---|
| 1–6 | **[Run the shared baseline above](#an-extension-is-failing--start-here-applies-to-all-extensions)** | Extension platform healthy |
| 7 | [WinRM_Remoting_Health](Windows_WinRM_Remoting_Health/) | WinRM service — the Log Analytics agent uses this |
| 8 | [Firewall_Profile_Baseline_Check](Windows_Firewall_Profile_Baseline_Check/) | Outbound port 443 open to your Log Analytics workspace |
| 9 | [DNS_NameResolution_Health](Windows_DNS_NameResolution_Health/) | Can resolve `*.ods.opinsights.azure.com` (your workspace URL) |
| 10 | [EventLog_Channel_Health](Windows_EventLog_Channel_Health/) | Event log channels readable — this is where your data comes from |
| 11 | [EventForwarding_WEF_Health](Windows_EventForwarding_WEF_Health/) | Windows Event Forwarding not conflicting with Azure Monitor collection |
| 12 | [Resource_Pressure_Snapshot](Windows_Resource_Pressure_Snapshot/) | Monitoring agent using too much CPU or memory |

**Where to find logs:**
- MMA: `C:\Program Files\Microsoft Monitoring Agent\Agent\Health Service State\`
- AMA: `C:\WindowsAzure\Resources\AMAData\`
- WAD: `C:\Packages\Plugins\Microsoft.Azure.Diagnostics.IaaSDiagnostics\<version>\`

---

### Azure Update Manager / Patch extension not working

Extension name: `Microsoft.CPlat.Core.WindowsPatchExtension`

| Run | Script | What it checks |
|---|---|---|
| 1–6 | **[Run the shared baseline above](#an-extension-is-failing--start-here-applies-to-all-extensions)** | Extension platform healthy |
| 7 | [WU_PendingActions_Check](Windows_WU_PendingActions_Check/) | Pending reboot, stuck updates, Windows Update service health |
| 8 | [Disk_Filesystem_Audit](Windows_Disk_Filesystem_Audit/) | Disk space — updates need room to download and stage |
| 9 | [SFC_DISM_Health_Signal](Windows_SFC_DISM_Health_Signal/) | Windows component store health — corruption blocks patching |
| 10 | [Service_Dependency_Break_Check](Windows_Service_Dependency_Break_Check/) | Windows Update, Cryptographic Services, and BITS running |
| 11 | [Proxy_WinHTTP_WinINET_Check](Windows_Proxy_WinHTTP_WinINET_Check/) | Proxy not blocking Microsoft update download endpoints |

**Where to find logs:** `C:\Packages\Plugins\Microsoft.CPlat.Core.WindowsPatchExtension\<version>\Status\`. Common: the extension reports "Succeeded" but patches didn't install — that's a Windows Update issue, start at step 7.

---

### DSC (Desired State Configuration) extension failing

Extension name: `Microsoft.Powershell.DSC`

| Run | Script | What it checks |
|---|---|---|
| 1–6 | **[Run the shared baseline above](#an-extension-is-failing--start-here-applies-to-all-extensions)** | Extension platform healthy |
| 7 | [WinRM_Remoting_Health](Windows_WinRM_Remoting_Health/) | DSC uses WinRM to apply configurations |
| 8 | [GroupPolicy_Processing_Health](Windows_GroupPolicy_Processing_Health/) | Group Policy can conflict with DSC configurations |
| 9 | [Service_Dependency_Break_Check](Windows_Service_Dependency_Break_Check/) | WMI and WinRM services running |
| 10 | [EventLog_Channel_Health](Windows_EventLog_Channel_Health/) | DSC event log: `Microsoft-Windows-DSC/Operational` |

**Where to find logs:** `C:\Packages\Plugins\Microsoft.Powershell.DSC\<version>\Status\` and Windows event log under `Microsoft-Windows-DSC/Operational`. To check current DSC state, run `Get-DscLocalConfigurationManager` in PowerShell.

---

### BGInfo extension not updating the desktop

Extension name: `Microsoft.Compute.BGInfo`

| Run | Script | What it checks |
|---|---|---|
| 1–6 | **[Run the shared baseline above](#an-extension-is-failing--start-here-applies-to-all-extensions)** | Extension platform healthy |
| 7 | [UserProfileService_Health](Windows_UserProfileService_Health/) | BGInfo writes to the desktop — profile issues block it |

BGInfo rarely fails on its own. If it's the only extension failing, it's usually a disk space issue (step 4 in the baseline) or stale extension state. Try removing and re-adding the extension from the Azure portal.

---

### VM Access extension (password reset or RDP re-enable) not working

Extension name: `Microsoft.Compute.VMAccessAgent`

| Run | Script | What it checks |
|---|---|---|
| 1–6 | **[Run the shared baseline above](#an-extension-is-failing--start-here-applies-to-all-extensions)** | Extension platform healthy |
| 7 | [RDP_Health_Snapshot](Windows_RDP_Health_Snapshot/) | If you used VM Access to fix RDP — check if RDP is working now |
| 8 | [Firewall_Profile_Baseline_Check](Windows_Firewall_Profile_Baseline_Check/) | VM Access re-enables the RDP firewall rule — verify it took effect |
| 9 | [UserProfileService_Health](Windows_UserProfileService_Health/) | Password reset succeeded but you still can't sign in — may be a profile issue |

---

### Dependency Agent (VM Insights) not reporting

Extension name: `Microsoft.Azure.Monitoring.DependencyAgent`

| Run | Script | What it checks |
|---|---|---|
| 1–6 | **[Run the shared baseline above](#an-extension-is-failing--start-here-applies-to-all-extensions)** | Extension platform healthy |
| 7 | [Resource_Pressure_Snapshot](Windows_Resource_Pressure_Snapshot/) | Dependency Agent can use significant CPU |
| 8 | [Firewall_Profile_Baseline_Check](Windows_Firewall_Profile_Baseline_Check/) | Outbound to Log Analytics workspace |
| 9 | [Service_Dependency_Break_Check](Windows_Service_Dependency_Break_Check/) | MicrosoftDependencyAgent service running |

---

### My extension isn't listed above

For any other extension (Qualys, Symantec, Chef, Puppet, third-party marketplace extensions):

| Run | Script | What it checks |
|---|---|---|
| 1–6 | **[Run the shared baseline above](#an-extension-is-failing--start-here-applies-to-all-extensions)** | All extensions use the same installation pipeline |
| 7 | [Firewall_Profile_Baseline_Check](Windows_Firewall_Profile_Baseline_Check/) | Extension may need outbound access to vendor servers |
| 8 | [DNS_NameResolution_Health](Windows_DNS_NameResolution_Health/) | Can resolve the vendor's server address |
| 9 | [EventLog_Channel_Health](Windows_EventLog_Channel_Health/) | Application event log for errors |
| 10 | [GroupPolicy_Processing_Health](Windows_GroupPolicy_Processing_Health/) | Group Policy may restrict extension behavior |
| 11 | [DriverSignature_Integrity_Check](Windows_DriverSignature_Integrity_Check/) | Code signing enforcement — can block unsigned extension binaries |

**Where to find extension logs (any extension):** `C:\Packages\Plugins\<Publisher.ExtensionType>\<version>\Status\` for status JSON, and the same folder for extension-specific logs.

## Run Command itself isn't working

If you can't use Run Command to execute these diagnostic scripts.

| Run | Script | What it checks |
|---|---|---|
| 1 | [WinRM_Remoting_Health](Windows_WinRM_Remoting_Health/) | WinRM service running, listeners configured, certificates |
| 2 | [Firewall_Profile_Baseline_Check](Windows_Firewall_Profile_Baseline_Check/) | Ports 5985/5986 (WinRM) not blocked |
| 3 | [SChannel_CertStore_Health](Windows_SChannel_CertStore_Health/) | HTTPS certificate valid |
| 4 | [Network_IMDS_Reachability](Windows_Network_IMDS_Reachability/) | VM can communicate with Azure for Run Command delivery |

## Network or DNS issues (not RDP-specific)

| Run | Script | What it checks |
|---|---|---|
| 1 | [Network_IMDS_Reachability](Windows_Network_IMDS_Reachability/) | Network adapter present, default route exists, Azure endpoints reachable |
| 2 | [DNS_NameResolution_Health](Windows_DNS_NameResolution_Health/) | DNS servers configured, name resolution working |
| 3 | [Firewall_Profile_Baseline_Check](Windows_Firewall_Profile_Baseline_Check/) | Windows Firewall profiles and rules |
| 4 | [Proxy_WinHTTP_WinINET_Check](Windows_Proxy_WinHTTP_WinINET_Check/) | Proxy configuration and bypass settings |
| 5 | [RouteTable_Anomaly_Check](Windows_RouteTable_Anomaly_Check/) | Route table for unexpected or missing routes |
| 6 | [NetworkBinding_Order_Check](Windows_NetworkBinding_Order_Check/) | Network adapter binding order |
| 7 | [NIC_AdvancedProperties_Baseline](Windows_NIC_AdvancedProperties_Baseline/) | Network adapter advanced settings |
| 8 | [IPv6_RDP_Path_Check](Windows_IPv6_RDP_Path_Check/) | IPv6 configuration and dual-stack behavior |
| 9 | [SMB_Client_Health](Windows_SMB_Client_Health/) | SMB/file sharing configuration |

## Slow VM or high CPU/memory usage

| Run | Script | What it checks |
|---|---|---|
| 1 | [Resource_Pressure_Snapshot](Windows_Resource_Pressure_Snapshot/) | Current CPU, memory, and commit charge |
| 2 | [PowerPlan_Throttling_Check](Windows_PowerPlan_Throttling_Check/) | Power plan — "Balanced" can throttle performance on VMs |
| 3 | [Startup_Delay_Analyzer](Windows_Startup_Delay_Analyzer/) | Slow boot contributors |
| 4 | [Disk_Filesystem_Audit](Windows_Disk_Filesystem_Audit/) | Disk space, temp drive, pagefile |
| 5 | [Port_Ephemeral_Exhaustion_Check](Windows_Port_Ephemeral_Exhaustion_Check/) | Running out of network ports (common under heavy load) |

## My VM crashed (blue screen) or keeps restarting

| Run | Script | What it checks |
|---|---|---|
| 1 | [CrashDump_Config_Validator](Windows_CrashDump_Config_Validator/) | Crash dump configured correctly to capture the next crash |
| 2 | [CrashHistory_Bugcheck_Summary](Windows_CrashHistory_Bugcheck_Summary/) | Existing crash dumps — bugcheck codes and frequency |
| 3 | [ReliabilityMonitor_Event_Signal](Windows_ReliabilityMonitor_Event_Signal/) | Reliability history — application and system failures |
| 4 | [Service_Boot_Audit](Windows_Service_Boot_Audit/) | Boot mode and recovery state |
| 5 | [BootPolicy_Drift_Check](Windows_BootPolicy_Drift_Check/) | Boot configuration hasn't been altered |

## Disk or storage problems

| Run | Script | What it checks |
|---|---|---|
| 1 | [Disk_Filesystem_Audit](Windows_Disk_Filesystem_Audit/) | Disk space, pagefile, temp drive (D:), dirty volumes |
| 2 | [NTFS_Integrity_Check](Windows_NTFS_Integrity_Check/) | Volume health, dirty bit, disk errors |
| 3 | [StorageSpaces_Health](Windows_StorageSpaces_Health/) | Storage Spaces/S2D pool and virtual disk health |
| 4 | [DriverStore_Health](Windows_DriverStore_Health/) | Driver store size and integrity |
| 5 | [VSS_Writer_Health](Windows_VSS_Writer_Health/) | Volume Shadow Copy writers — needed for backups and snapshots |

## Can't sign in with domain account or trust relationship broken

| Run | Script | What it checks |
|---|---|---|
| 1 | [Domain_Trust_SecureChannel_Check](Windows_Domain_Trust_SecureChannel_Check/) | Domain membership, secure channel to domain controller |
| 2 | [TimeSync_Kerberos_Health](Windows_TimeSync_Kerberos_Health/) | Clock sync — Kerberos authentication fails if time is off by more than 5 minutes |
| 3 | [DomainJoin_Readiness](Windows_DomainJoin_Readiness/) | DNS and domain controller reachability |
| 4 | [GroupPolicy_Processing_Health](Windows_GroupPolicy_Processing_Health/) | Group Policy can apply — NETLOGON/SYSVOL accessible |
| 5 | [UserProfileService_Health](Windows_UserProfileService_Health/) | User profile loading correctly |

## BitLocker, encryption, or security configuration

| Run | Script | What it checks |
|---|---|---|
| 1 | [Encryption_State_Check](Windows_Encryption_State_Check/) | BitLocker state, Azure Disk Encryption settings |
| 2 | [BitLocker_KeyProtector_Audit](Windows_BitLocker_KeyProtector_Audit/) | Encryption key protectors, TPM, recovery key |
| 3 | [SChannel_CertStore_Health](Windows_SChannel_CertStore_Health/) | Certificate store, TLS configuration, expired certs |
| 4 | [LSA_SSP_Baseline_Check](Windows_LSA_SSP_Baseline_Check/) | Local Security Authority and authentication providers |
| 5 | [Defender_Health_Snapshot](Windows_Defender_Health_Snapshot/) | Windows Defender status, definition updates, real-time protection |
| 6 | [DriverSignature_Integrity_Check](Windows_DriverSignature_Integrity_Check/) | Driver signing enforcement |

## Windows Update problems

| Run | Script | What it checks |
|---|---|---|
| 1 | [WU_PendingActions_Check](Windows_WU_PendingActions_Check/) | Pending reboot, stuck updates, Windows Update service |
| 2 | [SFC_DISM_Health_Signal](Windows_SFC_DISM_Health_Signal/) | Windows component store health — run this if updates keep failing |
| 3 | [Disk_Filesystem_Audit](Windows_Disk_Filesystem_Audit/) | Disk space — updates need free space to download and install |

## Backup or snapshot failures

| Run | Script | What it checks |
|---|---|---|
| 1 | [VSS_Writer_Health](Windows_VSS_Writer_Health/) | Volume Shadow Copy writers and service — needed for Azure Backup |
| 2 | [EventLog_Channel_Health](Windows_EventLog_Channel_Health/) | Event log service health |
| 3 | [CrashDump_Config_Validator](Windows_CrashDump_Config_Validator/) | Crash dump readiness for post-incident recovery |

## Event logs or monitoring not collecting data

| Run | Script | What it checks |
|---|---|---|
| 1 | [EventLog_Channel_Health](Windows_EventLog_Channel_Health/) | Event Log service, System/Application/Security channels |
| 2 | [EventForwarding_WEF_Health](Windows_EventForwarding_WEF_Health/) | Windows Event Forwarding configuration |
| 3 | [WinRM_Remoting_Health](Windows_WinRM_Remoting_Health/) | WinRM service — used by some monitoring solutions |

---

## I'm not sure what's wrong

Run these three first — they cover the most ground:

1. **[Network_IMDS_Reachability](Windows_Network_IMDS_Reachability/)** — Can the VM talk to Azure?
2. **[Service_Dependency_Break_Check](Windows_Service_Dependency_Break_Check/)** — Are core Windows services running?
3. **[EventLog_Channel_Health](Windows_EventLog_Channel_Health/)** — Can the VM collect diagnostic data?

Then look at the `-- Decision --` block in each script's output — it tells you the severity and what to do next.

---

## How to run these scripts

### From the Azure portal
1. Go to your VM in the [Azure portal](https://portal.azure.com)
2. Select **Operations → Run Command → RunPowerShellScript**
3. Paste the contents of the `.ps1` file from the script folder
4. Select **Run** and wait for the output

### From Azure CLI
```bash
az vm run-command invoke -g <resource-group> -n <vm-name> \
  --command-id RunPowerShellScript \
  --scripts @<FolderName>/<ScriptName>.ps1
```

## How to read the output

Every script gives you the same format:

```
=== Script Name ===
Check                                        Status
-------------------------------------------- ------
Some diagnostic check                        OK
Another check                                FAIL
...
-- Decision --
Likely cause severity                        FAIL   Hard configuration/service break
Next action                                  OK     Follow README interpretation ...
-- More Info --
Remediation references available             OK     See paired README Learn References

=== RESULT: X OK / Y FAIL / Z WARN ===
```

- **FAIL** = this is broken and needs to be fixed
- **WARN** = not broken yet, but should be investigated
- **OK** = healthy, no action needed

Open the script's **README.md** for a detailed explanation of every FAIL and WARN — including the likely cause, how to fix it, and links to Microsoft Learn documentation.
# Windows RunCommand Diagnostic Triage Map

Use this page when you have a **symptom** and need the fastest path to the right diagnostic script.

Don't browse 70 folders — start with the signal you have.

## Can't RDP into the VM

| Order | Script | What it checks |
|---|---|---|
| 1 | [RDP_Health_Snapshot](Windows_RDP_Health_Snapshot/) | RDP service, port 3389 listener, firewall rule, TermService, NLA |
| 2 | [TLS_Cipher_RDP_Compatibility_Audit](Windows_TLS_Cipher_RDP_Compatibility_Audit/) | TLS 1.2 server enabled, SecurityLayer, NLA setting, legacy TLS |
| 3 | [RDP_Certificate_Binding_Check](Windows_RDP_Certificate_Binding_Check/) | RDP cert thumbprint, cert present + not expired, NLA, port bind |
| 4 | [Firewall_Profile_Baseline_Check](Windows_Firewall_Profile_Baseline_Check/) | Profiles enabled, RDP rule, inbound default, BFE service |
| 5 | [Network_IMDS_Reachability](Windows_Network_IMDS_Reachability/) | NIC present, default route, WireServer, IMDS endpoint |

**If domain-joined and "can't sign in":** also run [Domain_Trust_SecureChannel_Check](Windows_Domain_Trust_SecureChannel_Check/) → [TimeSync_Kerberos_Health](Windows_TimeSync_Kerberos_Health/) → [UserProfileService_Health](Windows_UserProfileService_Health/).

## VM won't boot or is stuck at boot

| Order | Script | What it checks |
|---|---|---|
| 1 | [Service_Boot_Audit](Windows_Service_Boot_Audit/) | SafeBoot, boot recovery, event log access |
| 2 | [Service_Dependency_Break_Check](Windows_Service_Dependency_Break_Check/) | Auto-start failures, RpcSs, DcomLaunch, SCM errors |
| 3 | [GroupPolicy_Processing_Health](Windows_GroupPolicy_Processing_Health/) | GPSvc, operational log, GP errors, NETLOGON/SYSVOL |
| 4 | [ServiceStartupTimeout_Check](Windows_ServiceStartupTimeout_Check/) | Timeout thresholds, hung service detection |
| 5 | [BootPolicy_Drift_Check](Windows_BootPolicy_Drift_Check/) | BCD entries, boot configuration drift |

**If stuck at "Applying Group Policy":** start at step 3.
**If BSOD/unexpected restart:** jump to the [Crash & BSOD](#crash--bsod--unexpected-restart) section.

## Services failing or cascading failures

| Order | Script | What it checks |
|---|---|---|
| 1 | [Service_Dependency_Break_Check](Windows_Service_Dependency_Break_Check/) | RpcSs, DcomLaunch, auto-start failures, SCM error volume |
| 2 | [RPC_EndpointMapper_Check](Windows_RPC_EndpointMapper_Check/) | RPC endpoint mapper, port 135, DCOM |
| 3 | [ServiceStartupTimeout_Check](Windows_ServiceStartupTimeout_Check/) | Timeout thresholds, hung services |
| 4 | [TaskScheduler_Health](Windows_TaskScheduler_Health/) | Scheduler service, failed tasks, event errors |
| 5 | [EventLog_Channel_Health](Windows_EventLog_Channel_Health/) | EventLog service, System/Application/Security log readable |

## VM agent not reporting or offline

The agent itself is the problem — extensions can't run at all.

| Order | Script | What it checks |
|---|---|---|
| 1 | [VM_Agent_Health_Dump](Windows_VM_Agent_Health_Dump/) | GuestAgent + RdAgent services, heartbeat freshness, log errors |
| 2 | [Network_IMDS_Reachability](Windows_Network_IMDS_Reachability/) | WireServer 168.63.129.16, IMDS 169.254.169.254, default route |
| 3 | [Service_Dependency_Break_Check](Windows_Service_Dependency_Break_Check/) | RpcSs, DcomLaunch — agent depends on these |
| 4 | [Firewall_Profile_Baseline_Check](Windows_Firewall_Profile_Baseline_Check/) | Firewall blocking 168.63.129.16 or 169.254.169.254 |
| 5 | [RouteTable_Anomaly_Check](Windows_RouteTable_Anomaly_Check/) | UDR overriding fabric routes |

## Extension issues — shared baseline (run first for ANY extension)

Before diving into per-extension scripts, confirm the install pipeline is healthy.

| Order | Script | What it checks |
|---|---|---|
| 1 | [VM_Agent_Health_Dump](Windows_VM_Agent_Health_Dump/) | Confirm agent IS healthy — per-handler status (Ready/NotReady/Unresponsive) |
| 2 | [Extension_Install_Chain_Health](Windows_Extension_Install_Chain_Health/) | Handler registry, C:\Packages\Plugins accessible, WireServer, agent log errors |
| 3 | [Network_IMDS_Reachability](Windows_Network_IMDS_Reachability/) | WireServer + IMDS reachable — extensions need both |
| 4 | [Disk_Filesystem_Audit](Windows_Disk_Filesystem_Audit/) | C: drive space — extensions can't stage if disk is full |
| 5 | [Proxy_WinHTTP_WinINET_Check](Windows_Proxy_WinHTTP_WinINET_Check/) | Proxy blocking extension package download (storage blob URLs) |
| 6 | [SChannel_CertStore_Health](Windows_SChannel_CertStore_Health/) | Expired certs — blocks TLS to blob storage for package download |

If baseline is clean, jump to the specific extension section below.

---

### CustomScriptExtension (CSE) — stuck Transitioning, timeout, script errors

`Microsoft.Compute.CustomScriptExtension` / `Microsoft.Azure.Extensions.CustomScript`

| Order | Script | Why |
|---|---|---|
| 1–6 | **Run shared baseline above** | CSE downloads from storage — disk, proxy, certs are top blockers |
| 7 | [Firewall_Profile_Baseline_Check](Windows_Firewall_Profile_Baseline_Check/) | Outbound to storage account blocked (443) |
| 8 | [DNS_NameResolution_Health](Windows_DNS_NameResolution_Health/) | Storage FQDN resolution failing |
| 9 | [EventLog_Channel_Health](Windows_EventLog_Channel_Health/) | Application log for CSE handler errors |

**Tip:** CSE logs live at `C:\Packages\Plugins\Microsoft.Compute.CustomScriptExtension\<version>\Status\` and `...\Downloads\`. Check output file for script-level errors vs. infrastructure errors.

---

### Azure Disk Encryption (ADE) — encryption/decryption failed

`Microsoft.Azure.Security.AzureDiskEncryption` / `AzureDiskEncryptionForLinux`

| Order | Script | Why |
|---|---|---|
| 1–6 | **Run shared baseline above** | ADE needs agent + WireServer + certs |
| 7 | [Encryption_State_Check](Windows_Encryption_State_Check/) | BitLocker volumes, ADE settings, OS drive encryption state |
| 8 | [BitLocker_KeyProtector_Audit](Windows_BitLocker_KeyProtector_Audit/) | Key protectors, TPM, recovery key availability |
| 9 | [Disk_Filesystem_Audit](Windows_Disk_Filesystem_Audit/) | Pagefile, dirty volumes — ADE can't encrypt dirty FS |
| 10 | [GroupPolicy_Processing_Health](Windows_GroupPolicy_Processing_Health/) | GPO enforcing conflicting BitLocker policies |

**Tip:** ADE logs at `C:\Packages\Plugins\Microsoft.Azure.Security.AzureDiskEncryption\<version>\Status\`. If extension shows "Succeeded" but disk isn't encrypted, the issue is BitLocker config — start at step 7.

---

### Monitoring extensions (MMA / AMA / Diagnostics)

`Microsoft.EnterpriseCloud.Monitoring.MicrosoftMonitoringAgent` (MMA)
`Microsoft.Azure.Monitor.AzureMonitorWindowsAgent` (AMA)
`Microsoft.Azure.Diagnostics.IaaSDiagnostics` (WAD)

| Order | Script | Why |
|---|---|---|
| 1–6 | **Run shared baseline above** | All monitoring agents need fabric + cert connectivity |
| 7 | [WinRM_Remoting_Health](Windows_WinRM_Remoting_Health/) | MMA uses WinRM for some operations |
| 8 | [Firewall_Profile_Baseline_Check](Windows_Firewall_Profile_Baseline_Check/) | Outbound 443 to Log Analytics workspace / DCR endpoint |
| 9 | [DNS_NameResolution_Health](Windows_DNS_NameResolution_Health/) | Workspace FQDN resolution (*.ods.opinsights.azure.com) |
| 10 | [EventLog_Channel_Health](Windows_EventLog_Channel_Health/) | Event channels readable — data source for all monitoring agents |
| 11 | [EventForwarding_WEF_Health](Windows_EventForwarding_WEF_Health/) | WEF conflicts with AMA collection |
| 12 | [Resource_Pressure_Snapshot](Windows_Resource_Pressure_Snapshot/) | Monitoring agent consuming excessive CPU/memory |

**Tip:** MMA logs at `C:\Program Files\Microsoft Monitoring Agent\Agent\Health Service State\`. AMA logs at `C:\WindowsAzure\Resources\AMAData\`. WAD logs at `C:\Packages\Plugins\Microsoft.Azure.Diagnostics.IaaSDiagnostics\<version>\`.

---

### Windows Patch Extension (Azure Update Manager)

`Microsoft.CPlat.Core.WindowsPatchExtension`

| Order | Script | Why |
|---|---|---|
| 1–6 | **Run shared baseline above** | Patch extension needs full install chain |
| 7 | [WU_PendingActions_Check](Windows_WU_PendingActions_Check/) | Reboot required, pending renames, CBS corruption, install failures |
| 8 | [Disk_Filesystem_Audit](Windows_Disk_Filesystem_Audit/) | Disk space for update staging + download |
| 9 | [SFC_DISM_Health_Signal](Windows_SFC_DISM_Health_Signal/) | Component store health — corrupted store blocks patching |
| 10 | [Service_Dependency_Break_Check](Windows_Service_Dependency_Break_Check/) | wuauserv, cryptsvc, BITS dependencies running |
| 11 | [Proxy_WinHTTP_WinINET_Check](Windows_Proxy_WinHTTP_WinINET_Check/) | WU update download needs outbound 443 to Microsoft update endpoints |

**Tip:** Patch extension logs at `C:\Packages\Plugins\Microsoft.CPlat.Core.WindowsPatchExtension\<version>\Status\`. Common: extension "Succeeded" but patches failed — that's WU layer, start at step 7.

---

### DSC Extension (Desired State Configuration)

`Microsoft.Powershell.DSC`

| Order | Script | Why |
|---|---|---|
| 1–6 | **Run shared baseline above** | DSC handler follows normal install chain |
| 7 | [WinRM_Remoting_Health](Windows_WinRM_Remoting_Health/) | DSC uses WinRM/CIM for configuration application |
| 8 | [GroupPolicy_Processing_Health](Windows_GroupPolicy_Processing_Health/) | GPO can conflict with DSC-applied configurations |
| 9 | [Service_Dependency_Break_Check](Windows_Service_Dependency_Break_Check/) | WMI, WinRM dependencies for LCM |
| 10 | [EventLog_Channel_Health](Windows_EventLog_Channel_Health/) | DSC operational log: `Microsoft-Windows-DSC/Operational` |

**Tip:** DSC logs at `C:\Packages\Plugins\Microsoft.Powershell.DSC\<version>\Status\` and Windows event log `Microsoft-Windows-DSC/Operational`. LCM state: `Get-DscLocalConfigurationManager`.

---

### BGInfo Extension

`Microsoft.Compute.BGInfo`

| Order | Script | Why |
|---|---|---|
| 1–6 | **Run shared baseline above** | Lightweight — usually only fails on install chain issues |
| 7 | [UserProfileService_Health](Windows_UserProfileService_Health/) | BGInfo writes to desktop — profile issues block it |

**Tip:** BGInfo rarely fails on its own. If it's the only failing extension, it's typically disk full (step 4) or stale handler state — remove and re-add.

---

### VM Access Extension (password reset / RDP re-enable)

`Microsoft.Compute.VMAccessAgent`

| Order | Script | Why |
|---|---|---|
| 1–6 | **Run shared baseline above** | VMAccess follows normal handler pipeline |
| 7 | [RDP_Health_Snapshot](Windows_RDP_Health_Snapshot/) | If VMAccess was invoked to fix RDP — check if RDP is now working |
| 8 | [Firewall_Profile_Baseline_Check](Windows_Firewall_Profile_Baseline_Check/) | VMAccess re-enables RDP rule — verify firewall accepted it |
| 9 | [UserProfileService_Health](Windows_UserProfileService_Health/) | Password reset succeeded but login fails — profile issue |

---

### Dependency Agent (Azure Monitor VM Insights)

`Microsoft.Azure.Monitoring.DependencyAgent`

| Order | Script | Why |
|---|---|---|
| 1–6 | **Run shared baseline above** | Standard install chain |
| 7 | [Resource_Pressure_Snapshot](Windows_Resource_Pressure_Snapshot/) | Dependency Agent captures connection data — can cause CPU pressure |
| 8 | [Firewall_Profile_Baseline_Check](Windows_Firewall_Profile_Baseline_Check/) | Outbound to Log Analytics |
| 9 | [Service_Dependency_Break_Check](Windows_Service_Dependency_Break_Check/) | MicrosoftDependencyAgent service running |

---

### Extension you don't see listed above

For any other extension (Qualys, Symantec, Chef, Puppet, custom marketplace extensions):

| Order | Script | Why |
|---|---|---|
| 1–6 | **Run shared baseline above** | All extensions use the same install pipeline |
| 7 | [Firewall_Profile_Baseline_Check](Windows_Firewall_Profile_Baseline_Check/) | Extension may need outbound to vendor endpoints |
| 8 | [DNS_NameResolution_Health](Windows_DNS_NameResolution_Health/) | Vendor FQDN resolution |
| 9 | [EventLog_Channel_Health](Windows_EventLog_Channel_Health/) | Application log for handler errors |
| 10 | [GroupPolicy_Processing_Health](Windows_GroupPolicy_Processing_Health/) | GPO may block extension behavior |
| 11 | [DriverSignature_Integrity_Check](Windows_DriverSignature_Integrity_Check/) | Code signing enforcement — can block unsigned extension binaries |

**Tip:** All extension logs follow the same pattern: `C:\Packages\Plugins\<Publisher.Type>\<version>\Status\` for status JSON, `...\<version>\` for handler-specific logs.

## WinRM and Run Command connectivity

Run Command itself not working, or DSC/remoting extensions failing.

| Order | Script | What it checks |
|---|---|---|
| 1 | [WinRM_Remoting_Health](Windows_WinRM_Remoting_Health/) | WinRM service, HTTP/HTTPS listeners, certs, firewall rules |
| 2 | [Firewall_Profile_Baseline_Check](Windows_Firewall_Profile_Baseline_Check/) | WinRM ports (5985/5986) allowed |
| 3 | [SChannel_CertStore_Health](Windows_SChannel_CertStore_Health/) | HTTPS listener cert valid |
| 4 | [Network_IMDS_Reachability](Windows_Network_IMDS_Reachability/) | Fabric connectivity for Run Command delivery |

## Network connectivity issues (not RDP-specific)

| Order | Script | What it checks |
|---|---|---|
| 1 | [Network_IMDS_Reachability](Windows_Network_IMDS_Reachability/) | NIC present, default route, WireServer, IMDS |
| 2 | [DNS_NameResolution_Health](Windows_DNS_NameResolution_Health/) | DNS servers, public resolution, metadata alias, hosts overrides |
| 3 | [Firewall_Profile_Baseline_Check](Windows_Firewall_Profile_Baseline_Check/) | Profiles, RDP rule, inbound default, BFE |
| 4 | [Proxy_WinHTTP_WinINET_Check](Windows_Proxy_WinHTTP_WinINET_Check/) | WinHTTP/WinINET proxy, bypass list, fabric endpoint bypass |
| 5 | [RouteTable_Anomaly_Check](Windows_RouteTable_Anomaly_Check/) | Route table, unexpected routes, missing defaults |
| 6 | [NetworkBinding_Order_Check](Windows_NetworkBinding_Order_Check/) | NIC binding order, primary adapter |
| 7 | [NIC_AdvancedProperties_Baseline](Windows_NIC_AdvancedProperties_Baseline/) | NIC advanced settings, RSS, offload |
| 8 | [IPv6_RDP_Path_Check](Windows_IPv6_RDP_Path_Check/) | IPv6 path, dual-stack, DNS over IPv6 |
| 9 | [SMB_Client_Health](Windows_SMB_Client_Health/) | SMB client config, signing, dialects |

## Performance (slow VM, high CPU, memory pressure)

| Order | Script | What it checks |
|---|---|---|
| 1 | [Resource_Pressure_Snapshot](Windows_Resource_Pressure_Snapshot/) | CPU utilization, physical memory, commit charge |
| 2 | [PowerPlan_Throttling_Check](Windows_PowerPlan_Throttling_Check/) | Power plan, processor throttling, min/max states |
| 3 | [Startup_Delay_Analyzer](Windows_Startup_Delay_Analyzer/) | Boot time, startup delay contributors, slow services |
| 4 | [Disk_Filesystem_Audit](Windows_Disk_Filesystem_Audit/) | Pagefile, temp drive, dirty volumes |
| 5 | [Port_Ephemeral_Exhaustion_Check](Windows_Port_Ephemeral_Exhaustion_Check/) | Ephemeral port range, active connections, exhaustion risk |

## Crash / BSOD / unexpected restart

| Order | Script | What it checks |
|---|---|---|
| 1 | [CrashDump_Config_Validator](Windows_CrashDump_Config_Validator/) | Dump type, dump path, pagefile, AutoReboot, existing dumps |
| 2 | [CrashHistory_Bugcheck_Summary](Windows_CrashHistory_Bugcheck_Summary/) | MEMORY.DMP, minidumps, bugcheck codes, crash frequency |
| 3 | [ReliabilityMonitor_Event_Signal](Windows_ReliabilityMonitor_Event_Signal/) | Reliability events, application crashes, system failures |
| 4 | [Service_Boot_Audit](Windows_Service_Boot_Audit/) | SafeBoot, boot recovery, event log access |
| 5 | [BootPolicy_Drift_Check](Windows_BootPolicy_Drift_Check/) | BCD entries, boot config drift |

## Disk, storage, and filesystem issues

| Order | Script | What it checks |
|---|---|---|
| 1 | [Disk_Filesystem_Audit](Windows_Disk_Filesystem_Audit/) | Pagefile, temp drive D:, dirty volumes |
| 2 | [NTFS_Integrity_Check](Windows_NTFS_Integrity_Check/) | Fixed volumes, dirty bit, BootExecute, disk errors, C: exists |
| 3 | [StorageSpaces_Health](Windows_StorageSpaces_Health/) | Storage subsystem, pool/vdisk/pdisk health, S2D |
| 4 | [DriverStore_Health](Windows_DriverStore_Health/) | Driver store integrity, bloat, staged packages |
| 5 | [VSS_Writer_Health](Windows_VSS_Writer_Health/) | VSS writers, failed writers, VSS service, providers |

## Domain join and authentication failures

| Order | Script | What it checks |
|---|---|---|
| 1 | [Domain_Trust_SecureChannel_Check](Windows_Domain_Trust_SecureChannel_Check/) | Domain join, Netlogon, secure channel, DC discovery, DNS SRV |
| 2 | [TimeSync_Kerberos_Health](Windows_TimeSync_Kerberos_Health/) | Time source, clock offset, KDC reachability, Kerberos errors |
| 3 | [DomainJoin_Readiness](Windows_DomainJoin_Readiness/) | DNS, domain reachability, join prerequisites |
| 4 | [GroupPolicy_Processing_Health](Windows_GroupPolicy_Processing_Health/) | GPSvc, GP errors, NETLOGON/SYSVOL paths |
| 5 | [UserProfileService_Health](Windows_UserProfileService_Health/) | Profile service, registry, temp profiles, load errors |

## Encryption and security baseline

| Order | Script | What it checks |
|---|---|---|
| 1 | [Encryption_State_Check](Windows_Encryption_State_Check/) | BitLocker volumes, ADE extension, ADE settings, OS drive encrypted |
| 2 | [BitLocker_KeyProtector_Audit](Windows_BitLocker_KeyProtector_Audit/) | Key protectors, TPM, recovery key availability |
| 3 | [SChannel_CertStore_Health](Windows_SChannel_CertStore_Health/) | SChannel config, cert store, expired certs |
| 4 | [LSA_SSP_Baseline_Check](Windows_LSA_SSP_Baseline_Check/) | LSA security providers, SSP DLLs |
| 5 | [Defender_Health_Snapshot](Windows_Defender_Health_Snapshot/) | Defender service, definitions, real-time protection |
| 6 | [DriverSignature_Integrity_Check](Windows_DriverSignature_Integrity_Check/) | Driver signing enforcement, unsigned drivers |

## Windows Update issues

| Order | Script | What it checks |
|---|---|---|
| 1 | [WU_PendingActions_Check](Windows_WU_PendingActions_Check/) | Reboot required, pending renames, CBS, WU service, install failures |
| 2 | [SFC_DISM_Health_Signal](Windows_SFC_DISM_Health_Signal/) | Component store health, SFC/DISM repair readiness |
| 3 | [Disk_Filesystem_Audit](Windows_Disk_Filesystem_Audit/) | Disk space (updates need free space) |

## Backup and recovery

| Order | Script | What it checks |
|---|---|---|
| 1 | [VSS_Writer_Health](Windows_VSS_Writer_Health/) | VSS writers, failed writers, service state, providers |
| 2 | [EventLog_Channel_Health](Windows_EventLog_Channel_Health/) | Event log service and channel health |
| 3 | [CrashDump_Config_Validator](Windows_CrashDump_Config_Validator/) | Dump capture readiness for post-incident recovery |

## Monitoring and diagnostics platform health

| Order | Script | What it checks |
|---|---|---|
| 1 | [EventLog_Channel_Health](Windows_EventLog_Channel_Health/) | EventLog service, System/App/Security channels, error rate |
| 2 | [EventForwarding_WEF_Health](Windows_EventForwarding_WEF_Health/) | WEF collector, subscription state, forwarding errors |
| 3 | [WinRM_Remoting_Health](Windows_WinRM_Remoting_Health/) | WinRM service, listeners, remoting readiness |

---

## If your signal is unclear

Run these three in order — they cover the broadest triage surface:

1. **[Network_IMDS_Reachability](Windows_Network_IMDS_Reachability/)** — is the VM connected to Azure fabric?
2. **[Service_Dependency_Break_Check](Windows_Service_Dependency_Break_Check/)** — are core services running?
3. **[EventLog_Channel_Health](Windows_EventLog_Channel_Health/)** — can we collect diagnostic data?

Then check the `-- Decision --` block in each script's output — it tells you severity and next action.

## How to run any script

### Azure Portal
VM → Operations → Run Command → RunPowerShellScript → paste the `.ps1` content.

### Azure CLI
```bash
az vm run-command invoke -g <rg> -n <vm> --command-id RunPowerShellScript \
  --scripts @<FolderName>/<ScriptName>.ps1
```

### Mock test (offline, no VM needed)
```powershell
.\<ScriptName>.ps1 -MockConfig .\mock_config_sample.json -MockProfile broken
```

## Reading the output

Every Tier-2 script outputs the same format:

```
=== Script Name ===
Check                                        Status
-------------------------------------------- ------
Some diagnostic check                        OK
Another check                                FAIL
...
-- Decision --
Likely cause severity                        FAIL   Hard configuration/service break
Next action                                  OK     Follow README interpretation ...
-- More Info --
Remediation references available             OK     See paired README Learn References

=== RESULT: X OK / Y FAIL / Z WARN ===
```

- **FAIL** = blocking issue, fix before proceeding
- **WARN** = non-blocking but should investigate
- **OK** = healthy

Open the script's **README.md** for the **Interpretation Guide** — it maps every FAIL/WARN condition to likely cause, quick fix, and Microsoft Learn article.
