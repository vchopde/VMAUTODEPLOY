<#
Create Clones from a VM
1.create a file 

The Tool supports creation of Full clone and linked clone from Master VM.
The parent VM is required for the linked-clone to work and the parent VMs file cannot be renamed or moved.
#>
#------------------------- Functions -------------------------
function GetInput
{
    Param($prompt, $IsPassword = $false)
    $prompt = $prompt + ": "
    Write-Host $prompt -NoNewLine
    [Console]::ForegroundColor = "Blue"
    if ($IsPassword)
    {
        $input = Read-Host -AsSecureString
        $input = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($input))
    }
    else
    {
        $input = Read-Host
    }
    
    [Console]::ResetColor()
    return $input
}

function IsVMExists ()
{
    Param($VMExists)
	Write-Host "Checking if the VM $VMExists already Exists"
	[bool]$Exists = $false

	#Get all VMS and check if the VMs is already present in VC
	$listvm = Get-vm
	foreach ($lvm in $listvm)
	{
		if($VMExists -eq $lvm.Name )
		{
			$Exists = $true
		}
	}
	return $Exists
}

#------------------------- Main Script -------------------------

$vcAddress = GetInput -prompt "Your vCenter address" -IsPassword $false
$vcAdmin = GetInput -prompt "Your vCenter admin user name" -IsPassword $false
$vcPassword = GetInput -prompt "Your vCenter admin user password" -IsPassword $true
"-----------------------------------------------------"
$csvFile = '.\CloneVMs.csv'
#check if file exists
if (!(Test-Path $csvFile))
{
	write-host  -ForeGroundColor Red "CSV File $CSVFile not found"
	exit
}

# Connect to the VC (Parameterize VC)
#Connect to vCenter
$VC_Conn_State =Connect-VIServer $vcAddress -user $vcAdmin -password $vcPassword
if([string]::IsNullOrEmpty($VC_Conn_State))
{
   Write-Host 'Exit since failed to login vCenter'
   exit
}
else
{
  Write-Host 'vCenter is connected'
}

#Read input CSV file
$csvData = Import-CSV $csvFile 
#$csvData = Import-CSV $csvFile -header("VMName","Parentvm","Datastore","Host","Networkadapter","IP","Subnet","Gateway","DNS","Domain","PortGroups")
foreach ($line in $csvData)
{
    "`n-----------------------------------------------------"
    $VMName = $line.VMName
    $destVMName=$line.VMName
    $srcVM = $line.Parentvm
	$targetDSName = $line.Datastore
    $destHost = $line.Host
	$dstvmNetworkdapter = $line.NetworkAdapter
    $dstvmIP = $line.IP
    $dstvmSubnet =$line.Subnet
    $dstvmGateway= $line.Gateway
    $dstvmDns = $line.DNS
    $dstvmDomain = $line.Domain
    $dstvmPortgroup = $line.PortGroup

    write-host -ForeGroundColor Yellow "==> VM: $VMName`n"
    write-host  -ForeGroundColor GREEN "==> Clonning Will be done from : $srcVM`n"

	if (IsVMExists ($destVMName))
	{
		Write-Host "==> VM:$destVMName Already Exists in VC $vcAddress"
		 Write-Host  -ForeGroundColor RED "==> Skipping  clonning  for $destVMName"
          continue

	}  
  
    $vm = get-vm $srcvm -ErrorAction Stop | get-view -ErrorAction Stop
	$cloneSpec = new-object VMware.VIM.VirtualMachineCloneSpec
	$cloneSpec.Location = new-object VMware.VIM.VirtualMachineRelocateSpec
	Write-Host  -ForeGroundColor GREEN "==> Using Datastore $targetDSName"
	$newDS = Get-Datastore $targetDSName | Get-View
	$CloneSpec.Location.Datastore =  $newDS.summary.Datastore
    $cloneSpec.Location.Host = (get-vmhost -Name $destHost).Extensiondata.MoRef

    ####  Customize Guest OS
	
	$vmclonespec_os= New-Object  VMware.Vim.CustomizationSpec
	
	## Identity for Linux 
	$vmclonespec_os.identity= New-Object VMware.Vim.CustomizationLinuxPrep
	$vmclonespec_os.identity.hostname= New-Object VMware.Vim.CustomizationFixedName
	$vmclonespec_os.identity.hostname.name= $destVMName
	$vmclonespec_os.identity.domain=$dstvmDomain
	
	#GlobalIPSettings
     $vmclonespec_os.GlobalIPSettings = New-Object VMware.Vim.CustomizationGlobalIPSettings
	 $vmclonespec_os.GlobalIPSettings.dnsServerList=$dstvmDns
	 $vmclonespec_os.GlobalIPSettings.dnsSuffixList=$dstvmDomain
	 
    # adapter mapping

	    $vmclonespec_os.NicSettingMap += @(New-Object VMware.Vim.CustomizationAdapterMapping)	
	    $vmclonespec_os.NicSettingMap[0].Adapter = New-Object VMware.Vim.CustomizationIPSettings
        $vmclonespec_os.NicSettingMap[0].Adapter = New-Object VMware.Vim.CustomizationIPSettings
		
	# FixedIP
		$vmclonespec_os.NicSettingMap[0].Adapter.Ip = New-Object VMware.Vim.CustomizationFixedIp
		$vmclonespec_os.NicSettingMap[0].Adapter.Ip.IpAddress = $dstvmIP
		$vmclonespec_os.NicSettingMap[0].Adapter.SubnetMask = $dstvmSubnet
		$vmclonespec_os.NicSettingMap[0].Adapter.Gateway =  $dstvmGateway
		


    # Start the Clone task using the above parameters
    write-host "==> Starting clone process ... "
    $task = $vm.CloneVM_Task($vm.parent, $destVMName, $cloneSpec)
    # Get the task object
	$task = Get-Task | where { $_.id -eq $task }
    #Wait for the taks to Complete
    Wait-Task -Task $task
	
   write-host "==> Checking new VM ..." 
  get-vm $destVMName -ErrorAction stop 	

  write-host "==> Customizing guest OS ...  "
$newvm = Get-View (get-vm $destVMName -ErrorAction stop ).ID 
 $task=$newvm.CustomizeVM_Task($vmclonespec_os)
  # Get the task object
	$task = Get-Task | where { $_.id -eq $task }
               
    $newvm = Get-vm $destVMName
    
    sleep 10
    # Start the VM
	Start-VM $newvm
sleep 15

write-host "==> Setting  Portgroup for New VM  network adapters ...  "

Get
Get-VM $destVMName |Get-NetworkAdapter|Set-NetworkAdapter -NetworkName API_APPS -Confirm:$false 
Get-VM $destVMName |Get-NetworkAdapter|Set-NetworkAdapter -StartConnected:$true -Connected:$true -Confirm:$false


}
Disconnect-VIServer $vcAddress -Confirm:$true
exit

