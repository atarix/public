<#
.SYNOPSIS
    Enable Accelerated Networking for all Network Interfaces in a subscription.
.DESCRIPTION
    This script enables Accelerated Networking for all Network Interfaces in a subscription that match the specified prefix and do not contain the exclusion keyword.
    It logs the changes made to a CSV file and creates a log file for the operation.
.PARAMETER ReportOnly_Y_or_N
    Specify "Y" to report only, or "N" to enable Accelerated Networking. Default is "Y".
    If "Y", the script will only report the Network Interfaces that do not have Accelerated Networking enabled.
    If "N", the script will enable Accelerated Networking for those Network Interfaces.
.PARAMETER SubscriptionNamePrefix
    The prefix of the subscription names to filter the subscriptions.
.PARAMETER ExclusionKeyWords
    The keyword to exclude subscriptions from the operation.

.EXAMPLE
    .\enable-acceleratednetworking.ps1 -ReportOnly_Y_or_N "Y" -SubscriptionNamePrefix "MySubscriptionPrefix" -ExclusionKeyWords "Exclude"
    This example enables Accelerated Networking for all Network Interfaces in subscriptions that start with "MySubscriptionPrefix" and do not contain the word "Exclude".

    .Author: James Kho
    .Date: 2024-04-04
    .Version: 1.0   
    .Notes:
        - This script requires the Az PowerShell module to be installed and imported.
        - Ensure you have the necessary permissions to modify Network Interfaces in the specified subscriptions.
        - The script will create a log file and a CSV file in the C:\Logs directory. Ensure this directory exists or modify the script to create it.
        - The script uses Start-Transcript and Stop-Transcript for logging. Ensure you have permission to write to the specified log file path.

#>

param (
    [Parameter(Mandatory=$true)]
    [string]$ReportOnly_Y_or_N = "Y", # Y or N, if Y, only report, if N, enable Accelerated Networking

    [Parameter(Mandatory=$true)]
    [string]$SubscriptionNamePrefix,

    [Parameter(Mandatory=$true)]
    [array]$ExclusionKeyWords
)


#Create Log File
$LogTime = Get-Date -Format "MM-dd-yyyy_hh-mm-ss"
$LogFileName = "Enable_AcceleratedNetworking_$LogTime.log"
$LogFilePath = "C:\Logs\$LogFileName"
$LogCSV = "C:\Logs\Enable_AcceleratedNetworking_$LogTime.csv"

# Start logging
# Ensure the log directory exists
$LogDirectory = Split-Path -Path $LogFilePath
if (!(Test-Path -Path $LogDirectory)) {
    New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null
}

# Create or open the log file and start logging
Start-Transcript -Path $LogFilePath -Append

Connect-AzAccount
$subscriptions = Get-AzSubscription | Where-Object { $_.Name -like "$($SubscriptionNamePrefix)*" -and $_.Name -notmatch ($ExclusionKeyWords -join '|') }

foreach($sub in $subscriptions){

    Set-AzContext -Subscription $sub.Name

    $nics = Get-AzNetworkInterface | Where-Object { $_.Name -notLike "*pep*"}

    foreach($nic in $nics){

    if(!($nic.EnableAcceleratedNetworking)){
    
        if($ReportOnly_Y_or_N -eq "N"){
            # Enable Accelerated Networking
            Write-Host "Enabling Accelerated Networking for Network Interface $($nic.Name)..."
            $nic.EnableAcceleratedNetworking  = $true
            $nic | Set-AzNetworkInterface
            Get-AzNetworkInterface -Name $nic.Name | Select-Object Id, Name, VirtualMachine, ResourceGroupName, EnableAcceleratedNetworking| Export-Csv -Path $LogCSV -Append -NoTypeInformation
            }else{
            # Report only, does not enable Accelerated Networking
            Write-Host "Accelerated Networking is not enabled for Network Interface $($nic.Name)."
            Get-AzNetworkInterface -Name $nic.Name | Select-Object Id, Name, VirtualMachine, ResourceGroupName, EnableAcceleratedNetworking| Export-Csv -Path $LogCSV -Append -NoTypeInformation
            }
        }
    }
}

# Stop logging
Stop-Transcript

