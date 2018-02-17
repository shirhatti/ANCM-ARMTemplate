# Install IIS
Install-WindowsFeature -Name Web-Server

# Install WMSVC
Install-WindowsFeature -Name Web-Mgmt-Service
# Enable remote connections
Set-ItemProperty -Path  HKLM:\SOFTWARE\Microsoft\WebManagement\Server -Name EnableRemoteManagement -Value 1

# Install WebDeploy
$tempFile = [System.IO.Path]::GetTempFileName() |
    Rename-Item -NewName { $_ -replace 'tmp$', 'msi' } -PassThru
Invoke-WebRequest -Uri http://download.microsoft.com/download/0/1/D/01DC28EA-638C-4A22-A57B-4CEF97755C6C/WebDeploy_amd64_en-US.msi -OutFile $tempFile
$logFile = [System.IO.Path]::GetTempFileName()
$arguments= '/i ' + $tempFile + ' ADDLOCAL=ALL /qn /norestart LicenseAccepted="0" /lv ' + $logFile
$proc = (Start-Process -file msiexec -arg $arguments -Passthru)
$proc | Wait-Process
Get-Content $logFile
Set-Service -Name WMSVC -StartupType Automatic

# Install Server hosting bundle
$tempFile = [System.IO.Path]::GetTempFileName() |
    Rename-Item -NewName { $_ -replace 'tmp$', 'exe' } -PassThru
Invoke-WebRequest -Uri https://download.microsoft.com/download/1/1/0/11046135-4207-40D3-A795-13ECEA741B32/DotNetCore.2.0.5-WindowsHosting.exe -OutFile $tempFile
$logFile = [System.IO.Path]::GetTempFileName()
$proc = (Start-Process $tempFile -PassThru "/quiet /install /log $logFile")
$proc | Wait-Process
Get-Content $logFile

# Stop IIS
Stop-Service -Name W3SVC

# Install nightly ANCM
$tempFile = [System.IO.Path]::GetTempFileName() |
    Rename-Item -NewName { $_ -replace 'tmp$', 'ps1' } -PassThru
Invoke-WebRequest -Uri https://raw.githubusercontent.com/shirhatti/ANCM-ARMTemplate/master/install-ancm.ps1 -OutFile $tempFile
Invoke-Expression $tempFile

# Start IIS
Start-Service -Name W3SVC

# Start WMSVC
Start-Service -Name WMSVC

# Open port for WMSVC
New-NetFirewallRule -DisplayName "WMSVC" -Direction Inbound  -Action Allow -Protocol TCP -LocalPort 8172

# Add HTTPS binding
$cert = (Get-ChildItem -Path Cert:\LocalMachine\My\) | Where-Object {$_.FriendlyName -like "*WMSvc*"}
New-WebBinding -Name "Default Web Site" -Protocol "https" -Port 443 -HostHeader "*" 
(Get-WebBinding -Name "Default Web Site" -Port "443").AddSslCertificate($cert.Thumbprint, "My")

# Grant IIS_IUSRS write permissions for wwwroot
$path = "C:\inetpub\wwwroot"
$ar = (Get-Acl -Path $path).Access.Where{$_.IdentityReference -eq "BUILTIN\IIS_IUSRS"}[0]
$acl = (Get-Acl -Path $path)
$acl.RemoveAccessRule($ar[0])
$ar = New-Object System.Security.AccessControl.FileSystemAccessRule("BUILTIN\IIS_IUSRS", "Write, ReadAndExecute, Synchronize", "ContainerInherit, ObjectInherit", "None", "Allow")
$acl.AddAccessRule($ar)
Set-Acl -Path $path $acl

# Reboot
Restart-Computer
