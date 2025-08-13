<#
This script checks how much of the quota is used on a file share and returns the percentage used. Note the automation account's managed identity must have permissions to read the file share info or it will return an error.

#>

param (
    $rgname,        # Resource Group Name
    $stname,        # Storage Account Name
    $sharename,     # File Share Name
    $subname        # Subscription Name
)

function Show-Usage {
    Write-Host "`nUsage:" -ForegroundColor Red
    Write-Host "get-azure-file-share-capacity-usage.ps1 -rgname <ResourceGroupName> -stname <StorageAccountName> -sharename <FileShareName> -subname <SubscriptionName>" -ForegroundColor Red
    Write-Host "`nExample:" -ForegroundColor Red
    Write-Host "get-azure-file-share-capacity-usage.ps1 -rgname 'MyResourceGroup' -stname 'MyStorageAccount' -sharename 'MyFileShare' -subname 'MySubscription'`n" -ForegroundColor Red
}

function Assert-Params {
    $params = @($rgname, $stname, $sharename, $subname)
    foreach ($param in $params) {
        if (-not $param) {
            Write-Host "Error: Missing required parameter." -ForegroundColor Red
            Show-Usage
            throw "Required parameter is missing."
        }
    }
}

Assert-Params

Write-Host "Checking Azure File Share Capacity Usage..." -ForegroundColor Cyan
Write-Host "Resource Group      : $rgname" -ForegroundColor Cyan
Write-Host "Storage Account     : $stname" -ForegroundColor Cyan
Write-Host "File Share          : $sharename" -ForegroundColor Cyan
Write-Host "Subscription        : $subname`n" -ForegroundColor Cyan

try {
    connect-azaccount -Subscription $subname -Identity
}
catch {
    Write-Host "Error: Unable to connect to Azure with the provided subscription." -ForegroundColor Red
    throw "Connection failed."
}

try {
    $st = Get-AzRmStorageShare -resourcegroupname $rgname -StorageAccountName $stname -name $sharename -GetShareUsage
}
catch {
    Write-Host "Error: Unable to retrieve file share information. Please check the provided parameters and permissions." -ForegroundColor Red
    throw "Failed to retrieve file share information."
}

[int]$totalsize = $st.QuotaGiB
[int]$usage = [math]::Round(($st.ShareUsageBytes) / 1GB) 

$percentfull = ($usage / $totalsize) * 100

Write-Host "Total Size (GiB)    : $totalsize" -ForegroundColor Green
Write-Host "Used Size (GiB)     : $usage" -ForegroundColor Green
Write-Host "Percentage Used (%) : $percentfull" -ForegroundColor Green

write-output $percentfull