
#### WARNING: THIS SCRIPT ALTERS CRITICAL WINDOWS UPDATE SERVICES.
#### WARNING: THIS SCRIPT DELETES A FOLDER IN THE C:\Windows\ DIRECTORY.
#### THIS VERSION HAS BEEN DRY RAN ON A VIRTUAL MACHINE. 05/01/2025 2:10PM CST

#################################################################################################################################
#                                                                                                                               #
#  Script Name: Delete.SoftwareDistribution.ps1                                                                                 #
#  Purpose:                                                                                                                     #
#     This script is designed to delete the SoftwareDistribution folder and its contents on Windows systems in a modular        #
#     format that can be easily altered and reused depending on the environment and needs of the user.                          #
#  Prerequisites:                                                                                                               #
#     1. The script must be run with administrative privileges.                                                                 #
#     2. The script is designed to be run on Windows systems only.                                                              #
#     3. The script requires PowerShell to be installed on the system.                                                          #
#     4. Powershell 5.0 or higher.                                                                                              #
#  Version 1.0.1 - 04/30/2025                                                                                                   #
#  Log File Path: C:\Windows\config\logs\Delete.SoftwareDistribution.log                                                        #                                                                                                   #
#                                                                                                                               #
#                                                                                                                               #
#                             ############ Table of Contents #############                                                      #
#                             # 1. User Warning and Confirmation         #                                                      #
#                             # 2. Validate Folder Path                  #                                                      #
#                             # 3. Fetching and Cloning ACL              #                                                      #
#                             # 4. Stopping Windows Update Services      #                                                      #
#                             # 5. Taking Ownership of Files and Folders #                                                      #
#                             # 6. Grants admins full control            #                                                      #
#                             # 7. Deleting the Folder and its Contents  #                                                      #
#                             # 8. Restarting Windows Update Services    #                                                      #
#                             # 9. Restoring Original ACL                #                                                      #
#                             # 10. Final Output/Summary                 #                                                      #
#                             ############################################                                                      #
#                                                                                                                               #
#################################################################################################################################

###################################### Issues and Improvements #######################################
# 1. Add logging to script to improve error handling and debugging. -COMPLETED                       #
#    - Logging function and log file path added.                                                     #
#    - Logging added to the following areas:                                                         #
#       1. ACL                                                                                       #
#       2. Service management                                                                        #
#       3. File and folder ownership                                                                 #
#       4. Folder deletion                                                                           #
#       5. ACL restoration                                                                           #
#       6. Final summary                                                                             #
# 2. Add a function to check if the script is running with administrative privileges. -COMPLETED     #
# 3. Improve on in-script documentation and comments. -COMPLETED                                     #
#    - Added comments to explain the purpose of each section of the script.                          #
#    - Refining to make more consise and clear.                                                      #
# 4. Add post-job processing. -COMPLETED                                                             #
######################################################################################################

######################################################################################################
#      NOTES FOR ANSIBLE USAGE:                                                                      #
# 1. Uses exit codes to indicate success or failure. Will need fail_when                             #
#    Module needed to enssure exit codes are logged correctly in Ansible:                            #
#                                                                                                    #
#      # Execute the PowerShell script and account for exit codes                                    #
#    - name: Execute the PowerShell script                                                           #
#      win_shell: |                                                                                  #
#        powershell.exe -ExecutionPolicy Bypass -File C:\Scripts\Delete.SoftwareDistribution.ps1     #
#      register: script_result                                                                       #
#      failed_when: script_result.rc != 0 ## ensures that the script's exit code is checked ##       #
#                                                                                                    #
# 2. Requires administrative privileges to run.                                                      #
######################################################################################################


