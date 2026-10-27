$ErrorActionPreference = 'Stop'
$scriptPath = Join-Path $PSScriptRoot 'Windows_OSUpgrade_Assessment_Validation.ps1'
$tokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count -gt 0) {
    throw ($parseErrors | Out-String)
}

# Keep tests read-only: replace elevation and OS discovery, and mock machine queries.
$adminFunction = $ast.Find({
    param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Assert-Admin'
}, $true)
$source = Get-Content -LiteralPath $scriptPath -Raw
$source = $source.Remove($adminFunction.Extent.StartOffset, $adminFunction.Extent.EndOffset - $adminFunction.Extent.StartOffset).
    Insert($adminFunction.Extent.StartOffset, 'function Assert-Admin {}')
$source = $source.Replace('$winVer = [System.Environment]::OSVersion.Version', '$winVer = $testOSVersion')
$assessment = [scriptblock]::Create($source)

if (-not ('OSUpgradeAssessment.ClusterApi' -as [type])) {
    Add-Type -TypeDefinition @'
namespace OSUpgradeAssessment {
    public static class ClusterApi {
        public static uint State;
        public static uint Result;
        public static bool Fail;
        public static uint GetNodeClusterState(string nodeName, out uint clusterState) {
            if (Fail) throw new System.InvalidOperationException("Native query unavailable");
            clusterState = State;
            return Result;
        }
    }
}
'@
}

function Test-Assessment {
    param(
        [string]$Name,
        [uint32]$State = 0,
        [bool]$ServiceInstalled = $true,
        [bool]$QueryFails = $false,
        [uint32]$NativeResult = 0,
        [bool]$NativeFails = $false,
        [string]$ProductName = 'Windows Server 2016 Datacenter',
        [version]$testOSVersion = '10.0.14393',
        [long]$FreeSpace = 128GB,
        [long]$Memory = 8GB,
        [bool]$ExpectGeneric = $false,
        [string]$ExpectedText
    )

    [OSUpgradeAssessment.ClusterApi]::State = $State
    [OSUpgradeAssessment.ClusterApi]::Result = $NativeResult
    [OSUpgradeAssessment.ClusterApi]::Fail = $NativeFails
    $clusterQueryCount = 0
    function Get-ItemProperty { @{ ProductName = $ProductName; ReleaseId = '2009' } }
    function Get-PSDrive { @{ Free = $FreeSpace } }
    function Get-WmiObject { @{ SMBIOSBIOSVersion = 'Legacy' } }
    function Write-Host {}
    function Get-CimInstance {
        param($ClassName, $Filter, $ErrorAction)
        if ($ClassName -eq 'Win32_ComputerSystem') {
            return @{ TotalPhysicalMemory = $Memory }
        }
        if ($ClassName -ne 'Win32_Service' -or $Filter -ne "Name = 'ClusSvc'" -or $ErrorAction -ne 'Stop') {
            throw "Unexpected CIM query: $ClassName / $Filter / $ErrorAction"
        }
        Set-Variable -Name clusterQueryCount -Value ($clusterQueryCount + 1) -Scope 1
        if ($QueryFails) { throw 'Service query unavailable' }
        if ($ServiceInstalled) { return @{ Name = 'ClusSvc' } }
    }
    function Invoke-RestMethod {
        @{ securityProfile = @{ securityType = 'TrustedLaunch'; secureBootEnabled = $true; virtualTpmEnabled = $true } }
    }

    $output = (& $assessment) -join "`n"
    if ($output.Contains('The supported upgrade options are:') -ne $ExpectGeneric) {
        throw "${Name}: Unexpected generic upgrade recommendation.`n$output"
    }
    if (-not $output.Contains($ExpectedText)) {
        throw "${Name}: Missing expected output '$ExpectedText'.`n$output"
    }
    if ($ProductName -notlike 'Windows Server*' -and $clusterQueryCount -ne 0) {
        throw "${Name}: Client OS unexpectedly queried cluster membership."
    }
    Write-Output "PASS: $Name"
}

Test-Assessment -Name 'Clustering not installed' -ServiceInstalled $false -ExpectGeneric $true -ExpectedText 'Windows Server 2019, Windows Server 2022, or Windows Server 2025'
Test-Assessment -Name 'Native state not installed' -State 0 -ExpectGeneric $true -ExpectedText 'The supported upgrade options are:'
Test-Assessment -Name 'Feature installed but not configured' -State 1 -ExpectGeneric $true -ExpectedText 'The supported upgrade options are:'
Test-Assessment -Name 'Configured cluster service stopped' -State 3 -ExpectedText '[Warning] Failover-cluster membership detected.'
Test-Assessment -Name 'Configured cluster service running' -State 19 -ExpectedText '[Warning] Failover-cluster membership detected.'
Test-Assessment -Name 'Service query fails closed' -QueryFails $true -ExpectedText 'Service query unavailable'
Test-Assessment -Name 'Unknown readiness is explicit' -QueryFails $true -ExpectedText 'Cluster readiness not assessed - manual validation required.'
Test-Assessment -Name 'Native query error fails closed' -NativeResult 5 -ExpectedText 'Windows error code 5'
Test-Assessment -Name 'Native query unavailable fails closed' -NativeFails $true -ExpectedText 'Native query unavailable'
Test-Assessment -Name 'Unknown native state fails closed' -State 2 -ExpectedText 'unrecognized state: 2'
Test-Assessment -Name 'Cluster warning survives disk failure' -State 19 -FreeSpace 1GB -ExpectedText '[Warning] Failover-cluster membership detected.'
Test-Assessment -Name 'Cluster warning survives memory failure' -State 3 -Memory 1GB -ExpectedText '[Warning] Failover-cluster membership detected.'
Test-Assessment -Name 'Nonclustered disk failure still blocks recommendations' -State 1 -FreeSpace 1GB -ExpectedText '[Failed] Disk Space'
Test-Assessment -Name 'Nonclustered memory failure still blocks recommendations' -State 1 -Memory 1GB -ExpectedText '[Failed] Physical Memory'
Test-Assessment -Name 'Cluster guidance link' -State 19 -ExpectedText 'https://learn.microsoft.com/en-us/windows-server/failover-clustering/cluster-operating-system-rolling-upgrade'
Test-Assessment -Name 'Windows 10 behavior preserved' -ProductName 'Windows 10 Pro' -testOSVersion '10.0.19045' -ExpectedText 'FAILED: The VM is running Windows 10 Gen1.'
Test-Assessment -Name 'Windows 11 behavior preserved' -ProductName 'Windows 11 Pro' -testOSVersion '10.0.22621' -ExpectedText 'The system is already running Windows 11 22H2 or above.'
