## Do not use unless you have knowledge or testing of how actions will affect your enviorment.
## This script will alter critical Windows update services.
## No validation checks have been added.
## USE AT YOUR OWN RISK



# confirmation before proceeding with script
Write-Host "WARNING: This script will alter critical Windows update services. It's your ball game!" -ForegroundColor Red
$response = Read-Host "Continue? (Y/N)"
if ($response.ToUpper() -ne "YES") {
    Write-Host "Exiting Script..."
    exit
}

# saves file path as a variable
$folderpath = "C:\Windows\SoftwareDistribution"

# validates folder on machine
if (-not (Test-Path -Path $folderpath)) {
    Write-Host "Folder $folderpath does not exist. Exiting script..." -ForegroundColor Red
    exit
}

# collects current ACL for SoftwareDistribution
try {
    $acl = Get-Acl -Path $folderpath -ErrorAction Stop
    Write-Host "Successfully retrieved ACL for $folderpath."
} Catch {
    Write-Error "Failed to retrieve ACL for $folderpath."
    Write-Error "Error Details: $_"
}

# checks if services are running and stops them
$services = "wuauserv", "cryptsvc", "bits", "msiserver"
    foreach ($service in $services) {
        if (-not (Get-Service -Name $service -ErrorAction SilentlyContinue)) {
            Write-Host "Service $service does not exist. Skipping..." -ForegroundColor Yellow
            continue 
    }
        $attempts = 0
        $maxAttempts = 3

        while ($attempts -lt $maxAttempts) {
            try {
                if ((Get-Service  -Name $service).Status -eq "Running") {
                    Stop-Service -Name $service -ErrorAction Stop
                    Write-Host "Successfully stopped service: $service" -ForegroundColor Green
                    break
                } else {
                    Write-Host "Service $service is not running." -ForegroundColor Yellow
                    break
                }
            } catch {
                $attempts++
                Write-Host "Failed to stop service $service. Attempt $attempts of $maxAttempts"
                if ($attempts -ge $maxAttempts) {
                    Write-Error "Failed to stop service $service after $maxAttempts attenpts. Exiting script..."
                    exit 1
                }
                Start-Sleep -Seconds 2 
            }
         }
     }
 

# grabs all subfolders and contents
$items = Get-ChildItem -Path $folderpath -recurse -force

# parallels taking ownership of folders and files
$jobs=@()
foreach ($item in $items) {
    Write-Host "Beginning to take ownership of $($item.FullName)..."
    $jobs += Start-Job -ScriptBlock {
        param ($path)
        & takeown /f $path /r /d y
    } -ArgumentList $item.FullName
}
Write-Host "Ownership tasks successfully started."

# waiting for jobs to complete or timeout
Write-Host "Waiting for ownership tasks to complete..."
$timeout = 300  # Timeout in seconds
$startTime = Get-Date

while (($jobs | Where-Object { $_.State -ne "Completed" }).Count -gt 0) {
    Start-Sleep -Seconds 5
    if ((Get-Date) -gt $startTime.AddSeconds($timeout)) {
        Write-Error "Ownership tasks did not complete within the timeout period."
        break
    }
}

# checking failed jobs
foreach ($job in $jobs) {
    if ($job.State -ne "Completed") {
        Write-Error "Job $($job.Id) failed or did not complete."
    }
}

# grants admins full control
Write-Host "Granting admin control of $folderpath..."
icacls $folderpath /grant administrators: F /T /C
Write-Host "Admin controls granted successfully."

# deletes target folder
try {
    cmd /c rmdir /s /q "C:\Windows\SoftwareDistribution"
    Write-Host "Folder deleted successfully." -ForegroundColor Green
} catch {
    Write-Error "Failed to delete folder. Error:$_"
}

# starts services previously stopped
foreach ($service in $services) {
    $attempts = 0
    $maxAttempts = 3

    Write-Host "Processing $service..." -ForegroundColor Cyan

    while ($attempts -lt $maxAttempts) {
        try {
            # get service status
            $serviceStatus = (Get-Service -Name $service -ErrorAction Stop).Status

            # handles different server states
            if ($serviceStatus -eq "Stopped") {
                Start-Service -Name $service -ErrorAction Stop
                Write-Host "Restarted service $service successfully." -ForegroundColor Green
                break
            } elseif ($serviceStatus -eq "Running") {
                Write-Host "Service $service is already running." -ForegroundColor Green
                break
            } elseif ($serviceStatus -eq "Paused") {
                Write-Host "Service $service is Paused." -ForegroundColor Yellow
                break
            } else {
                Write-Host "Service $service state is Unknown." -ForegroundColor Red
                break
            }
        } catch {
            # handles any errors durring service management
            $attempts++
            if ($attempts -lt $maxAttempts) {
                Write-Host "Attempting to restart service $service...attempt $attempts of $maxAttempts" -ForegroundColor Yellow
                Start-Sleep -Seconds 2
            } else {
                Write-Error "Failed to start service $service after $maxAttempts attempts. Exiting script..." -ForegroundColor Red
                exit 1
            }
        }
    }
}


# outputs services statuses
Get-Service -Name $services

# applies ACL to folder
   
if (Test-Path -Path $folderpath) {
    try {
        Write-Output "Restoring original ACL for $folderpath..."
         Set-Acl -Path $folderpath -AclObject $acl
         Write-Output "Successfully restored original ACL to $folderpath."
    } Catch {
        Write Error "Failed to restore original ACL to $folderpath. Error:$_"
    }
} else {
    Write-Host "Folder $folderpath does not exist, skipping ACL restoration."
}