## Part 1: User Warning and Confirmation
# This section provides a warning to the user about the potential impact of running the script.
# Can be removed if a more zero-touch approach is desired.
Write-Host "WARNING: This script will alter critical Windows update services. Use at your own discression!" -ForegroundColor Red
$response = Read-Host "Continue? (Y/N)"
if (($response.ToUpper() -eq "NO") -or ($response.ToUpper() -eq "N")) {
    Write-Host "Exiting Script..." -ForegroundColor Red
    Log-Error -Message "User chose to exit the script." -Level "INFO"
    exit
} else {
    Write-Host "Continuing with script..." -ForegroundColor Green
    Log-Error -Message "User chose to continue with the script." -Level "INFO"
}


# Check if PowerShell version is 5.0 or higher
if ($PSVersionTable.PSVersion.Major -lt 5) {
    Write-Host "This script requires PowerShell 5.0 or higher. Exiting..." -ForegroundColor Red
    Log-Error -Message "This script requires PowerShell 5.0 or higher. Exiting..." -Level "ERROR"
    Write-Host "Exiting script..." -ForegroundColor Red
    exit 1
}

# Saves file path as a variable
$folderpath = "C:\Windows\SoftwareDistribution"


## Sets log file path
# This is the path where the log file will be saved.
$logFilePath = "C:\Windows\config\logs\Delete.SoftwareDistribution.log"


