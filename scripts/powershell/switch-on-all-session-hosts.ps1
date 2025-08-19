<# This script switches on all session hosts in Azure Virtual Desktop host pools for a specified duration.
   It disables scaling plans during the execution and re-enables them afterward.
   Usage: .\switch-on-all-session-hosts.ps1 -subname <SubscriptionName> [-durationInMinutes <DurationInMinutes>]
#>

param (
    $subname, # Subscription Name
    $durationInMinutes = 60 # Duration in minutes to check the file share usage
)

function Show-Usage {
    Write-Host "Usage: .\switch-on-all-session-hosts.ps1 -subname <SubscriptionName> [-durationInMinutes <DurationInMinutes>]" -ForegroundColor Yellow
    Write-Host "Example: .\switch-on-all-session-hosts.ps1 -subname 'MySubscription' -durationInMinutes 120" -ForegroundColor Yellow
    Write-Host "Parameters:" -ForegroundColor Yellow
    Write-Host "  -subname: Name of the Azure subscription." -ForegroundColor Yellow
    Write-Host "  -durationInMinutes: Duration in minutes to keep the session hosts on. Default is 60 minutes." -ForegroundColor Yellow
    exit 1
}

function Assert-Params {
    $params = @($subname, $durationInMinutes)
    foreach ($param in $params) {
        if (-not $param) {
            Write-Host "Error: Missing required parameter." -ForegroundColor Red
            Show-Usage
            throw "Required parameter is missing."
        }
    }
}

function Get-ScalingPlan {
    param (
        [string]$HostPoolName
    )

    try {
        $scalingPlans = Get-AzWvdScalingPlan
    }
    catch {
        Write-Host "Error: Unable to retrieve scaling plan for host pool: $HostPoolName" -ForegroundColor Red
        return $null
    }

    Write-Host "    Scaling plan: " -NoNewline -ForegroundColor Cyan
    foreach ($plan in $scalingPlans) {
        foreach ($hostPoolRef in $plan.HostPoolReference) {
            $hostPoolRefName = $hostPoolRef.HostPoolArmPath.Split('/')[-1]
            if ($hostPoolRefName -eq $HostPoolName) {
                Write-Host $plan.Name -ForegroundColor Green
                return @{
                    Name          = $plan.Name
                    Status        = $hostPoolRef.ScalingPlanEnabled ? "Enabled" : "Disabled"
                    ResourceId    = $hostPoolRef.HostPoolArmPath
                    ResourceGroup = $plan.ResourceGroupName
                }
            }
        }
    }
    Write-Host "Not found." -ForegroundColor Red
    return $null
}

