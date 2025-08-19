<# This script switches on all session hosts in Azure Virtual Desktop host pools for a specified duration.
   It disables scaling plans during the execution and re-enables them afterward.
   Usage: .\switch-on-all-session-hosts.ps1 -subname <SubscriptionName> [-durationInMinutes <DurationInMinutes>]
#>

param (
    $subname, # Subscription Name
    $durationInMinutes = 60 # Duration in minutes to check the file share usage
)

function Show-Usage {
    Write-Output "Usage: .\switch-on-all-session-hosts.ps1 -subname <SubscriptionName> [-durationInMinutes <DurationInMinutes>]"
    Write-Output "Example: .\switch-on-all-session-hosts.ps1 -subname 'MySubscription' -durationInMinutes 120"
    Write-Output "Parameters:"
    Write-Output "  -subname: Name of the Azure subscription."
    Write-Output "  -durationInMinutes: Duration in minutes to keep the session hosts on. Default is 60 minutes."
    exit 1
}

function Assert-Params {
    $params = @($subname, $durationInMinutes)
    foreach ($param in $params) {
        if (-not $param) {
            Write-Output "Error: Missing required parameter."
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
        Write-Output "Error: Unable to retrieve scaling plan for host pool: $HostPoolName" | Out-Null
        return $null
    }

    Write-Output "    Scaling plan: " | Out-Null
    foreach ($plan in $scalingPlans) {
        foreach ($hostPoolRef in $plan.HostPoolReference) {
            $hostPoolRefName = $hostPoolRef.HostPoolArmPath.Split('/')[-1]
            if ($hostPoolRefName -eq $HostPoolName) {
                Write-Output $plan.Name | Out-Null
                $scalingPlan = [PSCustomObject]@{
                    Name          = $plan.Name
                    Status        = if ($hostPoolRef.ScalingPlanEnabled) { "Enabled" } else { "Disabled" }
                    ResourceId    = $hostPoolRef.HostPoolArmPath
                    ResourceGroup = $plan.ResourceGroupName
                }
                return $scalingPlan
            }
        }
    }
    Write-Output "Not found." | Out-Null
    return $null
}

function Start-SessionHosts {
    param (
        [string]$HostPoolName,
        [string]$HostPoolResourceGroupName
    )

    Write-Output "`n    Starting session hosts for host pool: $HostPoolName"

    $sessionHosts = Get-AzWvdSessionHost -ResourceGroupName $HostPoolResourceGroupName -HostPoolName $HostPoolName -ErrorAction SilentlyContinue

    if ($sessionHosts) {
        foreach ($sessionHost in $sessionHosts) {
            try {
                $vm = Get-AzVM -ResourceId $sessionHost.ResourceId -Status

                if ($vm.Statuses.Code -contains "PowerState/running") {
                    Write-Output "    VM: $($sessionHost.Name) is already running."
                }
                else {
                    Write-Output "    Starting VM: $($sessionHost.Name)"
                    Get-AzVM -ResourceId $sessionHost.ResourceId | Start-AzVM -NoWait
                }
            }
            catch {
                Write-Output "    Failed to start VM $($sessionHost.Name): $_"
            }
        }

        # Wait for all VMs to be running
        Write-Output "    Waiting for VMs to be in running state..."

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
                    Write-Output "    Failed to retrieve status for VM $($sessionHost.Name): $_"
                }
            }

            if (-not $nonRunning) {
                Write-Output ("    All VMs are running after {0:N1} minutes." -f $sw.Elapsed.TotalMinutes)
                break
            }

            Write-Output "    These VMs are currently deallocated:"
            foreach ($vm in $nonRunning) {
                Write-Output "     - $($vm.Name)"
            }

            Write-Output ("    {0} – {1} VM(s) still starting..." -f (Get-Date -Format "HH:mm:ss"), $nonRunning.Count)
            Start-Sleep -Seconds $checkIntervalSeconds

        } while ($sw.Elapsed.TotalMinutes -lt $timeoutMinutes)

        if ($nonRunning) {
            Write-Output ("    Timeout of {0} min reached – {1} VM(s) are still not running." `
                    -f $timeoutMinutes, $nonRunning.Count)
            exit 1
        }

    }
    else {
        Write-Output "    No session hosts found in host pool '$HostPoolName'. Skipping VM start sequence."
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

    Write-Output "Waiting for $DurationInMinutes minutes..."

    while ($elapsedSeconds -lt $totalSeconds) {
        Start-Sleep -Seconds $intervalSeconds
        $elapsedSeconds += $intervalSeconds
        Write-Output ("Elapsed time: {0:N1} minutes" -f ($elapsedSeconds / 60))
    }

    Write-Output "Wait time completed."
}


# ================================================================
# Main Script Execution
# ================================================================
Assert-Params

Write-Output "Switching on all session hosts for $durationInMinutes minutes..."
Write-Output "Subscription        : $subname`n"

# scalingPlanSnaps empty array to store scaling plan snapshots for rollback
$scalingPlanSnaps = @()

# ----------------------------------------------------------------
# Connect to Azure account
# ----------------------------------------------------------------
try {
    connect-azaccount -Subscription $subname# -Identity
}
catch {
    Write-Output "Error: Unable to connect to Azure with the provided subscription."
    throw "Connection failed."
}

# ----------------------------------------------------------------
# Get Host Pools
# ----------------------------------------------------------------
try {
    $hostPools = Get-AzWvdHostPool
    if ($hostPools.Count -eq 0) {
        Write-Output "No host pools found in the subscription."
        exit 0
    }
    else {
        Write-Output "Found $($hostPools.Count) host pools in the subscription."
        foreach ($hostPool in $hostPools) {
            Write-Output "     - $($hostPool.Name)"
        }
    }
}
catch {
    Write-Output "Error: Unable to retrieve host pools for the subscription."
    throw "Failed to get host pools."
}


# ----------------------------------------------------------------
# Disable scaling plans for each host pool
# ----------------------------------------------------------------
foreach ($hostPool in $hostPools) {
    Write-Output "`nProcessing host pool: $($hostPool.Name)"

    $scalingPlan = Get-ScalingPlan -HostPoolName $hostPool.Name

    if ($scalingPlan) {
        Write-Output "          Status: "
        # Add scaling plan to snapshot for rollback
        $scalingPlanSnaps += $scalingPlan

        if ($scalingPlan.Status -eq "Enabled") {

            Write-Output "Enabled"

            $modifiedRefs = @{
                HostPoolArmPath    = $scalingPlan.ResourceId
                ScalingPlanEnabled = $false
            }

            Write-Output "`nDisabling scaling plan during script execution..."

            # ----------------------------------------------------------------
            # Disable scaling plans
            # ----------------------------------------------------------------
            try {
                Update-AzWvdScalingPlan -ResourceGroupName $scalingPlan.ResourceGroup -Name $scalingPlan.Name -HostPoolReference $modifiedRefs | Out-Null
            }
            catch {
                Write-Output "Error: Unable to disable scaling plan for host pool: $($hostPool.Name)"
                Write-Error $_
                continue
            }        
        }
        else {
            Write-Output "Disabled"
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
    Write-Output "`nRe-enabling scaling plan: $($scalingPlan.Name)"

    $modifiedRefs = @{
        HostPoolArmPath    = $scalingPlan.ResourceId
        ScalingPlanEnabled = $true
    }

    try {
        Update-AzWvdScalingPlan -ResourceGroupName $scalingPlan.ResourceGroup -Name $scalingPlan.Name -HostPoolReference $modifiedRefs | Out-Null
        Write-Output "Scaling plan re-enabled successfully."
    }
    catch {
        Write-Output "Error: Unable to re-enable scaling plan for host pool: $($scalingPlan.Name)"
        Write-Error $_
    }
}