## Error logging function
# This function logs error messages to a specified log file.
function Log-Error {
    param (
        [string]$Message
        [string]$Level = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "$timestamp Error: $Message"
    Add-Content -Path $logFilePath -Value $logMessage

}


## Part 2: Validate Folder Path
# This section checks if the specified folder path exists and logs the result.
if (-not (Test-Path -Path $folderpath)) {
    Write-Host "Folder $folderpath does not exist. Exiting script..." -ForegroundColor Red
    Log-Error -Message "Folder $folderpath does not exist. Exiting script..." -Level "ERROR"
    Write-Host "Exiting script..." -ForegroundColor Red
    Log-Error -Message "Exiting script..." -Level "INFO"
    exit
}


## Part 3: Fetching and Cloning ACL
# This section retrieves the Access Control List (ACL) for the specified folder path and backs it up.
# ACL is used to restore permissions after the script has completed its tasks--will likely be unnecessary as folder is deleted.
try {
    $acl = Get-Acl -Path $folderpath -ErrorAction Stop
    Write-Host "Successfully retrieved ACL for $folderpath."
    Log-Error -Message "Successfully retrieved ACL for $folderpath." -Level "INFO"
# catches errors from Get-Acl command
} Catch {
    $acl = $null # set to null if Get-Acl fails
    $errorMessage = "Failed to retrieve ACL for $folderpath. Error: $_"
    Write-Host $errorMessage -ForegroundColor Red
    Log-Error -Message $errorMessage -Level "ERROR"
    Write-Host "Exiting script..." -ForegroundColor Red
    Log-Error -Message "Exiting script..." -Level "INFO"
    exit 1
}


## Part 4: Stopping Windows Update Services
# This section stops the Windows Update services to ensure that no files are in use during the deletion process.
# The services being stopped are: wuauserv, cryptsvc, bits, and msiserver.
$services = "wuauserv", "cryptsvc", "bits", "msiserver"
foreach ($service in $services) {
    # checks if service exists
    if (-not (Get-Service -Name $service -ErrorAction SilentlyContinue)) {
        Write-Host "Service $service does not exist. Skipping..." -ForegroundColor Yellow
        Log-Error -Message "Service $service does not exist. Skipping..." -Level "WARNING"
        continue 
    }
    $attempts = 0
    $maxAttempts = 3

    while ($attempts -lt $maxAttempts) {
        Write-Host "Processing $service..." -ForegroundColor Cyan
        Log-Error -Message "Processing $service..." -Level "INFO"
        try {
            # get service status and stop service if running
            if ((Get-Service  -Name $service).Status -eq "Running") {
                Stop-Service -Name $service -ErrorAction Stop
                Write-Host "Successfully stopped service: $service" -ForegroundColor Green
                Log-Error -Message "Successfully stopped service: $service" -Level "INFO"
                break
            }
        } catch {
            # handles errors from Stop-Service command
            $attempts++
            $errorMessage = "Failed to stop service $service. Attempt $attempts of $maxAttempts. Error: $_"
            Write-Error $errorMessage -ForegroundColor Red 
            Log-Error -Message $errorMessage -Level "WARNING"
            if ($attempts -ge $maxAttempts) {
                # handles case where service fails to stop after max attempts
                $finalErrorMessage = "Failed to stop service $service after $maxAttempts attempts. Exiting script..."
                Write-Error $finalErrorMessage -ForegroundColor Red
                Log-Error -Message $finalErrorMessage -Level "ERROR"
                exit 1
            }
            Start-Sleep -Seconds 2 # wait before retrying to conserve resources
            Write-Host "Retrying to stop service $service...attempt $attempts of $maxAttempts" -ForegroundColor Yellow
            Log-Error -Message "Retrying to stop service $service...attempt $attempts of $maxAttempts" -Level "WARNING"
        }
    }
}


# Grabs all subfolders and contents
$items = Get-ChildItem -Path $folderpath -recurse -force


## Part 5: Taking Ownership of Files and Folders
# Parallels takeown command to take ownership of files and folders using Start-Job.
# Ownership of files and folders is required to delete them in certain enviorments.
$jobs=@()
# checks if items exist
foreach ($item in $items) {
    try {
        # checks if item is a file or folder
        Write-Host "Beginning to take ownership of $($item.FullName)..."
        Log-Error -Message "Beginning to take ownership of $($item.FullName)..." -Level "INFO"
        $jobs += Start-Job -ScriptBlock {   # parallel processing for takeown command
            param ($path)
            & takeown /f $path /r /d y   # take ownership of file/folder
        } -ArgumentList $item.FullName 
    # catching errors from takeown command
    } Catch {
        # handles case where takeown command fails
        $errorMessage = "Failed to take ownership of $($item.FullName). Error: $_"
        Write-Error $errorMessage -ForegroundColor Red
        Log-Error -Message $errorMessage -Level "ERROR"
    }
}

# waiting for jobs to complete or timeout
Write-Host "Waiting for all ownership tasks to complete..."
Log-Error -Message "Waiting for all ownership tasks to complete..." -Level "INFO"

# sets timeout for job completion
# timeout is set to 5 minutes (300 seconds)
$timeout = 300
$startTime = Get-Date

# checking if jobs are running
if ($jobs.Count -eq 0) {
    # handles case where no jobs were started
    Write-Host "No ownership tasks were started. Skipping wait process." -ForegroundColor Yellow
    Log-Error -Message "No ownership tasks were started. Skipping wait process." -Level "WARNING"
} else {
    # waiting for jobs to complete or timeout
    while (($jobs | Where-Object { $_.State -ne "Completed" }).Count -gt 0) {
        Start-Sleep -Seconds 5
        if ((Get-Date) -gt $startTime.AddSeconds($timeout)) {
            # handles case where timeout is reached
            $remainingJobs = $jobs | Where-Object {$_.State -ne "Completed"}
            foreach ($job in $remainingJobs) {
                # handles case where job is still running after timeout
                $jobDetails = "Job ID: $($job.Id), State: $($job.State), Command: $($job.Command), Error: $($job.Error)"
                Write-Error "Timeout reached for job: $jobDetails." -ForegroundColor Red
                Log-Error -Message "Timeout reached for job: $jobDetails." -Level "ERROR"
            }
            # handles case where jobs are still running after timeout
            Write-Error "Ownership tasks did not complete within the timeout period. $($remainingJobs.Count) jobs are still incomplete." -ForegroundColor Red
            Log-Error -Message "Ownership tasks did not complete within the timeout period. $($remainingJobs.Count) jobs are still incomplete." -Level "ERROR"
            break
        }
    }
}


# Process Completed Jobs
foreach ($job in $jobs) {
    if ($job.State -eq "Completed") {
        try {
            # handles case where job completed successfully
            $output = Receive-Job -Job $job -ErrorAction SilentlyContinue
            Write-Host "Job Output: $output" -ForegroundColor Green
            Log-Error -Message "Job completed successfully. Output: $output" -Level "INFO"
        } catch {
            $errorMessage = "Failed to receive job output for job $($job.Id). Error: $_"
            Write-Error $errorMessage -ForegroundColor Red
            Log-Error -Message $errorMessage -Level "ERROR"
        } finally {
            # cleans up completed job
            Remove-Job -Job $job -Force
            Write-Host "Removed job $($job.Id) from memory." -ForegroundColor Green
            Log-Error -Message "Removed job $($job.Id) from memory." -Level "INFO"
        }
    } else {
        # handles case where job did not complete successfully
        $errorMessage = "Job $($job.Id) did not complete successfully. State: $($job.State). Output: $($job.Output). Error: $($job.Error)."
        Write-Error $errorMessage -ForegroundColor Red
        Log-Error -Message $errorMessage -Level "ERROR"

        # remove incomplete job from memory
        Remove-Job -Job $job -Force
        Write-Host "Removed incomplete job $($job.Id) from memory." -ForegroundColor Red
        Log-Error -Message "Removed incomplete job $($job.Id) from memory." -Level "ERROR"
    }
}

# Final cleanup of all jobs
foreach ($job in $jobs) {
    if ($job.State -ne "Completed") {
        $errorMessage = "Job $($job.Id) failed or did not complete. Command: $($job.Command), Error: $($job.Error)."
        Write-Error $errorMessage -ForegroundColor Red
        Log-Error -Message $errorMessage -Level "ERROR"
    }
    Remove-Job -Job $job -Force
    Write-Host "Cleaned up job $($job.Id) from memory." -ForegroundColor Green
    Log-Error -Message "Cleaned up job $($job.Id) from memory." -Level "INFO"
}

# Checking failed job cases
foreach ($job in $jobs) {
    if ($job.State -ne "Completed") {
        # handles case where job failed or did not complete
        $errorMessage = "Job $($job.Id) failed or did not complete. Command: $($job.Command), Error: $($job.Error)."
        Log-Error -Message $errorMessage -Level "ERROR"
        Write-Error $errorMessage -ForegroundColor Red
    }
}


## Part 6: Grants admins full control
# This section grants full control to the administrators group for the specified folder path.
try{
    # checks if folder exists
    Write-Host "Granting admin controls to $folderpath..."
    Log-Error -Message "Granting admin controls to $folderpath..." -Level "INFO"
    # using icacls to grant full control to administrators group
    $icaclsOutput = icacls $folderpath /grant administrators: F /T /C 2>&1
    # checking if icacls command was successful
    if ($LASTEXITCODE -eq 0) {
        # handles successful icacls command
        Write-Host "Admin controls granted successfully." -ForegroundColor Green
        Log-Error -Message "Admin controls granted successfully." -Level "INFO"
    } else {
        # handles failed icacls command and throws to catch block
        throw "icacls command failed with exit code $LASTEXITCODE. Output: $icaclsOutput"
    }
} catch {
    # handles errors from icacls command
    $errorMessage = "Failed to grant admin controls. Error: $_. LastExitCode: $LASTEXITCODE & Output: $icaclsOutput"
    Write-Error $errorMessage -ForegroundColor Red
    Log-Error -Message $errorMessage -Level "ERROR"
    Write-Host "Exiting script..." -ForegroundColor Red
    Log-Error -Message "Exiting script..." -Level "INFO"
    exit 1
}


## Part 7: Deleting the Folder and its Contents
# This section deletes the specified folder and its contents using the rmdir command.
# Cmd is used due to the size of the folder and the number of files it contains.
try {
    # deletes folder and all contents
    cmd /c rmdir /s /q "C:\Windows\SoftwareDistribution"
    Write-Host "Folder deleted successfully." -ForegroundColor Green
    Log-Error -Message "Folder deleted successfully." -Level "INFO"
} catch {
    # handles errors from rmdir command
    Write-Error "Failed to delete folder. Error:$_"
    Log-Error -Message "Failed to delete folder. Error:$_" -Level "ERROR"
    Write-Host "Exiting script..." -ForegroundColor Red
    Log-Error -Message "Exiting script..." -Level "INFO"
    exit 1
}


## Part 8: Restarting Windows Update Services
# This section restarts the Windows Update services that were stopped earlier.
# The services being restarted are: wuauserv, cryptsvc, bits, and msiserver.
foreach ($service in $services) {
    $attempts = 0
    $maxAttempts = 3
    # checks if service exists
    Write-Host "Processing $service..." -ForegroundColor Cyan
    Log-Error -Message "Processing $service..." -Level "INFO"

    while ($attempts -lt $maxAttempts) {
        try {
            # get service status
            $serviceStatus = (Get-Service -Name $service -ErrorAction Stop).Status
            Log-Error -Message "Service $service status: $serviceStatus" -Level "INFO"

            # handles different server states
            if ($serviceStatus -eq "Stopped") {
                # handles case where service is stopped
                Start-Service -Name $service -ErrorAction Stop
                Write-Host "Restarted service $service successfully." -ForegroundColor Green
                Log-Error -Message "Restarted service $service successfully." -Level "INFO"
                break
            } elseif ($serviceStatus -eq "Running") {
                # handles case where service is already running
                Write-Host "Service $service is already running." -ForegroundColor Green
                Log-Error -Message "Service $service is already running." -Level "INFO"
                break
            } elseif ($serviceStatus -eq "Paused") {
                # handles case where service is paused
                Write-Host "Service $service is Paused." -ForegroundColor Yellow
                Log-Error -Message "Service $service is Paused." -Level "WARNING"
                Start-Service -Name $service -ErrorAction Stop
                break
            } else {
                # handles unknown service states
                Write-Host "Service $service state is Unknown." -ForegroundColor Red
                Log-Error -Message "Service $service state is Unknown." -Level "ERROR"
                break
            }
        } catch {
            # handles any errors durring service management
            $attempts++
            if ($attempts -lt $maxAttempts) {
                # handles case where service fails to start
                Write-Host "Attempting to restart service $service...attempt $attempts of $maxAttempts" -ForegroundColor Yellow
                Log-Error -Message "Attempting to restart service $service...attempt $attempts of $maxAttempts" -Level "WARNING"
                Start-Sleep -Seconds 2
            } else {
                # handles case where service fails to start after max attempts
                Write-Error "Failed to start service $service after $maxAttempts attempts. Exiting script..." -ForegroundColor Red
                Log-Error -Message "Failed to start service $service after $maxAttempts attempts. Exiting script..." -Level "ERROR"
                Write-Host "Exiting script..." -ForegroundColor Red
                Log-Error -Message "Exiting script..." -Level "INFO"
                exit 1
            }
        }
    }
}


# Outputs services statuses
Get-Service -Name $services
Log-Error -Message "Status of services: $services." -Level "INFO"


# Part 9: Restoring Original ACL
# This section restores the original ACL for the specified folder path.
# This is done to ensure that the permissions are set back to their original state in the event the folder is not fully deleted.
# This is likely unnecessary as the folder's deletion is the goal of the script.

# checks if ACL was retrieved successfully
if ($acl -ne $null) {
    Write-Host "ACL Restored: Yes" -ForegroundColor Green
    Log-Error -Message "ACL Restored: Yes" -Level "INFO"
} else {
    # handles case where ACL was not retrieved successfully
    if (-not (Test-Path -Path $folderpath)) {
        Write-Host "ACL Restored: No (Folder was deleted)" -ForegroundColor Yellow
        Log-Error -Message "ACL Restored: No (Folder was deleted)" -Level "INFO"
    } else {
        Write-Host "ACL Restored: Failed (ACL Backup not found)" -ForegroundColor Red
        Log-Error -Message "ACL Restored: Failed (ACL Backup not found)" -Level "ERROR"
    }
}

# checks if folder exists before restoring ACL
if (Test-Path -Path $folderpath) {
    try {
        # checks if folder exists
        Write-Output "Restoring original ACL for $folderpath..."
        Log-Error -Message "Restoring original ACL for $folderpath..." -Level "INFO"
        Set-Acl -Path $folderpath -AclObject $acl
        Write-Output "Successfully restored original ACL to $folderpath." -ForegroundColor Green
        Log-Error -Message "Successfully restored original ACL to $folderpath." -Level "INFO"
    } Catch {
        # handles errors from Set-Acl command
        Write Error "Failed to restore original ACL to $folderpath. Error:$_"
        Log-Error -Message "Failed to restore original ACL to $folderpath. Error:$_" -Level "ERROR"
        Write-Host "Exiting script..." -ForegroundColor Red
        Log-Error -Message "Exiting script..." -Level "INFO"
        exit 1
    }
} else {
    # handles case where folder does not exist
    Write-Host "Folder $folderpath does not exist, skipping ACL restoration."
    Log-Error -Message "Folder $folderpath does not exist, skipping ACL restoration." -Level "WARNING"
}


## Part 10: Final Output/Summary
# This section provides a summary of the script's actions and results.
# It checks if the folder was deleted, if the services were restarted, and if the ACL was restored.
Write-Host "Summary:" -ForegroundColor Cyan

# check if the folder was deleted
if (-not (Test-Path -Path $folderpath)) {
    Write-Host "Folder Deleted: Yes" -ForegroundColor Green
    Log-Error -Message "Folder Deleted: Yes" -Level "INFO"
} else {
    Write-Host "Folder Deleted: No" -ForegroundColor Red
    Log-Error -Message "Folder Deleted: No" -Level "ERROR"
}

# check if services were restarted
$servicesRestarted = $true
foreach ($service in $services) {
    if ((Get-Service -Name $service).Status -ne "Running") {
        $servicesRestarted = $false
        Log-Error -Message "Service $service was not restarted successfully." -Level "ERROR"
        break
    }
}

if ($servicesRestarted) {
    Write-Host "Services Restarted: Yes" -ForegroundColor Green
    Log-Error -Message "Services Restarted: Yes" -Level "INFO"
} else {
    Write-Host "Services Restarted: No" -ForegroundColor Red
    Log-Error -Message "Services Restarted: No" -Level "ERROR"
}

# check if ACL was restored
if ($acl -ne $null) {
    # checks if ACL restoration was successful
    Write-Host "ACL Restored: Yes" -ForegroundColor Red # if ACL is successfully restored, script did not run as expected
    Log-Error -Message "ACL Restored: Yes" -Level "INFO"
} else {
   if (-not (Test-Path -Path $folderpath)) {
        # handles case where folder was deleted and ACL restoration is skipped
        Write-Host "ACL Restored: No (ACL restoration skipped or failed)" -ForegroundColor Green # if script runs as expected ACL restoration will be skipped
        Log-Error -Message "ACL Restored: No (ACL restoration skipped or failed)" -Level "WARNING"
    } else {
        # handles case where ACL restoration failed due to missing backup
        Write-Host "ACL Restored: Failed (ACL Backup not found)" -ForegroundColor Red
        Log-Error -Message "ACL Restored: Failed (ACL Backup not found)" -Level "ERROR"
    }
}

Write-Host "Script completed successfully." -ForegroundColor Green
Write-Host "Log file saved at: $logFilePath" -ForegroundColor Green
Write-Host "Exiting script, goodbye! :)" -ForegroundColor Green
Log-Error -Message "Script completed successfully." -Level "INFO"
exit 0
# Fin~