function Start-SessionHosts {
    param (
        [string]$HostPoolName,
        [string]$HostPoolResourceGroupName
    )

    Write-Host "`n    Starting session hosts for host pool: $HostPoolName" -ForegroundColor Cyan

    $sessionHosts = Get-AzWvdSessionHost -ResourceGroupName $HostPoolResourceGroupName -HostPoolName $HostPoolName -ErrorAction SilentlyContinue

    if ($sessionHosts) {
        foreach ($sessionHost in $sessionHosts) {
            try {
                $vm = Get-AzVM -ResourceId $sessionHost.ResourceId -Status

                if ($vm.Statuses.Code -contains "PowerState/running") {
                    Write-Host "    VM: $($sessionHost.Name) is already running." -ForegroundColor Green
                }
                else {
                    Write-Host "    Starting VM: $($sessionHost.Name)" -ForegroundColor Cyan
                    Get-AzVM -ResourceId $sessionHost.ResourceId | Start-AzVM -NoWait
                }
            }
            catch {
                Write-Warning "    Failed to start VM $($sessionHost.Name): $_"
            }
        }

        # Wait for all VMs to be running
        Write-Host "    Waiting for VMs to be in running state..." -ForegroundColor Cyan

        $checkIntervalSeconds = 15
        $timeoutMinutes = 45
        $sw = [System.Diagnostics.Stopwatch]::StartNew()

        do {
            $nonRunning = @()
            foreach ($sessionHost in $sessionHosts) {
                try {
                    $vmStatus = Get-AzVM -ResourceId $sessionHost.ResourceId -Status
                    if ($vmStatus.Statuses.Code -notcontains 'PowerState/running' -and $sessionHost.Status -ne 'Available') {
                        $nonRunning += $sessionHost
                    }
                }
                catch {
                    Write-Warning "    Failed to retrieve status for VM $($sessionHost.Name): $_"
                }
            }

            if (-not $nonRunning) {
                Write-Host ("    All VMs are running after {0:N1} minutes." -f $sw.Elapsed.TotalMinutes) -ForegroundColor Green
                break
            }

            Write-Host "    These VMs are currently deallocated:" -ForegroundColor Yellow
            foreach ($vm in $nonRunning) {
                Write-Host "     - $($vm.Name)" -ForegroundColor Yellow
            }

            Write-Host ("    {0} – {1} VM(s) still starting..." -f (Get-Date -Format "HH:mm:ss"), $nonRunning.Count) -ForegroundColor DarkGray
            Start-Sleep -Seconds $checkIntervalSeconds

        } while ($sw.Elapsed.TotalMinutes -lt $timeoutMinutes)

        if ($nonRunning) {
            Write-Warning ("    Timeout of {0} min reached – {1} VM(s) are still not running." `
                    -f $timeoutMinutes, $nonRunning.Count)
            exit 1
        }

    }
    else {
        Write-Host "    No session hosts found in host pool '$HostPoolName'. Skipping VM start sequence." -ForegroundColor Yellow
    }
}


function Wait-AndLogProgress {
    param (
        [int]$DurationInMinutes
    )

    $totalSeconds = $DurationInMinutes * 60
    if ($totalSeconds -le 300) {
        $intervalSeconds = 10
    }
    else {
        $intervalSeconds = 300
    }
    $elapsedSeconds = 0

    Write-Host "Waiting for $DurationInMinutes minutes..." -ForegroundColor Yellow

    while ($elapsedSeconds -lt $totalSeconds) {
        Start-Sleep -Seconds $intervalSeconds
        $elapsedSeconds += $intervalSeconds
        Write-Host ("Elapsed time: {0:N1} minutes" -f ($elapsedSeconds / 60)) -ForegroundColor Cyan
    }

    Write-Host "Wait time completed." -ForegroundColor Green
}


# ================================================================
# Main Script Execution
# ================================================================
# Assert-Params

Write-Host "Switching on all session hosts for $durationInMinutes minutes..." -ForegroundColor Cyan
Write-Host "Subscription        : $subname`n" -ForegroundColor Cyan

$scalingPlanSnaps = @()

# ----------------------------------------------------------------
# Connect to Azure account
# ----------------------------------------------------------------
try {
    connect-azaccount -Subscription $subname -Identity
}
catch {
    Write-Host "Error: Unable to connect to Azure with the provided subscription." -ForegroundColor Red
    throw "Connection failed."
}

# ----------------------------------------------------------------
# Get Host Pools
# ----------------------------------------------------------------
try {
    $hostPools = Get-AzWvdHostPool
    if ($hostPools.Count -eq 0) {
        Write-Host "No host pools found in the subscription." -ForegroundColor Yellow
        exit 0
    }
    else {
        Write-Host "Found $($hostPools.Count) host pools in the subscription." -ForegroundColor Green
        foreach ($hostPool in $hostPools) {
            Write-Host "     - $($hostPool.Name)" -ForegroundColor Cyan
        }
    }
}
catch {
    Write-Host "Error: Unable to retrieve host pools for the subscription." -ForegroundColor Red
    throw "Failed to get host pools."
}


# ----------------------------------------------------------------
# Disable scaling plans for each host pool
# ----------------------------------------------------------------
foreach ($hostPool in $hostPools) {
    Write-Host "`nProcessing host pool: $($hostPool.Name)" -ForegroundColor Cyan

    $scalingPlan = Get-ScalingPlan -HostPoolName $hostPool.Name

    if ($scalingPlan) {
        Write-Host "          Status: " -NoNewline -ForegroundColor Cyan

        # Add scaling plan to snapshot for rollback
        $scalingPlanSnaps += $scalingPlan

        if ($scalingPlan.Status -eq "Enabled") {
            Write-Host "Enabled" -ForegroundColor Green

            $modifiedRefs = @{
                HostPoolArmPath    = $scalingPlan.ResourceId
                ScalingPlanEnabled = $false
            }

            Write-Host "`nDisabling scaling plan during script execution..." -ForegroundColor Yellow

            # ----------------------------------------------------------------
            # Disable scaling plans
            # ----------------------------------------------------------------
            try {
                Update-AzWvdScalingPlan -ResourceGroupName $scalingPlan.ResourceGroup -Name $scalingPlan.Name -HostPoolReference $modifiedRefs | Out-Null
            }
            catch {
                Write-Host "Error: Unable to disable scaling plan for host pool: $($hostPool.Name)" -ForegroundColor Red
                Write-Error $_
                continue
            }        }
        else {
            Write-Host "Disabled" -ForegroundColor Red
        }

        # ----------------------------------------------------------------
        # Start all session hosts in the host pool
        # ----------------------------------------------------------------
        Start-SessionHosts -HostPoolName $hostPool.Name -HostPoolResourceGroupName $hostPool.ResourceGroupName
    }
}

# ----------------------------------------------------------------
# Wait for the specified duration before re-enabling scaling plans
# ----------------------------------------------------------------
Wait-AndLogProgress -DurationInMinutes $durationInMinutes

foreach ($scalingPlan in $scalingPlanSnaps) {
    Write-Host "`nRe-enabling scaling plan: $($scalingPlan.Name)" -ForegroundColor Cyan

    $modifiedRefs = @{
        HostPoolArmPath    = $scalingPlan.ResourceId
        ScalingPlanEnabled = $true
    }

    try {
        Update-AzWvdScalingPlan -ResourceGroupName $scalingPlan.ResourceGroup -Name $scalingPlan.Name -HostPoolReference $modifiedRefs | Out-Null
        Write-Host "Scaling plan re-enabled successfully." -ForegroundColor Green
    }
    catch {
        Write-Host "Error: Unable to re-enable scaling plan for host pool: $($scalingPlan.Name)" -ForegroundColor Red
        Write-Error $_
    }
}



