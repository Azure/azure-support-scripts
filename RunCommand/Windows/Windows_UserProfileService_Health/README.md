# Windows UserProfileService Health

> **Tool ID:** RC-048 · **Bucket:** Identity/Profile · **Phase:** 2 (Deep diagnostic)

## What It Does

Validates the Windows User Profile Service and profile integrity. Checks service state, profile registry entries, detects temporary profiles, measures profile disk usage, reviews profile load errors, and validates the default profile template. Essential for diagnosing RDP login failures where users get temporary profiles or "cannot sign into your account" errors.

| Check area | What is validated |
|---|---|
| Profile service | ProfSvc (User Profile Service) running |
| Profile list | Profile registry entries in ProfileList |
| Temp profiles | Temporary/corrupted profiles detected |
| Profile size | Users folder size on C: drive |
| Load errors | Profile load error events (7 days) |
| Default profile | Default user profile template intact |

## Run Command Constraints Met

- ✅ PowerShell 5.1 only
- ✅ No Az module required
- ✅ No internet access needed
- ✅ Output < 4 KB
- ✅ No interactive prompts
- ✅ Read-only (diagnostic only)

## How to Run

### Azure Run Command (recommended)
Navigate to VM → Operations → Run Command → RunPowerShellScript → paste script.

### Azure CLI
```bash
az vm run-command invoke -g <rg> -n <vm> --command-id RunPowerShellScript \
  --scripts @Windows_UserProfileService_Health/Windows_UserProfileService_Health.ps1
```

### Mock test
```powershell
.\Windows_UserProfileService_Health.ps1 -MockConfig .\mock_config_sample.json -MockProfile broken
```

## Sample Output (Issues Detected)

```
=== Windows UserProfileService Health ===
Check                                        Status
-------------------------------------------- ------
Profile Service running                      FAIL
Profile list registry entries                OK
Temporary profiles present                   FAIL
Profile size on C: (Users folder)            WARN
Profile load errors (7d)                     FAIL
Default profile intact                       OK
-- Decision --
Likely cause severity                        FAIL   Hard configuration/service break
Next action                                  OK     Follow README interpretation and remediate FAIL rows first
-- More Info --
Remediation references available             OK     See paired README Learn References

=== RESULT: 2 OK / 3 FAIL / 1 WARN ===
```

## Interpretation Guide

