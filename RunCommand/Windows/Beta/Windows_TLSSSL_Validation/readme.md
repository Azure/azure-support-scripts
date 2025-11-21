
# Windows In-Place Upgrade Assessment Script

## Overview

This PowerShell script is designed to assess the readiness of a Windows machine (desktop or server) for an **in-place OS upgrade**, with special considerations for **Azure VMs**. It evaluates OS version, supported upgrade paths, system disk space, and Azure security features like **Trusted Launch**, **Secure Boot**, and **vTPM**.

---

## Key Features



---

## Requirements

- PowerShell 5.1 or later.
- Script must be run with administrative privileges.
- To retrieve Azure instance metadata, script must be executed on an **Azure VM** with **instance metadata service** access enabled.

---

## Usage

1. Open **PowerShell as Administrator**.
2. Run the script:

   ```powershell
   .\Windows_TLSSSL_Validation.ps1
   ```

3. Review the output for upgrade recommendations and any potential blockers.

---

## Output Examples

Example output on a Windows Server 2016 VM:

```
------------------------------------------------------------
This script scans TLS and SSL settings and configurations
summary at the end. If any errors are found, a remediation
link to Microsoft documentation is displayed.
Reference: https://aka.ms/xxxxxx
------------------------------------------------------------

=== TLS / Schannel Audit ===

-- Protocol configuration (Schannel) --

Protocol Role   Enabled DisabledByDefault EffectiveState            
-------- ----   ------- ----------------- --------------            
SSL 2.0  Client                           NotConfigured (OS default)
SSL 2.0  Server                           NotConfigured (OS default)
SSL 3.0  Client 0                         Disabled                  
SSL 3.0  Server 0                         Disabled                  
TLS 1.0  Client 0                         Disabled                  
TLS 1.0  Server 0                         Disabled                  
TLS 1.1  Client 0                         Disabled                  
TLS 1.1  Server 0                         Disabled                  
TLS 1.2  Client 1                         Enabled                   
TLS 1.2  Server 1                         Enabled                   
TLS 1.3  Client                           NotConfigured (OS default)
TLS 1.3  Server                           NotConfigured (OS default)



-- Cipher suites (effective order) --

Name                                    Protocols   
----                                    ---------   
TLS_AES_256_GCM_SHA384                  {772}       
TLS_AES_128_GCM_SHA256                  {772}       
TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384 {}          
TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256 {771, 65277}
TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384   {771, 65277}
TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256   {771, 65277}
TLS_ECDHE_ECDSA_WITH_AES_256_CBC_SHA384 {771, 65277}
TLS_ECDHE_ECDSA_WITH_AES_128_CBC_SHA256 {771, 65277}
TLS_ECDHE_RSA_WITH_AES_256_CBC_SHA384   {771, 65277}
TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA256   {771, 65277}



WARN: Weak cipher suites detected (review necessity):

Name                                    Protocols   
----                                    ---------   
TLS_AES_256_GCM_SHA384                  {772}       
TLS_AES_128_GCM_SHA256                  {772}       
TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384 {}          
TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256 {771, 65277}
TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384   {771, 65277}
TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256   {771, 65277}
TLS_ECDHE_ECDSA_WITH_AES_256_CBC_SHA384 {771, 65277}
TLS_ECDHE_ECDSA_WITH_AES_128_CBC_SHA256 {771, 65277}
TLS_ECDHE_RSA_WITH_AES_256_CBC_SHA384   {771, 65277}
TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA256   {771, 65277}



-- Cipher suite policy override --
Policy cipher suite order is set (overrides OS defaults):
TLS_AES_256_GCM_SHA384
TLS_AES_128_GCM_SHA256
TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384
TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256
TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384
TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256
TLS_ECDHE_ECDSA_WITH_AES_256_CBC_SHA384
TLS_ECDHE_ECDSA_WITH_AES_128_CBC_SHA256
TLS_ECDHE_RSA_WITH_AES_256_CBC_SHA384
TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA256

-- Recent Schannel/TLS errors (System log) --
No Schannel errors found in the last 14 days.
```
---

## References

- 
- 

## Liability
As described in the [MIT license](..\..\..\..\..\LICENSE.txt), these scripts are provided as-is with no warranty or liability associated with their use.

## Provide Feedback
We value your input. If you encounter problems with the scripts or ideas on how they can be improved please file an issue in the [Issues](https://github.com/Azure/azure-support-scripts/issues) section of the project.

## Known Issues