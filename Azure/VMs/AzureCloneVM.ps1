#Clone an existing VM in Azure. Ensure user has admin access to the target resource group. Requires AzCopy program be installed on machine at location below.
#### Parameters to edit ####
#Source Resource Group Name
$srcResourceGroupName = ""

#Target Resource Group Name
$tarResourceGroupName = ""

#Name of source VM to be copied
$srcVmName = ""

#Name of the new VM to be created
$newVmName = ""

#Ports (TCP) to allow through firewall
$portsToOpen = 80,443,3389

#VM instance size. Reference: https://azure.microsoft.com/en-us/documentation/articles/virtual-machines-windows-sizes/
$vmSize = "Standard_DS2_v2"

#Resources location
$location = "East US"

#If an existing Network Security Group (firewall rules) should be utilized for the VM then populate the name, otherwise leave empty and a new NSG will be created.
$existingNSGName = ""

#If an existing virtual network should be utilized for the VM then populate the name, otherwise leave empty and a new NSG will be created.
$existingVnetName = $tarResourceGroupName + "-vnet"

$subscriptionName = “”
#### End - Parameters to edit ####

# Log in to Azure Resource Manager
Login-AzureRmAccount

# Select the default subscription for your current session
Get-AzureRmSubscription –SubscriptionName $subscriptionName | Select-AzureRmSubscription

# Prep a new Storage Account intended for making a copy of a VM.
# Leverage the VHD URLs and access keys of the source Storage Account attached to the source VM and the intended new Storage Account and VM with the AZCopy tool.
# This script was modified from the help at: https://azure.microsoft.com/en-us/documentation/articles/virtual-machines-windows-vhd-copy/
#Create the new Storage Account for the to-be-created VM
$newStorAcc = New-AzureRmStorageAccount -ResourceGroupName $tarResourceGroupName -AccountName $newVmName -Location $location -Type "Premium_LRS"
$newStorKey = Get-AzureRmStorageAccountKey -Name $newVmName -ResourceGroupName $tarResourceGroupName
$newKey1 = $newStorKey[0].Value
$ctx = New-AzureStorageContext -StorageAccountName $newVmName -StorageAccountKey $newKey1
$newContName = "vhds"
$newStorCont = New-AzureStorageContainer -Name $newContName -Context $ctx
$newStorContUri = $ctx.BlobEndPoint + $newContName 

$srcVm = Get-AzureRmVM -ResourceGroupName $srcResourceGroupName -Name $srcVmName
#Check if Windows or Linux
$isWindows = $false
if ($srcVm.OSProfile.WindowsConfiguration) {
    $isWindows = $true
}

$isManagedDisk = $false
$managedDiskName
$srcManagedDisk
$srcStorContUri
$srcStorKey
$srcKey1
#Handle differently if Managed Disk. Help: https://docs.microsoft.com/en-us/azure/virtual-machines/scripts/virtual-machines-windows-powershell-sample-copy-managed-disks-to-same-or-different-subscription
if ($srcVm.StorageProfile.OsDisk.ManagedDisk) {
    $isManagedDisk = $true
    #Get storage account name
    $srcManagedDiskName = $srcVm.StorageProfile.OsDisk.Name
    #Get the source managed disk
    $srcManagedDisk = Get-AzureRMDisk -ResourceGroupName $srcResourceGroupName -DiskName $srcManagedDiskName
} else { #Get source VM storage URI
    $srcStorContUri = $srcVm.StorageProfile.OsDisk.Vhd.Uri.Substring(0,$srcVm.StorageProfile.OsDisk.Vhd.Uri.LastIndexOf("/"))
    $srcStorKey = Get-AzureRmStorageAccountKey -Name $srcVmName -ResourceGroupName $srcResourceGroupName
    $srcKey1 = $srcStorKey[0].Value
}

#Stop the source VM
Stop-AzureRmVM -ResourceGroupName $srcResourceGroupName -Name $srcVmName -Force

$tarManagedDiskConfig
$tarManagedDisk
#Copy the OS disk
if ($isManagedDisk) {
    $diskConfig = New-AzureRmDiskConfig -SourceResourceId $srcManagedDisk.Id -Location $srcManagedDisk.Location -CreateOption Copy 
    #Create a new managed disk in the target subscription and resource group
    $tarManagedDisk = New-AzureRmDisk -Disk $diskConfig -DiskName $newVmName -ResourceGroupName $tarResourceGroupName
} else {
    #Use AzCopy to copy files into blob
    &"C:\Program Files (x86)\Microsoft SDKs\Azure\AzCopy\AzCopy.exe" /Source:$srcStorContUri /Dest:$newStorContUri /SourceKey:$srcKey1 /DestKey:$newKey1 /S
}

