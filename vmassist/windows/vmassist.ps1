<#
.SYNOPSIS
    Assists in diagnosing Azure VM Guest Agent issues
.DESCRIPTION
    Assists in diagnosing Azure VM Guest Agentissues
.NOTES
    Supported on Windows Server 2012 R2 and later versions of Windows.
    Supported in Windows PowerShell 4.0+ and PowerShell 6.0+.
    Not supported on Linux.
.LINK
    https://github.com/Azure/azure-support-scripts/blob/master/vmassist/windows/README.md
.EXAMPLE
    RDP to Azure VM
    Launch an elevated PowerShell prompt
    Download and run vmassist.ps1 with the following command:
    (Invoke-WebRequest -Uri https://raw.githubusercontent.com/Azure/azure-support-scripts/master/vmassist/windows/vmassist.ps1 -OutFile vmassist.ps1) | .\vmassist.ps1
#>
#Requires -Version 4
[CmdletBinding(SupportsShouldProcess = $true)]
param (
    [string]$outputPath = 'C:\logs',
    [switch]$fakeFinding,
    [switch]$skipFirewall,
    [switch]$showFilters = $false,
    [switch]$useDotnetForNicDetails = $true,
    [switch]$showLog,
    [switch]$showReport,
    [switch]$acceptEula,
    [switch]$listChecks,
    [switch]$listFindings,
    [switch]$skipPSVersionCheck
)

trap
{
    $trappedError = $PSItem
    $global:trappedError = $trappedError
    $scriptLineNumber = $trappedError.InvocationInfo.ScriptLineNumber
    $line = $trappedError.InvocationInfo.Line.Trim()
    $exceptionMessage = $trappedError.Exception.Message
    $trappedErrorString = $trappedError.Exception.ErrorRecord | Out-String -ErrorAction SilentlyContinue
    Out-Log "[ERROR] $exceptionMessage Line $scriptLineNumber $line" -color Red
    $properties = @{
        vmId  = $vmId
        error = $trappedErrorString
    }
    continue
}

#region functions
function Get-Age
{
    param(
        [datetime]$start,
        [datetime]$end = (Get-Date)
    )

    $timespan = New-TimeSpan -Start $start -End $end
    $years = [Math]::Round($timespan.Days / 365, 1)
    $months = [Math]::Round($timespan.Days / 30, 1)
    $days = $timespan.Days
    $hours = $timespan.Hours
    $minutes = $timespan.Minutes
    $seconds = $timespan.Seconds

    if ($years -gt 1)
    {
        $age = "$years years"
    }
    elseif ($years -eq 1)
    {
        $age = "$years year"
    }
    elseif ($months -gt 1)
    {
        $age = "$months months"
    }
    elseif ($months -eq 1)
    {
        $age = "$months month"
    }
    elseif ($days -gt 1)
    {
        $age = "$days days"
    }
    elseif ($days -eq 1)
    {
        $age = "$days day"
    }
    elseif ($hours -gt 1)
    {
        $age = "$hours hrs"
    }
    elseif ($hours -eq 1)
    {
        $age = "$hours hr"
    }
    elseif ($minutes -gt 1)
    {
        $age = "$minutes mins"
    }
    elseif ($minutes -eq 1)
    {
        $age = "$minutes min"
    }
    elseif ($seconds -gt 1)
    {
        $age = "$seconds secs"
    }
    elseif ($seconds -eq 1)
    {
        $age = "$seconds sec"
    }

    if ($age)
    {
        return $age
    }
}

<#
Add check to compare file hashes of machine.config and machine.config.default - if they differ we know they changed machine.config
(Get-FileHash -Path C:\Windows\Microsoft.NET\Framework64\v4.0.30319\Config\machine.config -Algorithm SHA256 | Select-Object -ExpandProperty Hash) -eq (Get-FileHash -Path C:\Windows\Microsoft.NET\Framework64\v4.0.30319\Config\machine.config.default -Algorithm SHA256 | Select-Object -ExpandProperty Hash)
#>
function Get-WCFConfig
{
    <#
    Microsoft.VisualStudio.Diagnostics.ServiceModelSink.dll must be present for the related machine.config settings to work
    C:\Windows\Microsoft.NET\assembly\GAC_MSIL\Microsoft.VisualStudio.Diagnostics.ServiceModelSink\v4.0_4.0.0.0__b03f5f7f11d50a3a\Microsoft.VisualStudio.Diagnostics.ServiceModelSink.dll
    C:\Windows\assembly\GAC_MSIL\Microsoft.VisualStudio.Diagnostics.ServiceModelSink\3.0.0.0__b03f5f7f11d50a3a\Microsoft.VisualStudio.Diagnostics.ServiceModelSink.dll
    vsdiag_regwcf.exe is the tool to use to enable/disable WCF debugging. It does the machine.config edits.
    It is installed as part of the Windows Communication Framework component of Visual Studio, up-to-and-including VS2022:
    C:\Program Files\Microsoft Visual Studio\2022\Enterprise\Common7\IDE\vsdiag_regwcf.exe
    C:\OneDrive\tools\vsdiag_regwcf.exe -i
    gc C:\Windows\Microsoft.NET\Framework64\v4.0.30319\config\machine.config | findstr /i servicemodelsink
                <add name="Microsoft.VisualStudio.Diagnostics.ServiceModelSink.Behavior" type="Microsoft.VisualStudio.Diagnostics.ServiceModelSink.Behavior, Microsoft.VisualStudio.Diagnostics.ServiceModelSink, Version=4.0.0.0, Culture=neutral, PublicKeyToken=b03f5f7f11d50a3a"/></behaviorExtensions>
        <commonBehaviors><endpointBehaviors><Microsoft.VisualStudio.Diagnostics.ServiceModelSink.Behavior/></endpointBehaviors><serviceBehaviors><Microsoft.VisualStudio.Diagnostics.ServiceModelSink.Behavior/></serviceBehaviors></commonBehaviors></system.serviceModel>
    C:\OneDrive\tools\vsdiag_regwcf.exe -u
    gc C:\Windows\Microsoft.NET\Framework64\v4.0.30319\config\machine.config | findstr /i servicemodelsink
    #>
    Out-Log 'WCF debugging enabled:' -startLine
    $machineConfigx64FilePath = "$env:SystemRoot\Microsoft.NET\Framework64\v4.0.30319\config\machine.config"
    $matches = Get-Content -Path $machineConfigx64FilePath | Select-String -SimpleMatch 'Microsoft.VisualStudio.Diagnostics.ServiceModelSink'
    if ($matches)
    {
        $serviceModelSinkDllParentPath1 = 'C:\Windows\Microsoft.NET\assembly\GAC_MSIL\Microsoft.VisualStudio.Diagnostics.ServiceModelSink'
        $serviceModelSinkDllParentPath2 = 'C:\Windows\assembly\GAC_MSIL\Microsoft.VisualStudio.Diagnostics.ServiceModelSink'
        $serviceModelSinkDllPath1 = Get-ChildItem -Path $ServiceModelSinkDllParentPath1 -Filter 'Microsoft.VisualStudio.Diagnostics.ServiceModelSink.dll' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName
        $serviceModelSinkDllPath2 = Get-ChildItem -Path $ServiceModelSinkDllParentPath2 -Filter 'Microsoft.VisualStudio.Diagnostics.ServiceModelSink.dll' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName

        if (Get-CimClass -ClassName 'MSFT_VSInstance' -Namespace 'root/cimv2/vs' -ErrorAction SilentlyContinue)
        {
            $vsInstance = Invoke-ExpressionWithLogging "Get-CimInstance -ClassName 'MSFT_VSInstance' -Namespace 'root/cimv2/vs' -ErrorAction SilentlyContinue" -verboseOnly
        }
        elseif (Get-CimClass -ClassName 'MSFT_VSInstance' -Namespace 'root/cimv2' -ErrorAction SilentlyContinue)
        {
            $vsInstance = Invoke-ExpressionWithLogging "Get-CimInstance -ClassName 'MSFT_VSInstance' -Namespace 'root/cimv2' -ErrorAction SilentlyContinue" -verboseOnly
        }

        if ($vsInstance)
        {
            $productLocation = $vsInstance | Select-Object -ExpandProperty ProductLocation -ErrorAction SilentlyContinue
        }
        else
        {
            Out-Log 'Visual Studio is not installed.'
            Out-Log 'The vsdiag_regwcf.exe tool is installed by the Windows Communication Framework component of Visual Studio. It cannot run as a standalone EXE.'
            Out-Log 'To install Visual Studio: https://aka.ms/vs/17/release/vs_enterprise.exe'
        }

        if ($productLocation -and (Test-Path -Path $productLocation -PathType Leaf))
        {
            $vsdiagRegwcfFilePath = "$(Split-Path -Path $productLocation)\vsdiag_regwcf.exe"
            if (Test-Path -Path $vsdiagRegwcfFilePath -PathType Leaf)
            {
                $vsdiagRegwcfExists = $true
                Out-Log "Found $vsdiagRegwcfExists" -verboseOnly
            }
            else
            {
                $vsdiagRegwcfExists = $false
                Out-Log "File not found: $vsdiagRegwcfExists" -verboseOnly
            }
        }
        else
        {
            Out-Log "File not found: $productLocation"
            $vsdiagRegwcfExists = $false
        }

        $machineConfigStrings = $matches.ToString()
        $matchesString = $matches.Line.Replace('<', '&lt;').Replace('>', '&gt;')
        #$matchesString = "<div class='box'><pre><code>$matchesString</code></pre></div>"
        #$matchesString = $matches.Line

        $global:dbgMatchesString = $matchesString
        $wcfDebuggingEnabled = $true
        Out-Log $wcfDebuggingEnabled -color Red -endLine
        New-Check -name 'WCF debugging config' -result 'FAILED' -details 'WCF debugging is enabled'
        $global:dbgMachineConfigStrings = $machineConfigStrings
        $description = "$machineConfigx64FilePath shows WCF debugging is enabled:<p>$matchesString<p>"
        $global:dbgDescription = $description
        New-Finding -type Critical -name 'WCF debugging enabled' -description $description -mitigation 'We recommend only enabling WCF debugging while debugging a WCF issue. Please disable WCF debugging'
    }
    else
    {
        $wcfDebuggingEnabled = $false
        Out-Log $wcfDebuggingEnabled -color Green -endLine
        New-Check -name 'WCF debugging config' -result 'OK' -details 'WCF debugging not enabled'
    }
}

#Confirms this is a VM running in HyperV
function Confirm-HyperVGuest
{
    # SystemManufacturer/SystemProductName valus are in different locations depending if Gen1 vs Gen2
    $systemManufacturer = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\SystemInformation' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty SystemManufacturer -ErrorAction SilentlyContinue
    $systemProductName = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\SystemInformation' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty SystemProductName -ErrorAction SilentlyContinue
    if ([string]::IsNullOrEmpty($systemManufacturer) -and [string]::IsNullOrEmpty($systemProductName))
    {
        $systemManufacturer = Get-ItemProperty 'HKLM:\HARDWARE\DESCRIPTION\System\BIOS' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty SystemManufacturer
        $systemProductName = Get-ItemProperty 'HKLM:\HARDWARE\DESCRIPTION\System\BIOS' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty SystemProductName
        if ([string]::IsNullOrEmpty($systemManufacturer) -and [string]::IsNullOrEmpty($systemProductName))
        {
            $systemManufacturer = Get-ItemProperty 'HKLM:\SYSTEM\HardwareConfig\Current' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty SystemManufacturer
            $systemProductName = Get-ItemProperty 'HKLM:\SYSTEM\HardwareConfig\Current' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty SystemProductName
        }
    }
    Out-Log "SystemManufacturer: $systemManufacturer" -verboseOnly
    Out-Log "SystemProductName: $systemProductName" -verboseOnly

    if ($systemManufacturer -eq 'Microsoft Corporation' -and $systemProductName -eq 'Virtual Machine')
    {
        # Deterministic for being a Hyper-V guest, but not for if it's in Azure or local
        $isHyperVGuest = $true
    }
    else
    {
        $isHyperVGuest = $false
    }
    return $isHyperVGuest
}

#Gets crashing applications with eventId 1000 in the last day
function Get-ApplicationErrors
{
    param(
        [string]$name
    )
    Out-Log "$name process errors:" -startLine
    $applicationErrors = Get-WinEvent -FilterHashtable @{ProviderName = 'Application Error'; Id = 1000; StartTime = ((Get-Date).AddDays(-7))} -ErrorAction SilentlyContinue | Where-Object {$_.Message -match $name}
    if ($applicationErrors)
    {
        $applicationErrorsCount = $applicationErrors | Measure-Object | Select-Object -ExpandProperty Count
        $latestApplicationError = $applicationErrors | Sort-Object TimeCreated | Select-Object -Last 1
        $timeCreated = Get-Date $latestApplicationError.TimeCreated -Format 'yyyy-MM-ddTHH:mm:ss'
        $id = $latestApplicationError.Id
        $message = $latestApplicationError.Message
        $description = "$applicationErrorsCount $name process errors in the last 1 day. Most recent: $timeCreated $id $message"
        New-Finding -type 'Critical' -name "$name application error" -description $description -mitigation 'If this application failure was unexpected or is happening repeatedly then further investigation into the Application Event log details and/or C:\WindowsAzure\WaAppAgent.log may be needed to investigate what caused it to fail'
        New-Check -name "$name process errors" -result 'FAILED' -details ''
        Out-Log $false -color Red -endLine
    }
    else
    {
        New-Check -name "$name process errors" -result 'OK' -details "No $name process errors in last 1 day"
        Out-Log $true -color Green -endLine
    }
}

#Gets crashing services with eventId 7031 or 7034 in the last day
function Get-ServiceCrashes
{
    param(
        [string]$name
    )
    Out-Log "$name service crashes:" -startLine
    $serviceCrashes = Get-WinEvent -FilterHashtable @{ProviderName = 'Service Control Manager'; Id = 7031, 7034; StartTime = ((Get-Date).AddDays(-1))} -ErrorAction SilentlyContinue | Where-Object {$_.Message -match $name}
    if ($serviceCrashes)
    {
        $serviceCrashesCount = $serviceCrashes | Measure-Object | Select-Object -ExpandProperty Count
        $latestCrash = $serviceCrashes | Sort-Object TimeCreated | Select-Object -Last 1
        $timeCreated = Get-Date $latestCrash.TimeCreated -Format 'yyyy-MM-ddTHH:mm:ss'
        $id = $latestCrash.Id
        $message = $latestCrash.Message
        $description = "$serviceCrashesCount $name service crashes in the last 1 day. Most recent: $timeCreated $id $message"
        New-Finding -type 'Critical' -name "$name service terminated unexpectedly" -description $description -mitigation 'If this service crash was unexpected or is happening repeatedly then further investigation into the System/Application Event log details and/or C:\WindowsAzure\WaAppAgent.log may be needed to investigate what caused it to fail'
        $details = "$(Get-Age $timeCreated) ago ($timeCreated)"
        New-Check -name "$name service crashes" -result 'FAILED' -details $details
        Out-Log "$true $details" -color Red -endLine
    }
    else
    {
        New-Check -name "$name service crashes" -result 'OK' -details "No $name service crashes in last 1 day"
        Out-Log $false -color Green -endLine
    }
}

#Gets Windows Filtering Platform (WFP)
function Get-WfpFilters
{
    Out-Log 'Getting WFP filters:' -startLine

    $wireserverWfpFiltersPath = "$scriptFolderPath\wireserverFilters.xml"
    $result = Invoke-ExpressionWithLogging "netsh wfp show filters dir=OUT remoteaddr=168.63.129.16 file=$wireserverWfpFiltersPath" -verboseOnly
    [xml]$wireserverWfpFilters = Get-Content -Path $wireserverWfpFiltersPath

    $wfpFiltersPath = "$scriptFolderPath\wfpFilters.xml"
    $result = Invoke-ExpressionWithLogging "netsh wfp show filters file=$wfpFiltersPath" -verboseOnly
    [xml]$wfpFilters = Get-Content -Path $wfpFiltersPath

    $displayDataName = @{Name = 'displayData.name'; Expression = {$_.displayData.name}}
    $displayDataDescription = @{Name = 'displayData.description'; Expression = {$_.displayData.description}}
    $flagsNumItems = @{Name = 'flags.numItems'; Expression = {$_.flags.numItems}}
    $providerDataData = @{Name = 'providerData.data'; Expression = {$_.providerData.data}}
    $providerDataAsString = @{Name = 'providerData.asString'; Expression = {$_.providerData.asString}}
    $weightType = @{Name = 'weight.type'; Expression = {$_.weight.type}}
    $weightUint8 = @{Name = 'weight.uint8'; Expression = {$_.weight.uint8}}
    $filterConditionNumItems = @{Name = 'filterCondition.numItems'; Expression = {$_.filterCondition.numItems}}
    $actionType = @{Name = 'action.type'; Expression = {$_.action.type}}
    $actionFilterType = @{Name = 'action.filterType'; Expression = {$_.action.filterType}}
    $effectiveWeightType = @{Name = 'effectiveWeight.type'; Expression = {$_.effectiveWeight.type}}
    $effectiveWeightUint64 = @{Name = 'effectiveWeight.uint64'; Expression = {$_.effectiveWeight.uint64}}

    $providers = $wfpFilters.wfpdiag.providers.Item | Select-Object serviceName, providerKey, $displayDataName, $displayDataDescription, $flagsNumItems
    $filters = $wfpFilters.wfpdiag.filters.item | Select-Object $actionType, $displayDataName, $displayDataDescription, filterKey, providerKey, layerKey, subLayerKey, providerContextKey, filterId, reserved, $flagsNumItems, $providerDataData, $providerDataAsString, $weightType, $weightUint8, $filterConditionNumItems, $actionFilterType, $effectiveWeightType, $effectiveWeightUint64
    $filters = $filters | Sort-Object 'effectiveWeight.uint64'
    $wireserverFilters = $wireserverWfpFilters.wfpdiag.filters.item | Select-Object $actionType, $displayDataName, $displayDataDescription, filterKey, providerKey, layerKey, subLayerKey, providerContextKey, filterId, reserved, $flagsNumItems, $providerDataData, $providerDataAsString, $weightType, $weightUint8, $filterConditionNumItems, $actionFilterType, $effectiveWeightType, $effectiveWeightUint64
    $wireserverFilters = $wireserverFilters | Sort-Object 'effectiveWeight.uint64'

    $result = [PSCustomObject]@{
        Providers         = $providers
        Filters           = $filters
        WireserverFilters = $wireserverFilters
    }

    $filtersCount = $filters | Measure-Object | Select-Object -ExpandProperty Count
    Out-Log "$filtersCount WPF filters" -endLine
    return $result
}

#Gets enabled Firewall rules

function Get-EnabledFirewallRules
{
    Out-Log 'Getting enabled Windows firewall rules: ' -startLine
    $getNetFirewallRuleDuration = Measure-Command {$enabledRules = Get-NetFirewallRule -Enabled True}

    $getNetFirewallPortFilterStartTime = Get-Date

    foreach ($enabledRule in $enabledRules)
    {
        $portFilter = $enabledRule | Get-NetFirewallPortFilter
        $addressFilter = $enabledRule | Get-NetFirewallAddressFilter
        $enabledRule | Add-Member -MemberType NoteProperty -Name Protocol -Value $portFilter.Protocol
        $enabledRule | Add-Member -MemberType NoteProperty -Name LocalPort -Value $portFilter.LocalPort
        $enabledRule | Add-Member -MemberType NoteProperty -Name RemotePort -Value $portFilter.RemotePort
        $enabledRule | Add-Member -MemberType NoteProperty -Name IcmpType -Value $portFilter.IcmpType
        $enabledRule | Add-Member -MemberType NoteProperty -Name DynamicTarget -Value $portFilter.DynamicTarget
        $enabledRule | Add-Member -MemberType NoteProperty -Name LocalAddress -Value $addressFilter.LocalAddress
        $enabledRule | Add-Member -MemberType NoteProperty -Name RemoteAddress -Value $addressFilter.RemoteAddress
    }
    $getNetFirewallPortFilterEndTime = Get-Date
    $getNetFirewallPortFilterDuration = '{0:hh}:{0:mm}:{0:ss}.{0:ff}' -f (New-TimeSpan -Start $getNetFirewallPortFilterStartTime -End $getNetFirewallPortFilterEndTime)

    $enabledInboundFirewallRules = $enabledRules | Where-Object {$_.Direction -eq 'Inbound'} | Select-Object DisplayName, Profile, Action, Protocol, LocalPort, RemotePort, IcmpType, DynamicTarget, LocalAddress, RemoteAddress | Sort-Object DisplayName
    $enabledOutboundFirewallRules = $enabledRules | Where-Object {$_.Direction -eq 'Outbound'} | Select-Object DisplayName, Profile, Action, Protocol, LocalPort, RemotePort, IcmpType, DynamicTarget, LocalAddress, RemoteAddress | Sort-Object DisplayName
    $enabledFirewallRules = [PSCustomObject]@{
        Inbound  = $enabledInboundFirewallRules
        Outbound = $enabledOutboundFirewallRules
    }

    $enabledFirewallRulesCount = $enabledRules | Measure-Object | Select-Object -ExpandProperty Count
    $enabledInboundFirewallRulesCount = $enabledInboundFirewallRules | Measure-Object | Select-Object -ExpandProperty Count
    $enabledOutboundFirewallRulesCount = $enabledOutboundFirewallRules | Measure-Object | Select-Object -ExpandProperty Count
    Out-Log "$enabledFirewallRulesCount enabled Windows firewall rules ($enabledInboundFirewallRulesCount inbound, $enabledOutboundFirewallRulesCount outbound)" -endLine
    Out-Log "Get-NetFirewallRule duration: $('{0:hh}:{0:mm}:{0:ss}.{0:ff}' -f $getNetFirewallRuleDuration)" -verboseOnly
    Out-Log "Get-NetFirewallPortFilter duration: $getNetFirewallPortFilterDuration" -verboseOnly
    return $enabledFirewallRules
}

#Gets 3rd party (non-microsoft) modlules loaded into a process
# Get-Process WaAppAgent,WindowsAzureGuestAgent | Select-Object -ExpandProperty modules | Select-Object ModuleName, company, description, product, filename, @{Name = 'Version'; Expression = {$_.FileVersionInfo.FileVersion}} | Sort-Object company | ft ModuleName,Company,Description -a
function Get-ThirdPartyLoadedModules
{
    param(
        [string]$processName
    )
    $microsoftWindowsProductionPCA2011 = 'CN=Microsoft Windows Production PCA 2011, O=Microsoft Corporation, L=Redmond, S=Washington, C=US'
    Out-Log "Third-party modules in $($processName):" -startLine
    if ($isVMAgentInstalled)
    {
        $process = Get-Process -Name $processName -ErrorAction SilentlyContinue
        if ($process)
        {
            $processThirdPartyModules = $process | Select-Object -ExpandProperty modules | Where-Object Company -NE 'Microsoft Corporation' | Select-Object ModuleName, company, description, product, filename, @{Name = 'Version'; Expression = {$_.FileVersionInfo.FileVersion}} | Sort-Object company
            if ($processThirdPartyModules)
            {
                foreach ($processThirdPartyModule in $processThirdPartyModules)
                {
                    $filePath = $processThirdPartyModule.FileName
                    $signature = Invoke-ExpressionWithLogging "Get-AuthenticodeSignature -FilePath '$filePath' -ErrorAction SilentlyContinue" -verboseOnly
                    $issuer = $signature.SignerCertificate.Issuer
                    if ($issuer -eq $microsoftWindowsProductionPCA2011)
                    {
                        $processThirdPartyModules = $processThirdPartyModules | Where-Object {$_.FileName -ne $filePath}
                    }
                }
                if ($processThirdPartyModules)
                {
                    $details = "$($($processThirdPartyModules.ModuleName -join ',').TrimEnd(','))"
                    New-Check -name "Third-party modules in $processName" -result 'Info' -details $details
                    Out-Log $true -endLine -color Cyan
                    New-Finding -type Information -name "Third-party modules in $processName" -description $details -mitigation "Third-party .dlls have been put in the $processName process. Other applications occasionally do this and it will not necessarily cause the Guest Agent to fail. However, it is possible that these .dlls can cause unexpected failures in the Guest Agent that are difficult to debug. Although it is relatively rare that these cause an issue, if any of these .dlls are from unexpected applications and you've exhausted traditional troubleshooting methods then consider removing/reconfiguring the application so that it no longer injects its .dlls into the $processName process."
                }
                else
                {
                    New-Check -name "Third-party modules in $processName" -result 'OK' -details "No third-party modules in $processName"
                    Out-Log $false -endLine -color Green
                }
            }
            else
            {
                New-Check -name "Third-party modules in $processName" -result 'OK' -details "No third-party modules in $processName"
                Out-Log $false -endLine -color Green
            }
        }
        else
        {
            $details = "$processName process not running"
            New-Check -name "Third-party modules in $processName" -result 'Info' -details $details
            Out-Log $details -color Cyan -endLine
        }
    }
    else
    {
        New-Check -name "Third-party modules in $processName" -result 'SKIPPED' -details "Skipped (VM agent installed: $isVMAgentInstalled)"
        Out-Log "Skipped (VM agent installed: $isVMAgentInstalled)" -endLine
    }
}

#Gets Services
function Get-Services
{
    $services = Get-CimInstance -Query 'SELECT DisplayName,Description,ErrorControl,ExitCode,Name,PathName,ProcessId,StartMode,StartName,State,ServiceSpecificExitCode,ServiceType FROM Win32_Service' -ErrorAction SilentlyContinue
    if ($services)
    {
        foreach ($service in $services)
        {
            #[int32]$exitCode = $service.ExitCode
            [double]$exitCode = $service.ExitCode
            $exitCodeMessage = [ComponentModel.Win32Exception]$exitCode | Select-Object -ExpandProperty Message
            #[int32]$serviceSpecificExitCode = $service.ServiceSpecificExitCode
            [double]$serviceSpecificExitCode = $service.ServiceSpecificExitCode
            $serviceSpecificExitCodeMessage = [ComponentModel.Win32Exception]$serviceSpecificExitCode | Select-Object -ExpandProperty Message
            $service | Add-Member -MemberType NoteProperty -Name ExitCode -Value "$exitCode ($exitCodeMessage)" -Force
            $service | Add-Member -MemberType NoteProperty -Name ServiceSpecificExitCode -Value "$serviceSpecificExitCode ($serviceSpecificExitCodeMessage)" -Force
        }
        $services = $services | Select-Object DisplayName, Name, State, StartMode, StartName, ErrorControl, ExitCode, ServiceSpecificExitCode, ServiceType, ProcessId, PathName | Sort-Object DisplayName
    }
    else
    {
        $services = Get-Service -ErrorAction SilentlyContinue
        foreach ($service in $services)
        {
            if ($service.ServiceHandle)
            {
                $statusExt = [Win32.Service.Ext]::QueryServiceStatus($service.ServiceHandle)
                $win32ExitCode = $statusExt | Select-Object -ExpandProperty Win32ExitCode
                $win32ExitCodeMessage = [ComponentModel.Win32Exception]$win32ExitCode | Select-Object -ExpandProperty Message
                $serviceSpecificExitCode = $statusExt | Select-Object -ExpandProperty ServiceSpecificExitCode
                $serviceSpecificExitCodeMessage = [ComponentModel.Win32Exception]$serviceSpecificExitCode | Select-Object -ExpandProperty Message
                $service | Add-Member -MemberType NoteProperty -Name Win32ExitCode -Value "$win32ExitCode ($win32ExitCodeMessage)"
                $service | Add-Member -MemberType NoteProperty -Name ServiceSpecificExitCode -Value "$serviceSpecificExitCode ($serviceSpecificExitCodeMessage)"
            }
            else
            {
                $service | Add-Member -MemberType NoteProperty -Name Win32ExitCode -Value $null
                $service | Add-Member -MemberType NoteProperty -Name ServiceSpecificExitCode -Value $null
            }
        }
        $services = $services | Select-Object DisplayName, Name, Status, StartType, Win32ExitCode, ServiceSpecificExitCode | Sort-Object DisplayName
    }
    return $services
}

#Performs check on a service to verify its expected status and expected start type
function Get-ServiceChecks
{
    param(
        [string]$name,
        [string]$expectedStatus,
        [string]$expectedStartType
    )

    <#
    $serviceKeyPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$name"
    $serviceKey = Invoke-ExpressionWithLogging "Get-ItemProperty -Path '$serviceKeyPath' -ErrorAction SilentlyContinue" -verboseOnly
    if ($serviceKey)
    {
        $serviceKeyExists = $true

        $serviceKeyStartValue = $serviceKey.Start
        $serviceKeyErrorControlValue = $serviceKey.ErrorControl
        $serviceKeyImagePathValue = $serviceKey.ImagePath
        $serviceKeyObjectNameValue = $serviceKey.ObjectName
    }
    else
    {
        $serviceKeyExists = $false
    }

    $scExe = "$env:SystemRoot\System32\sc.exe"

    $scQueryExOutput = Invoke-ExpressionWithLogging "& $scExe queryex $name" -verboseOnly
    $scQueryExExitCode = $LASTEXITCODE

    $scQcOutput = Invoke-ExpressionWithLogging "& $scExe qc $name" -verboseOnly
    $scQcExitCode = $LASTEXITCODE
    #>

    Out-Log "$name service:" -startLine
    $regKeyPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$name"
    $imagePath = Invoke-ExpressionWithLogging "Get-ItemProperty -Path '$regKeyPath' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty ImagePath" -verboseOnly
    if ($imagePath)
    {
        Out-Log "ImagePath: $imagePath" -verboseOnly
        $fullName = Get-Item -Path $imagePath -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName
        if ($fullName -or $imagePath -match 'svchost')
        {
            if ($fullName)
            {
                Out-Log "Service binary location $fullName matches ImagePath value in the registry" -verboseOnly
            }

            $service = Invoke-ExpressionWithLogging "Get-Service -Name '$name' -ErrorAction SilentlyContinue" -verboseOnly
            if ($service)
            {
                $isInstalled = $true

                $win32Service = Invoke-ExpressionWithLogging "Get-CimInstance -Query `"SELECT * from Win32_Service WHERE Name='$name'`" -ErrorAction SilentlyContinue" -verboseOnly
                if ($win32Service)
                {
                    $processId = $win32Service.ProcessId
                    $startName = $win32Service.StartName
                    $pathName = $win32Service.PathName
                    $exitCode = $win32Service.ExitCode
                    $serviceSpecificExitCode = $win32Service.ServiceSpecificExitCode
                    $errorControl = $win32Service.ErrorControl
                    if ($processId)
                    {
                        $process = Invoke-ExpressionWithLogging "Get-Process -Id $processId -ErrorAction SilentlyContinue" -verboseOnly

                        if ($process)
                        {
                            $startTime = $process.StartTime
                            $uptime = '{0:dd}:{0:hh}:{0:mm}:{0:ss}' -f (New-TimeSpan -Start $process.StartTime -End (Get-Date))
                        }
                    }
                }

                $displayName = $service.DisplayName
                $binaryPathName = $service.BinaryPathName
                $userName = $service.UserName
                $status = $service.Status
                $startType = $service.StartType
                $requiredServices = $service.RequiredServices
                $dependentServices = $service.DependentServices
                $servicesDependedOn = $service.ServicesDependedOn

                $statusExt = [Win32.Service.Ext]::QueryServiceStatus($service.ServiceHandle)
                $win32ExitCode = $statusExt | Select-Object -ExpandProperty Win32ExitCode
                $serviceSpecificExitCode = $statusExt | Select-Object -ExpandProperty ServiceSpecificExitCode

                if ($status -eq $expectedStatus)
                {
                    $isExpectedStatus = $true
                }
                else
                {
                    $isExpectedStatus = $false
                }
                if ($startType -eq $expectedStartType)
                {
                    $isExpectedStartType = $true
                }
                else
                {
                    $isExpectedStartType = $false
                }

                if ($startName -and $uptime)
                {
                    $details = "Status: $status StartType: $startType Startname: $startName Uptime: $uptime"
                }
                else
                {
                    $details = "Status: $status StartType: $startType"
                }
            }
            else
            {
                $isInstalled = $false
            }

            if ($isInstalled -eq $false)
            {
                New-Check -name "$name service" -result 'FAILED' -details "$name service is not installed"
                New-Finding -type 'Critical' -name "$name service is not installed" -description '' -mitigation '<a href="https://learn.microsoft.com/en-us/azure/virtual-machines/extensions/agent-windows#manual-installation">Install the VM Guest Agent</a>'
                Out-Log 'Not Installed' -color Red -endLine
            }
            elseif ($isInstalled -eq $true -and $isExpectedStatus -eq $true -and $isExpectedStartType -eq $true)
            {
                New-Check -name "$name service" -result 'OK' -details $details
                Out-Log "Status: $status StartType: $startType StartName: $startName" -color Green -endLine
            }
            elseif ($isInstalled -eq $true -and $isExpectedStatus -eq $true -and $isExpectedStartType -eq $false)
            {
                New-Check -name "$name service" -result 'FAILED' -details $details
                New-Finding -type 'Warning' -name "$name service start type $startType (expected: $expectedStartType)" -description $details -mitigation "We recommend setting the 'Startup Type' of the $name service to '$expectedStartType'. Please open services.msc, double click the $name service, and change the 'Startup Type' to '$expectedStartType'"
                Out-Log "Status: $status (expected $expectedStatus) StartType: $startType (expected $expectedStartType)" -color Red -endLine
            }
            elseif ($isInstalled -eq $true -and $isExpectedStatus -eq $false -and $isExpectedStartType -eq $true)
            {
                New-Check -name "$name service" -result 'FAILED' -details $details
                New-Finding -type 'Critical' -name "$name service status $status (expected: $expectedStatus)" -description $details -mitigation "The $name service is not currently $expectedStatus. Open services.msc and start the service."
                Out-Log "Status: $status (expected $expectedStatus) StartType: $startType (expected $expectedStartType)" -color Red -endLine
            }
            elseif ($isInstalled -eq $true -and $isExpectedStatus -eq $false -and $isExpectedStartType -eq $false)
            {
                New-Check -name "$name service" -result 'FAILED' -details $details
                New-Finding -type 'Critical' -name "$name service status $status (expected: $expectedStatus)" -description $details -mitigation "The $name service is not currently $expectedStatus. Open services.msc and start the service. </br></br> We also recommend setting the 'Startup Type' of the $name service to '$expectedStartType'. Please open services.msc, double click the $name service, and change the 'Startup Type' to '$expectedStartType'"
                Out-Log "Status: $status (expected $expectedStatus) StartType: $startType (expected $expectedStartType)" -color Red -endLine
            }

            return $service
        }
        else
        {
            $imageName = Split-Path -Path $imagePath -Leaf
            $actualImagePath = Get-ChildItem -Path "$env:SystemDrive\WindowsAzure" -Filter $imageName -Recurse -File -ErrorAction SilentlyContinue
            if ($actualImagePath)
            {
                $details = 'ImagePath registry value is incorrect'
                New-Check -name "$name service" -result 'FAILED' -details $details
                $description = "HKLM:\SYSTEM\CurrentControlSet\Services\$name\ImagePath is '$imagePath' but actual location of $imageName is '$actualImagePath'"
                New-Finding -type 'Critical' -name "$name service ImagePath registry value is incorrect" -description $description -mitigation '<a href="https://learn.microsoft.com/en-us/azure/virtual-machines/extensions/agent-windows#manual-installation">Install the VM Guest Agent</a>'
                Out-Log 'Not Installed' -color Red -endLine
            }
            else
            {
                New-Check -name "$name service" -result 'FAILED' -details "$name service is not installed"
                New-Finding -type 'Critical' -name "$name service is not installed" -description '' -mitigation '<a href="https://learn.microsoft.com/en-us/azure/virtual-machines/extensions/agent-windows#manual-installation">Install the VM Guest Agent</a>'
                Out-Log 'Not Installed' -color Red -endLine
            }
        }
    }
    else
    {
        New-Check -name "$name service" -result 'FAILED' -details "$name service is not installed"
        New-Finding -type 'Critical' -name "$name service is not installed" -description '' -mitigation '<a href="https://learn.microsoft.com/en-us/azure/virtual-machines/extensions/agent-windows#manual-installation">Install the VM Guest Agent</a>'
        Out-Log 'Not Installed' -color Red -endLine
    }
}

function Out-Log
{
    param(
        [string]$text,
        [switch]$verboseOnly,
        [switch]$startLine,
        [switch]$endLine,
        [switch]$raw,
        [switch]$logonly,
        [ValidateSet('Black', 'Blue', 'Cyan', 'DarkBlue', 'DarkCyan', 'DarkGray', 'DarkGreen', 'DarkMagenta', 'DarkRed', 'DarkYellow', 'Gray', 'Green', 'Magenta', 'Red', 'White', 'Yellow')]
        [string]$color = 'White'
    )

    $utc = (Get-Date).ToUniversalTime()

    $logTimestampFormat = 'yyyy-MM-dd hh:mm:ssZ'
    $logTimestampString = Get-Date -Date $utc -Format $logTimestampFormat

    if ([string]::IsNullOrEmpty($script:scriptStartTimeUtc))
    {
        $script:scriptStartTimeUtc = $utc
        $script:scriptStartTimeUtcString = Get-Date -Date $utc -Format $logTimestampFormat
    }

    if ([string]::IsNullOrEmpty($script:lastCallTime))
    {
        $script:lastCallTime = $utc
    }

    $lastCallTimeSpan = New-TimeSpan -Start $script:lastCallTime -End $utc
    $lastCallTotalSeconds = $lastCallTimeSpan | Select-Object -ExpandProperty TotalSeconds
    $lastCallTimeSpanFormat = '{0:ss}.{0:ff}'
    $lastCallTimeSpanString = $lastCallTimeSpanFormat -f $lastCallTimeSpan
    $lastCallTimeSpanString = "$($lastCallTimeSpanString)s"
    $script:lastCallTime = $utc

    if ($verboseOnly)
    {
        $callstack = Get-PSCallStack
        $caller = $callstack | Select-Object -First 1 -Skip 1
        $caller = $caller.InvocationInfo.MyCommand.Name
        if ($caller -eq 'Invoke-ExpressionWithLogging')
        {
            $caller = $callstack | Select-Object -First 1 -Skip 2
            $caller = $caller.InvocationInfo.MyCommand.Name
        }

        if ($verbose)
        {
            $outputNeeded = $true
        }
        else
        {
            $outputNeeded = $false
        }
    }
    else
    {
        $outputNeeded = $true
    }

    if ($outputNeeded)
    {
        if ($raw)
        {
            if ($logonly)
            {
                if ($logFilePath)
                {
                    $text | Out-File $logFilePath -Append
                }
            }
            else
            {
                Write-Host $text -ForegroundColor $color
                if ($logFilePath)
                {
                    $text | Out-File $logFilePath -Append
                }
            }
        }
        else
        {
            $timespan = New-TimeSpan -Start $script:scriptStartTimeUtc -End $utc

            $timespanFormat = '{0:mm}:{0:ss}'
            $timespanString = $timespanFormat -f $timespan

            $consolePrefixString = "$timespanString "
            $logPrefixString = "$logTimestampString $timespanString $lastCallTimeSpanString"

            if ($logonly -or $global:quiet)
            {
                if ($logFilePath)
                {
                    "$logPrefixString $text" | Out-File $logFilePath -Append
                }
            }
            else
            {
                if ($verboseOnly)
                {
                    $consolePrefixString = "$consolePrefixString[$caller] "
                    $logPrefixString = "$logPrefixString[$caller] "
                }

                if ($startLine)
                {
                    $script:startLineText = $text
                    Write-Host $consolePrefixString -NoNewline -ForegroundColor DarkGray
                    Write-Host "$text " -NoNewline -ForegroundColor $color
                }
                elseif ($endLine)
                {
                    Write-Host $text -ForegroundColor $color
                    if ($logFilePath)
                    {
                        "$logPrefixString $script:startLineText $text" | Out-File $logFilePath -Append
                    }
                }
                else
                {
                    Write-Host $consolePrefixString -NoNewline -ForegroundColor DarkGray
                    Write-Host $text -ForegroundColor $color
                    if ($logFilePath)
                    {
                        "$logPrefixString $text" | Out-File $logFilePath -Append
                    }
                }
            }
        }
    }
}

function Invoke-ExpressionWithLogging
{
    param(
        [string]$command,
        [switch]$raw,
        [switch]$verboseOnly
    )

    if ($verboseOnly)
    {
        if ($verbose)
        {
            if ($raw)
            {
                Out-Log $command -verboseOnly -raw
            }
            else
            {
                Out-Log $command -verboseOnly
            }
        }
    }
    else
    {
        if ($raw)
        {
            Out-Log $command -raw
        }
        else
        {
            Out-Log $command
        }
    }

    <# This results in error:

    Cannot convert argument "newChar", with value: "", for "Replace" to type "System.Char": "Cannot convert value "" to
    type "System.Char". Error: "String must be exactly one character long.""

    $command = $command.Replace($green, '').Replace($reset, '')
    #>

    try
    {
        Invoke-Expression -Command $command
    }
    catch
    {
        $global:errorRecordObject = $PSItem
        Out-Log "`n$command`n" -raw -color Red
        Out-Log "$global:errorRecordObject" -raw -color Red
        if ($LASTEXITCODE)
        {
            Out-Log "`$LASTEXITCODE: $LASTEXITCODE`n" -raw -color Red
        }
    }
}

#Tests connectivity to an IP/port
function Test-Port
{
    param(
        [string]$ipAddress,
        [int]$port,
        [int]$timeout = 1000
    )
    <#
    Use TCPClient .NET class since Test-NetConnection cmdlet does not support setting a timeout
    Equivalent Test-NetConnection command (but doesn't support timeouts):
    Test-NetConnection -ComputerName $wireServer -Port 80 -InformationLevel Quiet -WarningAction SilentlyContinue
    #>
    $tcpClient = New-Object System.Net.Sockets.TCPClient
    $connect = $tcpClient.BeginConnect($ipAddress, $port, $null, $null)
    $wait = $connect.AsyncWaitHandle.WaitOne($timeout, $false)

    $result = [PSCustomObject]@{
        Succeeded = $null
        Error     = $null
    }

    if ($wait)
    {
        try
        {
            $tcpClient.EndConnect($connect)
        }
        catch [System.Net.Sockets.SocketException]
        {
            $testPortError = $_
            $result.Succeeded = $false
            $result.Error = $testPortError
            #$result | Add-Member -MemberType NoteProperty -Name Succeeded -Value $false -Force
            #$result | Add-Member -MemberType NoteProperty -Name Error -Value $testPortError -Force
            return $result
        }

        if ([bool]$testPortError -eq $false)
        {
            $result.Succeeded = $true
            return $result
        }
    }
    else
    {
        $result.Succeeded = $false
        return $result
    }
    $tcpClient.Close()
    $tcpClient.Dispose()
}

#Adds a check to the $checks list
function New-Check
{
    param(
        [string]$name,
        [ValidateSet('OK', 'FAILED', 'INFO', 'SKIPPED')]
        [string]$result,
        [string]$details
    )

    $date = Get-Date
    $date = $date.ToUniversalTime()
    $timeCreated = Get-Date -Date $date -Format yyyy-MM-ddTHH:mm:ss.ffZ

    $check = [PSCustomObject]@{
        TimeCreated = $timeCreated
        Name        = $name
        Result      = $result
        Details     = $details
    }
    $checks.Add($check)

}

#Adds a check to the $findings list
function New-Finding
{
    param(
        [ValidateSet('Information', 'Warning', 'Critical')]
        [string]$type,
        [string]$name,
        [string]$description,
        [string]$mitigation
    )

    $date = Get-Date
    $date = $date.ToUniversalTime()
    $timeCreated = Get-Date -Date $date -Format 'yyyy-MM-ddTHH:mm:ssZ'

    $finding = [PSCustomObject]@{
        TimeCreated = $timeCreated
        Type        = $type
        Name        = $name
        Description = $description
        Mitigation  = $mitigation
    }
    $findings.Add($finding)
    $global:dbgFinding = $finding
}

#Gets list of drivers
function Get-Drivers
{
    # Both Win32_SystemDriver and Driverquery.exe use WMI, and Win32_SystemDriver is faster
    # So no benefit to using Driverquery.exe
    <#
CN=Microsoft Windows Third Party Component CA 2012, O=Microsoft Corporation, L=Redmond, S=Washington, C=US
CN=Microsoft Windows Third Party Component CA 2013, O=Microsoft Corporation, L=Redmond, S=Washington, C=US
CN=Microsoft Windows Third Party Component CA 2014, O=Microsoft Corporation, L=Redmond, S=Washington, C=US
#>

    $microsoftIssuers = @'
CN=Microsoft Code Signing PCA 2010, O=Microsoft Corporation, L=Redmond, S=Washington, C=US
CN=Microsoft Code Signing PCA 2011, O=Microsoft Corporation, L=Redmond, S=Washington, C=US
CN=Microsoft Code Signing PCA, O=Microsoft Corporation, L=Redmond, S=Washington, C=US
CN=Microsoft Windows Production PCA 2011, O=Microsoft Corporation, L=Redmond, S=Washington, C=US
CN=Microsoft Windows Verification PCA, O=Microsoft Corporation, L=Redmond, S=Washington, C=US
'@

    $microsoftIssuers = $microsoftIssuers.Split("`n").Trim()

    $drivers = Get-CimInstance -Query 'SELECT * FROM Win32_SystemDriver'

    foreach ($driver in $drivers)
    {
        $driverPath = $driver.PathName.Replace('\??\', '')
        $driverFile = Get-Item -Path $driverPath -ErrorAction SilentlyContinue
        if ($driverFile)
        {
            $driver | Add-Member -MemberType NoteProperty -Name Path -Value $driverPath
            $driver | Add-Member -MemberType NoteProperty -Name Version -Value $driverFile.VersionInfo.FileVersionRaw
            $driver | Add-Member -MemberType NoteProperty -Name CompanyName -Value $driverFile.VersionInfo.CompanyName
        }

        # TODO: PS4.0 shows OS file as not signed, this was fixed in PS5.1
        # Need to handle the PS4.0 scenario
        $driverFileSignature = Invoke-ExpressionWithLogging "Get-AuthenticodeSignature -FilePath '$driverPath' -ErrorAction SilentlyContinue" -verboseOnly
        if ($driverFileSignature)
        {
            $driver | Add-Member -MemberType NoteProperty -Name Issuer -Value $driverFileSignature.Signercertificate.Issuer
            $driver | Add-Member -MemberType NoteProperty -Name Subject -Value $driverFileSignature.Signercertificate.Subject
        }
    }

    $microsoftRunningDrivers = $drivers | Where-Object {$_.State -eq 'Running' -and $_.Issuer -in $microsoftIssuers}
    $thirdPartyRunningDrivers = $drivers | Where-Object {$_.State -eq 'Running' -and $_.Issuer -notin $microsoftIssuers}

    $microsoftRunningDrivers = $microsoftRunningDrivers | Select-Object -Property Name, Description, Path, Version, CompanyName, Issuer
    $thirdPartyRunningDrivers = $thirdPartyRunningDrivers | Select-Object -Property Name, Description, Path, Version, CompanyName, Issuer

    $runningDrivers = [PSCustomObject]@{
        microsoftRunningDrivers  = $microsoftRunningDrivers
        thirdPartyRunningDrivers = $thirdPartyRunningDrivers
    }

    return $runningDrivers
}

#Checks if joined to a domain
function Get-JoinInfo
{
    $netApi32MemberDefinition = @'
using System;
using System.Collections.Generic;
using System.Text;
using System.Runtime.InteropServices;
public class NetAPI32{
    public enum DSREG_JOIN_TYPE {
    DSREG_UNKNOWN_JOIN,
    DSREG_DEVICE_JOIN,
    DSREG_WORKPLACE_JOIN
    }
    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
    public struct DSREG_USER_INFO {
        [MarshalAs(UnmanagedType.LPWStr)] public string UserEmail;
        [MarshalAs(UnmanagedType.LPWStr)] public string UserKeyId;
        [MarshalAs(UnmanagedType.LPWStr)] public string UserKeyName;
    }
    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
    public struct CERT_CONTEX {
        public uint   dwCertEncodingType;
        public byte   pbCertEncoded;
        public uint   cbCertEncoded;
        public IntPtr pCertInfo;
        public IntPtr hCertStore;
    }
    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
    public struct DSREG_JOIN_INFO
    {
        public int joinType;
        public IntPtr pJoinCertificate;
        [MarshalAs(UnmanagedType.LPWStr)] public string DeviceId;
        [MarshalAs(UnmanagedType.LPWStr)] public string IdpDomain;
        [MarshalAs(UnmanagedType.LPWStr)] public string TenantId;
        [MarshalAs(UnmanagedType.LPWStr)] public string JoinUserEmail;
        [MarshalAs(UnmanagedType.LPWStr)] public string TenantDisplayName;
        [MarshalAs(UnmanagedType.LPWStr)] public string MdmEnrollmentUrl;
        [MarshalAs(UnmanagedType.LPWStr)] public string MdmTermsOfUseUrl;
        [MarshalAs(UnmanagedType.LPWStr)] public string MdmComplianceUrl;
        [MarshalAs(UnmanagedType.LPWStr)] public string UserSettingSyncUrl;
        public IntPtr pUserInfo;
    }
    [DllImport("netapi32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    public static extern void NetFreeAadJoinInformation(
            IntPtr pJoinInfo);
    [DllImport("netapi32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    public static extern int NetGetAadJoinInformation(
            string pcszTenantId,
            out IntPtr ppJoinInfo);
}
'@

    if ($buildNumber -ge 10240)
    {
        if ([bool]([System.Management.Automation.PSTypeName]'NetAPI32').Type -eq $false)
        {
            $netApi32 = Add-Type -TypeDefinition $netApi32MemberDefinition -ErrorAction SilentlyContinue
        }

        if ([bool]([System.Management.Automation.PSTypeName]'NetAPI32').Type -eq $true)
        {
            $netApi32 = Add-Type -TypeDefinition $netApi32MemberDefinition -ErrorAction SilentlyContinue
            $pcszTenantId = $null
            $ptrJoinInfo = [IntPtr]::Zero

            # https://docs.microsoft.com/en-us/windows/win32/api/lmjoin/nf-lmjoin-netgetaadjoininformation
            # [NetAPI32]::NetFreeAadJoinInformation([IntPtr]::Zero);
            $retValue = [NetAPI32]::NetGetAadJoinInformation($pcszTenantId, [ref]$ptrJoinInfo)

            # https://docs.microsoft.com/en-us/openspecs/windows_protocols/ms-erref/18d8fbe8-a967-4f1c-ae50-99ca8e491d2d
            if ($retValue -eq 0)
            {
                # https://support.microsoft.com/en-us/help/2909958/exceptions-in-windows-powershell-other-dynamic-languages-and-dynamical
                $ptrJoinInfoObject = New-Object NetAPI32+DSREG_JOIN_INFO
                $joinInfo = [System.Runtime.InteropServices.Marshal]::PtrToStructure($ptrJoinInfo, [System.Type] $ptrJoinInfoObject.GetType())

                $ptrUserInfo = $joinInfo.pUserInfo
                $ptrUserInfoObject = New-Object NetAPI32+DSREG_USER_INFO
                $userInfo = [System.Runtime.InteropServices.Marshal]::PtrToStructure($ptrUserInfo, [System.Type] $ptrUserInfoObject.GetType())

                switch ($joinInfo.joinType)
                {
                    ([NetAPI32+DSREG_JOIN_TYPE]::DSREG_DEVICE_JOIN.value__) {$joinType = 'Joined to Azure AD (DSREG_DEVICE_JOIN)'}
                    ([NetAPI32+DSREG_JOIN_TYPE]::DSREG_UNKNOWN_JOIN.value__) {$joinType = 'Unknown (DSREG_UNKNOWN_JOIN)'}
                    ([NetAPI32+DSREG_JOIN_TYPE]::DSREG_WORKPLACE_JOIN.value__) {$joinType = 'Azure AD work account is added on the device (DSREG_WORKPLACE_JOIN)'}
                }
            }
            else
            {
                $joinType = 'Not Azure Joined'
            }
        }
    }
    else
    {
        $joinType = 'N/A'
    }

    $productType = Invoke-ExpressionWithLogging "Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\ProductOptions' | Select-Object -ExpandProperty ProductType" -verboseOnly

    switch ($productType)
    {
        'WinNT' {$role = 'Workstation'}
        'LanmanNT ' {$role = 'Domain controller'}
        'ServerNT' {$role = 'Server'}
    }

    $joinInfo = [PSCustomObject]@{
        JoinType = $joinType
        Role     = $role
    }

    return $joinInfo
}

#Gets handlers listed in aggregateStatus.json and compares them to what is in the extension config. If extension also exists in extension config then adds extension to array
function Get-ExtensionHandlers
{
    $extensionHandlers = New-Object System.Collections.Generic.List[Object]

    if ($isVMAgentInstalled)
        {
            $handlerKeyNames = $aggregateStatus.aggregateStatus.handlerAggregateStatus

            foreach ($handlerKeyName in $handlerKeyNames)
            {
                foreach($plugin in $extensions.Plugins.Plugin.name)
                {
                    if($handlerKeyName.handlername -contains $plugin)
                    {
                        $extensionHandlers.Add([PSCustomObject]@{
                            handlerName = $handlerKeyName.handlername; 
                            handlerVersion = $handlerKeyName.handlerVersion; 
                            handlerStatus = $handlerKeyName.status; 
                            sequenceNumber = $handlerKeyName.runtimeSettingsStatus.sequenceNumber; 
                            timestampUTC = $handlerKeyName.runtimeSettingsStatus.settingsStatus.timestampUTC; 
                            status = $handlerKeyName.runtimeSettingsStatus.settingsStatus.status.status; 
                            message = $handlerKeyName.runtimeSettingsStatus.settingsStatus.status.formattedMessage.message
                        })
                    }
                }
            }
        }    
    return $extensionHandlers
}

#endregion functions

$eula = @'
MICROSOFT SOFTWARE LICENSE TERMS
Microsoft Diagnostic Scripts and Utilities

 These license terms are an agreement between you and Microsoft Corporation (or one of its affiliates). IF YOU COMPLY WITH THESE LICENSE TERMS, YOU HAVE THE RIGHTS BELOW. BY USING THE SOFTWARE, YOU ACCEPT THESE TERMS.

1.	INSTALLATION AND USE RIGHTS. Subject to the terms and restrictions set forth in this license, Microsoft Corporation ("Microsoft") grants you ("Customer" or "you") a non-exclusive, non-assignable, fully paid-up license to use and reproduce the script or utility provided under this license (the "Software"), solely for Customer's internal business purposes, to help Microsoft troubleshoot issues with one or more Microsoft products, provided that such license to the Software does not include any rights to other Microsoft technologies (such as products or services). "Use" means to copy, install, execute, access, display, run or otherwise interact with the Software.

You may not sublicense the Software or any use of it through distribution, network access, or otherwise. Microsoft reserves all other rights not expressly granted herein, whether by implication, estoppel or otherwise. You may not reverse engineer, decompile or disassemble the Software, or otherwise attempt to derive the source code for the Software, except and to the extent required by third party licensing terms governing use of certain open source components that may be included in the Software, or remove, minimize, block, or modify any notices of Microsoft or its suppliers in the Software. Neither you nor your representatives may use the Software provided hereunder: (i) in a way prohibited by law, regulation, governmental order or decree; (ii) to violate the rights of others; (iii) to try to gain unauthorized access to or disrupt any service, device, data, account or network; (iv) to distribute spam or malware; (v) in a way that could harm Microsoft's IT systems or impair anyone else's use of them; (vi) in any application or situation where use of the Software could lead to the death or serious bodily injury of any person, or to physical or environmental damage; or (vii) to assist, encourage or enable anyone to do any of the above.

2.	DATA. Customer owns all rights to data that it may elect to share with Microsoft through using the Software. You can learn more about data collection and use in the help documentation and the privacy statement at https://aka.ms/privacy. Your use of the Software operates as your consent to these practices.

3.	FEEDBACK. If you give feedback about the Software to Microsoft, you grant to Microsoft, without charge, the right to use, share and commercialize your feedback in any way and for any purpose. You will not provide any feedback that is subject to a license that would require Microsoft to license its software or documentation to third parties due to Microsoft including your feedback in such software or documentation.

4.	EXPORT RESTRICTIONS. Customer must comply with all domestic and international export laws and regulations that apply to the Software, which include restrictions on destinations, end users, and end use. For further information on export restrictions, visit https://aka.ms/exporting.

5.	REPRESENTATIONS AND WARRANTIES. Customer will comply with all applicable laws under this agreement, including in the delivery and use of all data. Customer or a designee agreeing to these terms on behalf of an entity represents and warrants that it (i) has the full power and authority to enter into and perform its obligations under this agreement, (ii) has full power and authority to bind its affiliates or organization to the terms of this agreement, and (iii) will secure the permission of the other party prior to providing any source code in a manner that would subject the other party's intellectual property to any other license terms or require the other party to distribute source code to any of its technologies.

6.	DISCLAIMER OF WARRANTY. THE SOFTWARE IS PROVIDED "AS IS," WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL MICROSOFT OR ITS LICENSORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THE SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

7.	LIMITATION ON AND EXCLUSION OF DAMAGES. IF YOU HAVE ANY BASIS FOR RECOVERING DAMAGES DESPITE THE PRECEDING DISCLAIMER OF WARRANTY, YOU CAN RECOVER FROM MICROSOFT AND ITS SUPPLIERS ONLY DIRECT DAMAGES UP TO U.S. .00. YOU CANNOT RECOVER ANY OTHER DAMAGES, INCLUDING CONSEQUENTIAL, LOST PROFITS, SPECIAL, INDIRECT, OR INCIDENTAL DAMAGES. This limitation applies to (i) anything related to the Software, services, content (including code) on third party Internet sites, or third party applications; and (ii) claims for breach of contract, warranty, guarantee, or condition; strict liability, negligence, or other tort; or any other claim; in each case to the extent permitted by applicable law. It also applies even if Microsoft knew or should have known about the possibility of the damages. The above limitation or exclusion may not apply to you because your state, province, or country may not allow the exclusion or limitation of incidental, consequential, or other damages.

8.	BINDING ARBITRATION AND CLASS ACTION WAIVER. This section applies if you live in (or, if a business, your principal place of business is in) the United States.  If you and Microsoft have a dispute, you and Microsoft agree to try for 60 days to resolve it informally. If you and Microsoft can't, you and Microsoft agree to binding individual arbitration before the American Arbitration Association under the Federal Arbitration Act ("FAA"), and not to sue in court in front of a judge or jury. Instead, a neutral arbitrator will decide. Class action lawsuits, class-wide arbitrations, private attorney-general actions, and any other proceeding where someone acts in a representative capacity are not allowed; nor is combining individual proceedings without the consent of all parties. The complete Arbitration Agreement contains more terms and is at https://aka.ms/arb-agreement-4. You and Microsoft agree to these terms.

9.	LAW AND VENUE. If U.S. federal jurisdiction exists, you and Microsoft consent to exclusive jurisdiction and venue in the federal court in King County, Washington for all disputes heard in court (excluding arbitration). If not, you and Microsoft consent to exclusive jurisdiction and venue in the Superior Court of King County, Washington for all disputes heard in court (excluding arbitration).

10.	ENTIRE AGREEMENT. This agreement, and any other terms Microsoft may provide for supplements, updates, or third-party applications, is the entire agreement for the software.
'@

#region main

$scriptStartTime = Get-Date
$scriptStartTimeString = Get-Date -Date $scriptStartTime -Format yyyyMMddHHmmss
$scriptFullName = $MyInvocation.MyCommand.Path
$scriptFolderPath = Split-Path -Path $scriptFullName
$scriptName = Split-Path -Path $scriptFullName -Leaf
$scriptBaseName = $scriptName.Split('.')[0]

$PSDefaultParameterValues['*:ErrorAction'] = 'Stop'
$PSDefaultParameterValues['*:WarningAction'] = 'SilentlyContinue'
$ProgressPreference = 'SilentlyContinue'
$WarningPreference = 'SilentlyContinue'

$verbose = [bool]$PSBoundParameters['verbose']
$debug = [bool]$PSBoundParameters['debug']
if ($debug)
{
    $DebugPreference = 'Continue'
}

$psVersion = $PSVersionTable.PSVersion
$psVersionString = $psVersion.ToString()
# If run from PowerShell (PS6+), rerun from Windows Powershell if Windows PowerShell 4.0+ installed, otherwise fail with error saying Windows PowerShell 4.0+ is required
if ($skipPSVersionCheck -ne $true -and ($psVersion -lt [version]'4.0' -or $psVersion -ge [version]'6.0'))
{
    [version]$windowsPowerShellVersion = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\PowerShell\3\PowerShellEngine' -Name PowerShellVersion | Select-Object -ExpandProperty PowerShellVersion
    if ($windowsPowerShellVersion -ge [version]'4.0' -and $windowsPowerShellVersion -lt [version]'6.0')
    {
        #$vmassistScriptFilePath = 'c:\src\vmassist\vmassist.ps1'
        $vmassistCommand = $MyInvocation.MyCommand.Path

        if ($outputPath)
        {
            $vmassistCommand = "$vmassistCommand -outputPath $outputPath"
        }
        if ($fakeFinding)
        {
            $vmassistCommand = "$vmassistCommand -fakeFinding"
        }
        if ($skipFirewall)
        {
            $vmassistCommand = "$vmassistCommand -skipFirewall"
        }
        if ($showFilters)
        {
            $vmassistCommand = "$vmassistCommand -showFilters"
        }
        if ($useDotnetForNicDetails)
        {
            $vmassistCommand = "$vmassistCommand -useDotnetForNicDetails"
        }
        if ($showLog)
        {
            $vmassistCommand = "$vmassistCommand -showLog"
        }
        if ($showReport)
        {
            $vmassistCommand = "$vmassistCommand -showReport"
        }
        if ($acceptEula)
        {
            $vmassistCommand = "$vmassistCommand -acceptEula"
        }
        if ($listChecks)
        {
            $vmassistCommand = "$vmassistCommand -listChecks"
        }
        if ($listFindings)
        {
            $vmassistCommand = "$vmassistCommand -listFindings"
        }
        if ($skipPSVersionCheck)
        {
            $vmassistCommand = "$vmassistCommand -skipPSVersionCheck"
        }
        if ($verbose)
        {
            $vmassistCommand = "$vmassistCommand -verbose"
        }
        if ($debug)
        {
            $vmassistCommand = "$vmassistCommand -debug"
        }
        # powershell -noprofile -nologo -Command $vmassistCommand
        $command = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe -noprofile -nologo -Command $vmassistCommand"
        Invoke-Expression $command
        exit
    }
    else
    {
        Write-Error "You are using PowerShell $psVersionString. This script requires Windows PowerShell version 5.1, 5.0, or 4.0."
        exit 1
    }
}

if(!$acceptEula)
{
    Out-Log $eula
    Out-Log "Enter 'y' to accept or 'n' to decline the EULA" -color Yellow
    $acceptance = Read-Host

    while ($true) 
    {
        if ($acceptance.ToLower() -in @('y', 'yes')) 
        {
            Out-Log "You have accepted the EULA." -color Yellow
            break
        } elseif ($acceptance.ToLower() -in @('n', 'no')) 
        {
            Out-Log "You have declined the EULA. Exiting..." -color Yellow
            exit
        } else 
        {
            Out-Log "Invalid input. Please enter 'y' or 'n'."
            Out-Log "Enter 'y' to accept or 'n' to decline the EULA" -color Yellow
            $acceptance = Read-Host
        }
    }
}

if ($listChecks)
{
    $scriptFullName = 'C:\src\vmassist\vmassist.ps1'
    $script = Get-Content -Path $scriptFullName
    $lines = $script | Select-String -SimpleMatch -Pattern 'New-Check -name' | Select-Object -expand Line | ForEach-Object {$_.Trim()}
    $lines = $lines | ForEach-Object {(($_ -split '-name')[1] -split '-result')[0].Trim()} | Where-Object {$_ -and $_ -notmatch 'Trim'} | Sort-Object -Unique
    $lines.Replace('"', '').Replace("'", '')
    exit
}

if ($listFindings)
{
    $scriptFullName = 'C:\src\vmassist\vmassist.ps1'
    $script = Get-Content -Path $scriptFullName
    $lines = $script | Select-String -SimpleMatch -Pattern 'New-Finding -type' | Select-Object -expand Line | ForEach-Object {$_.Trim()}
    $lines = $lines | ForEach-Object {(($_ -split '-name')[1] -split '-description')[0].Trim()} | Where-Object {$_ -and $_ -notmatch 'Trim'} | Sort-Object -Unique
    $lines.Replace('"', '').Replace("'", '')
    exit
}

#Validates that script is ran as admim
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]'Administrator')
if ($isAdmin -eq $false)
{
    Write-Host 'Script must be run from an elevated PowerShell session' -ForegroundColor Cyan
    exit
}

if ($outputPath)
{
    $logFolderPath = $outputPath
}
else
{
    $logFolderParentPath = $env:TEMP
    $logFolderPath = "$logFolderParentPath\$scriptBaseName"
}
if ((Test-Path -Path $logFolderPath -PathType Container) -eq $false)
{
    Invoke-ExpressionWithLogging "New-Item -Path $logFolderPath -ItemType Directory -Force | Out-Null" -verboseOnly
}

$computerName = [System.Net.Dns]::GetHostName()

$logFilePath = "$logFolderPath\$($scriptBaseName)_$($computerName)_$($scriptStartTimeString).log"
if ((Test-Path -Path $logFilePath -PathType Leaf) -eq $false)
{
    New-Item -Path $logFilePath -ItemType File -Force | Out-Null
}
Out-Log "Log file: $logFilePath"

$result = New-Object System.Collections.Generic.List[Object]
$checks = New-Object System.Collections.Generic.List[Object]
$findings = New-Object System.Collections.Generic.List[Object]
$vm = New-Object System.Collections.Generic.List[Object]

#Gets Windows Version information
$ErrorActionPreference = 'SilentlyContinue'
$version = [environment]::osversion.version.ToString()
$buildNumber = [environment]::osversion.version.build
$currentVersionKeyPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
$currentVersionKey = Invoke-ExpressionWithLogging "Get-ItemProperty -Path '$currentVersionKeyPath' -ErrorAction SilentlyContinue" -verboseOnly
if ($currentVersionKey)
{
    $productName = $currentVersionKey.ProductName
    if ($productName -match 'Windows 10' -and $buildNumber -ge 22000)
    {
        $productName = $productName.Replace('Windows 10', 'Windows 11')
    }
    $ubr = $currentVersionKey.UBR
    # Starting with Win10/WS16, InstallDate is when the last cumulative update was installed, not when Windows itself was installed
    # $installDate = $currentVersionKey.InstallDate
    # $installDateString = Get-Date -Date ([datetime]'1/1/1970').AddSeconds($installDate) -Format yyyy-MM-ddTHH:mm:ss
    if ($buildNumber -ge 14393)
    {
        $releaseId = $currentVersionKey.ReleaseId
        $displayVersion = $currentVersionKey.DisplayVersion
    }
}
$ErrorActionPreference = 'Continue'

$installationType = Get-ItemProperty 'HKLM:\Software\Microsoft\Windows NT\CurrentVersion' -Name InstallationType | Select-Object -ExpandProperty InstallationType

if ($displayVersion)
{
    if ($installationType -eq 'Server Core')
    {
        $osVersion = "$productName $installationType $displayVersion $releaseId $version"
    }
    else
    {
        $osVersion = "$productName $displayVersion $releaseId $version"
    }
}
else
{
    if ($installationType -eq 'Server Core')
    {
        $osVersion = "$productName $installationType $version"
    }
    else
    {
        $osVersion = "$productName $version"
    }
}

Out-Log $osVersion -color Cyan
$timeZone = [System.TimeZoneInfo]::Local | Select-Object -ExpandProperty DisplayName
$isHyperVGuest = Confirm-HyperVGuest
Out-Log "Hyper-V Guest: $isHyperVGuest"

$parentProcessId = Get-CimInstance -Class Win32_Process -Filter "ProcessId = '$PID'" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty ParentProcessId
$grandparentProcessPid = Get-CimInstance -Class Win32_Process -Filter "ProcessId = '$parentProcessId'" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty ParentProcessId
$grandparentProcessName = Get-Process -Id $grandparentProcessPid -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name
if ($grandparentProcessName -eq 'sacsess')
{
    $isSacSess = $true
}
else
{
    $isSacSess = $false
}
Out-Log "SAC session: $isSacSess"

$uuidFromWMI = Get-CimInstance -Query 'SELECT UUID FROM Win32_ComputerSystemProduct' | Select-Object -ExpandProperty UUID
$lastConfig = Get-ItemProperty -Path 'HKLM:\SYSTEM\HardwareConfig' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty LastConfig
if ($lastConfig)
{
    $uuidFromRegistry = $lastConfig.ToLower().Replace('{', '').Replace('}', '')
}

$vmId = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows Azure' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty VmId

$windowsAzureFolderPath = "$env:SystemDrive\WindowsAzure"

#Creates check for the c:\WindowsAzure folder exists and if it does then check for Guest Agent .exes
Out-Log "$windowsAzureFolderPath folder exists:" -startLine
if (Test-Path -Path $windowsAzureFolderPath -PathType Container)
{
    $windowsAzureFolderExists = $true
    Out-Log $windowsAzureFolderExists -color Green -endLine
    New-Check -name "$windowsAzureFolderPath folder exists" -result 'OK' -details ''
    $windowsAzureFolder = Invoke-ExpressionWithLogging "Get-ChildItem -Path $windowsAzureFolderPath -Recurse -ErrorAction SilentlyContinue" -verboseOnly
    #Creates check for WindowsAzureGuestAgent.exe existing
    Out-Log 'WindowsAzureGuestAgent.exe exists:' -startLine
    $windowsAzureGuestAgentExe = $windowsAzureFolder | Where-Object {$_.Name -eq 'WindowsAzureGuestAgent.exe'}
    if ($windowsAzureGuestAgentExe)
    {
        New-Check -name "WindowsAzureGuestAgent.exe exists in $windowsAzureFolderPath" -result 'OK' -details ''
        $windowsAzureGuestAgentExeExists = $true
        $windowsAzureGuestAgentExeFileVersion = $windowsAzureGuestAgentExe | Select-Object -ExpandProperty VersionInfo | Select-Object -ExpandProperty FileVersion
        Out-Log "$windowsAzureGuestAgentExeExists (version $windowsAzureGuestAgentExeFileVersion)" -color Green -endLine
    }
    else
    {
        New-Check -name "WindowsAzureGuestAgent.exe exists in $windowsAzureFolderPath" -result 'FAILED' -details ''
        $windowsAzureGuestAgentExe = $false
        Out-Log $windowsAzureGuestAgentExeExists -color Red -endLine
    }
    #Creates check for WaAppAgent.exe existing
    Out-Log 'WaAppAgent.exe exists:' -startLine
    $waAppAgentExe = $windowsAzureFolder | Where-Object {$_.Name -eq 'WaAppAgent.exe'}
    if ($waAppAgentExe)
    {
        New-Check -name "WaAppAgent.exe exists in $windowsAzureFolderPath" -result 'OK' -details ''
        $waAppAgentExeExists = $true
        $waAppAgentExeFileVersion = $waAppAgentExe | Select-Object -ExpandProperty VersionInfo | Select-Object -ExpandProperty FileVersion
        Out-Log "$waAppAgentExeExists (version $waAppAgentExeFileVersion)" -color Green -endLine
    }
    else
    {
        New-Check -name "WaAppAgent.exe exists in $windowsAzureFolderPath" -result 'FAILED' -details ''
        $waAppAgentExeExists = $false
        Out-Log $waAppAgentExeExists -color Red -endLine
    }
}
else
{
    $windowsAzureFolderExists = $false
    New-Check -name "$windowsAzureFolderPath folder exists" -result 'FAILED' -details ''
    Out-Log $windowsAzureFolderExists -color Red -endLine
}

Add-Type -TypeDefinition @'
using Microsoft.Win32.SafeHandles;
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;

namespace Win32.Service
{
    public static class Ext
    {
        [StructLayout(LayoutKind.Sequential)]
        public struct SERVICE_STATUS
        {
            public int ServiceType;
            public int CurrentState;
            public int ControlsAccepted;
            public int Win32ExitCode;
            public int ServiceSpecificExitCode;
            public int CheckPoint;
            public int WaitHint;
        }

        [DllImport("Advapi32.dll", EntryPoint = "QueryServiceStatus")]
        private static extern bool NativeQueryServiceStatus(
            SafeHandle hService,
            out SERVICE_STATUS lpServiceStatus);

        public static SERVICE_STATUS QueryServiceStatus(SafeHandle serviceHandle)
        {
            SERVICE_STATUS res;
            if (!NativeQueryServiceStatus(serviceHandle, out res))
            {
                throw new Win32Exception();
            }

            return res;
        }
    }
}
'@

$rdagent = Get-ServiceChecks -name 'RdAgent' -expectedStatus 'Running' -expectedStartType 'Automatic'
if ($rdagent)
{
    $rdAgentServiceExists = $true
}
$windowsAzureGuestAgent = Get-ServiceChecks -name 'WindowsAzureGuestAgent' -expectedStatus 'Running' -expectedStartType 'Automatic'
if ($windowsAzureGuestAgent)
{
    $windowsAzureGuestAgentServiceExists = $true
}

$winmgmt = Get-ServiceChecks -name 'Winmgmt' -expectedStatus 'Running' -expectedStartType 'Automatic'
$keyiso = Get-ServiceChecks -name 'Keyiso' -expectedStatus 'Running' -expectedStartType 'Manual'

Get-ServiceCrashes -Name 'RdAgent'
Get-ServiceCrashes -Name 'Windows Azure Guest Agent'
Get-ApplicationErrors -Name 'WaAppagent'
Get-ApplicationErrors -Name 'WindowsAzureGuestAgent'

# TODO: WS25+ no longer include WMIC.exe (<WS25 versions have it in C:\Windows\System32\wbem\WMIC.exe), so need to use a different approach here
# It can be installed as a feature-on-demand in WS25, but since it'll ultimately even that won't an option, but to address this now
# https://learn.microsoft.com/en-us/windows-server/get-started/removed-deprecated-features-windows-server-2025#features-were-no-longer-developing
if ($productName.Contains("2008") -or $productName.Contains("2012") -or $productName.Contains("2016") -or $productName.Contains("2019") -or $productName.Contains("2022")) {
    Out-Log 'StdRegProv WMI class:' -startLine
    if ($winmgmt.Status -eq 'Running')
    {
        if ($fakeFinding)
        {
            # Using intentionally wrong class name NOTStdRegProv in order to generate a finding on-demand without having to change any config
            $stdRegProv = Invoke-ExpressionWithLogging "wmic /namespace:\\root\default Class NOTStdRegProv Call GetDWORDValue hDefKey='&H80000002' sSubKeyName='SYSTEM\CurrentControlSet\Services\Winmgmt' sValueName=Start 2>`$null" -verboseOnly
        }
        else
        {
            $stdRegProv = Invoke-ExpressionWithLogging "wmic /namespace:\\root\default Class StdRegProv Call GetDWORDValue hDefKey='&H80000002' sSubKeyName='SYSTEM\CurrentControlSet\Services\Winmgmt' sValueName=Start 2>`$null" -verboseOnly
        }

        $wmicExitCode = $LASTEXITCODE
        if ($wmicExitCode -eq 0)
        {
            $stdRegProvQuerySuccess = $true
            Out-Log $stdRegProvQuerySuccess -color Green -endLine
            New-Check -name 'StdRegProv WMI class' -result 'OK' -details 'StdRegProv WMI class query succeeded'
        }
        else
        {
            $stdRegProvQuerySuccess = $false
            Out-Log $stdRegProvQuerySuccess -color Red -endLine
            New-Check -name 'StdRegProv WMI class' -result 'FAILED' -details ''
            $description = "StdRegProv WMI class query failed with error code $wmicExitCode"
            New-Finding -type Critical -name 'StdRegProv WMI class query failed' -description $description -mitigation ''
        }
    }
    else
    {
        $details = 'Skipped (Winmgmt service not running)'
        New-Check -name 'StdRegProv WMI class' -result 'Skipped' -details $details
        Out-Log $details -endLine
    }
}

#Check to see if the Guest Agent is installed by validating if the c:\WindowsAzure folder, rdagent service, windowsazureguestagent service, waappagent.exe, and windowsazureguestagent.exe exist. Returns $true if installed
Out-Log 'VM Agent installed:' -startLine

$detailsSuffix = "$windowsAzureFolderPath exists: $([bool]$windowsAzureFolder), WaAppAgent.exe in $($windowsAzureFolderPath): $([bool]$waAppAgentExe), WindowsAzureGuestAgent.exe in $($windowsAzureFolderPath): $([bool]$windowsAzureGuestAgentExe), RdAgent service installed: $([bool]$rdagent), WindowsAzureGuestAgent service installed: $([bool]$windowsAzureGuestAgent)"
if ([bool]$windowsAzureFolder -and [bool]$rdagent -and [bool]$windowsAzureGuestAgent -and [bool]$waAppAgentExe -and [bool]$windowsAzureGuestAgentExe)
{
    $isVMAgentInstalled = $true
    $details = "VM agent is installed ($detailsSuffix)"
    New-Check -name 'VM agent installed' -result 'OK' -details $details
    Out-Log $isVMAgentInstalled -color Green -endLine
}
else
{
    $isVMAgentInstalled = $false
    $details = "VM agent is not installed ($detailsSuffix)"
    New-Check -name 'VM agent installed' -result 'FAILED' -details $details
    Out-Log $isVMAgentInstalled -color Red -endLine
    New-Finding -type Critical -Name 'VM agent not installed' -description $details -mitigation '<a href="https://learn.microsoft.com/en-us/azure/virtual-machines/extensions/agent-windows#manual-installation">Install the VM Guest Agent</a>'
}

#Checks if the Guest Agent was installed by .MSI or at VM provisioning
if ($isVMAgentInstalled)
{
    Out-Log 'VM agent installed by provisioning agent or Windows Installer package (MSI):' -startLine
    $uninstallKeyPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
    $uninstallKey = Invoke-ExpressionWithLogging "Get-Item -Path '$uninstallKeyPath' -ErrorAction SilentlyContinue" -verboseOnly
    $agentUninstallKey = $uninstallkey.GetSubKeyNames() | ForEach-Object {Get-ItemProperty -Path $uninstallKeyPath\$_ | Where-Object {$_.Publisher -eq 'Microsoft Corporation' -and $_.DisplayName -match 'Windows Azure VM Agent'}}
    $agentUninstallKeyDisplayName = $agentUninstallKey.DisplayName
    $agentUninstallKeyDisplayVersion = $agentUninstallKey.DisplayVersion
    $agentUninstallKeyInstallDate = $agentUninstallKey.InstallDate

    if ($agentUninstallKey)
    {
        New-Check -name 'VM agent installed by MSI' -result 'OK' -details ''
        Out-Log 'MSI: MSI' -color Green -endLine
    }
    else
    {
        New-Check -name 'VM agent installed by provisioning agent' -result 'OK' -details ''
        Out-Log 'Provisioning agent' -color Green -endLine
    }
}

#Checks if the Guest Agent is at or above the minimum supported version
Out-Log 'VM agent is supported version:' -startLine
if ($isVMAgentInstalled)
{
    $guestKeyPath = 'HKLM:\SOFTWARE\Microsoft\Virtual Machine\Guest'
    $guestKey = Invoke-ExpressionWithLogging "Get-ItemProperty -Path '$guestKeyPath' -ErrorAction SilentlyContinue" -verboseOnly
    if ($guestKey)
    {
        $guestKeyDHCPStatus = $guestKey.DHCPStatus
        $guestKeyDhcpWithFabricAddressTime = $guestKey.DhcpWithFabricAddressTime
        $guestKeyGuestAgentStartTime = $guestKey.GuestAgentStartTime
        $guestKeyGuestAgentStatus = $guestKey.GuestAgentStatus
        $guestKeyGuestAgentVersion = $guestKey.GuestAgentVersion
        $guestKeyOsVersion = $guestKey.OsVersion
        $guestKeyRequiredDotNetVersionPresent = $guestKey.RequiredDotNetVersionPresent
        $guestKeyTransparentInstallerStartTime = $guestKey.TransparentInstallerStartTime
        $guestKeyTransparentInstallerStatus = $guestKey.TransparentInstallerStatus
        $guestKeyWireServerStatus = $guestKey.WireServerStatus

        $minSupportedGuestAgentVersion = '2.7.41491.1010'
        if ($guestKeyGuestAgentVersion -and [version]$guestKeyGuestAgentVersion -ge [version]$minSupportedGuestAgentVersion)
        {
            New-Check -name 'VM agent is supported version' -result 'OK' -details "Installed version: $guestKeyGuestAgentVersion, minimum supported version: $minSupportedGuestAgentVersion"
            $isAtLeastMinSupportedVersion = $true
            Out-Log "$isAtLeastMinSupportedVersion (installed: $guestKeyGuestAgentVersion, minimum supported: $minSupportedGuestAgentVersion)" -color Green -endLine
        }
        else
        {
            New-Check -name 'VM agent is supported version' -result 'FAILED' -details "Installed version: $guestKeyGuestAgentVersion, minimum supported version: $minSupportedGuestAgentVersion"
            Out-Log "$isAtLeastMinSupportedVersion (installed: $guestKeyGuestAgentVersion, minimum supported: $minSupportedGuestAgentVersion)" -color Red -endLine
        }
    }
}
else
{
    $details = "Skipped (VM agent installed: $isVMAgentInstalled)"
    New-Check -name 'VM agent is supported version' -result 'Skipped' -details $details
    $isAtLeastMinSupportedVersion = $false
    Out-Log $details -endLine
}

#Gathers information on the Guest Agent
if ($isVMAgentInstalled)
{
    $guestAgentKeyPath = 'HKLM:\SOFTWARE\Microsoft\GuestAgent'
    $guestAgentKey = Invoke-ExpressionWithLogging "Get-ItemProperty -Path '$guestAgentKeyPath' -ErrorAction SilentlyContinue" -verboseOnly
    if ($guestAgentKey)
    {
        $guestAgentKeyContainerId = $guestAgentKey.ContainerId
        $guestAgentKeyDirectoryToDelete = $guestAgentKey.DirectoryToDelete
        $guestAgentKeyHeartbeatLastStatusUpdateTime = $guestAgentKey.HeartbeatLastStatusUpdateTime
        $guestAgentKeyIncarnation = $guestAgentKey.Incarnation
        $guestAgentKeyInstallerRestart = $guestAgentKey.InstallerRestart
        $guestAgentKeyManifestTimeStamp = $guestAgentKey.ManifestTimeStamp
        $guestAgentKeyMetricsSelfSelectionSelected = $guestAgentKey.MetricsSelfSelectionSelected
        $guestAgentKeyUpdateNewGAVersion = $guestAgentKey.'Update-NewGAVersion'
        $guestAgentKeyUpdatePreviousGAVersion = $guestAgentKey.'Update-PreviousGAVersion'
        $guestAgentKeyUpdateStartTime = $guestAgentKey.'Update-StartTime'
        $guestAgentKeyVmProvisionedAt = $guestAgentKey.VmProvisionedAt
        if ($guestAgentKeyVmProvisionedAt)
        {
            $guestAgentKeyVmProvisionedAt = `Get-Date -Date $guestAgentKeyVmProvisionedAt -Format 'yyyy-MM-ddTHH:mm:ss'
        }
    }

    $vm.Add([PSCustomObject]@{Property = 'ContainerId'; Value = $guestAgentKeyContainerId; Type = 'Agent'})
    $vm.Add([PSCustomObject]@{Property = 'DirectoryToDelete'; Value = $guestAgentKeyDirectoryToDelete; Type = 'Agent'})
    $vm.Add([PSCustomObject]@{Property = 'HeartbeatLastStatusUpdateTime'; Value = $guestAgentKeyHeartbeatLastStatusUpdateTime; Type = 'Agent'})
    $vm.Add([PSCustomObject]@{Property = 'Incarnation'; Value = $guestAgentKeyIncarnation; Type = 'Agent'})
    $vm.Add([PSCustomObject]@{Property = 'InstallerRestart'; Value = $guestAgentKeyInstallerRestart; Type = 'Agent'})
    $vm.Add([PSCustomObject]@{Property = 'ManifestTimeStamp'; Value = $guestAgentKeyManifestTimeStamp; Type = 'Agent'})
    $vm.Add([PSCustomObject]@{Property = 'MetricsSelfSelectionSelected'; Value = $guestAgentKeyMetricsSelfSelectionSelected; Type = 'Agent'})
    $vm.Add([PSCustomObject]@{Property = 'UpdateNewGAVersion'; Value = $guestAgentKeyUpdateNewGAVersion; Type = 'Agent'})
    $vm.Add([PSCustomObject]@{Property = 'UpdatePreviousGAVersion'; Value = $guestAgentKeyUpdatePreviousGAVersion; Type = 'Agent'})
    $vm.Add([PSCustomObject]@{Property = 'UpdateStartTime'; Value = $guestAgentKeyUpdateStartTime; Type = 'Agent'})
    $vm.Add([PSCustomObject]@{Property = 'VmProvisionedAt'; Value = $guestAgentKeyVmProvisionedAt; Type = 'Agent'})

    $windowsAzureKeyPath = 'HKLM:\SOFTWARE\Microsoft\Windows Azure'
    $windowsAzureKey = Invoke-ExpressionWithLogging "Get-ItemProperty -Path '$windowsAzureKeyPath' -ErrorAction SilentlyContinue" -verboseOnly
    if ($windowsAzureKey)
    {
        $vmId = $windowsAzureKey.vmId
        if ($vmId)
        {
            $vmId = $vmId.ToLower()
        }
    }

    $guestAgentUpdateStateKeyPath = 'HKLM:\SOFTWARE\Microsoft\Windows Azure\GuestAgentUpdateState'
    $guestAgentUpdateStateKey = Invoke-ExpressionWithLogging "Get-Item -Path '$guestAgentUpdateStateKeyPath' -ErrorAction SilentlyContinue" -verboseOnly
    if ($guestAgentUpdateStateKey)
    {
        $guestAgentUpdateStateSubKeyName = $guestAgentUpdateStateKey.GetSubKeyNames() | Sort-Object {[Version]$_} | Select-Object -Last 1
        $guestAgentUpdateStateSubKey = Invoke-ExpressionWithLogging "Get-ItemProperty -Path '$guestAgentUpdateStateKeyPath\$guestAgentUpdateStateSubKeyName' -ErrorAction SilentlyContinue" -verboseOnly
        if ($guestAgentUpdateStateSubKey)
        {
            $guestAgentUpdateStateCode = $guestAgentUpdateStateSubKey.Code
            $guestAgentUpdateStateMessage = $guestAgentUpdateStateSubKey.Message
            $guestAgentUpdateStateState = $guestAgentUpdateStateSubKey.State
        }
    }

    $handlerStateKeyPath = 'HKLM:\SOFTWARE\Microsoft\Windows Azure\HandlerState'
    $handlerStateKey = Invoke-ExpressionWithLogging "Get-Item -Path '$handlerStateKeyPath' -ErrorAction SilentlyContinue" -verboseOnly
    if ($handlerStateKey)
    {
        $handlerNames = $handlerStateKey.GetSubKeyNames()
        if ($handlerNames)
        {
            $handlerStates = New-Object System.Collections.Generic.List[Object]
            foreach ($handlerName in $handlerNames)
            {
                $handlerState = Invoke-ExpressionWithLogging "Get-ItemProperty -Path '$handlerStateKeyPath\$handlerName' -ErrorAction SilentlyContinue" -verboseOnly
                if ($handlerState)
                {
                    $handlerStates.Add($handlerState)
                    $handlerState = $null
                }
            }
        }
    }
}

# The ProxyEnable key controls the proxy settings.
# 0 disables them, and 1 enables them.
# If you are using a proxy, you will get its value under the ProxyServer key.
# This gets the same settings as running "netsh winhttp show proxy"
$proxyConfigured = $false
Out-Log 'Proxy configured:' -startLine
$netshWinhttpShowProxyOutput = netsh winhttp show proxy
Out-Log "`$netshWinhttpShowProxyOutput: $netshWinhttpShowProxyOutput" -verboseOnly
$proxyServers = $netshWinhttpShowProxyOutput | Select-String -SimpleMatch 'Proxy Server(s)' | Select-Object -ExpandProperty Line
if ([string]::IsNullOrEmpty($proxyServers) -eq $false)
{
    $proxyServers = $proxyServers.Trim()
    Out-Log "`$proxyServers: $proxyServers" -verboseOnly
    Out-Log "`$proxyServers.Length: $($proxyServers.Length)" -verboseOnly
    Out-Log "`$proxyServers.GetType(): $($proxyServers.GetType())" -verboseOnly
}
$connectionsKeyPath = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Internet Settings\Connections'
$connectionsKey = Get-ItemProperty -Path $connectionsKeyPath -ErrorAction SilentlyContinue
$winHttpSettings = $connectionsKey | Select-Object -ExpandProperty WinHttpSettings -ErrorAction SilentlyContinue
$winHttpSettings = ($winHttpSettings | ForEach-Object {'{0:X2}' -f $_}) -join ''
# '1800000000000000010000000000000000000000' is the default if nothing was ever configured
# '2800000000000000010000000000000000000000' is the default after running "netsh winhttp reset proxy"
# So either of those equate to "Direct access (no proxy server)." being returned by "netsh winhttp show proxy"
$defaultWinHttpSettings = @('1800000000000000010000000000000000000000', '2800000000000000010000000000000000000000')
if ($winHttpSettings -notin $defaultWinHttpSettings)
{
    $proxyConfigured = $true
}

# [System.Net.WebProxy]::GetDefaultProxy() works on Windows PowerShell but not PowerShell Core
$defaultProxy = Invoke-ExpressionWithLogging '[System.Net.WebProxy]::GetDefaultProxy()' -verboseOnly
$defaultProxyAddress = $defaultProxy.Address
$defaultProxyBypassProxyOnLocal = $defaultProxy.BypassProxyOnLocal
$defaultProxyBypassList = $defaultProxy.BypassList
$defaultProxyCredentials = $defaultProxy.Credentials
$defaultProxyUseDefaultCredentials = $defaultProxy.UseDefaultCredentials
$defaultProxyBypassArrayList = $defaultProxy.BypassArrayList

if ($defaultProxyAddress)
{
    $proxyConfigured = $true
}
Out-Log "Address: $defaultProxyAddress" -verboseOnly
Out-Log "BypassProxyOnLocal: $defaultProxyBypassProxyOnLocal" -verboseOnly
Out-Log "BypassList: $defaultProxyBypassList" -verboseOnly
Out-Log "Credentials: $defaultProxyCredentials" -verboseOnly
Out-Log "UseDefaultCredentials: $defaultProxyUseDefaultCredentials" -verboseOnly
Out-Log "BypassArrayList: $defaultProxyBypassArrayList" -verboseOnly

<#
HTTP_PROXY  : proxy server used on HTTP requests.
HTTPS_PROXY : proxy server used on HTTPS requests.
ALL_PROXY   : proxy server used on HTTP and/or HTTPS requests in case HTTP_PROXY and/or HTTPS_PROXY are not defined.
NO_PROXY    : comma-separated list of hostnames that should be excluded from proxying.
#>
Out-Log 'Proxy environment variables:' -verboseOnly
Out-Log "HTTP_PROXY : $env:HTTP_PROXY" -verboseOnly
Out-Log "HTTPS_PROXY : $env:HTTP_PROXY" -verboseOnly
Out-Log "ALL_PROXY : $env:HTTP_PROXY" -verboseOnly
Out-Log "NO_PROXY : $env:HTTP_PROXY" -verboseOnly
if ($env:HTTP_PROXY -or $env:HTTPS_PROXY -or $env:ALL_PROXY)
{
    $proxyConfigured = $true
}

$userInternetSettingsKeyPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
$userInternetSettingsKey = Invoke-ExpressionWithLogging "Get-ItemProperty -Path $userInternetSettingsKeyPath -ErrorAction SilentlyContinue" -verboseOnly
$userProxyEnable = $userInternetSettingsKey | Select-Object -ExpandProperty ProxyEnable -ErrorAction SilentlyContinue
$userProxyServer = $userInternetSettingsKey | Select-Object -ExpandProperty ProxyServer -ErrorAction SilentlyContinue
$userProxyOverride = $userInternetSettingsKey | Select-Object -ExpandProperty ProxyOverride -ErrorAction SilentlyContinue
$userAutoDetect = $userInternetSettingsKey | Select-Object -ExpandProperty AutoDetect -ErrorAction SilentlyContinue
Out-Log "$userInternetSettingsKeyPath\ProxyEnable: $userProxyEnable" -verboseOnly
Out-Log "$userInternetSettingsKeyPath\ProxyServer: $userProxyServer" -verboseOnly
Out-Log "$userInternetSettingsKeyPath\ProxyOverride: $userProxyOverride" -verboseOnly
Out-Log "$userInternetSettingsKeyPath\AutoDetect: $userAutoDetect" -verboseOnly
if ($userProxyEnable -and $userProxyServer)
{
    $proxyConfigured = $true
}

$machineInternetSettingsKeyPath = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
$machineInternetSettingsKey = Invoke-ExpressionWithLogging "Get-ItemProperty -Path $machineInternetSettingsKeyPath -ErrorAction SilentlyContinue" -verboseOnly
$machineProxyEnable = $machineInternetSettingsKey | Select-Object -ExpandProperty ProxyEnable -ErrorAction SilentlyContinue
$machineProxyServer = $machineInternetSettingsKey | Select-Object -ExpandProperty ProxyServer -ErrorAction SilentlyContinue
$machineProxyOverride = $machineInternetSettingsKey | Select-Object -ExpandProperty ProxyOverride -ErrorAction SilentlyContinue
$machineAutoDetect = $machineInternetSettingsKey | Select-Object -ExpandProperty AutoDetect -ErrorAction SilentlyContinue
Out-Log "$machineInternetSettingsKeyPath\ProxyEnable: $machineProxyEnable" -verboseOnly
Out-Log "$machineInternetSettingsKeyPath\ProxyServer: $machineProxyServer" -verboseOnly
Out-Log "$machineInternetSettingsKeyPath\ProxyOverride: $machineProxyOverride" -verboseOnly
Out-Log "$machineInternetSettingsKeyPath\Autodetect: $machineAutoDetect" -verboseOnly
if ($machineProxyEnable -and $machineProxyServer)
{
    $proxyConfigured = $true
}

$machinePoliciesInternetSettingsKeyPath = 'HKLM:\Software\Policies\Microsoft\Windows\CurrentVersion\Internet Settings'
$machinePoliciesInternetSettingsKey = Invoke-ExpressionWithLogging "Get-ItemProperty -Path $machinePoliciesInternetSettingsKeyPath -ErrorAction SilentlyContinue" -verboseOnly
$proxySettingsPerUser = $machinePoliciesInternetSettingsKey | Select-Object -ExpandProperty ProxySettingsPerUser -ErrorAction SilentlyContinue
Out-Log "$machinePoliciesInternetSettingsKeyPath\ProxySettingsPerUser: $proxySettingsPerUser" -verboseOnly

if ($proxyConfigured)
{
    New-Check -name 'Proxy configured' -result 'Info' -details $proxyServers
    Out-Log $proxyConfigured -color Cyan -endLine
    $mitigation = '<a href="https://learn.microsoft.com/en-us/troubleshoot/azure/virtual-machines/windows-azure-guest-agent#solution-3-enable-dhcp-and-make-sure-that-the-server-isnt-blocked-by-firewalls-proxies-or-other-sources">Ensure the proxy is not blocking connectivity to 168.63.129.16 on ports 80 or 32526</a>'
    New-Finding -type Information -name 'Proxy configured' -description $proxyServers -mitigation $mitigation
}
else
{
    New-Check -name 'Proxy configured' -result 'OK' -details 'No proxy detected'
    Out-Log $proxyConfigured -color Green -endLine
}

#Checks for the CRP certificate
Out-Log 'TenantEncryptionCert installed:' -startLine
if ($isVMAgentInstalled)
{
    $tenantEncryptionCerts = Get-ChildItem -Path 'Cert:\LocalMachine\My' | Where-Object {$_.FriendlyName -eq 'TenantEncryptionCert' -and $_.Issuer -eq 'DC=Windows Azure CRP Certificate Generator' -and $_.Subject -eq 'DC=Windows Azure CRP Certificate Generator'}
    # Only consider the newest tenant encryption cert if multiple found (which can happen)
    $tenantEncryptionCert = $tenantEncryptionCerts | Sort-Object NotBefore | Select-Object -Last 1
    if ($tenantEncryptionCert)
    {
        $tenantEncryptionCertInstalled = $true
        Out-Log $tenantEncryptionCertInstalled -color Green -endLine
        $subject = $tenantEncryptionCert.Subject
        $issuer = $tenantEncryptionCert.Issuer
        $effective = Get-Date -Date $tenantEncryptionCert.NotBefore.ToUniversalTime() -Format 'yyyy-MM-ddTHH:mm:ssZ'
        $expires = Get-Date -Date $tenantEncryptionCert.NotAfter.ToUniversalTime() -Format 'yyyy-MM-ddTHH:mm:ssZ'
        $now = Get-Date -Date (Get-Date).ToUniversalTime() -Format 'yyyy-MM-ddTHH:mm:ssZ'
        New-Check -name 'TenantEncryptionCert installed' -result 'OK' -details "Subject: $subject Issuer: $issuer"

        Out-Log 'TenantEncryptionCert within validity period:' -startLine
        if ($tenantEncryptionCert.NotBefore -le [System.DateTime]::Now -and $tenantEncryptionCert.NotAfter -gt [System.DateTime]::Now)
        {
            $tenantEncryptionCertWithinValidityPeriod = $true
            Out-Log $tenantEncryptionCertWithinValidityPeriod -color Green -endLine
            New-Check -name 'TenantEncryptionCert within validity period' -result 'OK' -details "Now: $now Effective: $effective Expires: $expires"
        }
        else
        {
            $tenantEncryptionCertWithinValidityPeriod = $false
            Out-Log $tenantEncryptionCertWithinValidityPeriod -color Red -endLine
            New-Check -name 'TenantEncryptionCert within validity period' -result 'FAILED' -details "Now: $now Effective: $effective Expires: $expires"
            New-Finding -type Critical -name 'TenantEncryptionCert not within validity period' -description "Now: $now Effective: $effective Expires: $expires" -mitigation '<a href="https://learn.microsoft.com/en-us/troubleshoot/azure/virtual-machines/windows/troubleshoot-extension-certificates-issues-windows-vm#solution-1-update-the-extension-certificate">Update the extension certificate</a>'
        }
    }
    else
    {
        New-Check -name 'TenantEncryptionCert installed' -result 'FAILED' -details ''
        New-Finding -type Critical -name 'TenantEncryptionCert not installed' -description '' -mitigation '<a href="https://learn.microsoft.com/en-us/troubleshoot/azure/virtual-machines/windows/troubleshoot-extension-certificates-issues-windows-vm#troubleshooting-checklist">Troubleshoot the extension certificate</a>'
        Out-Log $false -color Red -endLine
    }
}
else
{
    $details = "Skipped (VM agent installed: $isVMAgentInstalled)"
    New-Check -name 'TenantEncryptionCert installed' -result 'Skipped' -details $details
    Out-Log $details -endLine
}

Get-WCFConfig

# wireserver doesn't listen on 8080 even though it creates a BFE filter for it
# Test-NetConnection -ComputerName 168.63.129.16 -Port 80 -InformationLevel Quiet -WarningAction SilentlyContinue
# Test-NetConnection -ComputerName 168.63.129.16 -Port 32526 -InformationLevel Quiet -WarningAction SilentlyContinue
# Test-NetConnection -ComputerName 169.254.169.254 -Port 80 -InformationLevel Quiet -WarningAction SilentlyContinue
Out-Log 'Wireserver endpoint 168.63.129.16:80 reachable:' -startLine
$wireserverPort80Reachable = Test-Port -ipAddress '168.63.129.16' -port 80 -timeout 1000
$description = "Wireserver endpoint 168.63.129.16:80 reachable: $($wireserverPort80Reachable.Succeeded) $($wireserverPort80Reachable.Error)"
$mitigation = '<a href="https://learn.microsoft.com/en-us/azure/virtual-network/what-is-ip-address-168-63-129-16">Ensure that there is network connectivity to 168.63.129.16 on ports 80 and 32526.</a>'
if ($wireserverPort80Reachable.Succeeded)
{
    New-Check -name 'Wireserver endpoint 168.63.129.16:80 reachable' -result 'OK' -details 'Successfully connected to 168.63.129.16:80'
    Out-Log "$($wireserverPort80Reachable.Succeeded) $($wireserverPort80Reachable.Error)" -color Green -endLine
}
else
{
    New-Check -name 'Wireserver endpoint 168.63.129.16:80 reachable' -result 'FAILED' -details $($wireserverPort80Reachable.Error)
    Out-Log "$($wireserverPort80Reachable.Succeeded)" -color Red -endLine
    New-Finding -type Critical -name 'Wireserver endpoint 168.63.129.16:80 not reachable' -description $description -mitigation $mitigation
}

Out-Log 'Wireserver endpoint 168.63.129.16:32526 reachable:' -startLine
$wireserverPort32526Reachable = Test-Port -ipAddress '168.63.129.16' -port 32526 -timeout 1000
$description = "Wireserver endpoint 168.63.129.16:32526 reachable: $($wireserverPort32526Reachable.Succeeded) $($wireserverPort32526Reachable.Error)"
if ($wireserverPort32526Reachable.Succeeded)
{
    New-Check -name 'Wireserver endpoint 168.63.129.16:32526 reachable' -result 'OK' -details 'Successfully connected to 168.63.129.16:32526'
    Out-Log $wireserverPort32526Reachable.Succeeded -color Green -endLine
}
else
{
    New-Check -name 'Wireserver endpoint 168.63.129.16:32526 reachable' -result 'FAILED' -details $($wireserverPort32526Reachable.Error)
    Out-Log "$($wireserverPort32526Reachable.Succeeded)" -color Red -endLine
    New-Finding -type Critical -name 'Wireserver endpoint 168.63.129.16:32526 not reachable' -description $description -mitigation $mitigation
}

Out-Log 'Wireserver endpoint http://168.63.129.16/?comp=versions reachable:' -startLine
try {
    $exception = $null
    $wireRest = Invoke-RestMethod -Headers @{"Metadata"="true"} -Method GET -Uri http://168.63.129.16/?comp=versions 
}
catch {
    $exception = $_.Exception.InnerException.Message.ToString()
}

if(!$exception)
{
    New-Check -name 'Wireserver endpoint http://168.63.129.16/?comp=versions reachable' -result 'OK' -details 'Successfully connected to http://168.63.129.16/?comp=versions'
    Out-Log $true -color Green -endLine
}
else
{
    New-Check -name 'Wireserver endpoint http://168.63.129.16/?comp=versions not reachable' -result 'FAILED' -details $exception
    Out-Log $false -color Red -endLine
    New-Finding -type Critical -name 'Wireserver endpoint http://168.63.129.16/?comp=versions not reachable' -description $exception -mitigation $mitigation
}

Out-Log 'IMDS endpoint 169.254.169.254:80 reachable:' -startLine
$imdsReachable = Test-Port -ipAddress '169.254.169.254' -port 80 -timeout 1000
$description = "IMDS endpoint 169.254.169.254:80 reachable: $($imdsReachable.Succeeded) $($imdsReachable.Error)"
if ($imdsReachable.Succeeded)
{
    New-Check -name 'IMDS endpoint 169.254.169.254:80 reachable' -result 'OK' -details 'Successfully connected to 169.254.169.254:80'
    Out-Log $imdsReachable.Succeeded -color Green -endLine
}
else
{
    New-Check -name 'IMDS endpoint 169.254.169.254:80 reachable' -result 'FAILED' -details $($imdsReachable.Error)
    Out-Log "$($imdsReachable.Succeeded) $($imdsReachable.Error)" -color Red -endLine
    New-Finding -type Information -name 'IMDS endpoint 169.254.169.254:80 not reachable' -description $description -mitigation '<a href="https://learn.microsoft.com/en-us/azure/virtual-machines/instance-metadata-service">Ensure that there is network connectivity to 169.254.169.254 (IMDS) on port 80.</a>'
    }

#Gathers VM data from IMDS
if ($imdsReachable.Succeeded)
{
    Out-Log "IMDS endpoint http://169.254.169.254/metadata/instance returned expected result:" -startLine
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor 3072
    # Below three lines have it use a null proxy, bypassing any configured proxy
    # See also https://github.com/microsoft/azureimds/blob/master/IMDSSample.ps1
    $proxy = New-Object System.Net.WebProxy
    $webSession = New-Object Microsoft.PowerShell.Commands.WebRequestSession
    $webSession.Proxy = $proxy
    $apiVersions = Invoke-RestMethod -Headers @{'Metadata' = 'true'} -Method GET -Uri 'http://169.254.169.254/metadata/versions' -WebSession $webSession | Select-Object -ExpandProperty apiVersions
    $apiVersion = $apiVersions | Select-Object -Last 1
    $metadata = Invoke-RestMethod -Headers @{'Metadata' = 'true'} -Method GET -Uri "http://169.254.169.254/metadata/instance?api-version=$apiVersion" -WebSession $webSession
    $compute = $metadata | Select-Object -ExpandProperty compute -ErrorAction SilentlyContinue

    if ($compute)
    {
        $imdReturnedExpectedResult = $true
        Out-Log $imdReturnedExpectedResult -color Green -endLine
        New-Check -name 'IMDS endpoint http://169.254.169.254/metadata/instance' -result 'OK' -details "http://169.254.169.254/metadata/instance?api-version=$apiVersion returned expected result"

        $global:dbgMetadata = $metadata

        $azEnvironment = $metadata.compute.azEnvironment
        $vmName = $metadata.compute.name
        $vmId = $metadata.compute.vmId
        $resourceId = $metadata.compute.resourceId
        $licenseType = $metadata.compute.licenseType
        $planPublisher = $metadata.compute.plan.publisher
        $planProduct = $metadata.compute.plan.product
        $planName = $metadata.compute.plan.name
        $osDiskDiskSizeGB = $metadata.compute.storageProfile.osDisk.diskSizeGB
        $osDiskManagedDiskId = $metadata.compute.storageProfile.osDisk.managedDisk.id
        $osDiskManagedDiskStorageAccountType = $metadata.compute.storageProfile.osDisk.managedDisk.storageAccountType
        $osDiskCreateOption = $metadata.compute.storageProfile.osDisk.createOption
        $osDiskCaching = $metadata.compute.storageProfile.osDisk.caching
        $osDiskDiffDiskSettingsOption = $metadata.compute.storageProfile.osDisk.diffDiskSettings.option
        $osDiskEncryptionSettingsEnabled = $metadata.compute.storageProfile.osDisk.encryptionSettings.enabled
        $osDiskImageUri = $metadata.compute.storageProfile.osDisk.image.uri
        $osDiskName = $metadata.compute.storageProfile.osDisk.name
        $osDiskOsType = $metadata.compute.storageProfile.osDisk.osType
        $osDiskVhdUri = $metadata.compute.storageProfile.osDisk.vhd.uri
        $osDiskWriteAcceleratorEnabled = $metadata.compute.storageProfile.osDisk.writeAcceleratorEnabled
        $encryptionAtHost = $metadata.compute.securityProfile.encryptionAtHost
        $secureBootEnabled = $metadata.compute.securityProfile.secureBootEnabled
        $securityType = $metadata.compute.securityProfile.securityType
        $virtualTpmEnabled = $metadata.compute.securityProfile.virtualTpmEnabled
        $virtualMachineScaleSetId = $metadata.compute.virtualMachineScaleSet.id
        $vmScaleSetName = $metadata.compute.vmScaleSetName
        $zone = $metadata.compute.zone
        $dataDisks = $metadata.compute.storageProfile.dataDisks
        $priority = $metadata.compute.priority
        $platformFaultDomain = $metadata.compute.platformFaultDomain
        $platformSubFaultDomain = $metadata.compute.platformSubFaultDomain
        $platformUpdateDomain = $metadata.compute.platformUpdateDomain
        $placementGroupId = $metadata.compute.placementGroupId
        $extendedLocationName = $metadata.compute.extendedLocationName
        $extendedLocationType = $metadata.compute.extendedLocationType
        $evictionPolicy = $metadata.compute.evictionPolicy
        $hostId = $metadata.compute.hostId
        $hostGroupId = $metadata.compute.hostGroupId
        $isHostCompatibilityLayerVm = $metadata.compute.isHostCompatibilityLayerVm
        $hibernationEnabled = $metadata.compute.additionalCapabilities.hibernationEnabled
        $subscriptionId = $metadata.compute.subscriptionId
        $resourceGroupName = $metadata.compute.resourceGroupName
        $location = $metadata.compute.location
        $vmSize = $metadata.compute.vmSize
        $vmIdFromImds = $metadata.compute.vmId
        $publisher = $metadata.compute.publisher
        $offer = $metadata.compute.offer
        $sku = $metadata.compute.sku
        $version = $metadata.compute.version
        $imageReferenceId = $metadata.compute.storageProfile.imageReference.id
        if ($publisher)
        {
            $imageReference = "$publisher|$offer|$sku|$version"
        }
        else
        {
            if ($imageReferenceId)
            {
                $imageReference = "$($imageReferenceId.Split('/')[-1]) (custom image)"
            }
        }
        $interfaces = $metadata.network.interface
        $macAddress = $metadata.network.interface.macAddress
        $privateIpAddress = $metadata.network.interface | Select-Object -First 1 | Select-Object -ExpandProperty ipv4 -First 1 | Select-Object -ExpandProperty ipAddress -First 1 | Select-Object -ExpandProperty privateIpAddress -First 1
        $publicIpAddress = $metadata.network.interface | Select-Object -First 1 | Select-Object -ExpandProperty ipv4 -First 1 | Select-Object -ExpandProperty ipAddress -First 1 | Select-Object -ExpandProperty publicIpAddress -First 1
        $publicIpAddressReportedFromAwsCheckIpService = Invoke-RestMethod -Uri https://checkip.amazonaws.com -WebSession $webSession
        if ($publicIpAddressReportedFromAwsCheckIpService)
        {
            $publicIpAddressReportedFromAwsCheckIpService = $publicIpAddressReportedFromAwsCheckIpService.Trim()
        }
    }
    else
    {
        $imdReturnedExpectedResult = $false
        Out-Log $imdReturnedExpectedResult -color Red -endLine
        New-Check -name 'IMDS endpoint 169.254.169.254:80 returned expected result' -result 'FAILED' -details ''
    }
}

#If Guest Agent is installed and can reach the wireserver then gather data from aggregateStatus.json and from the goalState
if ($wireserverPort80Reachable.Succeeded -and $wireserverPort32526Reachable.Succeeded -and $isVMAgentInstalled)
{
    Out-Log 'Getting status from aggregatestatus.json' -verboseOnly
    $aggregateStatusJsonFilePath = $windowsAzureFolder | Where-Object {$_.Name -eq 'aggregatestatus.json'} | Select-Object -ExpandProperty FullName
    $aggregateStatus = Get-Content -Path $aggregateStatusJsonFilePath
    $aggregateStatus = $aggregateStatus -replace '\0' | ConvertFrom-Json

    $aggregateStatusGuestAgentStatusVersion = $aggregateStatus.aggregateStatus.guestAgentStatus.version
    $aggregateStatusGuestAgentStatusStatus = $aggregateStatus.aggregateStatus.guestAgentStatus.status
    $aggregateStatusGuestAgentStatusMessage = $aggregateStatus.aggregateStatus.guestAgentStatus.formattedMessage.message
    $aggregateStatusGuestAgentStatusLastStatusUploadMethod = $aggregateStatus.aggregateStatus.guestAgentStatus.lastStatusUploadMethod
    $aggregateStatusGuestAgentStatusLastStatusUploadTime = $aggregateStatus.aggregateStatus.guestAgentStatus.lastStatusUploadTime

    Out-Log "Version: $aggregateStatusGuestAgentStatusVersion" -verboseOnly
    Out-Log "Status: $aggregateStatusGuestAgentStatusStatus" -verboseOnly
    Out-Log "Message: $aggregateStatusGuestAgentStatusMessage" -verboseOnly
    Out-Log "LastStatusUploadMethod: $aggregateStatusGuestAgentStatusLastStatusUploadMethod" -verboseOnly
    Out-Log "LastStatusUploadTime: $aggregateStatusGuestAgentStatusLastStatusUploadTime" -verboseOnly

    $headers = @{'x-ms-version' = '2012-11-30'}
    $proxy = New-Object System.Net.WebProxy
    $webSession = New-Object Microsoft.PowerShell.Commands.WebRequestSession
    $webSession.Proxy = $proxy

    $goalState = Invoke-RestMethod -Method GET -Uri 'http://168.63.129.16/machine?comp=goalstate' -Headers $headers -WebSession $webSession | Select-Object -ExpandProperty GoalState

    $hostingEnvironmentConfigUri = $goalState.Container.RoleInstanceList.RoleInstance.Configuration.HostingEnvironmentConfig
    $sharedConfigUri = $goalState.Container.RoleInstanceList.RoleInstance.Configuration.SharedConfig
    $extensionsConfigUri = $goalState.Container.RoleInstanceList.RoleInstance.Configuration.ExtensionsConfig
    $fullConfigUri = $goalState.Container.RoleInstanceList.RoleInstance.Configuration.FullConfig
    $certificatesUri = $goalState.Container.RoleInstanceList.RoleInstance.Configuration.Certificates
    $configName = $goalState.Container.RoleInstanceList.RoleInstance.Configuration.ConfigName

    $hostingEnvironmentConfig = Invoke-RestMethod -Method GET -Uri $hostingEnvironmentConfigUri -Headers $headers -WebSession $webSession | Select-Object -ExpandProperty HostingEnvironmentConfig
    $sharedConfig = Invoke-RestMethod -Method GET -Uri $sharedConfigUri -Headers $headers -WebSession $webSession | Select-Object -ExpandProperty SharedConfig
    $extensions = Invoke-RestMethod -Method GET -Uri $extensionsConfigUri -Headers $headers -WebSession $webSession | Select-Object -ExpandProperty Extensions
    $rdConfig = Invoke-RestMethod -Method GET -Uri $fullConfigUri -Headers $headers -WebSession $webSession | Select-Object -ExpandProperty RDConfig
    $storedCertificate = $rdConfig.StoredCertificates.StoredCertificate | Where-Object {$_.name -eq 'TenantEncryptionCert'}
    $tenantEncryptionCertThumbprint = $storedCertificate.certificateId -split ':' | Select-Object -Last 1
    $tenantEncryptionCert = Get-ChildItem -Path Cert:\LocalMachine\My | Where-Object {$_.Thumbprint -eq $tenantEncryptionCertThumbprint}

    $statusUploadBlobUri = $extensions.StatusUploadBlob.'#text'
    $inVMGoalStateMetaData = $extensions.InVMGoalStateMetaData
}

#Checks if 3rd party modules are loaded in Guest Agent processes
if ($isVMAgentInstalled)
{
    Get-ThirdPartyLoadedModules -processName 'WaAppAgent'
    Get-ThirdPartyLoadedModules -processName 'WindowsAzureGuestAgent'
}

#Gets firewall rules/wfp filters
if ($skipFirewall -eq $false)
{
    $enabledFirewallRules = Get-EnabledFirewallRules
}
if ($showFilters -eq $true)
{
    $wfpFilters = Get-WfpFilters
}

#Validates permissions on the MachineKeys folder
$machineKeysDefaultSddl = 'O:SYG:SYD:PAI(A;;0x12019f;;;WD)(A;;FA;;;BA)'
Out-Log 'MachineKeys folder has default permissions:' -startLine
$machineKeysPath = 'C:\ProgramData\Microsoft\Crypto\RSA\MachineKeys'
$machineKeysAcl = Get-Acl -Path $machineKeysPath
$machineKeysSddl = $machineKeysAcl | Select-Object -ExpandProperty Sddl
$machineKeysAccess = $machineKeysAcl | Select-Object -ExpandProperty Access
$machineKeysAccessString = $machineKeysAccess | ForEach-Object {"$($_.IdentityReference) $($_.AccessControlType) $($_.FileSystemRights)"}
$machineKeysAccessString = $machineKeysAccessString -join '<br>'

if ($machineKeysSddl -eq $machineKeysDefaultSddl)
{
    $machineKeysHasDefaultPermissions = $true
    Out-Log $machineKeysHasDefaultPermissions -color Green -endLine
    $details = "$machineKeysPath folder has default NTFS permissions" # <br>SDDL: $machineKeysSddl<br>$machineKeysAccessString"
    New-Check -name 'MachineKeys folder permissions' -result 'OK' -details $details
}
else
{
    $machineKeysHasDefaultPermissions = $false
    Out-Log $machineKeysHasDefaultPermissions -color Cyan -endLine
    $details = "$machineKeysPath folder does not have default NTFS permissions<br>SDDL: $machineKeysSddl<br>$machineKeysAccessString"
    New-Check -name 'MachineKeys folder permissions' -result 'Info' -details $details
    $mitigation = '<a href="https://learn.microsoft.com/en-us/troubleshoot/azure/virtual-machines/troubleshoot-extension-certificates-issues-windows-vm#solution-2-fix-the-access-control-list-acl-in-the-machinekeys-or-systemkeys-folders">Troubleshoot extension certificates</a>'
    New-Finding -type Information -name 'Non-default MachineKeys permissions' -description $details -mitigation $mitigation
}

# Permissions on $env:SystemDrive\WindowsAzure and $env:SystemDrive\Packages folder during startup.
# It first removes all user/groups and then sets the following permission
# (Read & Execute: Everyone, Full Control: SYSTEM & Local Administrators only) to these folders.
# If GA fails to remove/set the permission, it can't proceed further.
Out-Log "$windowsAzureFolderPath folder has default permissions:" -startLine
if ($isVMAgentInstalled)
{
    $windowsAzureDefaultSddl = 'O:SYG:SYD:PAI(A;OICI;0x1200a9;;;WD)(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)'
    $windowsAzureAcl = Get-Acl -Path $windowsAzureFolderPath
    $windowsAzureSddl = $windowsAzureAcl | Select-Object -ExpandProperty Sddl
    $windowsAzureAccess = $windowsAzureAcl | Select-Object -ExpandProperty Access
    $windowsAzureAccessString = $windowsAzureAccess | ForEach-Object {"$($_.IdentityReference) $($_.AccessControlType) $($_.FileSystemRights)"}
    $windowsAzureAccessString = $windowsAzureAccessString -join '<br>'
    if ($windowsAzureSddl -eq $windowsAzureDefaultSddl)
    {
        $windowsAzureHasDefaultPermissions = $true
        Out-Log $windowsAzureHasDefaultPermissions -color Green -endLine
        $details = "$windowsAzureFolderPath folder has default NTFS permissions" # <br>SDDL: $windowsAzureSddl<br>$windowsAzureAccessString"
        New-Check -name "$windowsAzureFolderPath permissions" -result 'OK' -details $details
    }
    else
    {
        $windowsAzureHasDefaultPermissions = $false
        Out-Log $windowsAzureHasDefaultPermissions -color Cyan -endLine
        $details = "$windowsAzureFolderPath does not have default NTFS permissions<br>SDDL: $windowsAzureSddl<br>$windowsAzureAccessString"
        New-Check -name "$windowsAzureFolderPath permissions" -result 'Info' -details $details
        New-Finding -type Information -name "Non-default $windowsAzureFolderPath permissions" -description $details -mitigation 'The C:\WindowsAzure directory has been changed from its default permissions. Ensure the built-in System account has Full control to this folder, subfolder, and directories in order for the Guest Agent to work properly.'
    }
}
else
{
    $details = "Skipped (VM agent installed: $isVMAgentInstalled)"
    New-Check -name "$windowsAzureFolderPath permissions" -result 'Skipped' -details $details
    Out-Log $details -endLine
}

#Validates permissions on the Packages folder
$packagesFolderPath = "$env:SystemDrive\Packages"
Out-Log "$packagesFolderPath folder has default permissions:" -startLine
if ($isVMAgentInstalled)
{
    $packagesDefaultSddl = 'O:BAG:SYD:P(A;OICI;0x1200a9;;;WD)(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)'
    $packagesAcl = Get-Acl -Path $packagesFolderPath
    $packagesSddl = $packagesAcl | Select-Object -ExpandProperty Sddl
    $packagesAccess = $packagesAcl | Select-Object -ExpandProperty Access
    $packagessAccessString = $packagesAccess | ForEach-Object {"$($_.IdentityReference) $($_.AccessControlType) $($_.FileSystemRights)"}
    $packagesAccessString = $packagessAccessString -join '<br>'
    if ($packagesSddl -eq $packagesDefaultSddl)
    {
        $packagesHasDefaultPermissions = $true
        Out-Log $packagesHasDefaultPermissions -color Green -endLine
        $details = "$packagesFolderPath folder has default NTFS permissions" # <br>SDDL: $packagesSddl<br>$packagesAccessString"
        New-Check -name "$packagesFolderPath permissions" -result 'OK' -details $details
    }
    else
    {
        $packagesHasDefaultPermissions = $false
        Out-Log $packagesHasDefaultPermissions -color Cyan -endLine
        $details = "$packagesFolderPath does not have default NTFS permissions<br>SDDL: $packagesSddl<br>$packagesAccessString"
        New-Check -name "$packagesFolderPath permissions" -result 'Info' -details $details
        New-Finding -type Information -name "Non-default $packagesFolderPath permissions" -description $details -mitigation 'The C:\Packages directory has been changed from its default permissions. Ensure the built-in System account has Full control to this folder, subfolder, and directories in order for the Guest Agent to work properly.'
    }
}
else
{
    $details = "Skipped (VM agent installed: $isVMAgentInstalled)"
    New-Check -name "$packagesFolderPath permissions" -result 'Skipped' -details $details
    Out-Log $details -endLine
}

#Validates that there is enough free space on the OS disk
Out-Log 'System drive has sufficient disk space:' -startLine
$systemDriveLetter = "$env:SystemDrive" -split ':' | Select-Object -First 1
$systemDrive = Invoke-ExpressionWithLogging "Get-PSDrive -Name $systemDriveLetter" -verboseOnly
# "Get-PSDrive" doesn't call WMI but Free and Used properties are of type ScriptProperty,
# and make WMI calls when you view them.
$systemDriveFreeSpaceBytes = $systemDrive | Select-Object -ExpandProperty Free -ErrorAction SilentlyContinue
if ($systemDriveFreeSpaceBytes)
{
    $systemDriveFreeSpaceGB = [Math]::Round($systemDriveFreeSpaceBytes / 1GB, 1)
    $systemDriveFreeSpaceMB = [Math]::Round($systemDriveFreeSpaceBytes / 1MB, 1)

    if ($systemDriveFreeSpaceMB -lt 100)
    {
        $details = "<100MB free ($($systemDriveFreeSpaceMB)MB free) on drive $systemDriveLetter"
        Out-Log $false -color Red -endLine
        New-Check -name 'Disk space check (<1GB Warn, <100MB Critical)' -result 'FAILED' -details $details
        New-Finding -type Critical -name 'System drive low disk space' -description $details -mitigation 'You have <100MB of disk space remaining on your system drive. If you run out of disk space there can be unexpected failures if the OS or applications are no longer able to write to files. Please either free up space or <a href="https://learn.microsoft.com/en-us/azure/virtual-machines/windows/expand-disks">expand the drive</a>'
    }
    elseif ($systemDriveFreeSpaceGB -lt 1)
    {
        $details = "<1GB free ($($systemDriveFreeSpaceGB)GB free) on drive $systemDriveLetter"
        Out-Log $details -color Yellow -endLine
        New-Check -name 'Disk space check (<1GB Warn, <100MB Critical)' -result 'Warning' -details $details
        New-Finding -type Warning -name 'System drive low free space' -description $details -mitigation 'You have <1GB of disk space remaining on your system drive. If you run out of disk space there can be unexpected failures if the OS or applications are no longer able to write to files. Please consider either freeing up space or <a href="https://learn.microsoft.com/en-us/azure/virtual-machines/windows/expand-disks">expand the drive</a>'
    }
    else
    {
        $details = "$($systemDriveFreeSpaceGB)GB free on system drive $systemDriveLetter"
        Out-Log $details -color Green -endLine
        New-Check -name 'Disk space check (<1GB Warn, <100MB Critical)' -result 'OK' -details $details
    }
}
else
{
    $details = "Unable to determine free space on system drive $systemDriveLetter"
    Out-Log $details -color Cyan -endLine
    New-Check -name 'Disk space check (<1GB Warn, <100MB Critical)' -result 'Info' -details $details
    New-Finding -type Warning -name 'System drive low free space' -description $details -mitigation 'We were unable to determine how much free space is on your system drive. Please ensure that the system drive has available free space.'
}

$joinInfo = Get-JoinInfo
$joinType = $joinInfo.JoinType
$role = $joinInfo.Role

if ($winmgmt.Status -eq 'Running')
{
    $drivers = Get-Drivers
}

$scriptStartTimeLocalString = Get-Date -Date $scriptStartTime -Format o
$scriptStartTimeUTCString = Get-Date -Date $scriptStartTime -Format o

$scriptEndTime = Get-Date
$scriptEndTimeLocalString = Get-Date -Date $scriptEndTime -Format o
$scriptEndTimeUTCString = Get-Date -Date $scriptEndTime -Format 'yyyy-MM-ddTHH:mm:ssZ'

$scriptTimespan = New-TimeSpan -Start $scriptStartTime -End $scriptEndTime
$scriptDurationSeconds = $scriptTimespan.Seconds
$scriptDuration = '{0:hh}:{0:mm}:{0:ss}.{0:ff}' -f $scriptTimespan

# General VM data
$vm.Add([PSCustomObject]@{Property = 'scriptDurationSeconds'; Value = $scriptDurationSeconds; Type = 'General'})
$vm.Add([PSCustomObject]@{Property = 'azEnvironment'; Value = $azEnvironment; Type = 'General'})
$vm.Add([PSCustomObject]@{Property = 'location'; Value = $location; Type = 'General'})
$vm.Add([PSCustomObject]@{Property = 'vmName'; Value = $vmName; Type = 'General'})
$vm.Add([PSCustomObject]@{Property = 'vmId'; Value = $vmId; Type = 'General'})
$vm.Add([PSCustomObject]@{Property = 'resourceId'; Value = $resourceId; Type = 'General'})
if ($virtualMachineScaleSetId -and $vmScaleSetName)
{
    $vm.Add([PSCustomObject]@{Property = 'virtualMachineScaleSetId'; Value = $virtualMachineScaleSetId; Type = 'General'})
    $vm.Add([PSCustomObject]@{Property = 'vmScaleSetName'; Value = $vmScaleSetName; Type = 'General'})
}
$vm.Add([PSCustomObject]@{Property = 'subscriptionId'; Value = $subscriptionId; Type = 'General'})
$vm.Add([PSCustomObject]@{Property = 'resourceGroupName'; Value = $resourceGroupName; Type = 'General'})
$vm.Add([PSCustomObject]@{Property = 'vmSize'; Value = $vmSize; Type = 'General'})
$vm.Add([PSCustomObject]@{Property = 'vmAgentVersion'; Value = $guestKeyGuestAgentVersion; Type = 'General'})
$vm.Add([PSCustomObject]@{Property = 'imageReference'; Value = $imageReference; Type = 'General'})
$vm.Add([PSCustomObject]@{Property = 'planPublisher'; Value = $planPublisher; Type = 'General'})
$vm.Add([PSCustomObject]@{Property = 'planProduct'; Value = $planProduct; Type = 'General'})
$vm.Add([PSCustomObject]@{Property = 'planName'; Value = $planName; Type = 'General'})
$vm.Add([PSCustomObject]@{Property = 'zone'; Value = $zone; Type = 'General'})
$vm.Add([PSCustomObject]@{Property = 'priority'; Value = $priority; Type = 'General'})
$vm.Add([PSCustomObject]@{Property = 'platformFaultDomain'; Value = $platformFaultDomain; Type = 'General'})
$vm.Add([PSCustomObject]@{Property = 'platformSubFaultDomain'; Value = $platformSubFaultDomain; Type = 'General'})
$vm.Add([PSCustomObject]@{Property = 'platformUpdateDomain'; Value = $platformUpdateDomain; Type = 'General'})
$vm.Add([PSCustomObject]@{Property = 'placementGroupId'; Value = $placementGroupId; Type = 'General'})
$vm.Add([PSCustomObject]@{Property = 'extendedLocationName'; Value = $extendedLocationName; Type = 'General'})
$vm.Add([PSCustomObject]@{Property = 'extendedLocationType'; Value = $extendedLocationType; Type = 'General'})
$vm.Add([PSCustomObject]@{Property = 'evictionPolicy'; Value = $evictionPolicy; Type = 'General'})
$vm.Add([PSCustomObject]@{Property = 'hostId'; Value = $hostId; Type = 'General'})
$vm.Add([PSCustomObject]@{Property = 'hostGroupId'; Value = $hostGroupId; Type = 'General'})
$vm.Add([PSCustomObject]@{Property = 'isHostCompatibilityLayerVm'; Value = $isHostCompatibilityLayerVm; Type = 'General'})
$vm.Add([PSCustomObject]@{Property = 'hibernationEnabled'; Value = $hibernationEnabled; Type = 'General'})

# OS
$vm.Add([PSCustomObject]@{Property = 'osVersion'; Value = $osVersion; Type = 'OS'})
$vm.Add([PSCustomObject]@{Property = 'ubr'; Value = $ubr; Type = 'OS'})
$vm.Add([PSCustomObject]@{Property = 'osInstallDate'; Value = $installDateString; Type = 'OS'})
$vm.Add([PSCustomObject]@{Property = 'computerName'; Value = $computerName; Type = 'OS'})
$vm.Add([PSCustomObject]@{Property = 'licenseType'; Value = $licenseType; Type = 'OS'})
$vm.Add([PSCustomObject]@{Property = 'joinType'; Value = $joinType; Type = 'OS'})
$vm.Add([PSCustomObject]@{Property = 'role'; Value = $role; Type = 'OS'})
$vm.Add([PSCustomObject]@{Property = 'timeZone'; Value = $timeZone; Type = 'OS'})

#Gathers inforamtion on network interfaces and checks if DHCP is enabled on the NIC if it only has 1 IP
Out-Log 'DHCP-assigned IP addresses:' -startLine

$nics = New-Object System.Collections.Generic.List[Object]

if ($useDotnetForNicDetails)
{
    # [System.Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties().GetActiveTcpConnections()
    # get-winevent -ProviderName Microsoft-Windows-NCSI
    # reg query 'HKLM\SYSTEM\CurrentControlSet\Services\NlaSvc\Parameters\Internet'
    $networkListManager = [Activator]::CreateInstance([Type]::GetTypeFromCLSID([Guid]'{DCB00C01-570F-4A9B-8D69-199FDBA5723B}'))
    $connections = $networkListManager.GetNetworkConnections()

    $isConnected = $networkListManager.IsConnected
    $isConnectedToInternet = $networkListManager.IsConnectedToInternet

    foreach ($connection in $connections)
    {
        $category = $connection.GetNetwork().GetCategory()
        switch ($category)
        {
            0 {$networkProfile = 'Public'}
            1 {$networkProfile = 'Private'}
            2 {$networkProfile = 'DomainAuthenticated'}
        }
    }

    $isNetworkAvailable = [Net.NetworkInformation.NetworkInterface]::GetIsNetworkAvailable()
    $networkInterfaces = [Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces()
    # Description of 'Hyper-V Virtual Ethernet Adapter' is the vswitch on a Hyper-V host
    # Description of 'Microsoft Hyper-V Network Adapter' is the netvsc virtual NIC on a Hyper-V guest
    $networkInterfaces = $networkInterfaces | Where-Object {($_.NetworkInterfaceType -eq 'Ethernet' -and $_.Description -ne 'Hyper-V Virtual Ethernet Adapter') -or ($_.NetworkInterfaceType -eq 'Wireless80211' -and $_.Description -notmatch 'Microsoft Wi-Fi Direct Virtual Adapter') -and $_.Description -notmatch 'Bluetooth'}

    foreach ($networkInterface in $networkInterfaces)
    {
        $ipProperties = $networkInterface.GetIPProperties()
        $ipV4Properties = $ipProperties.GetIPv4Properties()
        $ipV6Properties = $ipProperties.GetIPv6Properties()

        $ipV4Addresses = $ipProperties | Select-Object -ExpandProperty UnicastAddresses | Select-Object -ExpandProperty Address | Where-Object {$_.AddressFamily -eq 'InterNetwork'}
        $ipV6Addresses = $ipProperties | Select-Object -ExpandProperty UnicastAddresses | Select-Object -ExpandProperty Address | Where-Object {$_.AddressFamily -eq 'InterNetworkV6'}

        if ([bool]$ipV4Properties.IsDhcpEnabled)
        {
            $dhcp = 'Enabled'
        }
        else
        {
            $dhcp = 'Disabled'
        }

        if ([bool]$ipV6Properties.IsDhcpEnabled)
        {
            $ipV6Dhcp = 'Enabled'
        }
        else
        {
            $ipV6Dhcp = 'Disabled'
        }

        $nic = [PSCustomObject]@{
            Description                        = $networkInterface.Description
            Alias                              = $networkInterface.Name
            Index                              = $ipV4Properties.Index
            MacAddress                         = $networkInterface.GetPhysicalAddress()
            Status                             = $networkInterface.OperationalStatus
            DHCP                               = $dhcp
            IpAddress                          = $ipV4Addresses
            DnsServers                         = $ipProperties.DnsAddresses.IPAddressToString
            DefaultGateway                     = $ipProperties.GatewayAddresses.Address.IPAddressToString
            Connected                          = $isConnected
            ConnectedToInternet                = $isConnectedToInternet
            Category                           = $networkProfile
            IPv6DHCP                           = $ipV6Dhcp
            IPv6IpAddress                      = $ipV6Addresses
            IPv6DnsServers                     = $ipProperties.DnsAddresses.IPAddressToString
            IPv6DefaultGateway                 = $ipProperties.GatewayAddresses.Address.IPAddressToString
            Id                                 = $networkInterface.Id
            # DHCPServerAddresses = $dhcpServerAddresses
            IsAutomaticPrivateAddressingActive = $ipV4Properties.IsAutomaticPrivateAddressingActive
            Mtu                                = $ipV4Properties.Mtu
        }
        $nics.Add($nic)
    }
    $global:dbgNics = $nics
}
elseif ($winmgmt.Status -eq 'Running')
{
    # Get-NetIPConfiguration depends on WMI (winmgmt service)
    $ipconfigs = Invoke-ExpressionWithLogging 'Get-NetIPConfiguration -Detailed' -verboseOnly
    foreach ($ipconfig in $ipconfigs)
    {
        $interfaceAlias = $ipconfig | Select-Object -ExpandProperty InterfaceAlias
        $interfaceIndex = $ipconfig | Select-Object -ExpandProperty InterfaceIndex
        $interfaceDescription = $ipconfig | Select-Object -ExpandProperty InterfaceDescription

        $netAdapter = $ipconfig | Select-Object -ExpandProperty NetAdapter
        $macAddress = $netAdapter | Select-Object -ExpandProperty MacAddress
        $macAddress = $macAddress -replace '-', ''
        $status = $netAdapter | Select-Object -ExpandProperty Status

        $netProfile = $ipconfig | Select-Object -ExpandProperty NetProfile
        $networkCategory = $netProfile | Select-Object -ExpandProperty NetworkCategory
        $ipV4Connectivity = $netProfile | Select-Object -ExpandProperty IPv4Connectivity
        $ipV6Connectivity = $netProfile | Select-Object -ExpandProperty IPv6Connectivity

        $ipV6LinkLocalAddress = $ipconfig | Select-Object -ExpandProperty IPv6LinkLocalAddress
        $ipV6Address = $ipV6LinkLocalAddress | Select-Object -ExpandProperty IPAddress

        $ipV4Address = $ipconfig | Select-Object -ExpandProperty IPv4Address
        $ipV4IpAddress = $ipV4Address | Select-Object -ExpandProperty IPAddress

        $ipV6DefaultGateway = $ipconfig | Select-Object -ExpandProperty IPv6DefaultGateway
        $ipV6DefaultGateway = $ipV6DefaultGateway | Select-Object -ExpandProperty NextHop

        $ipV4DefaultGateway = $ipconfig | Select-Object -ExpandProperty IPv4DefaultGateway
        $ipV4DefaultGateway = $ipV4DefaultGateway | Select-Object -ExpandProperty NextHop

        $netIPv6Interface = $ipconfig | Select-Object -ExpandProperty NetIPv6Interface
        $ipV6Dhcp = $netIPv6Interface | Select-Object -ExpandProperty DHCP

        $netIPv4Interface = $ipconfig | Select-Object -ExpandProperty NetIPv4Interface
        $ipV4Dhcp = $netIPv4Interface | Select-Object -ExpandProperty DHCP

        $dnsServer = $ipconfig | Select-Object -ExpandProperty DNSServer
        $ipV4DnsServers = $dnsServer | Where-Object {$_.AddressFamily -eq 2} | Select-Object -Expand ServerAddresses
        $ipV4DnsServers = $ipV4DnsServers -join ','
        $ipV6DnsServers = $dnsServer | Where-Object {$_.AddressFamily -eq 23} | Select-Object -Expand ServerAddresses
        $ipV6DnsServers = $ipV6DnsServers -join ','

        $nic = [PSCustomObject]@{
            Description        = $interfaceDescription
            Alias              = $interfaceAlias
            Index              = $interfaceIndex
            MacAddress         = $macAddress
            Status             = $status
            DHCP               = $ipV4Dhcp
            IpAddress          = $ipV4IpAddress
            DnsServers         = $ipV4DnsServers
            DefaultGateway     = $ipV4DefaultGateway
            Connectivity       = $ipV4Connectivity
            Category           = $networkCategory
            IPv6DHCP           = $ipV6Dhcp
            IPv6IpAddress      = $ipV6LinkLocalAddress
            IPv6DnsServers     = $ipV6DnsServers
            IPv6DefaultGateway = $ipV6DefaultGateway
            IPv6Connectivity   = $ipV6Connectivity
        }
        $nics.Add($nic)
        $global:dbgNics = $nics
    }
}
else
{
    Out-Log 'Unable to query network adapter details because winmgmt service is not running'
}

if ($winmgmt.Status -eq 'Running')
{
    # Get-NetRoute depends on WMI (winmgmt service)
    $routes = Get-NetRoute | Select-Object AddressFamily, State, ifIndex, InterfaceAlias, TypeOfRoute, RouteMetric, InterfaceMetric, DestinationPrefix, NextHop | Sort-Object InterfaceAlias
}
else
{
    Out-Log 'Unable to query network route details because winmgmt service is not running'
}

$dhcpDisabledNics = $nics | Where-Object {$_.DHCP -EQ 'Disabled' -and $_.IPAddress.count -eq 1}

if ($dhcpDisabledNics)
{
    $dhcpAssignedIpAddresses = $false
    Out-Log $dhcpAssignedIpAddresses -endLine -color Yellow
    $dhcpDisabledNicsString = 'DHCP-disabled NICs: '
    foreach ($dhcpDisabledNic in $dhcpDisabledNics)
    {
        $dhcpDisabledNicsString += "Description: $($dhcpDisabledNic.Description) Alias: $($dhcpDisabledNic.Alias) Index: $($dhcpDisabledNic.Index) IpAddress: $($dhcpDisabledNic.IpAddress)"
    }
    New-Check -name 'DHCP-assigned IP addresses' -result 'Info' -details $dhcpDisabledNicsString
    New-Finding -type Information -name 'DHCP-disabled NICs' -description $dhcpDisabledNicsString -mitigation 'If your NIC only has 1 IP address then we highly recommend that the NIC does not use static IP address assignment. Instead <a href="https://learn.microsoft.com/en-us/troubleshoot/azure/virtual-machines/windows/windows-azure-guest-agent#solution-3-enable-dhcp-and-make-sure-that-the-server-isnt-blocked-by-firewalls-proxies-or-other-sources">use DHCP</a> to dynamically get the IP address that you have set on the VMs NIC in Azure.'
}
else
{
    $dhcpAssignedIpAddresses = $true
    Out-Log $dhcpAssignedIpAddresses -endLine -color Green
    $details = 'All NICs with a single IP are assigned via DHCP'
    New-Check -name 'DHCP-assigned IP addresses' -result 'OK' -details $details
}

if ($imdsReachable.Succeeded)
{
    $nicsImds = New-Object System.Collections.Generic.List[Object]
    foreach ($interface in $interfaces)
    {
        $ipV4privateIpAddresses = $interface.ipV4.ipAddress.privateIpAddress -join ','
        $ipV4publicIpAddresses = $interface.ipV4.ipAddress.publicIpAddress -join ','
        $ipV6privateIpAddresses = $interface.ipV6.ipAddress.privateIpAddress -join ','
        $ipV6publicIpAddresses = $interface.ipV6.ipAddress.publicIpAddress -join ','

        if ($ipV4privateIpAddresses) {$ipV4privateIpAddresses = $ipV4privateIpAddresses.TrimEnd(',')}
        if ($ipV4publicIpAddresses) {$ipV4publicIpAddresses = $ipV4publicIpAddresses.TrimEnd(',')}
        if ($ipV6privateIpAddresses) {$ipV6privateIpAddresses = $ipV6privateIpAddresses.TrimEnd(',')}
        if ($ipV6publicIpAddresses) {$ipV6publicIpAddresses = $ipV6publicIpAddresses.TrimEnd(',')}

        $nicImds = [PSCustomObject]@{
            'MAC Address'      = $interface.macAddress
            'IPv4 Private IPs' = $ipV4privateIpAddresses
            'IPv4 Public IPs'  = $ipV4publicIpAddresses
            'IPv6 Private IPs' = $ipV6privateIpAddresses
            'IPv6 Public IPs'  = $ipV6publicIpAddresses
        }
        $nicsImds.Add($nicImds)
    }
}

# Security
if ($imdsReachable.Succeeded -eq $false)
{
    $ErrorActionPreference = 'SilentlyContinue'
    if (Confirm-SecureBootUEFI)
    {
        $secureBootEnabled = $true
    }
    else
    {
        $secureBootEnabled = $false
    }
    $ErrorActionPreference = 'Continue'
}
$vm.Add([PSCustomObject]@{Property = 'encryptionAtHost'; Value = $encryptionAtHost; Type = 'Security'})
$vm.Add([PSCustomObject]@{Property = 'secureBootEnabled'; Value = $secureBootEnabled; Type = 'Security'})
$vm.Add([PSCustomObject]@{Property = 'securityType'; Value = $securityType; Type = 'Security'})
$vm.Add([PSCustomObject]@{Property = 'virtualTpmEnabled'; Value = $virtualTpmEnabled; Type = 'Security'})

# Storage
$vm.Add([PSCustomObject]@{Property = 'osDiskDiskSizeGB'; Value = $osDiskDiskSizeGB; Type = 'Storage'})
$vm.Add([PSCustomObject]@{Property = 'osDiskManagedDiskId'; Value = $osDiskManagedDiskId; Type = 'Storage'})
$vm.Add([PSCustomObject]@{Property = 'osDiskManagedDiskStorageAccountType'; Value = $osDiskManagedDiskStorageAccountType; Type = 'Storage'})
$vm.Add([PSCustomObject]@{Property = 'osDiskCreateOption'; Value = $osDiskCreateOption; Type = 'Storage'})
$vm.Add([PSCustomObject]@{Property = 'osDiskCaching'; Value = $osDiskCaching; Type = 'Storage'})
$vm.Add([PSCustomObject]@{Property = 'osDiskDiffDiskSettings'; Value = $osDiskDiffDiskSettings; Type = 'Storage'})
$vm.Add([PSCustomObject]@{Property = 'osDiskEncryptionSettingsEnabled'; Value = $osDiskEncryptionSettingsEnabled; Type = 'Storage'})
$vm.Add([PSCustomObject]@{Property = 'osDiskImageUri'; Value = $osDiskImageUri; Type = 'Storage'})
$vm.Add([PSCustomObject]@{Property = 'osDiskName'; Value = $osDiskName; Type = 'Storage'})
$vm.Add([PSCustomObject]@{Property = 'osDiskOsType'; Value = $osDiskOsType; Type = 'Storage'})
$vm.Add([PSCustomObject]@{Property = 'osDiskVhdUri'; Value = $osDiskVhdUri; Type = 'Storage'})
$vm.Add([PSCustomObject]@{Property = 'osDiskWriteAcceleratorEnabled'; Value = $osDiskWriteAcceleratorEnabled; Type = 'Storage'})

foreach ($dataDisk in $dataDisks)
{
    $bytesPerSecondThrottle = $dataDisk.bytesPerSecondThrottle
    $diskCapacityBytes = $dataDisk.diskCapacityBytes
    $diskSizeGB = $dataDisk.diskSizeGB
    $imageUri = $dataDisk.image.uri
    $isSharedDisk = $dataDisk.isSharedDisk
    $isUltraDisk = $dataDisk.isUltraDisk
    $lun = $dataDisk.lun
    $managedDiskId = $dataDisk.managedDisk.id
    $name = $dataDisk.name
    $opsPerSecondThrottle = $dataDisk.opsPerSecondThrottle
    $vhdUri = $dataDisk.vhd.uri
    $writeAcceleratorEnabled = $dataDisk.writeAcceleratorEnabled

    $vm.Add([PSCustomObject]@{Property = "Data disk LUN $lun Name"; Value = $name; Type = 'Storage'})
    $vm.Add([PSCustomObject]@{Property = "Data disk LUN $lun BytesPerSecondThrottle"; Value = $bytesPerSecondThrottle; Type = 'Storage'})
    $vm.Add([PSCustomObject]@{Property = "Data disk LUN $lun diskCapacityBytes"; Value = $diskCapacityBytes; Type = 'Storage'})
    $vm.Add([PSCustomObject]@{Property = "Data disk LUN $lun diskSizeGB"; Value = $diskSizeGB; Type = 'Storage'})
    $vm.Add([PSCustomObject]@{Property = "Data disk LUN $lun imageUri"; Value = $imageUri; Type = 'Storage'})
    $vm.Add([PSCustomObject]@{Property = "Data disk LUN $lun isSharedDisk"; Value = $isSharedDisk; Type = 'Storage'})
    $vm.Add([PSCustomObject]@{Property = "Data disk LUN $lun isUltraDisk"; Value = $isUltraDisk; Type = 'Storage'})
    $vm.Add([PSCustomObject]@{Property = "Data disk LUN $lun managedDiskId"; Value = $managedDiskId; Type = 'Storage'})
    $vm.Add([PSCustomObject]@{Property = "Data disk LUN $lun opsPerSecondThrottle"; Value = $opsPerSecondThrottle; Type = 'Storage'})
    $vm.Add([PSCustomObject]@{Property = "Data disk LUN $lun vhd"; Value = $vhd; Type = 'Storage'})
    $vm.Add([PSCustomObject]@{Property = "Data disk LUN $lun writeAcceleratorEnabled"; Value = $writeAcceleratorEnabled; Type = 'Storage'})
}

$uninstallPaths = ('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKCU:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*')
$software = Get-ItemProperty -Path $uninstallPaths -ErrorAction SilentlyContinue
$software = $software | Where-Object {$_.DisplayName} | Select-Object DisplayName, DisplayVersion, Publisher, InstallDate | Sort-Object -Property DisplayName

if ($winmgmt.Status -eq 'Running')
{
    $updates = Get-HotFix | Select-Object -Property HotFixID, Description, InstalledOn | Sort-Object -Property InstalledOn -Descending
}
else
{
    Out-Log 'Unable to query Windows update details because the winmgmt service is not running'
}

$output = [PSCustomObject]@{

    wireserverPort80Reachable                             = $wireserverPort80Reachable
    wireserverPort32526Reachable                          = $wireserverPort32526Reachable
    windowsAzureFolderExists                              = $windowsAzureFolderExists
    windowsAzureGuestAgentExeFileVersion                  = $windowsAzureGuestAgentExeFileVersion
    waAppAgentExeFileVersion                              = $waAppAgentExeFileVersion

    computerName                                          = $computerName
    vmId                                                  = $vmId
    installDate                                           = $installDateString
    osVersion                                             = $osVersion
    ubr                                                   = $ubr

    subscriptionId                                        = $subscriptionId
    resourceGroupName                                     = $resourceGroupName
    location                                              = $location
    vmSize                                                = $vmSize
    vmIdFromImds                                          = $vmIdFromImds
    publisher                                             = $publisher
    offer                                                 = $offer
    sku                                                   = $sku
    version                                               = $version
    imageReference                                        = $imageReference
    privateIpAddress                                      = $privateIpAddress
    publicIpAddress                                       = $publicIpAddress
    publicIpAddressReportedFromAwsCheckIpService          = $publicIpAddressReportedFromAwsCheckIpService

    aggregateStatusGuestAgentStatusVersion                = $aggregateStatusGuestAgentStatusVersion
    aggregateStatusGuestAgentStatusStatus                 = $aggregateStatusGuestAgentStatusStatus
    aggregateStatusGuestAgentStatusFormattedMessage       = $aggregateStatusGuestAgentStatusMessage
    aggregateStatusGuestAgentStatusLastStatusUploadMethod = $aggregateStatusGuestAgentStatusLastStatusUploadMethod
    aggregateStatusGuestAgentStatusLastStatusUploadTime   = $aggregateStatusGuestAgentStatusLastStatusUploadTime

    guestKey                                              = $guestKey
    guestKeyPath                                          = $guestKeyPath
    guestKeyDHCPStatus                                    = $guestKeyDHCPStatus
    guestKeyDhcpWithFabricAddressTime                     = $guestKeyDhcpWithFabricAddressTime
    guestKeyGuestAgentStartTime                           = $guestKeyGuestAgentStartTime
    guestKeyGuestAgentStatus                              = $guestKeyGuestAgentStatus
    guestKeyGuestAgentVersion                             = $guestKeyGuestAgentVersion
    minSupportedGuestAgentVersion                         = $minSupportedGuestAgentVersion
    isAtLeastMinSupportedVersion                          = $isAtLeastMinSupportedVersion
    guestKeyOsVersion                                     = $guestKeyOsVersion
    guestKeyRequiredDotNetVersionPresent                  = $guestKeyRequiredDotNetVersionPresent
    guestKeyTransparentInstallerStartTime                 = $guestKeyTransparentInstallerStartTime
    guestKeyTransparentInstallerStatus                    = $guestKeyTransparentInstallerStatus
    guestKeyWireServerStatus                              = $guestKeyWireServerStatus

    windowsAzureKeyPath                                   = $windowsAzureKeyPath
    windowsAzureKey                                       = $windowsAzureKey

    guestAgentKey                                         = $guestAgentKey
    guestAgentKeyPath                                     = $guestAgentKeyPath
    guestAgentKeyContainerId                              = $guestAgentKeyContainerId
    guestAgentKeyDirectoryToDelete                        = $guestAgentKeyDirectoryToDelete
    guestAgentKeyHeartbeatLastStatusUpdateTime            = $guestAgentKeyHeartbeatLastStatusUpdateTime
    guestAgentKeyIncarnation                              = $guestAgentKeyIncarnation
    guestAgentKeyInstallerRestart                         = $guestAgentKeyInstallerRestart
    guestAgentKeyManifestTimeStamp                        = $guestAgentKeyManifestTimeStamp
    guestAgentKeyMetricsSelfSelectionSelected             = $guestAgentKeyMetricsSelfSelectionSelected
    guestAgentKeyUpdateNewGAVersion                       = $guestAgentKeyUpdateNewGAVersion
    guestAgentKeyUpdatePreviousGAVersion                  = $guestAgentKeyUpdatePreviousGAVersion
    guestAgentKeyUpdateStartTime                          = $guestAgentKeyUpdateStartTime
    guestAgentKeyVmProvisionedAt                          = $guestAgentKeyVmProvisionedAt

    guestAgentUpdateStateKeyPath                          = $guestAgentUpdateStateKeyPath
    guestAgentUpdateStateCode                             = $guestAgentUpdateStateCode
    guestAgentUpdateStateMessage                          = $guestAgentUpdateStateMessage
    guestAgentUpdateStateState                            = $guestAgentUpdateStateState

    handlerStateKeyPath                                   = $handlerStateKeyPath
    handlerStates                                         = $handlerStates

    rdAgentStatus                                         = $rdAgentStatus
    rdAgentStartType                                      = $rdAgentStartType

    rdAgentKeyPath                                        = $rdAgentKeyPath
    rdAgentKeyStartValue                                  = $rdAgentKeyStartValue
    rdAgentKeyErrorControlValue                           = $rdAgentKeyErrorControlValue
    rdAgentKeyImagePathValue                              = $rdAgentKeyImagePathValue
    rdAgentKeyObjectNameValue                             = $rdAgentKeyObjectNameValue

    rdAgentExitCode                                       = $rdAgentExitCode
    rdAgentErrorControl                                   = $rdAgentErrorControl

    scQueryExRdAgentOutput                                = $scQueryExRdAgentOutput
    scQueryExRdAgentExitCode                              = $scQueryExRdAgentExitCode
    scQcRdAgentOutput                                     = $scQcRdAgentOutput
    scQcRdAgentExitCode                                   = $scQcRdAgentExitCode

    windowsAzureGuestAgentStatus                          = $windowsAzureGuestAgentStatus
    windowsAzureGuestAgentStartType                       = $windowsAzureGuestAgentStartType

    windowsAzureGuestAgentKeyPath                         = $windowsAzureGuestAgentKeyPath
    windowsAzureGuestAgentKeyStartValue                   = $windowsAzureGuestAgentKeyStartValue
    windowsAzureGuestAgentKeyErrorControlValue            = $windowsAzureGuestAgentKeyErrorControlValue
    windowsAzureGuestAgentKeyImagePathValue               = $windowsAzureGuestAgentKeyImagePathValue
    windowsAzureGuestAgentKeyObjectNameValue              = $windowsAzureGuestAgentKeyObjectNameValue

    windowsAzureGuestAgentExitCode                        = $windowsAzureGuestAgentExitCode
    windowsAzureGuestAgentErrorControl                    = $windowsAzureGuestAgentErrorControl

    scQueryExWindowsAzureGuestAgentOutput                 = $scQueryExWindowsAzureGuestAgentOutput
    scQueryExWindowsAzureGuestAgentExitCode               = $scQueryExWindowsAzureGuestAgentExitCode
    scQcWindowsAzureGuestAgentOutput                      = $scQcWindowsAzureGuestAgentOutput
    scQcWindowsAzureGuestAgentExitCode                    = $scQcWindowsAzureGuestAgentExitCode

    userProxyEnable                                       = $userProxyEnable
    userProxyServer                                       = $userProxyServer
    machineProxyEnable                                    = $machineProxyEnable
    machineProxyServer                                    = $machineProxyServer

    scriptStartTimeLocal                                  = $scriptStartTimeLocalString
    scriptStartTimeUTC                                    = $scriptStartTimeUTCString
    scriptEndTimeLocal                                    = $scriptEndTimeLocalString
    scriptEndTimeUTC                                      = $scriptEndTimeUTCString
    scriptDuration                                        = $scriptDuration
}

#Creates HTML/CSS for the html report
$css = @'
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN"  "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
<html xmlns="http://www.w3.org/1999/xhtml">
<head>
    <style>
        body {
            font-family: sans-serif;
            text-align: left
        }
        table.table2 {
            border: 0px solid;
            border-collapse: collapse;
            text-align: left
        }
        table {
            background-color: #DDEBF7;
            border: 1px solid;
            border-collapse: collapse;
            text-align: left
        }
        th {
            background: #5B9BD5;
            border: 1px solid;
            color: White;
            font-size: 100%;
            padding: 5px;
            text-align: left;
            vertical-align: middle
        }
        tr:hover {
            background-color: Cyan;
        }
        tr:nth-child(odd) {
            background-color: #BDD7EE;
        }
        td {
            border: 1px solid;
            padding: 5px;
            text-align: left;
        }
        td.CRITICAL {
            background: Salmon;
            color: Black;
            text-align: center
        }
        td.WARNING {
            background: Yellow;
            color: Black;
            text-align: center
        }
        td.INFO {
            background: Cyan;
            color: Black;
            text-align: center
        }
        td.OK {
            background: PaleGreen;
            color: Black;
            text-align: center
        }
        td.PASSED {
            background: PaleGreen;
            color: Black;
            text-align: center
        }
        td.FAILED {
            background: Salmon;
            color: Black;
            text-align: center
        }
        td.SKIPPED {
            background: LightGrey;
            color: Black;
            text-align: center
        }
        /* Style the tab */
        .gray {
            color: dimgray;
            font-weight: bold;
        }
        .tab {
          overflow: hidden;
          border: 1px solid #ccc;
          background-color: #f1f1f1;
        }

        /* Style the buttons inside the tab */
        .tab button {
          background-color: inherit;
          float: left;
          border: none;
          outline: none;
          cursor: pointer;
          padding: 14px 16px;
          transition: 0.3s;
          font-size: 17px;
        }

        /* Change background color of buttons on hover */
        .tab button:hover {
          background-color: #ddd;
        }

        /* Create an active/current tablink class */
        .tab button.active {
          background-color: #ccc;
        }

        /* Style the tab content */
        .tabcontent {
          display: none;
          padding: 6px 12px;
          border: 1px solid #ccc;
          border-top: none;
        }

        /* Style the button that is used to open and close the collapsible content */
        .collapsible {
          background-color: #eee;
          color: #444;
          cursor: pointer;
          padding: 18px;
          width: 100%;
          border: none;
          text-align: left;
          outline: none;
          font-size: 15px;
        }

        /* Add a background color to the button if it is clicked on (add the .active class with JS), and when you move the mouse over it (hover) */
        .active, .collapsible:hover {
          background-color: #ccc;
        }

        /* Style the collapsible content. Note: hidden by default */
        .content {
          padding: 0 18px;
          display: none;
          overflow: hidden;
          background-color: #f1f1f1;
        }

        /* Style the buttons that are used to open and close the accordion panel */
        .accordion {
          background-color: #eee;
          color: #444;
          cursor: pointer;
          padding: 10px;
          width: 100%;
          text-align: left;
          border: none;
          outline: none;
          transition: 0.4s;
          font-family: sans-serif;
          font-size: 17px;
          font-weight: bold;
        }

        /* Add a background color to the button if it is clicked on (add the .active class with JS), and when you move the mouse over it (hover) */
        .active2, .accordion:hover {
          background-color: #ccc;
        }

        .accordion:after {
            content: '(Click to expand!) \02795'; /* Unicode character for "plus" sign (+) */
            color: #777;
            float: right;
            margin-left: 5px;
        }

          .active2:after {
            content: "\2796"; /* Unicode character for "minus" sign (-) */
        }

        /* Style the accordion panel. Note: hidden by default */
        .panel {
          padding: 0 18px;
          font-family: sans-serif;
          font-size: 17px;
          background-color: white;
          display: none;
          overflow: hidden;
        }
        .findings-table th:nth-child(1), .findings-table td:nth-child(1) {
            width: 12%;
        }
        .findings-table th:nth-child(2), .findings-table td:nth-child(2) {
            width: 5%;
        }
        .findings-table th:nth-child(3), .findings-table td:nth-child(3) {
            width: 18%;
        }
        .findings-table th:nth-child(4), .findings-table td:nth-child(4) {
            width: 25%;
        }
        .findings-table th:nth-child(5), .findings-table td:nth-child(5) {
            width: 40%;
        }

        .extensions-table th:nth-child(1), .extensions-table td:nth-child(1) {
            width: 10%;
        }
        .extensions-table th:nth-child(2), .extensions-table td:nth-child(2) {
            width: 10%;
        }
        .extensions-table th:nth-child(3), .extensions-table td:nth-child(3) {
            width: 10%;
        }
        .extensions-table th:nth-child(4), .extensions-table td:nth-child(4) {
            width: 10%;
        }
        .extensions-table th:nth-child(5), .extensions-table td:nth-child(5) {
            width: 5%;
        }
        .extensions-table th:nth-child(6), .extensions-table td:nth-child(6) {
            width: 55%;
        }
  
    </style>
</head>
<body>
'@

$tabs = @'
<div class="tab">
  <button class="tablinks active" onclick="openTab(event, 'Findings')">Findings</button>
  <button class="tablinks" onclick="openTab(event, 'OS')">OS</button>
  <button class="tablinks" onclick="openTab(event, 'Agent')">Agent</button>
  <button class="tablinks" onclick="openTab(event, 'Extensions')">Extensions</button>
  <button class="tablinks" onclick="openTab(event, 'Network')">Network</button>
  <button class="tablinks" onclick="openTab(event, 'Firewall')">Firewall</button>
  <button class="tablinks" onclick="openTab(event, 'Services')">Services</button>
  <button class="tablinks" onclick="openTab(event, 'Drivers')">Drivers</button>
  <button class="tablinks" onclick="openTab(event, 'Software')">Software</button>
  <button class="tablinks" onclick="openTab(event, 'Updates')">Updates</button>
</div>
'@

$script = @'
<script>
function openTab(evt, cityName) {
  var i, tabcontent, tablinks;
  tabcontent = document.getElementsByClassName("tabcontent");
  for (i = 0; i < tabcontent.length; i++) {
    tabcontent[i].style.display = "none";
  }
  tablinks = document.getElementsByClassName("tablinks");
  for (i = 0; i < tablinks.length; i++) {
    tablinks[i].className = tablinks[i].className.replace(" active", "");
  }
  document.getElementById(cityName).style.display = "block";
  evt.currentTarget.className += " active";
}

var coll = document.getElementsByClassName("collapsible");
var i;

for (i = 0; i < coll.length; i++) {
  coll[i].addEventListener("click", function() {
    this.classList.toggle("active");
    var content = this.nextElementSibling;
    if (content.style.display === "block") {
      content.style.display = "none";
    } else {
      content.style.display = "block";
    }
  });
}

var acc = document.getElementsByClassName("accordion");
var i;

for (i = 0; i < acc.length; i++) {
  acc[i].addEventListener("click", function() {
    /* Toggle between adding and removing the "active" class,
    to highlight the button that controls the panel */
    this.classList.toggle("active2");

    /* Toggle between hiding and showing the active panel */
    var panel = this.nextElementSibling;
    if (panel.style.display === "block") {
      panel.style.display = "none";
    } else {
      panel.style.display = "block";
    }
  });
}
</script>
'@

$stringBuilder = New-Object Text.StringBuilder

<# https://www.w3schools.com/howto/tryit.asp?filename=tryhow_js_collapsible
https://www.w3schools.com/howto/howto_js_accordion.asp
<button type="button" class="collapsible">Open Collapsible</button>
<div class="content">
  <p>Lorem ipsum dolor sit amet, consectetur adipisicing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat.</p>
</div>
#>
$css | ForEach-Object {[void]$stringBuilder.Append("$_`r`n")}

#Write system info to the top of the html file
if ($computerName)
{
    [void]$stringBuilder.Append("Host Name: <span style='font-weight:bold'>$computerName</span>")
}
if ($vmId)
{
    [void]$stringBuilder.Append(" VMID: <span style='font-weight:bold'>$vmId</span>")
}
if ($guestAgentKeyContainerId)
{
    [void]$stringBuilder.Append(" ContainerId: <span style='font-weight:bold'>$guestAgentKeyContainerId</span>")
}
if ($resourceId)
{
    [void]$stringBuilder.Append("<br>ResourceId: <span style='font-weight:bold'>$resourceId</span>")
}
[void]$stringBuilder.Append("<br>Report Created: <span style='font-weight:bold'>$scriptEndTimeUTCString</span> Duration: <span style='font-weight:bold'>$scriptDuration</span><p>")

$tabs | ForEach-Object {[void]$stringBuilder.Append("$_`r`n")}
#Adds any findings to the html file
[void]$stringBuilder.Append('<div id="Findings" class="tabcontent" style="display:block;">')
[void]$stringBuilder.Append("<h2 id=`"findings`">Findings</h2>`r`n")
$findingsCount = $findings | Measure-Object | Select-Object -ExpandProperty Count

if ($findingsCount -ge 1)
{
    foreach ($finding in $findings)
    {
        [void]$stringBuilder.Append("<button class='accordion'>$($finding.Name)</button>")
        [void]$stringBuilder.Append('<div class="panel" style="display:none;">')
        [void]$stringBuilder.Append('<p>')
        $findingsTable = $finding | ConvertTo-Html -Fragment -As Table 
        $findingsTable = $findingsTable -replace '<table>', '<table class="findings-table">'
        $findingsTable = $findingsTable -replace '<td>Critical</td>', '<td class="CRITICAL">Critical</td>'
        $findingsTable = $findingsTable -replace '<td>Warning</td>', '<td class="WARNING">Warning</td>'
        $findingsTable = $findingsTable -replace '<td>Information</td>', '<td class="INFO">Information</td>'
        $findingsTable | ForEach-Object {[void]$stringBuilder.Append("$_`r`n")}
        [void]$stringBuilder.Append('</p>')
        [void]$stringBuilder.Append('</div>')
    }
}
else
{
    [void]$stringBuilder.Append("<h3>No issues detected</h3>`r`n")
}
#Adds the list of checks as a table
$checksTable = $checks | Select-Object Name, Result, Details | ConvertTo-Html -Fragment -As Table
$checksTable = $checksTable -replace '<td>Info</td>', '<td class="INFO">Info</td>'
$checksTable = $checksTable -replace '<td>Passed</td>', '<td class="PASSED">Passed</td>'
$checksTable = $checksTable -replace '<td>OK</td>', '<td class="OK">OK</td>'
$checksTable = $checksTable -replace '<td>Failed</td>', '<td class="FAILED">Failed</td>'
$checksTable = $checksTable -replace '<td>Skipped</td>', '<td class="SKIPPED">Skipped</td>'
$global:dbgChecksTable = $checksTable
[void]$stringBuilder.Append("<h2 id=`"checks`">Checks</h2>`r`n")
$checksTable | ForEach-Object {[void]$stringBuilder.Append("$_`r`n")}
[void]$stringBuilder.Append('</div>')

[void]$stringBuilder.Append('<div id="OS" class="tabcontent">')
[void]$stringBuilder.Append("<h2 id=`"vm`">VM Details</h2>`r`n")

[void]$stringBuilder.Append("<h3 id=`"vmGeneral`">General</h3>`r`n")
$vmGeneralTable = $vm | Where-Object {$_.Type -eq 'General'} | Select-Object Property, Value | ConvertTo-Html -Fragment -As Table
$vmGeneralTable | ForEach-Object {[void]$stringBuilder.Append("$_`r`n")}

[void]$stringBuilder.Append("<h3 id=`"vmOS`">OS</h3>`r`n")
$vmOsTable = $vm | Where-Object {$_.Type -eq 'OS'} | Select-Object Property, Value | ConvertTo-Html -Fragment -As Table
$vmOsTable | ForEach-Object {[void]$stringBuilder.Append("$_`r`n")}

[void]$stringBuilder.Append("<h3 id=`"vmSecurity`">Security</h3>`r`n")
$vmSecurityTable = $vm | Where-Object {$_.Type -eq 'Security'} | Select-Object Property, Value | ConvertTo-Html -Fragment -As Table
$vmSecurityTable | ForEach-Object {[void]$stringBuilder.Append("$_`r`n")}
[void]$stringBuilder.Append('</div>')

[void]$stringBuilder.Append('<div id="Agent" class="tabcontent">')
[void]$stringBuilder.Append("<h3 id=`"vmAgent`">Agent</h3>`r`n")
$vmAgentTable = $vm | Where-Object {$_.Type -eq 'Agent'} | Select-Object Property, Value | ConvertTo-Html -Fragment -As Table
$vmAgentTable | ForEach-Object {[void]$stringBuilder.Append("$_`r`n")}
[void]$stringBuilder.Append('</div>')
#Populates extension tab with installed extensions
[void]$stringBuilder.Append('<div id="Extensions" class="tabcontent">')
$extensionHandlers = Get-ExtensionHandlers
if ($extensionHandlers)
{
    foreach ($extensionHandler in $extensionHandlers)
    {
        $handlerName = $extensionHandler.handlerName
        [void]$stringBuilder.Append("<h3>$handlerName</h3>`r`n")
        $vmHandlerValuesTable = $extensionHandler | Select-Object timestampUTC, handlerVersion, handlerStatus, sequenceNumber, status, message | ConvertTo-Html -Fragment -As Table
        $vmHandlerValuesTable = $vmHandlerValuesTable -replace '<table>', '<table class="extensions-table">'
        $vmHandlerValuesTable | ForEach-Object {[void]$stringBuilder.Append("$_`r`n")}
    }
}
else 
{
    [void]$stringBuilder.Append("<h3>No extensions detected. Either no extensions are installed or the Guest Agent isn't working</h3>`r`n")
}

[void]$stringBuilder.Append('</div>')
#Populates the Network tab
[void]$stringBuilder.Append('<div id="Network" class="tabcontent">')
[void]$stringBuilder.Append("<h4>NIC Details</h4>`r`n")
$vmNetworkTable = $nics | ConvertTo-Html -Fragment -As Table
$vmNetworkTable = $vmNetworkTable -replace '<td>Up</td>', '<td class="PASSED">Up</td>'
$vmNetworkTable = $vmNetworkTable -replace '<td>Down</td>', '<td class="FAILED">Down</td>'
$vmNetworkTable | ForEach-Object {[void]$stringBuilder.Append("$_`r`n")}

[void]$stringBuilder.Append("<h4>NIC Details from IMDS</h4>`r`n")
$vmNetworkImdsTable = $nicsImds | ConvertTo-Html -Fragment -As Table
$vmNetworkImdsTable | ForEach-Object {[void]$stringBuilder.Append("$_`r`n")}

[void]$stringBuilder.Append("<h4>Route Table</h4>`r`n")
$vmNetworkRoutesTable = $routes | ConvertTo-Html -Fragment -As Table
$vmNetworkRoutesTable | ForEach-Object {[void]$stringBuilder.Append("$_`r`n")}
[void]$stringBuilder.Append('</div>')

[void]$stringBuilder.Append('<div id="Firewall" class="tabcontent">')
[void]$stringBuilder.Append("<h3>Enabled Inbound Windows Firewall Rules</h3>`r`n")
if ($enabledFirewallRules.Inbound)
{
    $vmEnabledInboundFirewallRulesTable = $enabledFirewallRules.Inbound | ConvertTo-Html -Fragment -As Table
    $vmEnabledInboundFirewallRulesTable | ForEach-Object {[void]$stringBuilder.Append("$_`r`n")}
}
else
{
    [void]$stringBuilder.Append("<h5>There are no enabled inbound Windows Firewall rules</h5>`r`n")
}

[void]$stringBuilder.Append("<h3>Enabled Outbound Windows Firewall Rules</h3>`r`n")
if ($enabledFirewallRules.Outbound)
{
    $vmEnabledOutboundFirewallRulesTable = $enabledFirewallRules.Outbound | ConvertTo-Html -Fragment -As Table
    $vmEnabledOutboundFirewallRulesTable | ForEach-Object {[void]$stringBuilder.Append("$_`r`n")}
}
else
{
    [void]$stringBuilder.Append("<h4>There are no enabled outbound Windows Firewall rules</h4>`r`n")
}

if ($showFilters -eq $true)
{
[void]$stringBuilder.Append("<h3>Windows Filtering Platform Filters - Wireserver</h3>`r`n")
$wireserverWfpFiltersTable = $wfpFilters.wireserverFilters | ConvertTo-Html -Fragment -As Table
$wireserverWfpFiltersTable | ForEach-Object {[void]$stringBuilder.Append("$_`r`n")}
[void]$stringBuilder.Append("<h3>Windows Filtering Platform Filters</h3>`r`n")
$wfpFiltersTable = $wfpFilters.Filters | ConvertTo-Html -Fragment -As Table
$wfpFiltersTable | ForEach-Object {[void]$stringBuilder.Append("$_`r`n")}
[void]$stringBuilder.Append("<h3>Windows Filtering Platform Providers</h3>`r`n")
$wfpProvidersTable = $wfpFilters.Providers | ConvertTo-Html -Fragment -As Table
$wfpProvidersTable | ForEach-Object {[void]$stringBuilder.Append("$_`r`n")}
}
[void]$stringBuilder.Append('</div>')

#Populates Services tab
[void]$stringBuilder.Append('<div id="Services" class="tabcontent">')
$services = Get-Services
$vmServicesTable = $services | ConvertTo-Html -Fragment -As Table
$vmServicesTable | ForEach-Object {[void]$stringBuilder.Append("$_`r`n")}
[void]$stringBuilder.Append('</div>')

#Populates Drivers tab
[void]$stringBuilder.Append('<div id="Drivers" class="tabcontent">')
[void]$stringBuilder.Append("<h3 id=`"vmThirdpartyRunningDrivers`">Third-party Running Drivers</h3>`r`n")
$vmthirdPartyRunningDriversTable = $drivers.thirdPartyRunningDrivers | ConvertTo-Html -Fragment -As Table
if($vmThirdpartyRunningDrivers)
{
    $vmthirdPartyRunningDriversTable | ForEach-Object {[void]$stringBuilder.Append("$_`r`n")}
}
else 
{
    [void]$stringBuilder.Append("No third-party drivers detected`r`n")
}
[void]$stringBuilder.Append("<h3 id=`"vmMicrosoftRunningDrivers`">Microsoft Running Drivers</h3>`r`n")
$vmMicrosoftRunningDriversTable = $drivers.microsoftRunningDrivers | ConvertTo-Html -Fragment -As Table
$vmMicrosoftRunningDriversTable | ForEach-Object {[void]$stringBuilder.Append("$_`r`n")}
[void]$stringBuilder.Append('</div>')

<# Revisit outputting disk info from IMDS
[void]$stringBuilder.Append('<div id="Disk" class="tabcontent">')
[void]$stringBuilder.Append("<h3 id=`"vmStorage`">Storage</h3>`r`n")
$vmStorageTable = $vm | Where-Object {$_.Type -eq 'Storage'} | Select-Object Property, Value | ConvertTo-Html -Fragment -As Table
$vmStorageTable | ForEach-Object {[void]$stringBuilder.Append("$_`r`n")}
[void]$stringBuilder.Append('</div>')
#>

#Populates Software tab
[void]$stringBuilder.Append('<div id="Software" class="tabcontent">')
$vmSoftwareTable = $software | ConvertTo-Html -Fragment -As Table
$vmSoftwareTable | ForEach-Object {[void]$stringBuilder.Append("$_`r`n")}
[void]$stringBuilder.Append('</div>')

#Populates Updates tab
[void]$stringBuilder.Append('<div id="Updates" class="tabcontent">')
$vmUpdatesTable = $updates | ConvertTo-Html -Fragment -As Table
$vmUpdatesTable | ForEach-Object {[void]$stringBuilder.Append("$_`r`n")}
[void]$stringBuilder.Append('</div>')

$script | ForEach-Object {[void]$stringBuilder.Append("$_`r`n")}

[void]$stringBuilder.Append("</body>`r`n")
[void]$stringBuilder.Append("</html>`r`n")

$htm = $stringBuilder.ToString()

$checksJson = $checks | ConvertTo-Json -Depth 10

$properties = [PSCustomObject]@{}
$properties | Add-Member -MemberType NoteProperty -Name findingsCount -Value $findingsCount
$vm | Sort-Object Property | ForEach-Object {$properties | Add-Member -MemberType NoteProperty -Name $_.Property -Value $_.Value}

$global:dbgProperties = $properties
$global:dbgvm = $vm
$global:dbgchecks = $checks
$global:dbgchecksJson = $checksJson
$global:dbgfindings = $findings
$global:dbgfindingsJson = $findingsJson
$global:dbgnics = $nics

$htmFileName = "$($scriptBaseName)_$($computerName)_$($scriptStartTimeString).htm"
$htmFilePath = "$logFolderPath\$htmFileName"

$htm = $htm.Replace('&lt;', '<').Replace('&gt;', '>').Replace('&quot;', '"')

$htm | Out-File -FilePath $htmFilePath
Out-Log "Report: $htmFilePath"
if ($showReport -and $installationType -ne 'Server Core')
{
    Invoke-Item -Path $htmFilePath
}

Out-Log "Log: $logFilePath"
$scriptDuration = '{0:hh}:{0:mm}:{0:ss}.{0:ff}' -f (New-TimeSpan -Start $scriptStartTime -End (Get-Date))
Out-Log "$scriptName duration:" -startLine
Out-Log $scriptDuration -endLine -color Cyan

# [int]$findingsCount = $findings | Measure-Object | Select-Object -ExpandProperty Count
if ($findingsCount -ge 1)
{
    $color = 'Cyan'
}
else
{
    $color = 'Green'
}
Out-Log "$findingsCount issue(s) found." -color $color
if ($showLog -and (Test-Path -Path $logFilePath -PathType Leaf))
{
    Invoke-Item -Path $logFilePath
}

if ($showReport -and (Test-Path -Path $htmFilePath -PathType Leaf))
{
    Invoke-Item -Path $htmFilePath
}

$global:dbgOutput = $output
$global:dbgFindings = $findings
#endregion main
