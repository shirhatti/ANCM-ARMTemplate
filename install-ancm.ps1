#Requires -RunAsAdministrator

#
# Copyright (c) .NET Foundation and contributors. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.
#

<#
.SYNOPSIS
    Installs ANCM
.DESCRIPTION
    Installs ANCM. If ANCM already exists it will upgrade aspnetcore.dll and
    aspnetcorerh.dll
.PARAMETER Version
    Default: latest
    Represents a build version of the Microsoft.AspNetCore.Asp package on the specified feed
.PARAMETER Rollback
#>

[cmdletbinding()]
param(
    [string]$Version="latest",
    [switch]$Rollback
)

Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"
$ProgressPreference="SilentlyContinue"
$timeStamp = Get-Date -f MM-dd-yyyy_HH_mm_ss

function Get-LatestVersion() {
    return (Invoke-RestMethod -Uri https://dotnet.myget.org/F/aspnetcore-dev/api/v3/registration1/microsoft.aspnetcore.aspnetcoremodule/index.json).items[-1].upper
}

function Get-SpecificVersion([string]$Version) {

    switch ($Version.ToLower()) {
        { $_ -eq "latest" } {
            return Get-LatestVersion
        }
        default { return $Version }
    }
}

function Invoke-BackupFile($path)
{
    if ((Test-Path $path) -eq $true)
    {
        $backupPath = $path + "." + $timeStamp + ".bak"
        Copy-Item $path -Destination $backupPath
        Write-Host "Backed up " (Split-Path $path -Leaf) "to" $backupPath
    }
}

function Invoke-RestoreFile($path)
{
    $restorePath = $path + "." + $Version + ".bak"
    if ((Test-Path $restorePath) -eq $true)
    {
        Move-Item $restorePath -Destination $path -Force
        Write-Host "Restored " (Split-Path $restorePath -Leaf) "to" $path
    }
}

function Invoke-UpdateAppHostConfig {
    Invoke-BackupFile("C:\Windows\System32\inetsrv\config\applicationHost.config")
    Import-Module IISAdministration

    # Initialize variables
    $aspNetCoreHandlerFilePath="C:\windows\system32\inetsrv\aspnetcore.dll"
    Reset-IISServerManager -confirm:$false
    $sm = Get-IISServerManager

    # Add AppSettings section 
    $sm.GetApplicationHostConfiguration().RootSectionGroup.Sections.Add("appSettings")

    # Set Allow for handlers section
    $appHostconfig = $sm.GetApplicationHostConfiguration()
    $section = $appHostconfig.GetSection("system.webServer/handlers")
    $section.OverrideMode="Allow"

    # Add aspNetCore section to system.webServer
    $sectionaspNetCore = $appHostConfig.RootSectionGroup.SectionGroups["system.webServer"].Sections.Add("aspNetCore")
    $sectionaspNetCore.OverrideModeDefault = "Allow"
    $sm.CommitChanges()

    # Configure globalModule
    Reset-IISServerManager -confirm:$false
    $globalModules = Get-IISConfigSection "system.webServer/globalModules" | Get-IISConfigCollection
    New-IISConfigCollectionElement $globalModules -ConfigAttribute @{"name"="AspNetCoreModule";"image"=$aspNetCoreHandlerFilePath}

    # Configure module
    $modules = Get-IISConfigSection "system.webServer/modules" | Get-IISConfigCollection
    New-IISConfigCollectionElement $modules -ConfigAttribute @{"name"="AspNetCoreModule"}
}

function Test-ANCMExists()
{
    # Assuming that if schema exists, ANCM has been installed at some point
    return Test-Path C:\Windows\System32\inetsrv\Config\Schema\aspnetcore_schema.xml
}

function Invoke-UpdateANCM ($Version) {
    $tempFolder = [System.IO.Path]::GetTempFileName()
    Remove-Item $tempFolder
    $tempFile = [System.IO.Path]::GetTempFileName() |
        Rename-Item -NewName { $_ -replace 'tmp$', 'zip' } -PassThru
    $nupkgPath = "https://dotnet.myget.org/F/aspnetcore-dev/api/v2/package/Microsoft.AspNetCore.AspNetCoreModule/" + $Version
    Invoke-WebRequest -Uri $nupkgPath -OutFile $tempFile
    
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::ExtractToDirectory($tempFile, $tempFolder)
    $schemaPath = Join-Path -Path $tempFolder -ChildPath "aspnetcore_schema.xml"
    
    
    $binaryPath64bit = Join-Path -Path $tempFolder -ChildPath "contentFiles\any\any\x64"
    $binaryPath32bit = Join-Path -Path $tempFolder -ChildPath "contentFiles\any\any\x86"

    # Backup binaries before blowing them away with -Force
    Invoke-BackupFile("C:\Windows\System32\inetsrv\Config\Schema\aspnetcore_schema.xml")
    Invoke-BackupFile("C:\Windows\System32\inetsrv\aspnetcore.dll")
    Invoke-BackupFile("C:\Windows\System32\inetsrv\aspnetcorerh.dll")
    Invoke-BackupFile("C:\Windows\SysWOW64\inetsrv\aspnetcore.dll")
    Invoke-BackupFile("C:\Windows\SysWOW64\inetsrv\aspnetcorerh.dll")

    Copy-Item -Path $schemaPath -Destination "C:\Windows\System32\inetsrv\Config\Schema\aspnetcore_schema.xml" -Force
    Copy-Item -Path $binaryPath64bit\* -Destination C:\Windows\System32\inetsrv\ -Force 
    Copy-Item -Path $binaryPath32bit\* -Destination C:\Windows\SysWOW64\inetsrv\ -Force
}

Write-Host "Stopping IIS"
Stop-Service -Name WAS -Force

if ($Rollback) {
    Write-Host "Beginning rollback at " $timeStamp
    Invoke-RestoreFile("C:\Windows\System32\inetsrv\Config\Schema\aspnetcore_schema.xml")
    Invoke-RestoreFile("C:\Windows\System32\inetsrv\aspnetcore.dll")
    Invoke-RestoreFile("C:\Windows\System32\inetsrv\aspnetcorerh.dll")
    Invoke-RestoreFile("C:\Windows\SysWOW64\inetsrv\aspnetcore.dll")
    Invoke-RestoreFile("C:\Windows\SysWOW64\inetsrv\aspnetcorerh.dll")
}
else {
    
    Write-Host "Beginning install at " $timeStamp
    if ((Test-ANCMExists) -eq $false) {
        Invoke-UpdateAppHostConfig
    }
    $SpecificVersion = Get-SpecificVersion -Version $Version
    Invoke-UpdateANCM($SpecificVersion)

    Write-Host "To restore run `".\install-ancm.ps1 -Rollback -Version " $timeStamp "`""
}

Write-Host "Starting IIS"
Start-Service -Name W3SVC