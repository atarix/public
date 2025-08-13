param (
    $rgname,
    $sqlminame,    
    $subname
)

function Show-Usage {
    Write-Host "`nUsage:" -ForegroundColor Red
    Write-Host "get-azure-sqlmi-storage-usage.ps1 -rgname <ResourceGroupName> -sqlminame <SqlManagedInstanceName> -subname <SubscriptionName>" -ForegroundColor Red
    Write-Host "`nExample:" -ForegroundColor Red
    Write-Host "get-azure-sqlmi-storage-usage.ps1 -rgname 'MyResourceGroup' -sqlminame 'MySqlManagedInstance' -subname 'MySubscription'`n" -ForegroundColor Red
}

function Assert-Params {
    $params = @($rgname, $sqlminame, $subname)
    foreach ($param in $params) {
        if (-not $param) {
            Write-Host "Error: Missing required parameter." -ForegroundColor Red
            Show-Usage
            throw "Required parameter is missing."
        }
    }
}

Assert-Params

Write-Host "Checking Azure SQL Managed Instance Storage Usage..." -ForegroundColor Cyan
Write-Host "Resource Group       : $rgname" -ForegroundColor Cyan
Write-Host "SQL Managed Instance : $sqlminame" -ForegroundColor Cyan
Write-Host "Subscription         : $subname`n" -ForegroundColor Cyan

try {
    connect-azaccount -Subscription $subname -Identity
}
catch {
    Write-Host "Error: Unable to connect to Azure with the provided subscription." -ForegroundColor Red
    throw "Connection failed."
}

try {
    $mi = Get-AzSqlInstance -Name $sqlminame -ResourceGroupName $rgname
} catch {
    Write-Host "Error: Unable to retrieve SQL Managed Instance information. Please check the provided parameters and permissions." -ForegroundColor Red
    throw "Failed to retrieve SQL Managed Instance information."
}

try {
    $datausage = (get-azmetric -ResourceId $mi.id -MetricName "storage_space_used_mb").data | where {$_.average -ge 1} | sort timestamp -Descending | select -first 1
    $datausageinGB = [math]::Round(($datausage.average) / 1024)
} catch {
    Write-Host "Error: Unable to retrieve storage usage metrics. Please check the provided parameters and permissions." -ForegroundColor Red
    throw "Failed to retrieve storage usage metrics."
}

$percentfull = [math]::Round(($datausageinGB / $mi.StorageSizeInGB) * 100, 2)

Write-Host "Total Storage Size (GB) : $($mi.StorageSizeInGB)" -ForegroundColor Green
Write-Host "Used Storage Size (GB)  : $datausageinGB" -ForegroundColor Green
Write-Host "Percentage Used (%)     : $percentfull" -ForegroundColor Green

write-output $percentfull