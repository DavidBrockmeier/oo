﻿Using module .\Src\Offline-Resources.psm1
#Requires -RunAsAdministrator
#Requires -Version 5.1
#Requires -Module Dism
<#
	===========================================================================
	 Created with: 	SAPIEN Technologies, Inc., PowerShell Studio 2019 v5.7.182
	 Created on:   	11/20/2019 11:53 AM
	 Created by:   	BenTheGreat
	 Filename:     	Optimize-Offline.psm1
	 Version:       4.0.1.7
	 Last updated:	12/11/2020
	-------------------------------------------------------------------------
	 Module Name: Optimize-Offline
	===========================================================================
#>
Function Optimize-Offline
{
	<#
	.EXTERNALHELP Optimize-Offline-help.xml
	#>

	[CmdletBinding()]
	Param
	(
		[Parameter(Mandatory = $true,
			ValueFromPipeline = $true,
			HelpMessage = 'The full path to a Windows 10 Installation Media ISO, or a Windows 10 WIM, SWM or ESD file.')]
		[ValidateScript( {
				If ($PSItem.Exists -and $PSItem.Extension -eq '.ISO' -or $PSItem.Extension -eq '.WIM' -or $PSItem.Extension -eq '.SWM' -or $PSItem.Extension -eq '.ESD') { $true }
				Else { Throw ('Invalid source path: "{0}"' -f $PSItem.FullName) }
			})]
		[IO.FileInfo]$SourcePath,
		[Parameter(HelpMessage = 'Selectively or automatically deprovisions Windows Apps and removes their associated provisioning packages (.appx or .appxbundle).')]
		[ValidateSet('Select', 'Whitelist', 'All')]
		[String]$WindowsApps,
		[Parameter(HelpMessage = 'Populates and outputs a Gridview list of System Apps for selective removal.')]
		[Switch]$SystemApps,
		[Parameter(HelpMessage = 'Populates and outputs a Gridview list of Capability Packages for selective removal.')]
		[Switch]$Capabilities,
		[Parameter(HelpMessage = 'Populates and outputs a Gridview list of Windows Cabinet File Packages for selective removal.')]
		[Switch]$Packages,
		[Parameter(HelpMessage = 'Populates and outputs a Gridview list of Windows Optional Features for selective disabling and enabling.')]
		[Switch]$Features,
		[Parameter(HelpMessage = 'Integrates the Developer Mode Feature into the image.')]
		[Switch]$DeveloperMode,
		[Parameter(HelpMessage = 'Integrates the Microsoft Windows Store and its required dependencies into the image.')]
		[Switch]$WindowsStore,
		[Parameter(HelpMessage = 'Integrates the Microsoft Edge HTML or Chromium Browser into the image.')]
		[Switch]$MicrosoftEdge,
		[Parameter(HelpMessage = 'Integrates the traditional Win32 Calculator into the image.')]
		[Switch]$Win32Calc,
		[Parameter(HelpMessage = 'Integrates the Windows Server Data Deduplication Feature into the image.')]
		[Switch]$Dedup,
		[Parameter(HelpMessage = 'Integrates the Microsoft Diagnostic and Recovery Toolset (DaRT 10) and Windows 10 Debugging Tools into Windows Setup and Windows Recovery.')]
		[ValidateSet('Setup', 'Recovery')]
		[String[]]$DaRT,
		[Parameter(HelpMessage = 'Applies optimized settings to the image registry hives.')]
		[Switch]$Registry,
		[Parameter(HelpMessage = 'Integrates user-specific content added to the "Content/Additional" directory into the image when enabled within the hashtable.')]
		[Hashtable]$Additional = @{ Setup = $false; Wallpaper = $false; SystemLogo = $false; LockScreen = $false; RegistryTemplates = $false; LayoutModification = $false; Unattend = $false; Drivers = $false; NetFx3 = $false },
		[Parameter(HelpMessage = 'Creates a new bootable Windows Installation Media ISO.')]
		[ValidateSet('Prompt', 'No-Prompt')]
		[String]$ISO
	)

	Begin
	{
		#region Pre-Processing Block
		$LocalScope | Add-Member -MemberType NoteProperty -Name Variables -Value (Get-Variable).Name -PassThru | Add-Member -MemberType NoteProperty -Name ErrorActionPreference -Value $ErrorActionPreference -PassThru | Add-Member -MemberType NoteProperty -Name ProgressPreference -Value $ProgressPreference
		$ErrorActionPreference = 'SilentlyContinue'
		$Global:ProgressPreference = 'SilentlyContinue'
		$Host.UI.RawUI.BackgroundColor = 'Black'
		Clear-Host
		Test-Requirements
		If (Get-WindowsImage -Mounted) { Dismount-Images; Clear-Host }
		[Void](Clear-WindowsCorruptMountPoint)
		$Global:Error.Clear()
		#endregion Pre-Processing Block
	}
	Process
	{
		#region Create the Working File Structure
		Set-Location -Path $OptimizeOffline.Directory
		[Environment]::CurrentDirectory = (Get-Location -PSProvider FileSystem).ProviderPath
		@(Get-ChildItem -Path $OptimizeOffline.Directory -Filter OfflineTemp_* -Directory), (GetPath -Path $Env:SystemRoot -Child 'Logs\DISM\dism.log') | Purge -ErrorAction Ignore
		Try
		{
			@($TempDirectory, $ImageFolder, $WorkFolder, $ScratchFolder, $LogFolder) | Create -ErrorAction Stop
		}
		Catch
		{
			$PSCmdlet.WriteWarning($OptimizeData.FailedToCreateWorkingFileStructure)
			Get-ChildItem -Path $OptimizeOffline.Directory -Filter OfflineTemp_* -Directory | Purge -ErrorAction Ignore
			Break
		}
		#endregion Create the Working File Structure

		#region Media Export
		Switch ($SourcePath.Extension)
		{
			'.ISO'
			{
				$ISOMount = (Mount-DiskImage -ImagePath $SourcePath.FullName -StorageType ISO -PassThru | Get-Volume).DriveLetter + ':'
				[Void](Get-PSDrive)
				If (!(Get-ChildItem -Path (GetPath -Path $ISOMount -Child sources) -Filter install* -File))
				{
					$PSCmdlet.WriteWarning($OptimizeData.InvalidWindowsInstallMedia -f $SourcePath.Name)
					Do
					{
						[Void](Dismount-DiskImage -ImagePath $SourcePath.FullName)
					}
					While ((Get-DiskImage -ImagePath $SourcePath.FullName).Attached -eq $true)
					$TempDirectory | Purge
					Break
				}
				$Host.UI.RawUI.WindowTitle = ($OptimizeData.ExportingMedia -f $SourcePath.Name)
				Write-Host ($OptimizeData.ExportingMedia -f $SourcePath.Name) -ForegroundColor Cyan
				$ISOMedia = Create -Path (GetPath -Path $TempDirectory -Child $SourcePath.BaseName) -PassThru
				$ISOMedia | Export-DataFile -File ISOMedia
				ForEach ($Item In Get-ChildItem -Path $ISOMount -Recurse)
				{
					$ISOExport = $ISOMedia.FullName + $Item.FullName.Replace($ISOMount, $null)
					Copy-Item -Path $Item.FullName -Destination $ISOExport
				}
				Do
				{
					[Void](Dismount-DiskImage -ImagePath $SourcePath.FullName)
				}
				While ((Get-DiskImage -ImagePath $SourcePath.FullName).Attached -eq $true)
				If ((Get-ChildItem -Path (GetPath -Path $ISOMedia.FullName -Child sources) -Filter install* -File | Measure-Object).Count -gt 1 -and (Get-ChildItem -Path (GetPath -Path $ISOMedia.FullName -Child sources) -Filter install* -File | Select-Object -First 1).Extension -eq '.SWM')
				{
					Try
					{
						$InstallWim = Get-ChildItem -Path (GetPath -Path $ISOMedia.FullName -Child sources) -Filter install* -File | Select-Object -First 1 | Move-Item -Destination $ImageFolder -PassThru -ErrorAction Stop | Set-ItemProperty -Name IsReadOnly -Value $false -PassThru | Get-Item | Select-Object -ExpandProperty FullName
						$SwmFiles = Get-ChildItem -Path (GetPath -Path $ISOMedia.FullName -Child sources) -Filter install* -File | Move-Item -Destination $ImageFolder -PassThru -ErrorAction Stop | Set-ItemProperty -Name IsReadOnly -Value $false -PassThru | Get-Item | Select-Object -ExpandProperty FullName
					}
					Catch [Management.Automation.ItemNotFoundException] { Break }
				}
				Else
				{
					Try { $InstallWim = Get-ChildItem -Path (GetPath -Path $ISOMedia.FullName -Child sources) -Filter install.* -File | Move-Item -Destination $ImageFolder -PassThru -ErrorAction Stop | Set-ItemProperty -Name IsReadOnly -Value $false -PassThru | Get-Item | Select-Object -ExpandProperty FullName }
					Catch [Management.Automation.ItemNotFoundException] { Break }
				}
				If ($DaRT -or $Additional.ContainsValue($true))
				{
					If ($DaRT -and $DaRT.Contains('Setup') -or ($Additional.Drivers -and (Get-ChildItem -Path $OptimizeOffline.BootDrivers -Include *.inf -Recurse -Force)))
					{
						Try { $BootWim = Get-ChildItem -Path (GetPath -Path $ISOMedia.FullName -Child sources) -Filter boot.* -File | Move-Item -Destination $ImageFolder -PassThru -ErrorAction Stop | Set-ItemProperty -Name IsReadOnly -Value $false -PassThru | Get-Item | Select-Object -ExpandProperty FullName }
						Catch [Management.Automation.ItemNotFoundException] { Break }
					}
				}
				Break
			}
			Default
			{
				$Host.UI.RawUI.WindowTitle = ($OptimizeData.CopyingImage -f $SourcePath.Extension.TrimStart('.').ToUpper(), $SourcePath.DirectoryName)
				Write-Host ($OptimizeData.CopyingImage -f $SourcePath.Extension.TrimStart('.').ToUpper(), $SourcePath.DirectoryName) -ForegroundColor Cyan
				Try { $InstallWim = Get-ChildItem -Path $SourcePath.FullName -Filter $SourcePath.Name | Copy-Item -Destination $ImageFolder -PassThru -ErrorAction Stop | Rename-Item -NewName ('install' + $SourcePath.Extension) -PassThru | Set-ItemProperty -Name IsReadOnly -Value $false -PassThru | Get-Item | Select-Object -ExpandProperty FullName }
				Catch [Management.Automation.ItemNotFoundException] { Break }
				If ($SourcePath.Extension -eq '.SWM')
				{
					Try { $SwmFiles = Get-ChildItem -Path $SourcePath.DirectoryName -Filter "$($SourcePath.BaseName)*$($SourcePath.Extension)" -Exclude $SourcePath.Name -Recurse | Where-Object -Property Name -Like "$($SourcePath.BaseName)*.swm" | Copy-Item -Destination $ImageFolder -PassThru -ErrorAction Stop | Set-ItemProperty -Name IsReadOnly -Value $false -PassThru }
					Catch [Management.Automation.ItemNotFoundException] { Break }
					$I = 2
					$SwmFiles = Get-ChildItem -Path $ImageFolder -Include $SwmFiles.PSChildName -File -Recurse | ForEach-Object -Process { Rename-Item -Path $PSItem -NewName ('install{0:D1}.swm' -f $I++) -PassThru }
				}
				If ($ISO) { Remove-Variable -Name ISO }
				Break
			}
		}

		If ([IO.File]::Exists($InstallWim))
		{
			Switch ([IO.Path]::GetExtension($InstallWim))
			{
				'.ESD' { $DynamicParams.ESD = $true; Break }
				'.SWM' { $DynamicParams.SWM = $true; Break }
				Default { $DynamicParams.WIM = $true; Break }
			}
			If ($BootWim)
			{
				If ([IO.File]::Exists($BootWim)) { $DynamicParams.BootImage = $true }
			}
		}
		Else
		{
			$PSCmdlet.WriteWarning($OptimizeData.FailedToReturnInstallImage -f $ImageFolder)
			$TempDirectory | Purge
			Break
		}
		#endregion Media Export

		#region Image and Metadata Validation
		If ((Get-WindowsImage -ImagePath $InstallWim -ScratchDirectory $ScratchFolder -LogPath $DISMLog -LogLevel 1).Count -gt 1)
		{
			Do
			{
				$Host.UI.RawUI.WindowTitle = $OptimizeData.SelectWindowsEdition
				$EditionList = Get-WindowsImage -ImagePath $InstallWim -ScratchDirectory $ScratchFolder -LogPath $DISMLog -LogLevel 1 | Select-Object -Property @{ Label = 'Index'; Expression = { ($PSItem.ImageIndex) } }, @{ Label = 'Name'; Expression = { ($PSItem.ImageName) } }, @{ Label = 'Size (GB)'; Expression = { '{0:N2}' -f ($PSItem.ImageSize / 1GB) } } | Out-GridView -Title "Select the Windows 10 Edition to Optimize." -OutputMode Single
			}
			While ($EditionList.Length -eq 0)
			$ImageIndex = $EditionList.Index
		}
		Else { $ImageIndex = 1 }

		Try
		{
			$Host.UI.RawUI.WindowTitle = "Validating Image Metadata."
			$InstallInfo = $InstallWim | Get-ImageData -Index $ImageIndex -ErrorAction Stop
		}
		Catch
		{
			$PSCmdlet.WriteWarning($OptimizeData.FailedToRetrieveImageMetadata -f (GetPath -Path $InstallWim -Split Leaf))
			$TempDirectory | Purge
			Break
		}

		If ($InstallInfo.VersionTable.Major -ne 10)
		{
			$PSCmdlet.WriteWarning($OptimizeData.UnsupportedImageVersion -f $InstallInfo.Version)
			$TempDirectory | Purge
			Break
		}

		If ($InstallInfo.Architecture -ne 'amd64')
		{
			$PSCmdlet.WriteWarning($OptimizeData.UnsupportedImageArch -f $InstallInfo.Architecture)
			$TempDirectory | Purge
			Break
		}

		If ($InstallInfo.InstallationType.Contains('Server') -or $InstallInfo.InstallationType.Contains('WindowsPE'))
		{
			$PSCmdlet.WriteWarning($OptimizeData.UnsupportedImageType -f $InstallInfo.InstallationType)
			$TempDirectory | Purge
			Break
		}

		If ($InstallInfo.Build -ge '17134' -and $InstallInfo.Build -le '19041')
		{
			If ($InstallInfo.Name -like "*LTSC*")
			{
				$DynamicParams.LTSC = $true
				If ($WindowsApps) { Remove-Variable -Name WindowsApps }
				If ($Win32Calc.IsPresent) { $Win32Calc = ![Switch]::Present }
			}
			Else
			{
				If ($WindowsStore.IsPresent) { $WindowsStore = ![Switch]::Present }
				If ($MicrosoftEdge.IsPresent -and $InstallInfo.Build -ge '18362')
				{
					If ($InstallInfo.Build -eq '18362') { $EdgeChromiumUBR = 833 }
					Else { $EdgeChromiumUBR = 601 }
				}
				Else { $MicrosoftEdge = ![Switch]::Present }
			}
			If ($InstallInfo.Build -eq '17134' -and $DeveloperMode.IsPresent) { $DeveloperMode = ![Switch]::Present }
			If ($InstallInfo.Language -ne $OptimizeOffline.Culture)
			{
				If ($MicrosoftEdge.IsPresent) { $MicrosoftEdge = ![Switch]::Present }
				If ($Win32Calc.IsPresent) { $Win32Calc = ![Switch]::Present }
				If ($Dedup.IsPresent) { $Dedup = ![Switch]::Present }
				If ($DaRT) { Remove-Variable -Name DaRT }
			}
		}
		Else
		{
			$PSCmdlet.WriteWarning($OptimizeData.UnsupportedImageBuild -f $InstallInfo.Build)
			$TempDirectory | Purge
			Break
		}
		#endregion Image and Metadata Validation

		#region Image Preparation
		If (!$DynamicParams.WIM)
		{
			$ExportToWimParams = @{
				SourceImagePath      = $InstallWim
				SourceIndex          = $ImageIndex
				DestinationImagePath = '{0}\install.wim' -f $WorkFolder
				CheckIntegrity       = $true
				ScratchDirectory     = $ScratchFolder
				LogPath              = $DISMLog
				LogLevel             = 1
				ErrorAction          = 'Stop'
			}
			If ($DynamicParams.ESD) { $ExportToWimParams.CompressionType = 'Maximum' }
			Else { $ExportToWimParams.SplitImageFilePattern = ('{0}\install*.swm' -f $ImageFolder) }
			Try
			{
				$Host.UI.RawUI.WindowTitle = ($OptimizeData.ExportingInstallToWim -f (GetPath -Path $InstallWim -Split Leaf), (GetPath -Path ([IO.Path]::ChangeExtension($InstallWim, '.wim')) -Split Leaf))
				Write-Host ($OptimizeData.ExportingInstallToWim -f (GetPath -Path $InstallWim -Split Leaf), (GetPath -Path ([IO.Path]::ChangeExtension($InstallWim, '.wim')) -Split Leaf)) -ForegroundColor Cyan
				[Void](Export-WindowsImage @ExportToWimParams)
				$ImageIndex = 1
			}
			Catch
			{
				$PSCmdlet.WriteWarning($OptimizeData.FailedExportingInstallToWim -f (GetPath -Path $InstallWim -Split Leaf), (GetPath -Path ([IO.Path]::ChangeExtension($InstallWim, '.wim')) -Split Leaf))
				$TempDirectory | Purge
				Break
			}
			Finally
			{
				$InstallWim | Purge
				If ($DynamicParams.SWM) { $SwmFiles | Purge }
			}
			Try
			{
				$InstallWim = Get-ChildItem -Path $WorkFolder -Filter install.wim | Move-Item -Destination $ImageFolder -Force -PassThru | Select-Object -ExpandProperty FullName
				$InstallInfo = $InstallWim | Get-ImageData -Index $ImageIndex -ErrorAction Stop
			}
			Catch
			{
				$PSCmdlet.WriteWarning($OptimizeData.FailedToRetrieveImageMetadata -f (GetPath -Path $InstallWim -Split Leaf))
				$TempDirectory | Purge
				Break
			}
		}

		If ($Global:Error.Count -ne 0) { $Global:Error.Clear() }

		Try
		{
			Log ($OptimizeData.SupportedImageBuild -f $InstallInfo.Build)
			Start-Sleep 3
			$OptimizeTimer = [Diagnostics.Stopwatch]::StartNew()
			$InstallMount | Create -ErrorAction Stop
			$MountInstallParams = @{
				ImagePath        = $InstallWim
				Index            = $ImageIndex
				Path             = $InstallMount
				CheckIntegrity   = $true
				ScratchDirectory = $ScratchFolder
				LogPath          = $DISMLog
				LogLevel         = 1
				ErrorAction      = 'Stop'
			}
			Log ($OptimizeData.MountingImage -f $InstallInfo.Name)
			[Void](Mount-WindowsImage @MountInstallParams)
			RegHives -Load
			Get-ItemProperty -Path "HKLM:\WIM_HKLM_SOFTWARE\Microsoft\Windows NT\CurrentVersion" | Export-DataFile -File CurrentVersion
			RegHives -Unload
		}
		Catch
		{
			Log ($OptimizeData.FailedMountingImage -f $InstallInfo.Name) -Type Error -ErrorRecord $Error[0]
			Stop-Optimize
		}

		If ($DaRT -or $Additional.ContainsValue($true))
		{
			If ($DaRT -and $DaRT.Contains('Recovery') -or ($Additional.Drivers -and (Get-ChildItem -Path $OptimizeOffline.RecoveryDrivers -Include *.inf -Recurse -Force)))
			{
				$WinREPath = GetPath -Path $InstallMount -Child 'Windows\System32\Recovery\winre.wim'
				If (Test-Path -Path $WinREPath)
				{
					$RecoveryWim = Move-Item -Path $WinREPath -Destination $ImageFolder -Force -PassThru | Select-Object -ExpandProperty FullName
					$DynamicParams.RecoveryImage = $true
				}
			}
		}

		If ($DynamicParams.BootImage)
		{
			Try
			{
				$BootInfo = $BootWim | Get-ImageData -Index 2 -ErrorAction Stop
			}
			Catch
			{
				Log ($OptimizeData.FailedToRetrieveImageMetadata -f (GetPath -Path $BootWim -Split Leaf)) -Type Error -ErrorRecord $Error[0]
				Stop-Optimize
			}
			Try
			{
				$BootMount | Create -ErrorAction Stop
				$MountBootParams = @{
					Path             = $BootMount
					ImagePath        = $BootWim
					Index            = 2
					CheckIntegrity   = $true
					ScratchDirectory = $ScratchFolder
					LogPath          = $DISMLog
					LogLevel         = 1
					ErrorAction      = 'Stop'
				}
				Log ($OptimizeData.MountingImage -f $BootInfo.Name)
				[Void](Mount-WindowsImage @MountBootParams)
			}
			Catch
			{
				Log ($OptimizeData.FailedMountingImage -f $BootInfo.Name) -Type Error -ErrorRecord $Error[0]
				Stop-Optimize
			}
		}

		If ($DynamicParams.RecoveryImage)
		{
			Try
			{
				$RecoveryInfo = $RecoveryWim | Get-ImageData -Index 1 -ErrorAction Stop
			}
			Catch
			{
				Log ($OptimizeData.FailedToRetrieveImageMetadata -f (GetPath -Path $RecoveryWim -Split Leaf)) -Type Error -ErrorRecord $Error[0]
				Stop-Optimize
			}
			Try
			{
				$RecoveryMount | Create -ErrorAction Stop
				$MountRecoveryParams = @{
					Path             = $RecoveryMount
					ImagePath        = $RecoveryWim
					Index            = 1
					CheckIntegrity   = $true
					ScratchDirectory = $ScratchFolder
					LogPath          = $DISMLog
					LogLevel         = 1
					ErrorAction      = 'Stop'
				}
				Log ($OptimizeData.MountingImage -f $RecoveryInfo.Name)
				[Void](Mount-WindowsImage @MountRecoveryParams)
			}
			Catch
			{
				Log ($OptimizeData.FailedMountingImage -f $RecoveryInfo.Name) -Type Error -ErrorRecord $Error[0]
				Stop-Optimize
			}
		}

		If ((Repair-WindowsImage -Path $InstallMount -CheckHealth -ScratchDirectory $ScratchFolder -LogPath $DISMLog -LogLevel 1).ImageHealthState -eq 'Healthy')
		{
			Log $OptimizeData.PreOptimizedImageHealthHealthy
			Start-Sleep 3; Clear-Host
		}
		Else
		{
			Log $OptimizeData.PreOptimizedImageHealthCorrupted -Type Error
			Stop-Optimize
		}
		#endregion Image Preparation

		#region Provisioned App Package Removal
		If ($WindowsApps -and (Get-AppxProvisionedPackage -Path $InstallMount -ScratchDirectory $ScratchFolder -LogPath $DISMLog -LogLevel 1).Count -gt 0)
		{
			$Host.UI.RawUI.WindowTitle = "Remove Provisioned App Packages."
			$AppxPackages = Get-AppxProvisionedPackage -Path $InstallMount -ScratchDirectory $ScratchFolder -LogPath $DISMLog -LogLevel 1 | Select-Object -Property DisplayName, PackageName | Sort-Object -Property DisplayName
			If ($InstallInfo.Build -eq '19041')
			{
				$AppxPackages = $AppxPackages | ForEach-Object -Process {
					$DisplayName = $PSItem.DisplayName; $PackageName = $PSItem.PackageName
					If ($DisplayName -eq 'Microsoft.549981C3F5F10') { $DisplayName = 'CortanaApp.View.App' }
					[PSCustomObject]@{ DisplayName = $DisplayName; PackageName = $PackageName }
				}
			}
			$RemovedAppxPackages = [Collections.Hashtable]::New()
			Switch ($PSBoundParameters.WindowsApps)
			{
				'Select'
				{
					Try
					{
						$AppxPackages | Out-GridView -Title "Select the Provisioned App Packages to Remove." -PassThru | ForEach-Object -Process {
							$RemoveAppxParams = @{
								Path             = $InstallMount
								PackageName      = $PSItem.PackageName
								ScratchDirectory = $ScratchFolder
								LogPath          = $DISMLog
								LogLevel         = 1
								ErrorAction      = 'Stop'
							}
							Log ($OptimizeData.RemovingWindowsApp -f $PSItem.DisplayName)
							[Void](Remove-AppxProvisionedPackage @RemoveAppxParams)
							$RemovedAppxPackages.Add($PSItem.DisplayName, $PSItem.PackageName)
						}
						$DynamicParams.WindowsApps = $true
					}
					Catch
					{
						Log $OptimizeData.FailedRemovingWindowsApps -Type Error -ErrorRecord $Error[0]
						Stop-Optimize
					}
					Break
				}
				'Whitelist'
				{
					If (Test-Path -Path $OptimizeOffline.AppxWhitelist)
					{
						Try
						{
							If ($InstallInfo.Build -eq '19041')
							{
								$WhitelistJSON = Get-Content -Path $OptimizeOffline.AppxWhitelist -Raw -ErrorAction Stop
								If ($WhitelistJSON.Contains('Microsoft.549981C3F5F10')) { $WhitelistJSON = $WhitelistJSON.Replace('Microsoft.549981C3F5F10', 'CortanaApp.View.App') }
								$WhitelistJSON = $WhitelistJSON | ConvertFrom-Json -ErrorAction Stop
							}
							Else
							{
								$WhitelistJSON = Get-Content -Path $OptimizeOffline.AppxWhitelist -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
							}
							$AppxPackages | ForEach-Object -Process {
								If ($PSItem.DisplayName -notin $WhitelistJSON.DisplayName)
								{
									$RemoveAppxParams = @{
										Path             = $InstallMount
										PackageName      = $PSItem.PackageName
										ScratchDirectory = $ScratchFolder
										LogPath          = $DISMLog
										LogLevel         = 1
										ErrorAction      = 'Stop'
									}
									Log ($OptimizeData.RemovingWindowsApp -f $PSItem.DisplayName)
									[Void](Remove-AppxProvisionedPackage @RemoveAppxParams)
									$RemovedAppxPackages.Add($PSItem.DisplayName, $PSItem.PackageName)
								}
							}
							$DynamicParams.WindowsApps = $true
						}
						Catch
						{
							Log $OptimizeData.FailedRemovingWindowsApps -Type Error -ErrorRecord $Error[0]
							Stop-Optimize
						}
					}
					Break
				}
				'All'
				{
					Try
					{
						$AppxPackages | ForEach-Object -Process {
							$RemoveAppxParams = @{
								Path             = $InstallMount
								PackageName      = $PSItem.PackageName
								ScratchDirectory = $ScratchFolder
								LogPath          = $DISMLog
								LogLevel         = 1
								ErrorAction      = 'Stop'
							}
							Log ($OptimizeData.RemovingWindowsApp -f $PSItem.DisplayName)
							[Void](Remove-AppxProvisionedPackage @RemoveAppxParams)
							$RemovedAppxPackages.Add($PSItem.DisplayName, $PSItem.PackageName)
						}
						$DynamicParams.WindowsApps = $true
					}
					Catch
					{
						Log $OptimizeData.FailedRemovingWindowsApps -Type Error -ErrorRecord $Error[0]
						Stop-Optimize
					}
					Break
				}
			}
			$Host.UI.RawUI.WindowTitle = $null; Clear-Host
		}
		#endregion Provisioned App Package Removal

		#region System App Removal
		If ($SystemApps.IsPresent)
		{
			Clear-Host
			$Host.UI.RawUI.WindowTitle = "Remove System Apps."
			$PSCmdlet.WriteWarning($OptimizeData.SystemAppsWarning)
			Start-Sleep 5
			$InboxAppsKey = "HKLM:\WIM_HKLM_SOFTWARE\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore\InboxApplications"
			RegHives -Load
			$InboxAppsPackages = Get-ChildItem -Path $InboxAppsKey -Name | ForEach-Object -Process {
				$DisplayName = $PSItem.Split('_')[0]; $PackageName = $PSItem
				If ($DisplayName -like '1527c705-839a-4832-9118-54d4Bd6a0c89') { $DisplayName = 'Microsoft.Windows.FilePicker' }
				If ($DisplayName -like 'c5e2524a-ea46-4f67-841f-6a9465d9d515') { $DisplayName = 'Microsoft.Windows.FileExplorer' }
				If ($DisplayName -like 'E2A4F912-2574-4A75-9BB0-0D023378592B') { $DisplayName = 'Microsoft.Windows.AppResolverUX' }
				If ($DisplayName -like 'F46D4000-FD22-4DB4-AC8E-4E1DDDE828FE') { $DisplayName = 'Microsoft.Windows.AddSuggestedFoldersToLibarayDialog' }
				[PSCustomObject]@{ DisplayName = $DisplayName; PackageName = $PackageName }
			} | Sort-Object -Property DisplayName | Out-GridView -Title "Remove System Apps." -PassThru
			If ($InboxAppsPackages)
			{
				Clear-Host
				$RemovedSystemApps = [Collections.Hashtable]::New()
				Try
				{
					$InboxAppsPackages | ForEach-Object -Process {
						$PackageKey = (GetPath -Path $InboxAppsKey -Child $PSItem.PackageName) -replace 'HKLM:', 'HKLM'
						Log ($OptimizeData.RemovingSystemApp -f $PSItem.DisplayName)
						$RET = StartExe $REG -Arguments ('DELETE "{0}" /F' -f $PackageKey) -ErrorAction Stop
						If ($RET -eq 1) { Log ($OptimizeData.FailedRemovingSystemApp -f $PSItem.DisplayName) -Type Error; Continue }
						$RemovedSystemApps.Add($PSItem.DisplayName, $PSItem.PackageName)
						Start-Sleep 2
					}
					$DynamicParams.SystemApps = $true
				}
				Catch
				{
					Log $OptimizeData.FailedRemovingSystemApps -Type Error -ErrorRecord $Error[0]
					Stop-Optimize
				}
				Finally
				{
					RegHives -Unload
				}
			}
			$Host.UI.RawUI.WindowTitle = $null; Clear-Host
		}
		#endregion System App Removal

		#region Removed Package Clean-up
		If ($DynamicParams.WindowsApps -or $DynamicParams.SystemApps)
		{
			Log $OptimizeData.RemovedPackageCleanup
			If ($DynamicParams.WindowsApps)
			{
				If ($InstallInfo.Build -lt '19041')
				{
					If ((Get-AppxProvisionedPackage -Path $InstallMount -ScratchDirectory $ScratchFolder -LogPath $DISMLog -LogLevel 1).Count -eq 0) { Get-ChildItem -Path (GetPath -Path $InstallMount -Child 'Program Files\WindowsApps') -Force | Purge -Force }
					Else { Get-ChildItem -Path (GetPath -Path $InstallMount -Child 'Program Files\WindowsApps') -Force | Where-Object -Property Name -In $RemovedAppxPackages.Values | Purge -Force }
				}
				Else
				{
					If ((Get-AppxProvisionedPackage -Path $InstallMount -ScratchDirectory $ScratchFolder -LogPath $DISMLog -LogLevel 1).Count -eq 0) { Get-ChildItem -Path (GetPath -Path $InstallMount -Child 'Program Files\WindowsApps') -Force | Purge -Force }
				}
			}
			RegHives -Load
			$Visibility = [Text.StringBuilder]::New('hide:')
			If ($RemovedAppxPackages.'Microsoft.WindowsMaps')
			{
				RegKey -Path "HKLM:\WIM_HKLM_SYSTEM\Maps" -Name "AutoUpdateEnabled" -Value 0 -Type DWord
				If (Test-Path -Path "HKLM:\WIM_HKLM_SYSTEM\ControlSet001\Services\MapsBroker") { RegKey -Path "HKLM:\WIM_HKLM_SYSTEM\ControlSet001\Services\MapsBroker" -Name "Start" -Value 4 -Type DWord }
				[Void]$Visibility.Append('maps;maps-downloadmaps;')
			}
			If ($RemovedAppxPackages.'Microsoft.Wallet' -and (Test-Path -Path "HKLM:\WIM_HKLM_SYSTEM\ControlSet001\Services\WalletService")) { RegKey -Path "HKLM:\WIM_HKLM_SYSTEM\ControlSet001\Services\WalletService" -Name "Start" -Value 4 -Type DWord }
			If ($RemovedAppxPackages.'Microsoft.XboxIdentityProvider' -and ($RemovedAppxPackages.Keys -like "*Xbox*").Count -gt 1 -or $RemovedSystemApps.'Microsoft.XboxGameCallableUI')
			{
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\Windows\GameDVR" -Name "AllowGameDVR" -Value 0 -Type DWord
				RegKey -Path "HKLM:\WIM_HKCU\Software\Microsoft\Windows\CurrentVersion\GameDVR" -Name "AppCaptureEnabled" -Value 0 -Type DWord
				RegKey -Path "HKLM:\WIM_HKCU\Software\Microsoft\Windows\CurrentVersion\GameDVR" -Name "AudioCaptureEnabled" -Value 0 -Type DWord
				RegKey -Path "HKLM:\WIM_HKCU\Software\Microsoft\Windows\CurrentVersion\GameDVR" -Name "CursorCaptureEnabled" -Value 0 -Type DWord
				RegKey -Path "HKLM:\WIM_HKCU\Software\Microsoft\GameBar" -Name "AutoGameModeEnabled" -Value 0 -Type DWord
				RegKey -Path "HKLM:\WIM_HKCU\Software\Microsoft\GameBar" -Name "AllowAutoGameMode" -Value 0 -Type DWord
				RegKey -Path "HKLM:\WIM_HKCU\Software\Microsoft\GameBar" -Name "UseNexusForGameBarEnabled" -Value 0 -Type DWord
				RegKey -Path "HKLM:\WIM_HKCU\Software\Microsoft\GameBar" -Name "ShowStartupPanel" -Value 0 -Type DWord
				RegKey -Path "HKLM:\WIM_HKCU\System\GameConfigStore" -Name "GameDVR_Enabled" -Value 0 -Type DWord
				RegKey -Path "HKLM:\WIM_HKCU\System\GameConfigStore" -Name "GameDVR_FSEBehavior" -Value 2 -Type DWord
				RegKey -Path "HKLM:\WIM_HKCU\System\GameConfigStore" -Name "GameDVR_FSEBehaviorMode" -Value 2 -Type DWord
				@("xbgm", "XblAuthManager", "XblGameSave", "xboxgip", "XboxGipSvc", "XboxNetApiSvc") | ForEach-Object -Process { If (Test-Path -Path "HKLM:\WIM_HKLM_SYSTEM\ControlSet001\Services\$($PSItem)") { RegKey -Path "HKLM:\WIM_HKLM_SYSTEM\ControlSet001\Services\$($PSItem)" -Name "Start" -Value 4 -Type DWord } }
				[Void]$Visibility.Append('gaming-gamebar;gaming-gamedvr;gaming-broadcasting;gaming-gamemode;gaming-xboxnetworking;quietmomentsgame;')
				If ($InstallInfo.Build -lt '17763') { [Void]$Visibility.Append('gaming-trueplay;') }
			}
			If ($RemovedAppxPackages.'Microsoft.YourPhone' -or $RemovedSystemApps.'Microsoft.Windows.CallingShellApp')
			{
				[Void]$Visibility.Append('mobile-devices;mobile-devices-addphone;mobile-devices-addphone-direct;')
				If (Test-Path -Path "HKLM:\WIM_HKLM_SYSTEM\ControlSet001\Services\PhoneSvc") { RegKey -Path "HKLM:\WIM_HKLM_SYSTEM\ControlSet001\Services\PhoneSvc" -Name "Start" -Value 4 -Type DWord }
			}
			If ($RemovedSystemApps.'Microsoft.MicrosoftEdge' -and !$MicrosoftEdge.IsPresent) { RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Microsoft\EdgeUpdate" -Name "DoNotUpdateToEdgeWithChromium" -Value 1 -Type DWord }
			If ($RemovedSystemApps.'Microsoft.BioEnrollment')
			{
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\Biometrics" -Name "Enabled" -Value 0 -Type DWord
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\Biometrics\Credential Provider" -Name "Enabled" -Value 0 -Type DWord
				If (Test-Path -Path "HKLM:\WIM_HKLM_SYSTEM\ControlSet001\Services\WbioSrvc") { RegKey -Path "HKLM:\WIM_HKLM_SYSTEM\ControlSet001\Services\WbioSrvc" -Name "Start" -Value 4 -Type DWord }
			}
			If ($RemovedSystemApps.'Microsoft.Windows.SecureAssessmentBrowser')
			{
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Microsoft\Windows\CurrentVersion\SecureAssessment" -Name "AllowScreenMonitoring" -Value 0 -Type DWord
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Microsoft\Windows\CurrentVersion\SecureAssessment" -Name "AllowTextSuggestions" -Value 0 -Type DWord
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Microsoft\Windows\CurrentVersion\SecureAssessment" -Name "RequirePrinting" -Value 0 -Type DWord
			}
			If ($RemovedSystemApps.'Microsoft.Windows.ContentDeliveryManager')
			{
				@("ContentDeliveryAllowed", "FeatureManagementEnabled", "OemPreInstalledAppsEnabled", "PreInstalledAppsEnabled", "PreInstalledAppsEverEnabled", "RotatingLockScreenEnabled",
					"RotatingLockScreenOverlayEnabled", "SilentInstalledAppsEnabled", "SoftLandingEnabled", "SystemPaneSuggestionsEnabled", "SubscribedContentEnabled",
					"SubscribedContent-202913Enabled", "SubscribedContent-202914Enabled", "SubscribedContent-280797Enabled", "SubscribedContent-280811Enabled", "SubscribedContent-280812Enabled",
					"SubscribedContent-280813Enabled", "SubscribedContent-280814Enabled", "SubscribedContent-280815Enabled", "SubscribedContent-280810Enabled", "SubscribedContent-280817Enabled",
					"SubscribedContent-310091Enabled", "SubscribedContent-310092Enabled", "SubscribedContent-310093Enabled", "SubscribedContent-310094Enabled", "SubscribedContent-314558Enabled",
					"SubscribedContent-314559Enabled", "SubscribedContent-314562Enabled", "SubscribedContent-314563Enabled", "SubscribedContent-314566Enabled", "SubscribedContent-314567Enabled",
					"SubscribedContent-338380Enabled", "SubscribedContent-338387Enabled", "SubscribedContent-338381Enabled", "SubscribedContent-338388Enabled", "SubscribedContent-338382Enabled",
					"SubscribedContent-338389Enabled", "SubscribedContent-338386Enabled", "SubscribedContent-338393Enabled", "SubscribedContent-346480Enabled", "SubscribedContent-346481Enabled",
					"SubscribedContent-353694Enabled", "SubscribedContent-353695Enabled", "SubscribedContent-353696Enabled", "SubscribedContent-353697Enabled", "SubscribedContent-353698Enabled",
					"SubscribedContent-353699Enabled", "SubscribedContent-88000044Enabled", "SubscribedContent-88000045Enabled", "SubscribedContent-88000105Enabled", "SubscribedContent-88000106Enabled",
					"SubscribedContent-88000161Enabled", "SubscribedContent-88000162Enabled", "SubscribedContent-88000163Enabled", "SubscribedContent-88000164Enabled", "SubscribedContent-88000165Enabled",
					"SubscribedContent-88000166Enabled") | ForEach-Object -Process { RegKey -Path "HKLM:\WIM_HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name $PSItem -Value 0 -Type DWord }
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\Windows\CloudContent" -Name "DisableWindowsConsumerFeatures" -Value 1 -Type DWord
				RegKey -Path "HKLM:\WIM_HKCU\Software\Policies\Microsoft\Microsoft\Windows\CurrentVersion\PushNotifications" -Name "NoCloudApplicationNotification" -Value 1 -Type DWord
			}
			If ($RemovedSystemApps.'Microsoft.Windows.SecHealthUI')
			{
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\Windows Defender" -Name "DisableAntiSpyware" -Value 1 -Type DWord
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\Windows Defender\Spynet" -Name "SpyNetReporting" -Value 0 -Type DWord
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\Windows Defender\Spynet" -Name "SubmitSamplesConsent" -Value 2 -Type DWord
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\Windows Defender\MpEngine" -Name "MpEnablePus" -Value 0 -Type DWord
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\Windows Defender\Reporting" -Name "DisableEnhancedNotifications" -Value 1 -Type DWord
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection" -Name "DisableBehaviorMonitoring" -Value 1 -Type DWord
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection" -Name "DisableRealtimeMonitoring" -Value 1 -Type DWord
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection" -Name "DisableOnAccessProtection" -Value 1 -Type DWord
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection" -Name "DisableScanOnRealtimeEnable" -Value 1 -Type DWord
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection" -Name "DisableIOAVProtection" -Value 1 -Type DWord
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\Windows Defender\Policy Manager" -Name "AllowBehaviorMonitoring" -Value 2 -Type DWord
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\Windows Defender\Policy Manager" -Name "AllowCloudProtection" -Value 0 -Type DWord
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\Windows Defender\Policy Manager" -Name "AllowRealtimeMonitoring" -Value 0 -Type DWord
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\Windows Defender\Policy Manager" -Name "SubmitSamplesConsent" -Value 2 -Type DWord
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\Windows Defender\UX Configuration" -Name "Notification_Suppress" -Value 1 -Type DWord
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\MRT" -Name "DontOfferThroughWUAU" -Value 1 -Type DWord
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\MRT" -Name "DontReportInfectionInformation" -Value 1 -Type DWord
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\Windows Defender Security Center\Systray" -Name "HideSystray" -Value 1 -Type DWord
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Microsoft\Windows Defender\Features" -Name "TamperProtection" -Value 0 -Type DWord -Force
				RegKey -Path "HKLM:\WIM_HKCU\Software\Microsoft\Windows Security Health\State" -Name "AccountProtection_MicrosoftAccount_Disconnected" -Value 1 -Type DWord
				RegKey -Path "HKLM:\WIM_HKCU\Software\Microsoft\Windows Security Health\State" -Name "AppAndBrowser_EdgeSmartScreenOff" -Value 0 -Type DWord
				RegKey -Path "HKLM:\WIM_HKCU\Software\Microsoft\Windows\CurrentVersion\AppHost" -Name "SmartScreenEnabled" -Value "Off" -Type String
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer" -Name "SmartScreenEnabled" -Value "Off" -Type String
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Explorer" -Name "SmartScreenEnabled" -Value "Off" -Type String
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Microsoft\Windows\CurrentVersion\AppHost" -Name "EnableWebContentEvaluation" -Value 0 -Type DWord
				RegKey -Path "HKLM:\WIM_HKCU\Software\Microsoft\Windows\CurrentVersion\AppHost" -Name "EnableWebContentEvaluation" -Value 0 -Type DWord
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\Windows\System" -Name "EnableSmartScreen" -Value 0 -Type DWord
				@("SecurityHealthService", "WinDefend", "WdNisSvc", "WdNisDrv", "WdBoot", "WdFilter", "Sense") | ForEach-Object -Process { If (Test-Path -Path "HKLM:\WIM_HKLM_SYSTEM\ControlSet001\Services\$($PSItem)") { RegKey -Path "HKLM:\WIM_HKLM_SYSTEM\ControlSet001\Services\$($PSItem)" -Name "Start" -Value 4 -Type DWord } }
				@("HKLM:\WIM_HKLM_SOFTWARE\Classes\*\shellex\ContextMenuHandlers\EPP", "HKLM:\WIM_HKLM_SOFTWARE\Classes\Directory\shellex\ContextMenuHandlers\EPP", "HKLM:\WIM_HKLM_SOFTWARE\Classes\Drive\shellex\ContextMenuHandlers\EPP",
					"HKLM:\WIM_HKLM_SYSTEM\ControlSet001\Control\WMI\AutoLogger\DefenderApiLogger", "HKLM:\WIM_HKLM_SYSTEM\ControlSet001\Control\WMI\AutoLogger\DefenderAuditLogger") | Purge
				Remove-KeyProperty -Path "HKLM:\WIM_HKLM_SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Name "SecurityHealth"
				If (!$DynamicParams.LTSC -or $MicrosoftEdge.IsPresent)
				{
					RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\MicrosoftEdge\PhishingFilter" -Name "EnabledV9" -Value 0 -Type DWord
					RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\WOW6432Node\Policies\Microsoft\MicrosoftEdge\PhishingFilter" -Name "EnabledV9" -Value 0 -Type DWord
				}
				If ($InstallInfo.Build -ge '17763')
				{
					RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\Windows Defender\SmartScreen" -Name "ConfigureAppInstallControlEnabled" -Value 1 -Type DWord
					RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\Windows Defender\SmartScreen" -Name "ConfigureAppInstallControl" -Value "Anywhere" -Type String
				}
				[Void]$Visibility.Append('windowsdefender;')
				$DynamicParams.SecHealthUI = $true
			}
			If ($Visibility.Length -gt 5)
			{
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" -Name "SettingsPageVisibility" -Value $Visibility.ToString().TrimEnd(';') -Type String
				RegKey -Path "HKLM:\WIM_HKCU\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer" -Name "SettingsPageVisibility" -Value $Visibility.ToString().TrimEnd(';') -Type String
			}
			RegHives -Unload
			If ($DynamicParams.SecHealthUI -and (Get-WindowsOptionalFeature -Path $InstallMount -FeatureName Windows-Defender-Default-Definitions -ScratchDirectory $ScratchFolder -LogPath $DISMLog -LogLevel 1 | Where-Object -Property State -EQ Enabled))
			{
				Try
				{
					$DisableDefenderOptionalFeature = @{
						Path             = $InstallMount
						FeatureName      = 'Windows-Defender-Default-Definitions'
						Remove           = $true
						NoRestart        = $true
						ScratchDirectory = $ScratchFolder
						LogPath          = $DISMLog
						LogLevel         = 1
						ErrorAction      = 'Stop'
					}
					Log $OptimizeData.DisablingDefenderOptionalFeature
					[Void](Disable-WindowsOptionalFeature @DisableDefenderOptionalFeature)
				}
				Catch
				{
					Log $OptimizeData.FailedDisablingDefenderOptionalFeature -Type Error -ErrorRecord $Error[0]
					Start-Sleep 3
				}
			}
		}
		#endregion Removed Package Clean-up

		#region Import Custom App Associations
		If (Test-Path -Path $OptimizeOffline.CustomAppAssociations)
		{
			Log $OptimizeData.ImportingCustomAppAssociations
			$RET = StartExe $DISM -Arguments ('/Image:"{0}" /Import-DefaultAppAssociations:"{1}" /ScratchDir:"{2}" /LogPath:"{3}" /LogLevel:1' -f $InstallMount, $OptimizeOffline.CustomAppAssociations, $ScratchFolder, $DISMLog)
			If ($RET -ne 0) { Log $OptimizeData.FailedImportingCustomAppAssociations -Type Error; Start-Sleep 3 }
		}
		#endregion Import Custom App Associations

		#region Windows Capability and Cabinet File Package Removal
		If ($Capabilities.IsPresent)
		{
			Clear-Host
			$Host.UI.RawUI.WindowTitle = "Remove Windows Capabilities."
			$WindowsCapabilities = Get-WindowsCapability -Path $InstallMount -ScratchDirectory $ScratchFolder -LogPath $DISMLog -LogLevel 1 | Where-Object { $PSItem.Name -notlike "*Language.Basic*" -and $PSItem.Name -notlike "*TextToSpeech*" -and $PSItem.State -eq 'Installed' } | Select-Object -Property Name, State | Sort-Object -Property Name | Out-GridView -Title "Remove Windows Capabilities." -PassThru
			If ($WindowsCapabilities)
			{
				Try
				{
					$WindowsCapabilities | ForEach-Object -Process {
						$RemoveCapabilityParams = @{
							Path             = $InstallMount
							Name             = $PSItem.Name
							ScratchDirectory = $ScratchFolder
							LogPath          = $DISMLog
							LogLevel         = 1
							ErrorAction      = 'Stop'
						}
						Log ($OptimizeData.RemovingWindowsCapability -f $PSItem.Name.Split('~')[0])
						[Void](Remove-WindowsCapability @RemoveCapabilityParams)
					}
					$DynamicParams.Capabilities = $true
				}
				Catch
				{
					Log $OptimizeData.FailedRemovingWindowsCapabilities -Type Error -ErrorRecord $Error[0]
					Stop-Optimize
				}
				$Host.UI.RawUI.WindowTitle = $null; Clear-Host
			}
		}

		If ($Packages.IsPresent)
		{
			Clear-Host
			$Host.UI.RawUI.WindowTitle = "Remove Windows Packages."
			$WindowsPackages = Get-WindowsPackage -Path $InstallMount -ScratchDirectory $ScratchFolder -LogPath $DISMLog -LogLevel 1 | Where-Object { $PSItem.ReleaseType -eq 'OnDemandPack' -or $PSItem.ReleaseType -eq 'LanguagePack' -or $PSItem.ReleaseType -eq 'FeaturePack' -and $PSItem.PackageName -notlike "*20H2Enablement*" -and $PSItem.PackageName -notlike "*LanguageFeatures-Basic*" -and $PSItem.PackageName -notlike "*LanguageFeatures-TextToSpeech*" -and $PSItem.PackageState -eq 'Installed' } | Select-Object -Property PackageName, ReleaseType | Sort-Object -Property PackageName | Out-GridView -Title "Remove Windows Packages." -PassThru
			If ($WindowsPackages)
			{
				Try
				{
					$WindowsPackages | ForEach-Object -Process {
						$RemovePackageParams = @{
							Path             = $InstallMount
							PackageName      = $PSItem.PackageName
							NoRestart        = $true
							ScratchDirectory = $ScratchFolder
							LogPath          = $DISMLog
							LogLevel         = 1
							ErrorAction      = 'Stop'
						}
						Log ($OptimizeData.RemovingWindowsPackage -f $PSItem.PackageName.Replace('Package', $null).Split('~')[0].TrimEnd('-'))
						[Void](Remove-WindowsPackage @RemovePackageParams)
					}
					$DynamicParams.Packages = $true
				}
				Catch
				{
					Log $OptimizeData.FailedRemovingWindowsPackages -Type Error -ErrorRecord $Error[0]
					Stop-Optimize
				}
				$Host.UI.RawUI.WindowTitle = $null; Clear-Host
			}
		}
		#endregion Windows Capability and Cabinet File Package Removal

		#region Disable Unsafe Optional Features
		<#
		@('SMB1Protocol', 'MicrosoftWindowsPowerShellV2Root') | ForEach-Object -Process { Get-WindowsOptionalFeature -Path $InstallMount -FeatureName $PSItem -ScratchDirectory $ScratchFolder -LogPath $DISMLog -LogLevel 1 | Where-Object -Property State -EQ Disabled | Disable-WindowsOptionalFeature -Path $InstallMount -Remove -NoRestart -ScratchDirectory $ScratchFolder -LogPath $DISMLog -LogLevel 1 }
		#>
		ForEach ($Feature In @('SMB1Protocol', 'MicrosoftWindowsPowerShellV2Root'))
		{
			If (Get-WindowsOptionalFeature -Path $InstallMount -FeatureName $Feature -ScratchDirectory $ScratchFolder -LogPath $DISMLog -LogLevel 1 | Where-Object -Property State -EQ Enabled)
			{
				Try
				{
					$DisableOptionalFeatureParams = @{
						Path             = $InstallMount
						FeatureName      = $Feature
						Remove           = $true
						NoRestart        = $true
						ScratchDirectory = $ScratchFolder
						LogPath          = $DISMLog
						LogLevel         = 1
						ErrorAction      = 'Stop'
					}
					Log ($OptimizeData.DisablingUnsafeOptionalFeature -f $Feature)
					[Void](Disable-WindowsOptionalFeature @DisableOptionalFeatureParams)
				}
				Catch
				{
					Log ($OptimizeData.FailedDisablingUnsafeOptionalFeature -f $Feature) -Type Error -ErrorRecord $Error[0]
					Stop-Optimize
				}
			}
		}
		#endregion Disable Unsafe Optional Features

		#region Disable/Enable Optional Features
		If ($Features.IsPresent)
		{
			Clear-Host
			$Host.UI.RawUI.WindowTitle = "Disable Optional Features."
			$DisableFeatures = Get-WindowsOptionalFeature -Path $InstallMount -ScratchDirectory $ScratchFolder -LogPath $DISMLog -LogLevel 1 | Where-Object -Property State -EQ Enabled | Select-Object -Property FeatureName, State | Sort-Object -Property FeatureName | Out-GridView -Title "Disable Optional Features." -PassThru
			If ($DisableFeatures)
			{
				Try
				{
					$DisableFeatures | ForEach-Object -Process {
						$DisableFeatureParams = @{
							Path             = $InstallMount
							FeatureName      = $PSItem.FeatureName
							Remove           = $true
							NoRestart        = $true
							ScratchDirectory = $ScratchFolder
							LogPath          = $DISMLog
							LogLevel         = 1
							ErrorAction      = 'Stop'
						}
						Log ($OptimizeData.DisablingOptionalFeature -f $PSItem.FeatureName)
						[Void](Disable-WindowsOptionalFeature @DisableFeatureParams)
					}
					$DynamicParams.DisabledOptionalFeatures = $true
				}
				Catch
				{
					Log $OptimizeData.FailedDisablingOptionalFeatures -Type Error -ErrorRecord $Error[0]
					Stop-Optimize
				}
				$Host.UI.RawUI.WindowTitle = $null; Clear-Host
			}
			Clear-Host
			$Host.UI.RawUI.WindowTitle = "Enable Optional Features."
			$EnableFeatures = Get-WindowsOptionalFeature -Path $InstallMount -ScratchDirectory $ScratchFolder -LogPath $DISMLog -LogLevel 1 | Where-Object { $PSItem.FeatureName -notlike "SMB1Protocol*" -and $PSItem.FeatureName -ne "Windows-Defender-Default-Definitions" -and $PSItem.FeatureName -notlike "MicrosoftWindowsPowerShellV2*" -and $PSItem.State -eq "Disabled" } | Select-Object -Property FeatureName, State | Sort-Object -Property FeatureName | Out-GridView -Title "Enable Optional Features." -PassThru
			If ($EnableFeatures)
			{
				Try
				{
					$EnableFeatures | ForEach-Object -Process {
						$EnableFeatureParams = @{
							Path             = $InstallMount
							FeatureName      = $PSItem.FeatureName
							All              = $true
							LimitAccess      = $true
							NoRestart        = $true
							ScratchDirectory = $ScratchFolder
							LogPath          = $DISMLog
							LogLevel         = 1
							ErrorAction      = 'Stop'
						}
						Log ($OptimizeData.EnablingOptionalFeature -f $PSItem.FeatureName)
						[Void](Enable-WindowsOptionalFeature @EnableFeatureParams)
					}
					$DynamicParams.EnabledOptionalFeatures = $true
				}
				Catch
				{
					Log $OptimizeData.FailedEnablingOptionalFeatures -Type Error -ErrorRecord $Error[0]
					Stop-Optimize
				}
				$Host.UI.RawUI.WindowTitle = $null; Clear-Host
			}
		}
		#endregion Disable/Enable Optional Features

		#region DeveloperMode Integration
		If ($DeveloperMode.IsPresent -and (Test-Path -Path $OptimizeOffline.DevMode -Filter *DeveloperMode-Desktop-Package*.cab) -and !(Get-WindowsPackage -Path $InstallMount -ScratchDirectory $ScratchFolder -LogPath $DISMLog -LogLevel 1 | Where-Object -Property PackageName -Like *DeveloperMode*))
		{
			$DevModeExpand = Create -Path (GetPath -Path $WorkFolder -Child DeveloperMode) -PassThru
			[Void](StartExe $EXPAND -Arguments ('"{0}" F:* "{1}"' -f (GetPath -Path $OptimizeOffline.DevMode -Child "Microsoft-OneCore-DeveloperMode-Desktop-Package~$($InstallInfo.Architecture)~~10.0.$($InstallInfo.Build).1.cab"), $DevModeExpand.FullName))
			Try
			{
				Log $OptimizeData.IntegratingDeveloperMode
				$RET = StartExe $DISM -Arguments ('/Image:"{0}" /Add-Package /PackagePath:"{1}" /ScratchDir:"{2}" /LogPath:"{3}" /LogLevel:1' -f $InstallMount, (GetPath -Path $DevModeExpand.FullName -Child update.mum), $ScratchFolder, $DISMLog)
				If ($RET -eq 0) { $DynamicParams.DeveloperMode = $true }
				Else { Throw }
			}
			Catch
			{
				Log $OptimizeData.FailedIntegratingDeveloperMode -Type Error
				Stop-Optimize
			}
			If ($DynamicParams.DeveloperMode)
			{
				RegHives -Load
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock" -Name "AllowAllTrustedApps" -Value 1 -Type DWord
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock" -Name "AllowDevelopmentWithoutDevLicense" -Value 1 -Type DWord
				RegHives -Unload
			}
		}
		#endregion DeveloperMode Integration

		#region Windows Store Integration
		If ($WindowsStore.IsPresent -and (Test-Path -Path $OptimizeOffline.WindowsStore -Filter Microsoft.WindowsStore*.appxbundle) -and !(Get-AppxProvisionedPackage -Path $InstallMount -ScratchDirectory $ScratchFolder -LogPath $DISMLog -LogLevel 1 | Where-Object -Property DisplayName -EQ Microsoft.WindowsStore))
		{
			Log $OptimizeData.IntegratingWindowsStore
			$StoreBundle = Get-ChildItem -Path $OptimizeOffline.WindowsStore -Filter Microsoft.WindowsStore*.appxbundle -File | Select-Object -ExpandProperty FullName
			$PurchaseBundle = Get-ChildItem -Path $OptimizeOffline.WindowsStore -Filter Microsoft.StorePurchaseApp*.appxbundle -File | Select-Object -ExpandProperty FullName
			$XboxBundle = Get-ChildItem -Path $OptimizeOffline.WindowsStore -Filter Microsoft.XboxIdentityProvider*.appxbundle -File | Select-Object -ExpandProperty FullName
			$InstallerBundle = Get-ChildItem -Path $OptimizeOffline.WindowsStore -Filter Microsoft.DesktopAppInstaller*.appxbundle -File | Select-Object -ExpandProperty FullName
			$StoreLicense = Get-ChildItem -Path $OptimizeOffline.WindowsStore -Filter Microsoft.WindowsStore*.xml -File | Select-Object -ExpandProperty FullName
			$PurchaseLicense = Get-ChildItem -Path $OptimizeOffline.WindowsStore -Filter Microsoft.StorePurchaseApp*.xml -File | Select-Object -ExpandProperty FullName
			$XboxLicense = Get-ChildItem -Path $OptimizeOffline.WindowsStore -Filter Microsoft.XboxIdentityProvider*.xml -File | Select-Object -ExpandProperty FullName
			$InstallerLicense = Get-ChildItem -Path $OptimizeOffline.WindowsStore -Filter Microsoft.DesktopAppInstaller*.xml -File | Select-Object -ExpandProperty FullName
			$DependencyPackages = [Collections.Generic.List[String]]::New()
			$DependencyPackages = Get-ChildItem -Path $OptimizeOffline.WindowsStore -Filter Microsoft.VCLibs*.appx -File | Select-Object -ExpandProperty FullName
			$DependencyPackages += Get-ChildItem -Path $OptimizeOffline.WindowsStore -Filter *Native.Framework*.appx -File | Select-Object -ExpandProperty FullName
			$DependencyPackages += Get-ChildItem -Path $OptimizeOffline.WindowsStore -Filter *Native.Runtime*.appx -File | Select-Object -ExpandProperty FullName
			If (!$DynamicParams.DeveloperMode)
			{
				RegHives -Load
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock" -Name "AllowAllTrustedApps" -Value 1 -Type DWord
				RegHives -Unload
			}
			Try
			{
				$StorePackage = @{
					Path                  = $InstallMount
					PackagePath           = $StoreBundle
					DependencyPackagePath = $DependencyPackages
					LicensePath           = $StoreLicense
					ScratchDirectory      = $ScratchFolder
					LogPath               = $DISMLog
					LogLevel              = 1
					ErrorAction           = 'Stop'
				}
				[Void](Add-AppxProvisionedPackage @StorePackage)
				$PurchasePackage = @{
					Path                  = $InstallMount
					PackagePath           = $PurchaseBundle
					DependencyPackagePath = $DependencyPackages
					LicensePath           = $PurchaseLicense
					ScratchDirectory      = $ScratchFolder
					LogPath               = $DISMLog
					LogLevel              = 1
					ErrorAction           = 'Stop'
				}
				[Void](Add-AppxProvisionedPackage @PurchasePackage)
				$XboxPackage = @{
					Path                  = $InstallMount
					PackagePath           = $XboxBundle
					DependencyPackagePath = $DependencyPackages
					LicensePath           = $XboxLicense
					ScratchDirectory      = $ScratchFolder
					LogPath               = $DISMLog
					LogLevel              = 1
					ErrorAction           = 'Stop'
				}
				[Void](Add-AppxProvisionedPackage @XboxPackage)
				$DependencyPackages.Clear()
				$DependencyPackages = Get-ChildItem -Path $OptimizeOffline.WindowsStore -Filter *Native.Runtime*.appx -File | Select-Object -ExpandProperty FullName
				$InstallerPackage = @{
					Path                  = $InstallMount
					PackagePath           = $InstallerBundle
					DependencyPackagePath = $DependencyPackages
					LicensePath           = $InstallerLicense
					ScratchDirectory      = $ScratchFolder
					LogPath               = $DISMLog
					LogLevel              = 1
					ErrorAction           = 'Stop'
				}
				[Void](Add-AppxProvisionedPackage @InstallerPackage)
				$DynamicParams.WindowsStore = $true
			}
			Catch
			{
				Log $OptimizeData.FailedIntegratingWindowsStore -Type Error -ErrorRecord $Error[0]
				Stop-Optimize
			}
			If ($DynamicParams.WindowsStore)
			{
				RegHives -Load
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock" -Name "AllowAllTrustedApps" -Value 0 -Type DWord
				RegHives -Unload
			}
		}
		#endregion Windows Store Integration

		#region Microsoft Edge Integration
		If ($MicrosoftEdge.IsPresent)
		{
			If ($DynamicParams.LTSC -and (Test-Path -Path $OptimizeOffline.MicrosoftEdge -Filter Microsoft-Windows-Internet-Browser-Package*.cab) -and !(Get-WindowsPackage -Path $InstallMount -ScratchDirectory $ScratchFolder -LogPath $DISMLog -LogLevel 1 | Where-Object -Property PackageName -Like *Internet-Browser*))
			{
				Try
				{
					Log $OptimizeData.IntegratingMicrosoftEdge
					@((GetPath -Path $OptimizeOffline.MicrosoftEdge -Child "Microsoft-Windows-Internet-Browser-Package~$($InstallInfo.Architecture)~~10.0.$($InstallInfo.Build).1.cab"),
						(GetPath -Path $OptimizeOffline.MicrosoftEdge -Child "Microsoft-Windows-Internet-Browser-Package~$($InstallInfo.Architecture)~$($InstallInfo.Language)~10.0.$($InstallInfo.Build).1.cab")) | ForEach-Object -Process { [Void](Add-WindowsPackage -Path $InstallMount -PackagePath $PSItem -IgnoreCheck -ScratchDirectory $ScratchFolder -LogPath $DISMLog -LogLevel 1 -ErrorAction Stop) }
					$DynamicParams.MicrosoftEdge = $true
				}
				Catch
				{
					Log $OptimizeData.FailedIntegratingMicrosoftEdge -Type Error -ErrorRecord $Error[0]
					Stop-Optimize
				}
			}
			ElseIf (!$DynamicParams.LTSC -and (Test-Path -Path $OptimizeOffline.MicrosoftEdge -Filter Microsoft-Windows-Chromium-Browser-Package*.cab) -and !(Get-WindowsPackage -Path $InstallMount -ScratchDirectory $ScratchFolder -LogPath $DISMLog -LogLevel 1 | Where-Object -Property PackageName -Like *KB4559309*) -and !(Get-WindowsPackage -Path $InstallMount -ScratchDirectory $ScratchFolder -LogPath $DISMLog -LogLevel 1 | Where-Object -Property PackageName -Like *KB4584229*) -and !(Get-ChildItem -Path (GetPath -Path $InstallMount -Child "Windows\WinSxS\*firsttimeinstaller*\MicrosoftEdgeStandaloneInstaller.exe") -File -Force -ErrorAction SilentlyContinue))
			{
				Log $OptimizeData.IntegratingMicrosoftEdgeChromium
				If (!$RemovedSystemApps.'Microsoft.MicrosoftEdge')
				{
					RegHives -Load
					RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\EdgeUpdate" -Name "Allowsxs" -Value 1 -Type DWord
					RegHives -Unload
				}
				Try
				{
					[Void](Add-WindowsPackage -Path $InstallMount -PackagePath (GetPath -Path $OptimizeOffline.MicrosoftEdge -Child "Microsoft-Windows-Chromium-Browser-Package~$($InstallInfo.Architecture)~~10.0.$($InstallInfo.Build).$($EdgeChromiumUBR).cab") -IgnoreCheck -ScratchDirectory $ScratchFolder -LogPath $DISMLog -LogLevel 1 -ErrorAction Stop)
					$DynamicParams.MicrosoftEdgeChromium = $true
				}
				Catch
				{
					Log $OptimizeData.FailedIntegratingMicrosoftEdgeChromium -Type Error -ErrorRecord $Error[0]
					Stop-Optimize
				}
			}
		}
		#endregion Microsoft Edge Integration

		#region Microsoft Edge Policy Integration
		If ($DynamicParams.MicrosoftEdge -or $DynamicParams.MicrosoftEdgeChromium)
		{
			If (Test-Path -Path $OptimizeOffline.MicrosoftEdge -Filter MicrosoftEdgePolicies.wim)
			{
				Try
				{
					$ExpandEdgePoliciesParams = @{
						ImagePath        = ('{0}\MicrosoftEdgePolicies.wim' -f $OptimizeOffline.MicrosoftEdge)
						Index            = 1
						ApplyPath        = $InstallMount
						CheckIntegrity   = $true
						Verify           = $true
						ScratchDirectory = $ScratchFolder
						LogPath          = $DISMLog
						LogLevel         = 1
						ErrorAction      = 'Stop'
					}
					Log $OptimizeData.IntegratingMicrosoftEdgePolicies
					[Void](Expand-WindowsImage @ExpandEdgePoliciesParams)
				}
				Catch
				{
					Log $OptimizeData.FailedIntegratingMicrosoftEdgePolicies -Type Error -ErrorRecord $Error[0]
					Start-Sleep 3
				}
			}
			RegHives -Load
			RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer" -Name "DisableEdgeDesktopShortcutCreation" -Value 1 -Type DWord
			RegKey -Path "HKLM:\WIM_HKCU\Software\Policies\Microsoft\MicrosoftEdge\Main" -Name "AllowPrelaunch" -Value 0 -Type DWord
			RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\MicrosoftEdge\Main" -Name "AllowPrelaunch" -Value 0 -Type DWord
			RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\WOW6432Node\Policies\Microsoft\MicrosoftEdge\Main" -Name "AllowPrelaunch" -Value 0 -Type DWord
			RegKey -Path "HKLM:\WIM_HKCU\Software\Policies\Microsoft\MicrosoftEdge\TabPreloader" -Name "PreventTabPreloading" -Value 1 -Type DWord
			RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\MicrosoftEdge\TabPreloader" -Name "PreventTabPreloading" -Value 1 -Type DWord
			RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\WOW6432Node\Policies\Microsoft\MicrosoftEdge\TabPreloader" -Name "PreventTabPreloading" -Value 1 -Type DWord
			RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\MicrosoftEdge\Main" -Name "DoNotTrack" -Value 1 -Type DWord
			RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\WOW6432Node\Policies\Microsoft\MicrosoftEdge\Main" -Name "DoNotTrack" -Value 1 -Type DWord
			RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\MicrosoftEdge\Addons" -Name "FlashPlayerEnabled" -Value 0 -Type DWord
			RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\WOW6432Node\Policies\Microsoft\MicrosoftEdge\Addons" -Name "FlashPlayerEnabled" -Value 0 -Type DWord
			RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\MicrosoftEdge\BooksLibrary" -Name "EnableExtendedBooksTelemetry" -Value 0 -Type DWord
			RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\WOW6432Node\Policies\Microsoft\MicrosoftEdge\BooksLibrary" -Name "EnableExtendedBooksTelemetry" -Value 0 -Type DWord
			RegKey -Path "HKLM:\WIM_HKCU\Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppContainer\Storage\microsoft.microsoftedge_8wekyb3d8bbwe\MicrosoftEdge\Main" -Name "DoNotTrack" -Value 1 -Type DWord
			RegKey -Path "HKLM:\WIM_HKCU\Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppContainer\Storage\microsoft.microsoftedge_8wekyb3d8bbwe\MicrosoftEdge\Main" -Name "ShowSearchSuggestionsGlobal" -Value 0 -Type DWord
			RegKey -Path "HKLM:\WIM_HKCU\Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppContainer\Storage\microsoft.microsoftedge_8wekyb3d8bbwe\MicrosoftEdge\Main" -Name "IE10TourShown" -Value 1 -Type DWord
			RegKey -Path "HKLM:\WIM_HKCU\Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppContainer\Storage\microsoft.microsoftedge_8wekyb3d8bbwe\MicrosoftEdge\Main" -Name "DisallowDefaultBrowserPrompt" -Value 1 -Type DWord
			RegKey -Path "HKLM:\WIM_HKCU\Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppContainer\Storage\microsoft.microsoftedge_8wekyb3d8bbwe\MicrosoftEdge\FlipAhead" -Name "FPEnabled" -Value 0 -Type DWord
			RegKey -Path "HKLM:\WIM_HKCU\Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppContainer\Storage\microsoft.microsoftedge_8wekyb3d8bbwe\MicrosoftEdge\FirstRun" -Name "LastFirstRunVersionDelivered" -Value 1 -Type DWord
			RegKey -Path "HKLM:\WIM_HKCU\Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppContainer\Storage\microsoft.microsoftedge_8wekyb3d8bbwe\MicrosoftEdge\ServiceUI" -Name "EnableCortana" -Value 0 -Type DWord
			If ($DynamicParams.LTSC -and $DynamicParams.SecHealthUI)
			{
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\MicrosoftEdge\PhishingFilter" -Name "EnabledV9" -Value 0 -Type DWord
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\WOW6432Node\Policies\Microsoft\MicrosoftEdge\PhishingFilter" -Name "EnabledV9" -Value 0 -Type DWord
				RegKey -Path "HKLM:\WIM_HKCU\Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppContainer\Storage\microsoft.microsoftedge_8wekyb3d8bbwe\MicrosoftEdge\PhishingFilter" -Name "EnabledV9" -Value 0 -Type DWord
			}
			If ($DynamicParams.MicrosoftEdgeChromium)
			{
				$EdgeAppPath = (GetPath -Path $InstallMount -Child 'Program Files (x86)\Microsoft\Edge\Application') | Create -PassThru
				[IO.File]::WriteAllText((GetPath -Path $EdgeAppPath.FullName -Child master_preferences), (@'
{"distribution":{"system_level":true,"do_not_create_desktop_shortcut":true,"do_not_create_quick_launch_shortcut":true,"do_not_create_taskbar_shortcut":true}}
'@).Trim(), [Text.UTF8Encoding]::New($true))
				$Base64String = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes( { Get-ChildItem -Path @("HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components", "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Active Setup\Installed Components") -Recurse | Get-ItemProperty | Select-Object -Property PSPath, StubPath | Where-Object -Property StubPath -Match configure-user-settings | ForEach-Object -Process { Remove-Item -Path $PSItem.PSPath -Force }; Get-ChildItem -Path "$Env:SystemDrive\Users\*\Desktop" -Filter *lnk -Recurse | Where-Object -Property Name -Like *Edge* | Remove-Item -Force }))
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce" -Name "EdgeCleanup" -Value "%SYSTEMROOT%\System32\WindowsPowerShell\v1.0\powershell.exe -ExecutionPolicy Bypass -NoProfile -EncodedCommand $Base64String" -Type ExpandString
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\EdgeUpdate" -Name "CreateDesktopShortcutDefault" -Value 0 -Type DWord
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\WOW6432Node\Policies\Microsoft\EdgeUpdate" -Name "CreateDesktopShortcutDefault" -Value 0 -Type DWord
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\Edge" -Name "HideFirstRunExperience" -Value 1 -Type DWord
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\WOW6432Node\Policies\Microsoft\Edge" -Name "HideFirstRunExperience" -Value 1 -Type DWord
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\Edge" -Name "BackgroundModeEnabled" -Value 0 -Type DWord
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\WOW6432Node\Policies\Microsoft\Edge" -Name "BackgroundModeEnabled" -Value 0 -Type DWord
			}
			RegHives -Unload
		}
		#endregion Microsoft Edge Policy Integration

		#region Win32 Calculator Integration
		If ($Win32Calc.IsPresent -and (Test-Path -Path $OptimizeOffline.Win32Calc -Filter Win32Calc.wim) -and !(Get-WindowsPackage -Path $InstallMount -ScratchDirectory $ScratchFolder -LogPath $DISMLog -LogLevel 1 | Where-Object -Property PackageName -Like *win32calc*))
		{
			Try
			{
				$ExpandCalcParams = @{
					ImagePath        = '{0}\Win32Calc.wim' -f $OptimizeOffline.Win32Calc
					Index            = 1
					ApplyPath        = $InstallMount
					CheckIntegrity   = $true
					Verify           = $true
					ScratchDirectory = $ScratchFolder
					LogPath          = $DISMLog
					LogLevel         = 1
					ErrorAction      = 'Stop'
				}
				Log $OptimizeData.IntegratingWin32Calc
				[Void](Expand-WindowsImage @ExpandCalcParams)
				$DynamicParams.Win32Calc = $true
			}
			Catch
			{
				Log $OptimizeData.FailedIntegratingWin32Calc -Type Error -ErrorRecord $Error[0]
				Stop-Optimize
			}
			If ($DynamicParams.Win32Calc)
			{
				Add-Content -Path (GetPath -Path $InstallMount -Child 'ProgramData\Microsoft\Windows\Start Menu\Programs\Accessories\desktop.ini') -Value 'Calculator.lnk=@%SystemRoot%\System32\shell32.dll,-22019' -Encoding Unicode -Force
				RegHives -Load
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\RegisteredApplications" -Name "Windows Calculator" -Value "SOFTWARE\Microsoft\Windows\CurrentVersion\Applets\Calculator\Capabilities" -Type String
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\WOW6432Node\RegisteredApplications" -Name "Windows Calculator" -Value "SOFTWARE\Microsoft\Windows\CurrentVersion\Applets\Calculator\Capabilities" -Type String
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Classes\calculator" -Name "(default)" -Value "URL:calculator" -Type String
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Classes\calculator" -Name "URL Protocol" -Value "" -Type String
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Classes\calculator\DefaultIcon" -Name "(default)" -Value "C:\Windows\System32\win32calc.exe,0" -Type String
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Classes\calculator\shell\open\command" -Name "(default)" -Value "C:\Windows\System32\win32calc.exe" -Type String
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Microsoft\Windows\CurrentVersion\ShellCompatibility\InboxApp" -Name "56230F2FD0CC3EB4_Calculator_lnk_amd64.lnk" -Value "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Accessories\Calculator.lnk" -Type String -Force
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Microsoft\Windows\CurrentVersion\App Management\WindowsFeatureCategories" -Name "COMMONSTART/Programs/Accessories/Calculator.lnk" -Value "SOFTWARE_CATEGORY_UTILITIES" -Type String -Force
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\App Management\WindowsFeatureCategories" -Name "COMMONSTART/Programs/Accessories/Calculator.lnk" -Value "SOFTWARE_CATEGORY_UTILITIES" -Type String -Force
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Microsoft\Windows\CurrentVersion\Applets\Calculator\Capabilities" -Name "ApplicationName" -Value "%SystemRoot%\System32\win32calc.exe" -Type ExpandString
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Applets\Calculator\Capabilities" -Name "ApplicationName" -Value "%SystemRoot%\System32\win32calc.exe" -Type ExpandString
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Microsoft\Windows\CurrentVersion\Applets\Calculator\Capabilities" -Name "ApplicationDescription" -Value "%SystemRoot%\System32\win32calc.exe,-217" -Type ExpandString
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Applets\Calculator\Capabilities" -Name "ApplicationDescription" -Value "%SystemRoot%\System32\win32calc.exe,-217" -Type ExpandString
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Microsoft\Windows\CurrentVersion\Applets\Calculator\Capabilities\URLAssociations" -Name "calculator" -Value "calculator" -Type String
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Applets\Calculator\Capabilities\URLAssociations" -Name "calculator" -Value "calculator" -Type String
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Microsoft\Windows\CurrentVersion\WINEVT\Channels\Microsoft-Windows-Calculator/Debug" -Name "OwningPublisher" -Value "{75f48521-4131-4ac3-9887-65473224fcb2}" -Type String
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Microsoft\Windows\CurrentVersion\WINEVT\Channels\Microsoft-Windows-Calculator/Debug" -Name "Enabled" -Value 0 -Type DWord
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Microsoft\Windows\CurrentVersion\WINEVT\Channels\Microsoft-Windows-Calculator/Debug" -Name "Isolation" -Value 0 -Type DWord
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Microsoft\Windows\CurrentVersion\WINEVT\Channels\Microsoft-Windows-Calculator/Debug" -Name "ChannelAccess" -Value "O:BAG:SYD:(A;;0x2;;;S-1-15-2-1)(A;;0xf0007;;;SY)(A;;0x7;;;BA)(A;;0x7;;;SO)(A;;0x3;;;IU)(A;;0x3;;;SU)(A;;0x3;;;S-1-5-3)(A;;0x3;;;S-1-5-33)(A;;0x1;;;S-1-5-32-573)" -Type String
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Microsoft\Windows\CurrentVersion\WINEVT\Channels\Microsoft-Windows-Calculator/Debug" -Name "Type" -Value 3 -Type DWord
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Microsoft\Windows\CurrentVersion\WINEVT\Channels\Microsoft-Windows-Calculator/Diagnostic" -Name "OwningPublisher" -Value "{75f48521-4131-4ac3-9887-65473224fcb2}" -Type String
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Microsoft\Windows\CurrentVersion\WINEVT\Channels\Microsoft-Windows-Calculator/Diagnostic" -Name "Enabled" -Value 0 -Type DWord
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Microsoft\Windows\CurrentVersion\WINEVT\Channels\Microsoft-Windows-Calculator/Diagnostic" -Name "Isolation" -Value 0 -Type DWord
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Microsoft\Windows\CurrentVersion\WINEVT\Channels\Microsoft-Windows-Calculator/Diagnostic" -Name "ChannelAccess" -Value "O:BAG:SYD:(A;;0x2;;;S-1-15-2-1)(A;;0xf0007;;;SY)(A;;0x7;;;BA)(A;;0x7;;;SO)(A;;0x3;;;IU)(A;;0x3;;;SU)(A;;0x3;;;S-1-5-3)(A;;0x3;;;S-1-5-33)(A;;0x1;;;S-1-5-32-573)" -Type String
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Microsoft\Windows\CurrentVersion\WINEVT\Channels\Microsoft-Windows-Calculator/Diagnostic" -Name "Type" -Value 2 -Type DWord
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Microsoft\Windows\CurrentVersion\WINEVT\Publishers\{75f48521-4131-4ac3-9887-65473224fcb2}" -Name "(default)" -Value "Microsoft-Windows-Calculator" -Type String
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Microsoft\Windows\CurrentVersion\WINEVT\Publishers\{75f48521-4131-4ac3-9887-65473224fcb2}" -Name "ResourceFileName" -Value "%SystemRoot%\System32\win32calc.exe" -Type ExpandString
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Microsoft\Windows\CurrentVersion\WINEVT\Publishers\{75f48521-4131-4ac3-9887-65473224fcb2}" -Name "MessageFileName" -Value "%SystemRoot%\System32\win32calc.exe" -Type ExpandString
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Microsoft\Windows\CurrentVersion\WINEVT\Publishers\{75f48521-4131-4ac3-9887-65473224fcb2}\ChannelReferences" -Name "Count" -Value 2 -Type DWord
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Microsoft\Windows\CurrentVersion\WINEVT\Publishers\{75f48521-4131-4ac3-9887-65473224fcb2}\ChannelReferences\0" -Name "(default)" -Value "Microsoft-Windows-Calculator/Diagnostic" -Type String
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Microsoft\Windows\CurrentVersion\WINEVT\Publishers\{75f48521-4131-4ac3-9887-65473224fcb2}\ChannelReferences\0" -Name "Id" -Value 16 -Type DWord
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Microsoft\Windows\CurrentVersion\WINEVT\Publishers\{75f48521-4131-4ac3-9887-65473224fcb2}\ChannelReferences\0" -Name "Flags" -Value 0 -Type DWord
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Microsoft\Windows\CurrentVersion\WINEVT\Publishers\{75f48521-4131-4ac3-9887-65473224fcb2}\ChannelReferences\1" -Name "(default)" -Value "Microsoft-Windows-Calculator/Debug" -Type String
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Microsoft\Windows\CurrentVersion\WINEVT\Publishers\{75f48521-4131-4ac3-9887-65473224fcb2}\ChannelReferences\1" -Name "Id" -Value 17 -Type DWord
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Microsoft\Windows\CurrentVersion\WINEVT\Publishers\{75f48521-4131-4ac3-9887-65473224fcb2}\ChannelReferences\1" -Name "Flags" -Value 0 -Type DWord
				RegHives -Unload
			}
		}
		#endregion Win32 Calculator Integration

		#region Data Deduplication Integration
		If ($Dedup.IsPresent -and (Test-Path -Path $OptimizeOffline.Dedup -Filter Microsoft-Windows-FileServer-ServerCore-Package*.cab) -and (Test-Path -Path $OptimizeOffline.Dedup -Filter Microsoft-Windows-Dedup-Package*.cab) -and !(Get-WindowsPackage -Path $InstallMount -ScratchDirectory $ScratchFolder -LogPath $DISMLog -LogLevel 1 | Where-Object { $PSItem.PackageName -like "*Windows-Dedup*" -or $PSItem.PackageName -like "*FileServer-ServerCore*" }))
		{
			Try
			{
				Log $OptimizeData.IntegratingDataDedup
				@((GetPath -Path $OptimizeOffline.Dedup -Child "Microsoft-Windows-FileServer-ServerCore-Package~31bf3856ad364e35~$($InstallInfo.Architecture)~~10.0.$($InstallInfo.Build).1.cab"),
					(GetPath -Path $OptimizeOffline.Dedup -Child "Microsoft-Windows-FileServer-ServerCore-Package~31bf3856ad364e35~$($InstallInfo.Architecture)~$($InstallInfo.Language)~10.0.$($InstallInfo.Build).1.cab"),
					(GetPath -Path $OptimizeOffline.Dedup -Child "Microsoft-Windows-Dedup-Package~31bf3856ad364e35~$($InstallInfo.Architecture)~~10.0.$($InstallInfo.Build).1.cab"),
					(GetPath -Path $OptimizeOffline.Dedup -Child "Microsoft-Windows-Dedup-Package~31bf3856ad364e35~$($InstallInfo.Architecture)~$($InstallInfo.Language)~10.0.$($InstallInfo.Build).1.cab")) | ForEach-Object -Process { [Void](Add-WindowsPackage -Path $InstallMount -PackagePath $PSItem -IgnoreCheck -ScratchDirectory $ScratchFolder -LogPath $DISMLog -LogLevel 1 -ErrorAction Stop) }
				$EnableDedup = @{
					Path             = $InstallMount
					FeatureName      = 'Dedup-Core'
					All              = $true
					LimitAccess      = $true
					NoRestart        = $true
					ScratchDirectory = $ScratchFolder
					LogPath          = $DISMLog
					LogLevel         = 1
					ErrorAction      = 'Stop'
				}
				[Void](Enable-WindowsOptionalFeature @EnableDedup)
				$DynamicParams.DataDeduplication = $true
			}
			Catch
			{
				Log $OptimizeData.FailedIntegratingDataDedup -Type Error -ErrorRecord $Error[0]
				Stop-Optimize
			}
			If ($DynamicParams.DataDeduplication)
			{
				RegHives -Load
				RegKey -Path "HKLM:\WIM_HKLM_SYSTEM\ControlSet001\Services\SharedAccess\Defaults\FirewallPolicy\FirewallRules" -Name "FileServer-ServerManager-DCOM-TCP-In" -Value "v2.29|Action=Allow|Active=TRUE|Dir=In|Protocol=6|LPort=135|App=%systemroot%\\system32\\svchost.exe|Svc=RPCSS|Name=File Server Remote Management (DCOM-In)|Desc=Inbound rule to allow DCOM traffic to manage the File Services role.|EmbedCtxt=File Server Remote Management|" -Type String
				RegKey -Path "HKLM:\WIM_HKLM_SYSTEM\ControlSet001\Services\SharedAccess\Defaults\FirewallPolicy\FirewallRules" -Name "FileServer-ServerManager-SMB-TCP-In" -Value "v2.29|Action=Allow|Active=TRUE|Dir=In|Protocol=6|LPort=445|App=System|Name=File Server Remote Management (SMB-In)|Desc=Inbound rule to allow SMB traffic to manage the File Services role.|EmbedCtxt=File Server Remote Management|" -Type String
				RegKey -Path "HKLM:\WIM_HKLM_SYSTEM\ControlSet001\Services\SharedAccess\Defaults\FirewallPolicy\FirewallRules" -Name "FileServer-ServerManager-Winmgmt-TCP-In" -Value "v2.29|Action=Allow|Active=TRUE|Dir=In|Protocol=6|LPort=RPC|App=%systemroot%\\system32\\svchost.exe|Svc=Winmgmt|Name=File Server Remote Management (WMI-In)|Desc=Inbound rule to allow WMI traffic to manage the File Services role.|EmbedCtxt=File Server Remote Management|" -Type String
				RegKey -Path "HKLM:\WIM_HKLM_SYSTEM\ControlSet001\Services\SharedAccess\Parameters\FirewallPolicy\FirewallRules" -Name "FileServer-ServerManager-DCOM-TCP-In" -Value "v2.29|Action=Allow|Active=TRUE|Dir=In|Protocol=6|LPort=135|App=%systemroot%\\system32\\svchost.exe|Svc=RPCSS|Name=File Server Remote Management (DCOM-In)|Desc=Inbound rule to allow DCOM traffic to manage the File Services role.|EmbedCtxt=File Server Remote Management|" -Type String
				RegKey -Path "HKLM:\WIM_HKLM_SYSTEM\ControlSet001\Services\SharedAccess\Parameters\FirewallPolicy\FirewallRules" -Name "FileServer-ServerManager-SMB-TCP-In" -Value "v2.29|Action=Allow|Active=TRUE|Dir=In|Protocol=6|LPort=445|App=System|Name=File Server Remote Management (SMB-In)|Desc=Inbound rule to allow SMB traffic to manage the File Services role.|EmbedCtxt=File Server Remote Management|" -Type String
				RegKey -Path "HKLM:\WIM_HKLM_SYSTEM\ControlSet001\Services\SharedAccess\Parameters\FirewallPolicy\FirewallRules" -Name "FileServer-ServerManager-Winmgmt-TCP-In" -Value "v2.29|Action=Allow|Active=TRUE|Dir=In|Protocol=6|LPort=RPC|App=%systemroot%\\system32\\svchost.exe|Svc=Winmgmt|Name=File Server Remote Management (WMI-In)|Desc=Inbound rule to allow WMI traffic to manage the File Services role.|EmbedCtxt=File Server Remote Management|" -Type String
				RegHives -Unload
			}
		}
		#endregion Data Deduplication Integration

		#region Microsoft DaRT 10 Integration
		If ($DaRT -and (Test-Path -Path $OptimizeOffline.DaRT -Filter MSDaRT10_*.wim))
		{
			$CodeName = Switch ($InstallInfo.Build)
			{
				17134 { 'RS4'; Break }
				17763 { 'RS5'; Break }
				18362 { '19H2'; Break }
				19041 { '20H1'; Break }
			}
			If ($DaRT.Contains('Setup') -and $DynamicParams.BootImage)
			{
				Try
				{
					$ExpandDaRTBootParams = @{
						ImagePath        = '{0}\MSDaRT10_{1}.wim' -f $OptimizeOffline.DaRT, $CodeName
						Index            = 1
						ApplyPath        = $BootMount
						CheckIntegrity   = $true
						Verify           = $true
						ScratchDirectory = $ScratchFolder
						LogPath          = $DISMLog
						LogLevel         = 1
						ErrorAction      = 'Stop'
					}
					Log ($OptimizeData.IntegratingDaRT10 -f $CodeName, $BootInfo.Name)
					[Void](Expand-WindowsImage @ExpandDaRTBootParams)
				}
				Catch
				{
					Log $OptimizeData.FailedIntegratingDaRT10 -Type Error -ErrorRecord $Error[0]
					Stop-Optimize
				}
				If (!(Test-Path -Path (GetPath -Path $BootMount -Child 'Windows\System32\fmapi.dll'))) { Copy-Item -Path (GetPath -Path $InstallMount -Child 'Windows\System32\fmapi.dll') -Destination (GetPath -Path $BootMount -Child 'Windows\System32\fmapi.dll') -Force }
				@'
[LaunchApps]
%WINDIR%\System32\wpeinit.exe
%WINDIR%\System32\netstart.exe
%SYSTEMDRIVE%\setup.exe
'@ | Out-File -FilePath (GetPath -Path $BootMount -Child 'Windows\System32\winpeshl.ini') -Force
			}
			If ($DaRT.Contains('Recovery') -and $DynamicParams.RecoveryImage)
			{
				Try
				{
					$ExpandDaRTRecoveryParams = @{
						ImagePath        = '{0}\MSDaRT10_{1}.wim' -f $OptimizeOffline.DaRT, $CodeName
						Index            = 1
						ApplyPath        = $RecoveryMount
						CheckIntegrity   = $true
						Verify           = $true
						ScratchDirectory = $ScratchFolder
						LogPath          = $DISMLog
						LogLevel         = 1
						ErrorAction      = 'Stop'
					}
					Log ($OptimizeData.IntegratingDaRT10 -f $CodeName, $RecoveryInfo.Name)
					[Void](Expand-WindowsImage @ExpandDaRTRecoveryParams)
				}
				Catch
				{
					Log $OptimizeData.FailedIntegratingDaRT10 -Type Error -ErrorRecord $Error[0]
					Stop-Optimize
				}
				If (!(Test-Path -Path (GetPath -Path $RecoveryMount -Child 'Windows\System32\fmapi.dll'))) { Copy-Item -Path (GetPath -Path $InstallMount -Child 'Windows\System32\fmapi.dll') -Destination (GetPath -Path $RecoveryMount -Child 'Windows\System32\fmapi.dll') -Force }
				@'
[LaunchApps]
%WINDIR%\System32\wpeinit.exe
%WINDIR%\System32\netstart.exe
%SYSTEMDRIVE%\sources\recovery\recenv.exe
'@ | Out-File -FilePath (GetPath -Path $RecoveryMount -Child 'Windows\System32\winpeshl.ini') -Force
			}
			Start-Sleep 3; Clear-Host
		}
		#endregion Microsoft DaRT 10 Integration

		#region Apply Optimized Registry Settings
		If ($Registry.IsPresent)
		{
			If (Test-Path -Path (GetPath -Path $OptimizeOffline.Resources -Child "Public\$($OptimizeOffline.Culture)\Set-RegistryProperties.strings.psd1"))
			{
				Set-RegistryProperties
			}
			Else
			{
				Log ($OptimizeData.MissingRequiredRegistryData -f (GetPath -Path (GetPath -Path $OptimizeOffline.Resources -Child "Public\$($OptimizeOffline.Culture)\Set-RegistryProperties.strings.psd1") -Split Leaf)) -Type Error
				Start-Sleep 3
			}
		}
		#endregion Apply Optimized Registry Settings

		#region Additional Content Integration
		If ($Additional.ContainsValue($true))
		{
			If ($Additional.Setup -and (Test-Path -Path (GetPath -Path $OptimizeOffline.Setup -Child *)))
			{
				Try
				{
					Log $OptimizeData.ApplyingSetupContent
					(GetPath -Path $InstallMount -Child 'Windows\Setup\Scripts') | Create
					Get-ChildItem -Path $OptimizeOffline.Setup -Exclude RebootRecovery.png, RefreshExplorer.png, README.md | Copy-Item -Destination (GetPath -Path $InstallMount -Child 'Windows\Setup\Scripts') -Recurse -Force -ErrorAction Stop
				}
				Catch
				{
					Log $OptimizeData.FailedApplyingSetupContent -Type Error -ErrorRecord $Error[0]
					(GetPath -Path $InstallMount -Child 'Windows\Setup\Scripts') | Purge
				}
				Finally
				{
					Start-Sleep 3
				}
			}
			If ($Additional.Wallpaper -and (Test-Path -Path (GetPath -Path $OptimizeOffline.Wallpaper -Child *)))
			{
				Try
				{
					Log $OptimizeData.ApplyingWallpaper
					Get-ChildItem -Path $OptimizeOffline.Wallpaper -Directory | Copy-Item -Destination (GetPath -Path $InstallMount -Child 'Windows\Web\Wallpaper') -Recurse -Force -ErrorAction Stop
					Get-ChildItem -Path (GetPath -Path $OptimizeOffline.Wallpaper -Child *) -Include *.jpg, *.png, *.bmp, *.gif -File | Copy-Item -Destination (GetPath -Path $InstallMount -Child 'Windows\Web\Wallpaper') -Force -ErrorAction Stop
				}
				Catch
				{
					Log $OptimizeData.FailedApplyingWallpaper -Type Error -ErrorRecord $Error[0]
				}
				Finally
				{
					Start-Sleep 3
				}
			}
			If ($Additional.SystemLogo -and (Test-Path -Path (GetPath -Path $OptimizeOffline.SystemLogo -Child *.bmp)))
			{
				Try
				{
					Log $OptimizeData.ApplyingSystemLogo
					(GetPath -Path $InstallMount -Child 'Windows\System32\oobe\info\logo') | Create
					Copy-Item -Path (GetPath -Path $OptimizeOffline.SystemLogo -Child *.bmp) -Destination (GetPath -Path $InstallMount -Child 'Windows\System32\oobe\info\logo') -Recurse -Force -ErrorAction Stop
				}
				Catch
				{
					Log $OptimizeData.FailedApplyingSystemLogo -Type Error -ErrorRecord $Error[0]
					(GetPath -Path $InstallMount -Child 'Windows\System32\oobe\info\logo') | Purge
				}
				Finally
				{
					Start-Sleep 3
				}
			}
			If ($Additional.LockScreen -and (Test-Path -Path (GetPath -Path $OptimizeOffline.LockScreen -Child *.jpg)))
			{
				Set-LockScreen
				Start-Sleep 3
			}
			If ($Additional.RegistryTemplates -and (Test-Path -Path (GetPath -Path $OptimizeOffline.RegistryTemplates -Child *.reg)))
			{
				Import-RegistryTemplates
				Start-Sleep 3
			}
			If ($Additional.LayoutModification -and (Test-Path -Path (GetPath -Path $OptimizeOffline.LayoutModification -Child *.xml)))
			{
				Try
				{
					Log $OptimizeData.ApplyingLayoutModification
					Copy-Item -Path (GetPath -Path $OptimizeOffline.LayoutModification -Child *.xml) -Destination (GetPath -Path $InstallMount -Child 'Users\Default\AppData\Local\Microsoft\Windows\Shell\LayoutModification.xml') -Force -ErrorAction Stop
					$DynamicParams.LayoutModification = $true
				}
				Catch
				{
					Log $OptimizeData.FailedApplyingLayoutModification -Type Error -ErrorRecord $Error[0]
				}
				Finally
				{
					Start-Sleep 3
				}
			}
			If ($Additional.Unattend -and (Test-Path -Path (GetPath -Path $OptimizeOffline.Unattend -Child unattend.xml)))
			{
				Try
				{
					$ApplyUnattendParams = @{
						UnattendPath     = '{0}\unattend.xml' -f $OptimizeOffline.Unattend
						Path             = $InstallMount
						ScratchDirectory = $ScratchFolder
						LogPath          = $DISMLog
						LogLevel         = 1
						ErrorAction      = 'Stop'
					}
					Log $OptimizeData.ApplyingAnswerFile
					[Void](Use-WindowsUnattend @ApplyUnattendParams)
					(GetPath -Path $InstallMount -Child 'Windows\Panther') | Create
					Copy-Item -Path (GetPath -Path $OptimizeOffline.Unattend -Child unattend.xml) -Destination (GetPath -Path $InstallMount -Child 'Windows\Panther') -Force
				}
				Catch
				{
					Log $OptimizeData.FailedApplyingAnswerFile -Type Error -ErrorRecord $Error[0]
					(GetPath -Path $InstallMount -Child 'Windows\Panther') | Purge
					Start-Sleep 3
				}
			}
			If ($Additional.Drivers)
			{
				Get-ChildItem -Path $OptimizeOffline.Drivers -Recurse -Force | ForEach-Object -Process { $PSItem.Attributes = 0x80 }
				If (Get-ChildItem -Path $OptimizeOffline.InstallDrivers -Include *.inf -Recurse -Force)
				{
					Try
					{
						$InstallDriverParams = @{
							Path             = $InstallMount
							Driver           = $OptimizeOffline.InstallDrivers
							Recurse          = $true
							ForceUnsigned    = $true
							ScratchDirectory = $ScratchFolder
							LogPath          = $DISMLog
							LogLevel         = 1
							ErrorAction      = 'Stop'
						}
						Log ($OptimizeData.InjectingDriverPackages -f $InstallInfo.Name)
						[Void](Add-WindowsDriver @InstallDriverParams)
						$DynamicParams.InstallImageDrivers = $true
					}
					Catch
					{
						Log ($OptimizeData.FailedInjectingDriverPackages -f $InstallInfo.Name) -Type Error -ErrorRecord $Error[0]
						Start-Sleep 3
					}
				}
				If ($DynamicParams.BootImage -and (Get-ChildItem -Path $OptimizeOffline.BootDrivers -Include *.inf -Recurse -Force))
				{
					Try
					{
						$BootDriverParams = @{
							Path             = $BootMount
							Driver           = $OptimizeOffline.BootDrivers
							Recurse          = $true
							ForceUnsigned    = $true
							ScratchDirectory = $ScratchFolder
							LogPath          = $DISMLog
							LogLevel         = 1
							ErrorAction      = 'Stop'
						}
						Log ($OptimizeData.InjectingDriverPackages -f $BootInfo.Name)
						[Void](Add-WindowsDriver @BootDriverParams)
						$DynamicParams.BootImageDrivers = $true
					}
					Catch
					{
						Log ($OptimizeData.FailedInjectingDriverPackages -f $BootInfo.Name) -Type Error -ErrorRecord $Error[0]
						Start-Sleep 3
					}
				}
				If ($DynamicParams.RecoveryImage -and (Get-ChildItem -Path $OptimizeOffline.RecoveryDrivers -Include *.inf -Recurse -Force))
				{
					Try
					{
						$RecoveryDriverParams = @{
							Path             = $RecoveryMount
							Driver           = $OptimizeOffline.RecoveryDrivers
							Recurse          = $true
							ForceUnsigned    = $true
							ScratchDirectory = $ScratchFolder
							LogPath          = $DISMLog
							LogLevel         = 1
							ErrorAction      = 'Stop'
						}
						Log ($OptimizeData.InjectingDriverPackages -f $RecoveryInfo.Name)
						[Void](Add-WindowsDriver @RecoveryDriverParams)
						$DynamicParams.RecoveryImageDrivers = $true
					}
					Catch
					{
						Log ($OptimizeData.FailedInjectingDriverPackages -f $RecoveryInfo.Name) -Type Error -ErrorRecord $Error[0]
						Start-Sleep 3
					}
				}
			}
			If ($Additional.NetFx3 -and (Get-ChildItem -Path (GetPath -Path $ISOMedia.FullName -Child 'sources\sxs') -Filter *netfx3*.cab) -and (Get-WindowsOptionalFeature -Path $InstallMount -FeatureName NetFx3 -ScratchDirectory $ScratchFolder -LogPath $DISMLog -LogLevel 1 | Where-Object -Property State -EQ DisabledWithPayloadRemoved))
			{
				Try
				{
					$EnableNetFx3Params = @{
						Path             = $InstallMount
						FeatureName      = 'NetFx3'
						Source           = '{0}\sources\sxs' -f $ISOMedia.FullName
						All              = $true
						LimitAccess      = $true
						NoRestart        = $true
						ScratchDirectory = $ScratchFolder
						LogPath          = $DISMLog
						LogLevel         = 1
						ErrorAction      = 'Stop'
					}
					Log $OptimizeData.EnablingNetFx3
					[Void](Enable-WindowsOptionalFeature @EnableNetFx3Params)
					$DynamicParams.NetFx3 = $true
				}
				Catch
				{
					Log $OptimizeData.FailedEnablingNetFx3 -Type Error -ErrorRecord $Error[0]
					Start-Sleep 3
				}
			}
		}
		#endregion Additional Content Integration

		#region Start Menu Clean-up
		If (!$DynamicParams.LayoutModification)
		{
			$LayoutTemplate = @"
<LayoutModificationTemplate xmlns:defaultlayout="http://schemas.microsoft.com/Start/2014/FullDefaultLayout"
    xmlns:start="http://schemas.microsoft.com/Start/2014/StartLayout" Version="1"
    xmlns:taskbar="http://schemas.microsoft.com/Start/2014/TaskbarLayout"
    xmlns="http://schemas.microsoft.com/Start/2014/LayoutModification">
    <LayoutOptions StartTileGroupsColumnCount="2" StartTileGroupCellWidth="6" FullScreenStart="false" />
    <DefaultLayoutOverride>
        <StartLayoutCollection>
            <defaultlayout:StartLayout GroupCellWidth="6">
                <start:Group Name="$($InstallInfo.Name)">
                    <start:DesktopApplicationTile Size="2x2" Column="0" Row="0" DesktopApplicationID="Microsoft.Windows.Computer" />
                    <start:DesktopApplicationTile Size="2x2" Column="2" Row="0" DesktopApplicationLinkPath="%APPDATA%\Microsoft\Windows\Start Menu\Programs\System Tools\Master Control Panel.lnk" />
                    <start:DesktopApplicationTile Size="1x1" Column="4" Row="0" DesktopApplicationLinkPath="%APPDATA%\Microsoft\Windows\Start Menu\Programs\Windows PowerShell\Windows PowerShell.lnk" />
                    <start:DesktopApplicationTile Size="1x1" Column="4" Row="1" DesktopApplicationID="Microsoft.Windows.AdministrativeTools" />
                    <start:DesktopApplicationTile Size="1x1" Column="5" Row="0" DesktopApplicationLinkPath="%APPDATA%\Microsoft\Windows\Start Menu\Programs\System Tools\UWP File Explorer.lnk" />
                    <start:DesktopApplicationTile Size="1x1" Column="5" Row="1" DesktopApplicationID="Microsoft.Windows.Shell.RunDialog" />
                </start:Group>
            </defaultlayout:StartLayout>
        </StartLayoutCollection>
    </DefaultLayoutOverride>
    <CustomTaskbarLayoutCollection PinListPlacement="Replace">
        <defaultlayout:TaskbarLayout>
            <taskbar:TaskbarPinList>
                <taskbar:DesktopApp DesktopApplicationLinkPath="#leaveempty"/>
            </taskbar:TaskbarPinList>
        </defaultlayout:TaskbarLayout>
    </CustomTaskbarLayoutCollection>
</LayoutModificationTemplate>
"@
			Try
			{
				Log $OptimizeData.CleanupStartMenu
				$MCPShell = New-Object -ComObject WScript.Shell -ErrorAction Stop
				$MCPShortcut = $MCPShell.CreateShortcut((GetPath -Path $InstallMount -Child 'Users\Default\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\System Tools\Master Control Panel.lnk'))
				$MCPShortcut.TargetPath = "%SystemRoot%\explorer.exe"
				$MCPShortcut.Arguments = "shell:::{ED7BA470-8E54-465E-825C-99712043E01C}"
				$MCPShortcut.WorkingDirectory = "%SystemRoot%"
				$MCPShortcut.Description = "Windows Control Panel All Tasks."
				$MCPShortcut.IconLocation = "%SystemRoot%\System32\imageres.dll,-27"
				$MCPShortcut.Save()
			}
			Catch
			{
				$LayoutTemplate = $LayoutTemplate.Replace('Master Control Panel.lnk', 'Control Panel.lnk')
			}
			Finally
			{
				[Void][Runtime.InteropServices.Marshal]::ReleaseComObject($MCPShell)
			}
			If ($RemovedSystemApps.'Microsoft.Windows.FileExplorer') { $LayoutTemplate = $LayoutTemplate.Replace('UWP File Explorer.lnk', 'File Explorer.lnk') }
			Else
			{
				Try
				{
					$UWPShell = New-Object -ComObject WScript.Shell -ErrorAction Stop
					$UWPShortcut = $UWPShell.CreateShortcut((GetPath -Path $InstallMount -Child 'Users\Default\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\System Tools\UWP File Explorer.lnk'))
					$UWPShortcut.TargetPath = "%SystemRoot%\explorer.exe"
					$UWPShortcut.Arguments = "shell:AppsFolder\c5e2524a-ea46-4f67-841f-6a9465d9d515_cw5n1h2txyewy!App"
					$UWPShortcut.WorkingDirectory = "%SystemRoot%"
					$UWPShortcut.Description = "UWP File Explorer"
					$UWPShortcut.Save()
				}
				Catch
				{
					$LayoutTemplate = $LayoutTemplate.Replace('UWP File Explorer.lnk', 'File Explorer.lnk')
				}
				Finally
				{
					[Void][Runtime.InteropServices.Marshal]::ReleaseComObject($UWPShell)
				}
			}
			Try
			{
				$LayoutTemplate | Out-File -FilePath (GetPath -Path $InstallMount -Child 'Users\Default\AppData\Local\Microsoft\Windows\Shell\LayoutModification.xml') -Encoding UTF8 -Force -ErrorAction Stop
			}
			Catch
			{
				Log $OptimizeData.FailedCleanupStartMenu -Type Error
			}
			Finally
			{
				Start-Sleep 3; Clear-Host
			}
		}
		#endregion Start Menu Clean-up

		#region Create Package Summary
		@('DeveloperMode', 'WindowsStore', 'MicrosoftEdge', 'MicrosoftEdgeChromium', 'DataDeduplication', 'InstallImageDrivers', 'BootImageDrivers', 'RecoveryImageDrivers', 'NetFx3') | ForEach-Object -Process { If ($DynamicParams.ContainsKey($PSItem)) { $DynamicParams.PackageSummary = $true } }
		If ($DynamicParams.PackageSummary)
		{
			Log $OptimizeData.CreatingPackageSummaryLog
			$PackageLog = New-Item -Path $LogFolder -Name PackageSummary.log -ItemType File -Force
			If ($DynamicParams.WindowsStore) { "`t`t`t`tIntegrated Provisioned App Packages", (Get-AppxProvisionedPackage -Path $InstallMount -ScratchDirectory $ScratchFolder -LogPath $DISMLog -LogLevel 1 | Select-Object -Property PackageName) | Out-File -FilePath $PackageLog.FullName -Append -Encoding UTF8 -Force }
			If ($DynamicParams.DeveloperMode -or $DynamicParams.MicrosoftEdge -or $DynamicParams.MicrosoftEdgeChromium -or $DynamicParams.DataDeduplication -or $DynamicParams.NetFx3) { "`t`t`t`tIntegrated Windows Packages", (Get-WindowsPackage -Path $InstallMount -ScratchDirectory $ScratchFolder -LogPath $DISMLog -LogLevel 1 | Where-Object { $PSItem.PackageName -like "*DeveloperMode*" -or $PSItem.PackageName -like "*Internet-Browser*" -or $PSItem.PackageName -like "*KB4559309*" -or $PSItem.PackageName -like "*KB4584229*" -or $PSItem.PackageName -like "*Windows-FileServer-ServerCore*" -or $PSItem.PackageName -like "*Windows-Dedup*" -or $PSItem.PackageName -like "*NetFx3*" } | Select-Object -Property PackageName, PackageState) | Out-File -FilePath $PackageLog.FullName -Append -Encoding UTF8 -Force }
			If ($DynamicParams.InstallImageDrivers) { "`t`t`t`tIntegrated Drivers (Install)", (Get-WindowsDriver -Path $InstallMount -ScratchDirectory $ScratchFolder -LogPath $DISMLog -LogLevel 1 | Select-Object -Property ProviderName, ClassName, Version, BootCritical | Sort-Object -Property ProviderName | Format-Table -AutoSize) | Out-File -FilePath $PackageLog.FullName -Append -Encoding UTF8 -Force }
			If ($DynamicParams.BootImageDrivers) { "`t`t`t`tIntegrated Drivers (Boot)", (Get-WindowsDriver -Path $BootMount -ScratchDirectory $ScratchFolder -LogPath $DISMLog -LogLevel 1 | Select-Object -Property ProviderName, ClassName, Version, BootCritical | Sort-Object -Property ProviderName | Format-Table -AutoSize) | Out-File -FilePath $PackageLog.FullName -Append -Encoding UTF8 -Force }
			If ($DynamicParams.RecoveryImageDrivers) { "`t`t`t`tIntegrated Drivers (Recovery)", (Get-WindowsDriver -Path $RecoveryMount -ScratchDirectory $ScratchFolder -LogPath $DISMLog -LogLevel 1 | Select-Object -Property ProviderName, ClassName, Version, BootCritical | Sort-Object -Property ProviderName | Format-Table -AutoSize) | Out-File -FilePath $PackageLog.FullName -Append -Encoding UTF8 -Force }
		}
		#endregion Create Package Summary

		#region Image Finalization
		If ((Repair-WindowsImage -Path $InstallMount -CheckHealth -ScratchDirectory $ScratchFolder -LogPath $DISMLog -LogLevel 1).ImageHealthState -eq 'Healthy')
		{
			Log $OptimizeData.PostOptimizedImageHealthHealthy
			@"
This $($InstallInfo.Name) installation was optimized with $($OptimizeOffline.BaseName) version $($ManifestData.ModuleVersion)
on $(Get-Date -UFormat "%m/%d/%Y at %r")
"@ | Out-File -FilePath (GetPath -Path $InstallMount -Child Optimize-Offline.txt) -Encoding Unicode -Force
			Start-Sleep 3
		}
		Else
		{
			Log $OptimizeData.PostOptimizedImageHealthCorrupted -Type Error
			Stop-Optimize
		}

		If ($DynamicParams.BootImage)
		{
			Try
			{
				Invoke-Cleanup Boot
				$DismountBootParams = @{
					Path             = $BootMount
					Save             = $true
					CheckIntegrity   = $true
					ScratchDirectory = $ScratchFolder
					LogPath          = $DISMLog
					LogLevel         = 1
					ErrorAction      = 'Stop'
				}
				Log ($OptimizeData.SavingDismountingImage -f $BootInfo.Name)
				[Void](Dismount-WindowsImage @DismountBootParams)
			}
			Catch
			{
				Log ($OptimizeData.FailedSavingDismountingImage -f $BootInfo.Name) -Type Error -ErrorRecord $Error[0]
				Stop-Optimize
			}
			Try
			{
				Log ($OptimizeData.RebuildingExportingImage -f $BootInfo.Name)
				Get-WindowsImage -ImagePath $BootWim | ForEach-Object -Process {
					$ExportBootParams = @{
						SourceImagePath      = $BootWim
						SourceIndex          = $PSItem.ImageIndex
						DestinationImagePath = '{0}\boot.wim' -f $WorkFolder
						CheckIntegrity       = $true
						ScratchDirectory     = $ScratchFolder
						LogPath              = $DISMLog
						LogLevel             = 1
						ErrorAction          = 'Stop'
					}
					[Void](Export-WindowsImage @ExportBootParams)
				}
			}
			Catch
			{
				Log ($OptimizeData.FailedRebuildingExportingImage -f $BootInfo.Name) -Type Error -ErrorRecord $Error[0]
				Start-Sleep 3
			}
		}

		If ($DynamicParams.RecoveryImage)
		{
			Try
			{
				Invoke-Cleanup Recovery
				$DismountRecoveryParams = @{
					Path             = $RecoveryMount
					Save             = $true
					CheckIntegrity   = $true
					ScratchDirectory = $ScratchFolder
					LogPath          = $DISMLog
					LogLevel         = 1
					ErrorAction      = 'Stop'
				}
				Log ($OptimizeData.SavingDismountingImage -f $RecoveryInfo.Name)
				[Void](Dismount-WindowsImage @DismountRecoveryParams)
			}
			Catch
			{
				Log ($OptimizeData.FailedSavingDismountingImage -f $RecoveryInfo.Name) -Type Error -ErrorRecord $Error[0]
				Stop-Optimize
			}
			Try
			{
				$ExportRecoveryParams = @{
					SourceImagePath      = $RecoveryWim
					SourceIndex          = 1
					DestinationImagePath = '{0}\winre.wim' -f $WorkFolder
					CheckIntegrity       = $true
					ScratchDirectory     = $ScratchFolder
					LogPath              = $DISMLog
					LogLevel             = 1
					ErrorAction          = 'Stop'
				}
				Log ($OptimizeData.RebuildingExportingImage -f $RecoveryInfo.Name)
				[Void](Export-WindowsImage @ExportRecoveryParams)
			}
			Catch
			{
				Log ($OptimizeData.FailedRebuildingExportingImage -f $RecoveryInfo.Name) -Type Error -ErrorRecord $Error[0]
				Start-Sleep 3
			}
		}

		If (Get-ChildItem -Path $WorkFolder -Filter boot.wim) { Get-ChildItem -Path $WorkFolder -Filter boot.wim | Move-Item -Destination $BootWim -Force }
		If (Get-ChildItem -Path $WorkFolder -Filter winre.wim)
		{
			$WinREPath = Get-ChildItem -Path $WorkFolder -Filter winre.wim | Move-Item -Destination $WinREPath -Force -PassThru
			(Get-Item -Path $WinREPath -Force).Attributes = 0x2006
		}

		Try
		{
			Invoke-Cleanup Install
			$DismountInstallParams = @{
				Path             = $InstallMount
				Save             = $true
				CheckIntegrity   = $true
				ScratchDirectory = $ScratchFolder
				LogPath          = $DISMLog
				LogLevel         = 1
				ErrorAction      = 'Stop'
			}
			Log ($OptimizeData.SavingDismountingImage -f $InstallInfo.Name)
			[Void](Dismount-WindowsImage @DismountInstallParams)
		}
		Catch
		{
			Log ($OptimizeData.FailedSavingDismountingImage -f $InstallInfo.Name) -Type Error -ErrorRecord $Error[0]
			Stop-Optimize
		}

		Try
		{
			$CompressionType = Get-CompressionType -ErrorAction Stop
		}
		Catch
		{
			Do
			{
				$CompressionType = @('Solid', 'Maximum', 'Fast', 'None') | Select-Object -Property @{ Label = 'Compression'; Expression = { ($PSItem) } } | Out-GridView -Title "Select Final Image Compression." -OutputMode Single | Select-Object -ExpandProperty Compression
			}
			While ($CompressionType.Length -eq 0)
		}

		Try
		{
			Log ($OptimizeData.RebuildingExportingCompressed -f $InstallInfo.Name, $CompressionType)
			Switch ($CompressionType)
			{
				'Solid'
				{
					$SolidImage = Compress-Solid -ErrorAction Stop
					If ($SolidImage.Exists)
					{
						$InstallWim | Purge
						If ($DynamicParams.BootImage) { $ImageFiles = @('install.esd', 'boot.wim') }
						Else { $ImageFiles = 'install.esd' }
					}
					Else
					{
						If ($DynamicParams.BootImage) { $ImageFiles = @('install.wim', 'boot.wim') }
						Else { $ImageFiles = 'install.wim' }
						Throw
					}
					Break
				}
				Default
				{
					$ExportInstallParams = @{
						SourceImagePath      = $InstallWim
						SourceIndex          = $ImageIndex
						DestinationImagePath = '{0}\install.wim' -f $WorkFolder
						CompressionType      = $CompressionType
						CheckIntegrity       = $true
						ScratchDirectory     = $ScratchFolder
						LogPath              = $DISMLog
						LogLevel             = 1
						ErrorAction          = 'Stop'
					}
					[Void](Export-WindowsImage @ExportInstallParams)
					If ($DynamicParams.BootImage) { $ImageFiles = @('install.wim', 'boot.wim') }
					Else { $ImageFiles = 'install.wim' }
					Break
				}
			}
		}
		Catch
		{
			Log ($OptimizeData.FailedRebuildingExportingCompressed -f $InstallInfo.Name, $CompressionType) -Type Error -ErrorRecord $Error[0]
			Start-Sleep 3
		}
		Finally
		{
			[Void](Clear-WindowsCorruptMountPoint)
		}

		If (Get-ChildItem -Path $WorkFolder -Filter install.wim) { Get-ChildItem -Path $WorkFolder -Filter install.wim | Move-Item -Destination $InstallWim -Force }

		If (Get-ChildItem -Path $WorkFolder -Include InstallInfo.xml, CurrentVersion.xml -Recurse -File)
		{
			Try
			{
				$InstallInfo = Get-ImageData -Update -ErrorAction Stop
			}
			Catch
			{
				Log ($OptimizeData.FailedToUpdateImageMetadata -f (GetPath -Path $InstallWim -Split Leaf)) -Type Error -ErrorRecord $Error[0]
				Start-Sleep 3
			}
		}
		Else
		{
			Log ($OptimizeData.MissingRequiredDataFiles -f (GetPath -Path $InstallWim -Split Leaf)) -Type Error
			Start-Sleep 3
		}

		If ($ISOMedia.Exists)
		{
			Log $OptimizeData.OptimizingInstallMedia
			Optimize-InstallMedia
			Get-ChildItem -Path $ImageFolder -Include $ImageFiles -Recurse | Move-Item -Destination (GetPath -Path $ISOMedia.FullName -Child sources) -Force
			If ($ISO)
			{
				Try
				{
					Log ($OptimizeData.CreatingISO -f $ISO)
					$ISOFile = New-ISOMedia -BootType $ISO -ErrorAction Stop
				}
				Catch
				{
					Log ($OptimizeData.FailedCreatingISO -f $ISO) -Type Error -ErrorRecord $Error[0]
					Start-Sleep 3
				}
			}
		}

		Try
		{
			Log $OptimizeData.FinalizingOptimizations
			$SaveDirectory = Create -Path (GetPath -Path $OptimizeOffline.Directory -Child Optimize-Offline_$((Get-Date).ToString('yyyy-MM-ddThh.mm.ss'))) -PassThru
			If ($ISOFile) { Move-Item -Path $ISOFile -Destination $SaveDirectory.FullName }
			Else
			{
				If ($ISOMedia.Exists) { Move-Item -Path $ISOMedia.FullName -Destination $SaveDirectory.FullName }
				Else { Get-ChildItem -Path $ImageFolder -Include $ImageFiles -Recurse | Move-Item -Destination $SaveDirectory.FullName }
			}
		}
		Finally
		{
			$OptimizeTimer.Stop()
			Log ($OptimizeData.OptimizationsCompleted -f $OptimizeOffline.BaseName, [Math]::Round($OptimizeTimer.Elapsed.TotalMinutes, 0).ToString(), ($Global:Error.Count + $OptimizeErrors.Count)) -Finalized
			If ($Global:Error.Count -gt 0 -or $OptimizeErrors.Count -gt 0) { Export-ErrorLog }
			[Void](Get-ChildItem -Path $LogFolder -Include *.log -Exclude DISM.log -Recurse | Compress-Archive -DestinationPath (GetPath -Path $SaveDirectory.FullName -Child OptimizeLogs.zip) -CompressionLevel Fastest)
			($InstallInfo | Out-String).Trim() | Out-File -FilePath (GetPath -Path $SaveDirectory.FullName -Child WimFileInfo.xml) -Encoding UTF8
			@($TempDirectory, (GetPath -Path $Env:SystemRoot -Child 'Logs\DISM\dism.log')) | Purge -ErrorAction Ignore
		}
		#endregion Image Finalization
	}
	End
	{
		#region Post-Processing Block
		((Compare-Object -ReferenceObject (Get-Variable).Name -DifferenceObject $LocalScope.Variables).InputObject).ForEach{ Remove-Variable -Name $PSItem -ErrorAction Ignore }
		$ErrorActionPreference = $LocalScope.ErrorActionPreference
		$Global:ProgressPreference = $LocalScope.ProgressPreference
		$Global:Error.Clear()
		#endregion Post-Processing Block
	}
}
# SIG # Begin signature block
# MIIIDgYJKoZIhvcNAQcCoIIH/zCCB/sCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUXJK+Xcwr5UtDXk+8Ez5D9SK1
# 78qgggV7MIIFdzCCBF+gAwIBAgITGgAAABuiU/ojidF4nQAAAAAAGzANBgkqhkiG
# 9w0BAQsFADBFMRQwEgYKCZImiZPyLGQBGRYEVEVDSDEVMBMGCgmSJomT8ixkARkW
# BU9NTklDMRYwFAYDVQQDEw1PTU5JQy5URUNILUNBMB4XDTIwMDUxNjExNTAzOFoX
# DTIxMDUxNjExNTAzOFowUzEUMBIGCgmSJomT8ixkARkWBFRFQ0gxFTATBgoJkiaJ
# k/IsZAEZFgVPTU5JQzEOMAwGA1UEAxMFVXNlcnMxFDASBgNVBAMTC0JlblRoZUdy
# ZWF0MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAllg+PmYSHbLuBPbI
# uHgIAhNky4d9dENqbHAO2W25Tsn4wPz/g7CLHK+kaVq8LwIj6pC9zwdlXs6zWcU5
# 4xCmNwKhEs75WLeMA3KuV3B07SEULRloQuzlhzzbRulvAeQRHOPKzj+qtgmLY69U
# 8o/FsSYG5ZehaCDXF+0N7tC/IWuJViaQnxNBISRlOo+2iUIHk5E9bTwFBOySBHiz
# HYFKtcm7viRaH4izBL5zBPZZwrwA9iQDVU/Nld5EMyWouDkPybtGIuVLj/6PWEdN
# OHw1QcYFlmb+7AE5DyPkouR6VMrMwloVRCMdGyMsuoxO89C925GJXxggpgmlS+sW
# 9koCWQIDAQABo4ICUDCCAkwwJQYJKwYBBAGCNxQCBBgeFgBDAG8AZABlAFMAaQBn
# AG4AaQBuAGcwEwYDVR0lBAwwCgYIKwYBBQUHAwMwDgYDVR0PAQH/BAQDAgeAMDEG
# A1UdEQQqMCigJgYKKwYBBAGCNxQCA6AYDBZCZW5UaGVHcmVhdEBPTU5JQy5URUNI
# MB0GA1UdDgQWBBSobni9ugG9hTy2Dmdb/GDEwJJpxTAfBgNVHSMEGDAWgBRs5nLk
# 5cGEWCwNRP1xmRx6dvhqkzCByQYDVR0fBIHBMIG+MIG7oIG4oIG1hoGybGRhcDov
# Ly9DTj1PTU5JQy5URUNILUNBLENOPUFOVUJJUyxDTj1DRFAsQ049UHVibGljJTIw
# S2V5JTIwU2VydmljZXMsQ049U2VydmljZXMsQ049Q29uZmlndXJhdGlvbixEQz1P
# TU5JQyxEQz1URUNIP2NlcnRpZmljYXRlUmV2b2NhdGlvbkxpc3Q/YmFzZT9vYmpl
# Y3RDbGFzcz1jUkxEaXN0cmlidXRpb25Qb2ludDCBvgYIKwYBBQUHAQEEgbEwga4w
# gasGCCsGAQUFBzAChoGebGRhcDovLy9DTj1PTU5JQy5URUNILUNBLENOPUFJQSxD
# Tj1QdWJsaWMlMjBLZXklMjBTZXJ2aWNlcyxDTj1TZXJ2aWNlcyxDTj1Db25maWd1
# cmF0aW9uLERDPU9NTklDLERDPVRFQ0g/Y0FDZXJ0aWZpY2F0ZT9iYXNlP29iamVj
# dENsYXNzPWNlcnRpZmljYXRpb25BdXRob3JpdHkwDQYJKoZIhvcNAQELBQADggEB
# AHkE5DhgUC3lTaRW9IO5XDjndfLppttn4C6YgU/XKYqFryxIIhVcPjNSbjDhqIXP
# +HyurG56f/0DgnOwj2x0ijVXYxpW1IOW6ni1NGbq22WJF1Zbsl6XYkBV0Uwi9nDN
# kXTf0lDebn0fTujWTuSQTUi5QB/w12X6yQUd7H/S51ycsnYRZpnzNnVmTJPJAmPS
# ERpemwj9gZkiibbdm9vAO5p9UesX9iqwSyrhsfwS1rmW4tUWqYqHhZIpQjF1CCV3
# +u6H/f9XXGtwDl4OKFYOiXUqHx7U7+AYwRd51uQgtKocNa0d7pD93bLGrPlkmMsI
# 8xKcO909nyejvk01H5obHCcxggH9MIIB+QIBATBcMEUxFDASBgoJkiaJk/IsZAEZ
# FgRURUNIMRUwEwYKCZImiZPyLGQBGRYFT01OSUMxFjAUBgNVBAMTDU9NTklDLlRF
# Q0gtQ0ECExoAAAAbolP6I4nReJ0AAAAAABswCQYFKw4DAhoFAKB4MBgGCisGAQQB
# gjcCAQwxCjAIoAKAAKECgAAwGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwHAYK
# KwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwIwYJKoZIhvcNAQkEMRYEFKYVouxw
# ROcemuXdhHQ72oMUK9+mMA0GCSqGSIb3DQEBAQUABIIBABkIobqUV7ps8HxLXRaY
# eyYfJd2CtdHRr/NGFIuUbgv71Ptrpp93k1sfQA4fkpFB0EETYKHGQMESS5rtShBE
# Jwo2wDYwHr4KS3QoZCPW+B9Kp9jmTY/o3j738US8MHcZYue0+HtTTS6wotkENSsO
# IFGw8Yqy7UehPz0tSV4w1Ut2vbIAnek7M+RIgOr7nKOkhJKVRVE148hKAqf27+8B
# E20kUO5ENrwAbc9g3FJskf3JUHYgW+AJ3wRJkyqVxq3YY7saq0vcWNy0mFR7krGy
# ZJxcbvILN0jSivUZpBWFVYdkd4FzOFtm6OFE3whzMFAQpo8+A1qm7xjpvwjcrrgp
# MjY=
# SIG # End signature block
