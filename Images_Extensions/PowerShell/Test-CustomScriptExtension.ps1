Start-Transcript -Path "$env:SystemRoot\Temp\PowerShell_transcript.$($env:COMPUTERNAME).$(Get-Date ((Get-Date).ToUniversalTime()) -f yyyyMMddHHmmss).txt" -IncludeInvocationHeader
Set-PSDebug -Trace 2
Write-Output "Write-Output output from $($MyInvocation.MyCommand.Name)"
exit 2
Stop-Transcript