# Create the new VM Windows server VM from an existing OS disk in a storage account (leverages copied OS disk that was made using AZCopy).
# This script was modified from the help at: https://azure.microsoft.com/en-us/documentation/articles/virtual-machines-windows-create-vm-specialized/
$osDiskUri
$dataDiskName
$dataDiskUri
if (!$isManagedDisk) {
    # Set the URI for the OS disk VHD that you want to use. In this example, the VHD file named "*.vhd" is in a storage account with a typical container name of "vhds".
    $osDiskUri = $newStorContUri + $srcVm.StorageProfile.OsDisk.Vhd.Uri.Substring($srcVm.StorageProfile.OsDisk.Vhd.Uri.LastIndexOf("/"))

    # Optional: Add existing data disks by using the URLs of the copied data VHDs at the appropriate Logical Unit Number (Lun).
    #$dataDiskName = $newVmName + "dataDisk"
    #$dataDiskUri = "https://cityworksdisks.blob.core.windows.net/vhds/sql2014sp2stdev-disk-1.vhd"
}

#IP address resource name.
$ipName = $newVmName

#Network interface resource name.
$nicName = $newVmName

#Name of the OS disk resource.
$osDiskName = $newVmName + "osDisk"

$nsg
if ($existingNSGName.Length -eq 0) {
    #Create firewall rules
    $ruleNum = 1
    $priority = 100
    $firewallRules = New-Object System.Collections.ArrayList
    foreach ($port in $portsToOpen) {
        $rule = New-AzureRmNetworkSecurityRuleConfig -Name "rule$ruleNum"  -Priority $priority `
            -Access Allow -Protocol Tcp -Direction Inbound `
            -SourceAddressPrefix Internet -SourcePortRange * `
            -DestinationAddressPrefix * -DestinationPortRange $port
        $firewallRules.Add($rule)
        $ruleNum++
        $priority = $priority + 10
    }
    #Create new network security group
    $nsg = New-AzureRmNetworkSecurityGroup -ResourceGroupName $tarResourceGroupName -Location $location -Name $newVmName -SecurityRules $firewallRules
} else {
    #Get existing network security group
    $nsg = Get-AzureRmNetworkSecurityGroup -Name $existingNSGName -ResourceGroupName $tarResourceGroupName
}

$vnet
if ($existingVnetName.Length -eq 0) {
    #Create new virtual network
    $singleSubnet = New-AzureRmVirtualNetworkSubnetConfig -Name "default" -AddressPrefix 10.0.0.0/24
    $vnet = New-AzureRmVirtualNetwork -Name $newVmName -ResourceGroupName $tarResourceGroupName -Location $location -AddressPrefix 10.0.0.0/16 -Subnet $singleSubnet
} else {
    #Assign existing virtual network
    $vnet = Get-AzureRmVirtualNetwork -Name $existingVnetName -ResourceGroupName $tarResourceGroupName
}

$pip = New-AzureRmPublicIpAddress -Name $ipName -ResourceGroupName $tarResourceGroupName -Location $location -AllocationMethod Dynamic 
$pip.DnsSettings += @{DomainNameLabel = $newVmName}
Set-AzureRmPublicIpAddress -PublicIpAddress $pip

$nic = New-AzureRmNetworkInterface -Name $nicName -ResourceGroupName $tarResourceGroupName -Location $location -SubnetId $vnet.Subnets[0].Id -PublicIpAddressId $pip.Id -NetworkSecurityGroupId $nsg.Id

#Set the VM name and size. This example sets the VM name to "myVM" and the VM size to "Standard_A2".
$VirtualMachine = New-AzureRmVMConfig -VMName $newVmName -VMSize $vmSize

#Add the NIC
$VirtualMachine = Add-AzureRmVMNetworkInterface -VM $VirtualMachine -Id $nic.Id

if ($isManagedDisk) {#Help: https://docs.microsoft.com/en-us/azure/virtual-machines/scripts/virtual-machines-windows-powershell-sample-create-vm-from-managed-os-disks?toc=%2fpowershell%2fmodule%2ftoc.json
    if ($isWindows) {
        $VirtualMachine = Set-AzureRmVMOSDisk -VM $VirtualMachine -ManagedDiskId $tarManagedDisk.Id -CreateOption attach -Windows
    } else {
        $VirtualMachine = Set-AzureRmVMOSDisk -VM $VirtualMachine -ManagedDiskId $tarManagedDisk.Id -CreateOption attach -Linux
    }
} else {
    #Add the OS disk by using the URL of the copied OS VHD. In this example, when the OS disk is created, the term "osDisk" is appened to the VM name to create the OS disk name. This example also specifies that this Windows-based VHD should be attached to the VM as the OS disk.
    if ($isWindows) {
        $VirtualMachine = Set-AzureRmVMOSDisk -VM $VirtualMachine -Name $osDiskName -VhdUri $osDiskUri -CreateOption attach -Windows
    } else {
        $VirtualMachine = Set-AzureRmVMOSDisk -VM $VirtualMachine -Name $osDiskName -VhdUri $osDiskUri -CreateOption attach -Linux
    }
    #Create optional secondary data disk
    #$vm = Add-AzureRmVMDataDisk -VM $vm -Name $dataDiskName -VhdUri $dataDiskUri -Lun 0 -CreateOption attach -DiskSizeInGB 137
}

#Create the new VM
New-AzureRmVM -ResourceGroupName $tarResourceGroupName -Location $location -VM $VirtualMachine

#Check that the VM was created
$vmList = Get-AzureRmVM -ResourceGroupName $tarResourceGroupName
$vmList.Name