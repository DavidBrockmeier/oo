﻿#Requires -RunAsAdministrator
<#
	.SYNOPSIS
		Start-Optimize is a configuration call script for the Optimize-Offline module.

	.DESCRIPTION
		Start-Optimize automatically imports the configuration JSON file into the Optimize-Offline module.

	.EXAMPLE
		.\Start-Optimize.ps1

		This command will import all values set in the configuration JSON file into the Optimize-Offline module and begin the optimization process.

	.NOTES
		Start-Optimize requires that the configuration JSON file is present in the root path of the Optimize-Offline module.
#>
[CmdletBinding()]
Param ()

$Global:Error.Clear()

# Ensure we are running with administrative permissions.
If (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
{
	Write-Warning "Elevation is required to process optimizations. Please relaunch Start-Optimize as an administrator."
	Start-Sleep 3
	Exit
}

# Ensure the configuration JSON file exists.
If (!(Test-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath Configuration.json)))
{
	Write-Warning ('The required configuration JSON file does not exist: "{0}"' -f (Join-Path -Path $PSScriptRoot -ChildPath Configuration.json))
	Start-Sleep 3
	Exit
}

# If the configuration JSON or ordered collection list variables still exists from a previous session, remove them.
If ((Test-Path -Path Variable:\ContentJSON) -or (Test-Path -Path Variable:\ConfigParams))
{
	Remove-Variable -Name ContentJSON, ConfigParams -ErrorAction Ignore
}

# Use a Try/Catch/Finally block in case the configuration JSON file URL formatting is invalid so we can catch it, correct its formatting and continue.
Try
{
	$ContentJSON = Get-Content -Path (Join-Path -Path $PSScriptRoot -ChildPath Configuration.json) -Raw | ConvertFrom-Json
}
Catch [ArgumentException]
{
	$ContentJSON = (Get-Content -Path (Join-Path -Path $PSScriptRoot -ChildPath Configuration.json) -Raw).Replace('\', '\\') | Set-Content -Path (Join-Path -Path $Env:TEMP -ChildPath Configuration.json) -Encoding UTF8 -Force -PassThru
	$ContentJSON = $ContentJSON | ConvertFrom-Json
	Move-Item -Path (Join-Path -Path $Env:TEMP -ChildPath Configuration.json) -Destination $PSScriptRoot -Force
	$Global:Error.Remove($Error[-1])
}
Finally
{
	$ContentJSON.PSObject.Properties.Remove('_Info')
}

# Convert the JSON object into a nested ordered collection list. We use the PSObject.Properties method to retain the JSON object order.
$ConfigParams = [Ordered]@{ }
ForEach ($Name In $ContentJSON.PSObject.Properties.Name)
{
	$Value = $ContentJSON.PSObject.Properties.Item($Name).Value
	If ($Value -is [PSCustomObject])
	{
		$ConfigParams.$Name = [Ordered]@{ }
		ForEach ($Property in $Value.PSObject.Properties)
		{
			$ConfigParams.$Name[$Property.Name] = $Property.Value
		}
	}
	Else
	{
		$ConfigParams.$Name = $Value
	}
}

# Import the Optimize-Offline module and call it by passing the JSON configuration.
If ($PSVersionTable.PSVersion.Major -gt 5)
{
	Try
	{
		Import-Module Dism -SkipEditionCheck -Force -WarningAction Ignore -ErrorAction Stop
	}
	Catch
	{
		Write-Warning 'Failed to import the required Dism module.'
		Start-Sleep 3
		Exit
	}
	Try
	{
		Import-Module (Join-Path -Path $PSScriptRoot -ChildPath Optimize-Offline.psm1) -SkipEditionCheck -Force -WarningAction Ignore -ErrorAction Stop
	}
	Catch
	{
		Write-Warning ('Failed to import the Optimize-Offline module: "{0}"' -f (Join-Path -Path $PSScriptRoot -ChildPath Optimize-Offline.psm1))
		Start-Sleep 3
		Exit
	}
}
Else
{
	Try
	{
		Import-Module (Join-Path -Path $PSScriptRoot -ChildPath Optimize-Offline.psm1) -Force -WarningAction Ignore -ErrorAction Stop
	}
	Catch
	{
		Write-Warning ('Failed to import the Optimize-Offline module: "{0}"' -f (Join-Path -Path $PSScriptRoot -ChildPath Optimize-Offline.psm1))
		Start-Sleep 3
		Exit
	}
}

Optimize-Offline @ConfigParams