#create logging directory and start transcription
$LogFile = "$Env:SystemDrive\WindowsAzure\Logs\ChkDsk-SysReg.log"
Start-Transcript -Path $LogFile

Write-Output '#01 - enumerate virtual disks and set online'
$partitionlist = $null
$disklist = get-wmiobject Win32_diskdrive |Where-Object {$_.model -like 'Microsoft Virtual Disk'} 
ForEach ($disk in $disklist)
{
	$diskID = $disk.index
	$command = @"
	select disk $diskID
	online disk noerr
"@
	$command | diskpart

    $partitionlist += Get-Partition -DiskNumber $diskID
}

Write-Output '#02 - enumerate partitions to repair them'
forEach ( $partition in $partitionlist )
{
    $driveLetter = ($partition.DriveLetter + ":")
    $dirtyFlag = fsutil dirty query $driveLetter
    If ($dirtyFlag -notmatch "NOT Dirty")
    {
        Write-Output '02 - ' + $driveLetter + ' dirty bit set  -> running chkdsk'
        chkdsk $driveLetter /f
    }
    else
    {
        Write-Output '02 - ' + $driveLetter + ' dirty bit not set  -> skipping chkdsk'
    }
}

$partGroups = $partitionlist | group DiskNumber 

Write-Output '#03 - enumerate partitions to reconfigure boot cfg'
forEach ( $partitionGroup in $partitionlist | group DiskNumber )
{
    #reset paths for each part group (disk)
    $isBcdPath = $false
    $bcdPath = ''
    $bcdDrive = ''
    $isOsPath = $false
    $osPath = ''
    $osDrive = ''

    #scan all partitions of a disk for bcd store and os file location 
    ForEach ($drive in $partitionGroup.Group | select -ExpandProperty DriveLetter )
    {      
        #check if no bcd store was found on the previous partition already
        if ( -not $isBcdPath )
        {
            $bcdPath =  $drive + ':\boot\bcd'
            $bcdDrive = $drive + ':'
            $isBcdPath = Test-Path $bcdPath

            #if no bcd was found yet at the default location look for the uefi location too
            if ( -not $isBcdPath )
            {
                $bcdPath =  $drive + ':\efi\microsoft\boot\bcd'
                $bcdDrive = $drive + ':'
                $isBcdPath = Test-Path $bcdPath

            } 
        }        
        
        #check if os loader was found on the previous partition already
        if (-not $isOsPath)
        {
            $osPath = $drive + ':\windows\system32\winload.exe'
            $isOsPath = Test-Path $osPath
            if ($isOsPath)
            {
                $osDrive = $drive + ':'
            }
        }
    }

    #if both was found update bcd store
    if ( $isBcdPath -and $isOsPath )
    {
        #revert pending actions to let sfc succeed in most cases
        dism.exe /image:$osDrive /cleanup-image /revertpendingactions

        Write-Output '#04 - runing SFC.exe' $osDrive\windows
        sfc /scannow /offbootdir=$osDrive /offwindir=$osDrive\windows

        Write-Output '#05 - runing dism to restore health on ' $osDrive 
        Dism /Image:$osDrive /Cleanup-Image /RestoreHealth /Source:c:\windows\winsxs
        
        Write-Output '#06 - enumvering corrupt system files in ' $osDrive\windows\system32\
        get-childitem -Path $osDrive\windows\system32\* -include *.dll,*.exe `
            | %{$_.VersionInfo | ? FileVersion -eq $null | select FileName, ProductVersion, FileVersion }  

        Write-Output '#07 - setting bcd recovery and default id for ' $bcdPath
        $bcdout = bcdedit /store $bcdPath /enum bootmgr /v
        $defaultLine = $bcdout | Select-String 'displayorder' | select -First 1
        $defaultId = '{'+$defaultLine.ToString().Split('{}')[1] + '}'
        
        bcdedit /store $bcdPath /default $defaultId
        bcdedit /store $bcdPath /set $defaultId  recoveryenabled Off
        bcdedit /store $bcdPath /set $defaultId  bootstatuspolicy IgnoreAllFailures

        #setting os device does not support multiple recovery disks attached at the same time right now (as default will be overwritten each iteration)
        $isDeviceUnknown= bcdedit /store $bcdPath /enum osloader | Select-String 'device' | Select-String 'unknown'
        
        if ($isDeviceUnknown)
        {
            bcdedit /store $bcdPath /set $defaultId device partition=$osDrive 
            bcdedit /store $bcdPath /set $defaultId osdevice partition=$osDrive 
        }
              

        #load reg to make sure system regback contains data
        $RegBackup = Get-ChildItem  $osDrive\windows\system32\config\Regback\system
        If($RegBackup.Length -ne 0)
		{
            Write-Output '#06 - restoring registry on ' $osDrive 
			move $osDrive\windows\system32\config\system $osDrive\windows\system32\config\system_org -Force
	                copy $osDrive\windows\system32\config\Regback\system $osDrive\windows\system32\config\system -Force
		}
        
    }      
}


Write-Output '#10 - offlining data disks'
ForEach ($disk in $disklist)
{
	$diskID = $disk.index
	$command = @"
	select disk $diskID
	offline disk noerr
"@
	$command | diskpart
}

#end logging
Stop-Transcript