| FAIL/WARN condition | Likely cause | Quick fix | Learn link |
|---|---|---|---|
| **Profile Service running** FAIL | ProfSvc is stopped. Users will get temporary profiles or login failures. | `Set-Service ProfSvc -StartupType Automatic; Start-Service ProfSvc` | [Troubleshoot user profile service](https://learn.microsoft.com/troubleshoot/windows-server/user-profiles-and-logon/user-profile-cannot-be-loaded) |
| **Temporary profiles present** FAIL | Users have `.bak` profile entries in `HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList` — their profiles are corrupted and loading as temp profiles. | Delete the `.bak` registry key and rename the original if both exist. See [Fix corrupted user profiles](https://learn.microsoft.com/troubleshoot/windows-server/user-profiles-and-logon/fix-corrupted-user-profiles) | [Fix corrupted user profiles](https://learn.microsoft.com/troubleshoot/windows-server/user-profiles-and-logon/fix-corrupted-user-profiles) |
| **Profile size on C: (Users folder)** WARN | Users folder consuming significant disk space. Large profiles slow login and may fill the OS disk. | `Get-ChildItem C:\Users -Directory \| ForEach-Object { $s=(Get-ChildItem $_.FullName -Recurse -Force -ErrorAction SilentlyContinue \| Measure-Object -Property Length -Sum).Sum/1MB; "{0}: {1:N0} MB" -f $_.Name,$s }` | [Troubleshoot disk space issues](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/troubleshoot-low-disk-space) |
| **Profile load errors (7d)** FAIL | Event ID 1500/1511/1515 in Application log — profile service cannot load profiles. May be permissions, disk full, or registry corruption. | `Get-WinEvent -FilterHashtable @{LogName='Application'; ProviderName='Microsoft-Windows-User Profiles Service'; StartTime=(Get-Date).AddDays(-7)}` | [User profile cannot be loaded](https://learn.microsoft.com/troubleshoot/windows-server/user-profiles-and-logon/user-profile-cannot-be-loaded) |
| **Default profile intact** WARN | Default user profile template missing or corrupted. New users will get broken profiles. | Verify `C:\Users\Default` exists with NTUSER.DAT. If missing, copy from a healthy VM or extract from install media. | [Default user profile](https://learn.microsoft.com/windows/deployment/customize-default-user-profile) |

## Related Articles

| Article | Link |
|---|---|
| Troubleshoot "cannot sign into your account" | [learn.microsoft.com](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/troubleshoot-rdp-cannot-sign-into-account) |
| User profile cannot be loaded | [learn.microsoft.com](https://learn.microsoft.com/troubleshoot/windows-server/user-profiles-and-logon/user-profile-cannot-be-loaded) |
| Must change password at login | [learn.microsoft.com](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/must-change-password) |

### Mock test
```powershell
.\Windows_UserProfileService_Health.ps1 -MockConfig .\mock_config_sample.json -MockProfile broken
```

## Sample Output (Issues Detected)

```
=== Windows UserProfileService Health ===
Check                                        Status
-------------------------------------------- ------
Profile Service running                      FAIL
Profile list registry entries                OK
Temporary profiles present                   FAIL
Profile size on C: (Users folder)            WARN
Profile load errors (7d)                     FAIL
Default profile intact                       OK
-- Decision --
Likely cause severity                        FAIL   Hard configuration/service break
Next action                                  OK     Follow README interpretation and remediate FAIL rows first
-- More Info --
Remediation references available             OK     See paired README Learn References

=== RESULT: 2 OK / 3 FAIL / 1 WARN ===
```

## Interpretation Guide

| FAIL/WARN condition | Likely cause | Quick fix | Learn link |
|---|---|---|---|
| **Profile Service running** FAIL | ProfSvc is stopped. Users will get temporary profiles or login failures. | `Set-Service ProfSvc -StartupType Automatic; Start-Service ProfSvc` | [Troubleshoot user profile service](https://learn.microsoft.com/troubleshoot/windows-server/user-profiles-and-logon/user-profile-cannot-be-loaded) |
| **Temporary profiles present** FAIL | Users have `.bak` profile entries in `HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList` — their profiles are corrupted and loading as temp profiles. | Delete the `.bak` registry key and rename the original if both exist. See [Fix corrupted user profiles](https://learn.microsoft.com/troubleshoot/windows-server/user-profiles-and-logon/fix-corrupted-user-profiles) | [Fix corrupted user profiles](https://learn.microsoft.com/troubleshoot/windows-server/user-profiles-and-logon/fix-corrupted-user-profiles) |
| **Profile size on C: (Users folder)** WARN | Users folder consuming significant disk space. Large profiles slow login and may fill the OS disk. | `Get-ChildItem C:\Users -Directory \| ForEach-Object { $s=(Get-ChildItem $_.FullName -Recurse -Force -ErrorAction SilentlyContinue \| Measure-Object -Property Length -Sum).Sum/1MB; "{0}: {1:N0} MB" -f $_.Name,$s }` | [Troubleshoot disk space issues](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/troubleshoot-low-disk-space) |
| **Profile load errors (7d)** FAIL | Event ID 1500/1511/1515 in Application log — profile service cannot load profiles. May be permissions, disk full, or registry corruption. | `Get-WinEvent -FilterHashtable @{LogName='Application'; ProviderName='Microsoft-Windows-User Profiles Service'; StartTime=(Get-Date).AddDays(-7)}` | [User profile cannot be loaded](https://learn.microsoft.com/troubleshoot/windows-server/user-profiles-and-logon/user-profile-cannot-be-loaded) |
| **Default profile intact** WARN | Default user profile template missing or corrupted. New users will get broken profiles. | Verify `C:\Users\Default` exists with NTUSER.DAT. If missing, copy from a healthy VM or extract from install media. | [Default user profile](https://learn.microsoft.com/windows/deployment/customize-default-user-profile) |

## Related Articles

| Article | Link |
|---|---|
| Troubleshoot "cannot sign into your account" | [learn.microsoft.com](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/troubleshoot-rdp-cannot-sign-into-account) |
| User profile cannot be loaded | [learn.microsoft.com](https://learn.microsoft.com/troubleshoot/windows-server/user-profiles-and-logon/user-profile-cannot-be-loaded) |
| Must change password at login | [learn.microsoft.com](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/must-change-password) |
