# --------------------------------------------------------------------------------------------
# Find Unused Storage Accounts 
# Description: This script will find all storage accounts in a subscription and resource group that have not been used for a specified number of days.
# Filename: FindUnusedStorageAccounts.ps1
# Author: Darel Johnson
# Date: 04/12/2023
# Modified: 04/13/2023
# Usage instructions: 
# Set the Execution Policy to allow the script to run. From an elevated PowerShell prompt, run the following command:
# Set-ExecutionPolicy -ExecutionPolicy Unrestricted -Scope CurrentUser
# Run the script with the following parameters:
# .\FindUnusedStorageAccounts.ps1 -subscriptionName "Your Subscription Name" -resourceGroupName "Your Resource Group Name" -daysAgo 90 -needCsv [Y]/[y]
# --------------------------------------------------------------------------------------------

param (
    [Parameter(Mandatory=$true)]
    [string] $subscriptionName,
    [Parameter(Mandatory=$true)]
    [string] $resourceGroupName,
	[Parameter(Mandatory=$true)]
	[int] $daysAgo,
    [Parameter(Mandatory=$false)]
    [string] $needCsv
)

# Check if Azure PowerShell module is installed
if (-not (Get-InstalledModule -Name Az -ErrorAction SilentlyContinue)) {
    Install-Module -Name Az -AllowClobber -Scope CurrentUser -Force
}

# Authenticate to your Azure account if not already authenticated
if (-not (Get-AzContext)) {
    Connect-AzAccount
}

# Set the target subscription
Select-AzSubscription -SubscriptionName $subscriptionName

# Set threshold for unused storage accounts (e.g., 30 days)
$unusedThresholdDays = $daysAgo
$thresholdDate = (Get-Date).AddDays(-$unusedThresholdDays)

# Set output CSV file name
$createCsv = $needCsv
$OutputCsv = "UnusedStorageAccounts.csv"

# Get all storage accounts in the target subscription and resource group
$storageAccounts = Get-AzStorageAccount -ResourceGroupName $resourceGroupName

# Initialize an empty list to store unused storage accounts
$unusedStorageAccounts = @()

# Initialize an empty list storage blobs
$storageBlobs = @()

# Initialize variables to track progress
$TotalStorageAccounts = $StorageAccounts.Count
$ProcessedStorageAccounts = 0

foreach ($StorageAccount in $StorageAccounts) {
    $Context = $StorageAccount.Context
    
    $MaxRetries = 3
    $RetryCount = 0
    $Containers = $null

    while ($RetryCount -lt $MaxRetries) {
        try {
            $Containers = Get-AzStorageContainer -Context $Context
            break
        }
        catch {
            $RetryCount++
            Write-Host -Foregroundcolor Orange "Error while fetching containers for $($StorageAccount.StorageAccountName). Retrying ($RetryCount of $MaxRetries)"
            Start-Sleep -Seconds (2 * $RetryCount)
        }
    }

    $IsUnused = $true

    foreach ($Container in $Containers) {
        $Blobs = Get-AzStorageBlob -Container $Container.Name -Context $Context

        foreach ($Blob in $Blobs) {
           
            if ($Blob.LastModified -gt $ThresholdDate) {
                $IsUnused = $false
                Write-Host -Foregroundcolor Blue "Found $($Blob.Name)  blob in $($StorageAccount.StorageAccountName) storage account"
                break
            }
        }

        if (-not $IsUnused) {
            break
        }
    }

    if ($IsUnused -and $null -eq $Blob) {
        $unusedStorageAccounts += $StorageAccount
        $storageBlobs += $Blob
    }

    $ProcessedStorageAccounts++

    # Show progress
    Write-Host ""
    $PercentComplete = [math]::Round(($ProcessedStorageAccounts / $TotalStorageAccounts) * 100, 2)
    Write-Host "Processing storage account: $($StorageAccount.StorageAccountName) ($ProcessedStorageAccounts of $TotalStorageAccounts, $PercentComplete% complete)"
}

# Clear progress
Write-Progress -Activity "Finding unused storage accounts" -Completed

# Output the list of unused storage accounts
if ($unusedStorageAccounts.Count -gt 0){
    Write-Host ""
    Write-Host "Unused storage accounts were found for a period of $($unusedThresholdDays) days."
    Write-Host "$($storageBlobs.Count) blobs were found in unused storage accounts" -Foregroundcolor Blue

    foreach ($storageAccount in $unusedStorageAccounts) {
        Write-Host "Storage Account Name: $($storageAccount.StorageAccountName)" -Foregroundcolor Cyan
        Write-Host "Location: $($storageAccount.Location)" -Foregroundcolor Magenta 
        Write-Host ""
    }
    # Report unused storage accounts in a table
	$unusedStorageAccounts | Format-Table -Property StorageAccountName, Location
}
else{
	Write-Host "No unused storage accounts were found."
    Write-Host ""
	Write-Host "$($storageBlobs.Count) blobs were found in storage account containers" -Foregroundcolor Orange
}

# Output unused storage accounts to CSV file
If ($createCsv -eq "Y" -or $createCsv -eq "y" -and $createCsv -ne "n" -or $createCsv -ne "N" -or $null -ne $createCsv) {
    Write-Host "Creating CSV file..."
    Write-Host ""
    $UnusedStorageAccounts | Select-Object -Property StorageAccountName, Location | Export-Csv -Path $OutputCsv -NoTypeInformation

    # Display completion message
    Write-Host "The list of unused storage accounts has been exported to $OutputCsv" -ForegroundColor Green
}
