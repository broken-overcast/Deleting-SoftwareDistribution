## Do not use unless you have knowledge or testing of how actions will affect your enviorment.
## This script will alter critical Windows update services.
## No validation checks have been added.
## USE AT YOUR OWN RISK



# stop related update services
Stop-Service -Name "wuauserv", "cryptsvc", "bits", "msiserver"

# grabs all subfolders and contents
$items Get-ChildItem -Path "C:\Windows\SoftwareDistribution" -recurse -force

# parallels taking ownership of folders and files
$jobs=@()
foreach ($item in items) {
    $jobs += Start-Job -ScriptBlock {
        param ($path)
        & takeown /f $path /r /d y
    } -ArgumentList $item.fullname
}

# wait for jobs to complete
$jobs | Wait-Job

# grants admins full control
icacls "C:\Windows\SoftwareDistribution" /grant administrators: F /T /C

# deletes target folder
cmd /c rmdir /s /q "C:\Windows\SoftwareDistribution"

# starts services previously stopped
Start-Service -Name "wuauserv","cryptsvc","bits","msiserver"

# outputs target service status
Get-Service -Name "wuauserv","cryptsvc","bits","msiserver"
