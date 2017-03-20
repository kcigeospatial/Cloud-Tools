﻿#Deletes all the resources, of any type, with a given name in a particular resource group. Can be used to delete a VM and its associated resources.

# Log in to Azure Resource Manager
Login-AzureRmAccount
# Select a default subscription for your current session
Get-AzureRmSubscription –SubscriptionName “” | Select-AzureRmSubscription

#Name of VM to delete
$vmName = ""
#The resource group name VM belongs to
$rgName = ""

$resources = Find-AzureRmResource -ResourceGroupNameContains $rgName -ResourceNameEquals $vmName
foreach ($resource in $resources) {
    Remove-AzureRmResource -ResourceId $resource.ResourceId -Force
}