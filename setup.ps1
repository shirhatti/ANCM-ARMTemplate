# Install IIS
Install-WindowsFeature -Name Web-Server

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
$tempFolder = [System.IO.Path]::GetTempFileName()
Remove-Item $tempFolder
$tempFile = [System.IO.Path]::GetTempFileName() |
    Rename-Item -NewName { $_ -replace 'tmp$', 'zip' } -PassThru
Add-Type -AssemblyName System.IO.Compression.FileSystem
Invoke-WebRequest -Uri https://dotnet.myget.org/F/aspnetcore-dev/api/v2/package/Microsoft.AspNetCore.AspNetCoreModule/2.1.0-preview2-28189 -OutFile $tempFile
[System.IO.Compression.ZipFile]::ExtractToDirectory($tempFile, $tempFolder)
$schemaPath = Join-Path -Path $tempFolder -ChildPath "aspnetcore_schema.xml"
Copy-Item -Path $schemaPath -Destination "C:\Windows\System32\inetsrv\Config\Schema\aspnetcore_schema.xml"
$binaryPath64bit = Join-Path -Path $tempFolder -ChildPath "contentFiles\any\any\x64"
$binaryPath32bit = Join-Path -Path $tempFolder -ChildPath "contentFiles\any\any\x86"
Copy-Item -Path $binaryPath64bit\* -Destination C:\Windows\System32\inetsrv\ -Force 
Copy-Item -Path $binaryPath32bit\* -Destination C:\Windows\SysWOW64\inetsrv\ -Force

# Start IIS
Start-Service -Name W3SVC

# Start WMSVC
Start-Service -Name WMSVC

# Open port for WMSVC
New-NetFirewallRule -DisplayName "WMSVC" -Direction Inbound  -Action Allow -Protocol TCP -LocalPort 8172
