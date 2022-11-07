<#
.SYNOPSIS
    Finds all FSlogix folders in specified directory and cross checks 
    if the user is disabled, exists and/or is inactive. Based on specified 
    parameters, will then remove the stale containers from the directory.

.DESCRIPTION
    Will automatically clean up stale FSLogix container folders based on 
    the specified criteria.

.PARAMETER *
    Parameters are available as specified in the param block below.

.NOTES
    Version:        1.1
    Author:         Tom Schoen
    Creation Date:  01-11-2022
    Purpose/Change: Initial script development
  
.EXAMPLE
    Remove all containers for disabled, removed/non-existent and inactive users but exclude folders "folder1" and "folder2" from location "F:\" and output logs to "C:\temp".
    .\script.ps1 -ContainerPath "F:\" -DeleteDisabled -DeleteRemoved -DeleteInactive -ExcludeFolders @("folder1","folder2") -LogPath "C:\temp"

.EXAMPLE
    Remove all containers for disabled users from Azure Files share "\\mystorageaccount.file.core.windows.net\share" and don't ask for confirmation.
    .\script.ps1 -ContainerPath "\\mystorageaccount.file.core.windows.net\share" -DeleteDisabled -Confirm

.EXAMPLE
    Dry run for removal of all containers for users that have not logged in for 30 days from Azure Files share "\\mystorageaccount.file.core.windows.net\share".
    .\script.ps1 -ContainerPath "\\mystorageaccount.file.core.windows.net\share" -DeleteInactive -InactiveDays 30 -WhatIf
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory, HelpMessage = "The full (UNC) path to the FSLogix container directory.")]
    [string]
    $ContainerPath,

    [Parameter(HelpMessage = "The full (UNC) path to output the log file to.")]
    $LogPath = $False,

    [Parameter(HelpMessage = "The name to prepend to the log file.")]
    [string]
    $LogName = "FSLogixCleanUp",

    [Parameter(HelpMessage = "If set, enables dry-run mode.")]
    [switch]
    $WhatIf,

    [Parameter(HelpMessage = "Array of strings with folder names to exclude in recursion.")]
    [string[]]
    $ExcludeFolders,

    [Parameter(HelpMessage = "Number of days a user must have not logged into Active Directory to be considered inactive.")]
    [int]
    $InactiveDays = 90,

    [Parameter(HelpMessage = "If set, containers belonging to disabled users will be deleted.")]
    [switch]
    $DeleteDisabled,

    [Parameter(HelpMessage = "If set, containers belonging to removed/non-existing users will be deleted.")]
    [switch]
    $DeleteRemoved,

    [Parameter(HelpMessage = "If set, containers belonging to inactive users will be deleted.")]
    [switch]
    $DeleteInactive,

    [Parameter(HelpMessage = "If set, don't ask for confirmation before execution.")]
    [switch]
    $Confirm,

    [Parameter(HelpMessage = "if set, don't use the FlipFlop name convention (%username%_%sid%) but use the default (%sid%_%username%)")]
    [switch]
    $NoFlipFlop
)

function Write-Log {
    param (
        [Parameter(Mandatory)]
        [string]
        $LogMessage,

        [string]
        $LogLevel,

        $LogPath,

        [string]
        $LogName = "ScriptLog",

        [string]
        $LogHeader,

        [switch]
        $NoDate
    )
    
    if ($NoDate) {
        $Message = "[$LogLevel] $LogMessage"
    }
    else {
        $Message = "$(Get-Date -Format "u") [$LogLevel] $LogMessage"
    }

    if ($LogPath) {
        $File = (Join-Path -Path $LogPath -ChildPath "$LogName.log")
        if (-not (Test-Path $File)) {
            Add-Content -Path $File -Value ""
        }
        Add-content -Path $File -Value $Message
    }
    
    Write-Output $Message

}

[decimal]$SpaceDisabled = 0
[decimal]$SpaceRemoved = 0
[decimal]$SpaceInactive = 0
[int]$ContainerCount = 0
$LogName = "$LogName`_$(Get-Date -Format "yyyyMMdd_HHmmss")"

Write-Log -LogPath $LogPath -LogName $LogName -LogMessage "========================================" -LogLevel "Info"
Write-Log -LogPath $LogPath -LogName $LogName -LogMessage "Starting execution" -LogLevel "Info"
Write-Log -LogPath $LogPath -LogName $LogName -LogMessage "Container Path:       $ContainerPath" -LogLevel "Info"
Write-Log -LogPath $LogPath -LogName $LogName -LogMessage "Excluded folders:     $ExcludeFolders" -LogLevel "Info"
Write-Log -LogPath $LogPath -LogName $LogName -LogMessage "Deletion options" -LogLevel "Info"
Write-Log -LogPath $LogPath -LogName $LogName -LogMessage "Removed Users:        $DeleteRemoved" -LogLevel "Info"
Write-Log -LogPath $LogPath -LogName $LogName -LogMessage "Disabled Users:       $DeleteDisabled" -LogLevel "Info"
Write-Log -LogPath $LogPath -LogName $LogName -LogMessage "Inactive Users:       $DeleteInactive ($InactiveDays days)" -LogLevel "Info"
Write-Log -LogPath $LogPath -LogName $LogName -LogMessage "========================================" -LogLevel "Info"

if (-not (Test-Path -Path $ContainerPath)) {
    Write-Log -LogPath $LogPath -LogName $LogName -LogMessage "Container Path not accessible or does not exist." -LogLevel "Error"
    Exit
}

if ($True -eq $WhatIf) {
    Write-Log -LogPath $LogPath -LogName $LogName -LogMessage "Executing with WhatIf switch set. No changes will be made." -LogLevel "Info"
}
elseif ($False -eq $Confirm) {
    Write-Log -LogPath $LogPath -LogName $LogName -LogMessage "Executing without WhatIf switch set. Specified containers will be deleted." -LogLevel "Info"
    
    $ConfirmTitle = 'Confirm execution'
    $ConfirmQuestion = 'Do you want to continue?'
    $ConfirmChoices = '&Yes', '&No'

    $ConfirmDecision = $Host.UI.PromptForChoice($ConfirmTitle, $ConfirmQuestion, $ConfirmChoices, 1)
    if ($ConfirmDecision -eq 1) {
        Write-Log -LogPath $LogPath -LogName $LogName -LogMessage "Execution stopped by user." -LogLevel "Info"
        Exit
    }
}

$ContainerDirs = Get-ChildItem -Path $ContainerPath -Directory -Exclude $ExcludeFolders

foreach ($ContainerDir in $ContainerDirs) {
    $ContainerCount++

    if ($True -eq $NoFlipFlop) {
        $UserName = $ContainerDir.Name.Substring($ContainerDir.Name.IndexOf('_') + 1)
    }
    else {
        $UserName = $ContainerDir.Name.Substring(0, $ContainerDir.Name.IndexOf('_S-1-5'))
    }

    $ContainerDir = Join-Path $ContainerPath $ContainerDir
    try { 
        $ADUser = Get-ADUser -Identity $UserName -Properties sAMAccountName, Enabled, lastLogon, lastLogonDate
    }
    catch [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException] {
        $ADUser = $False
    }

    $ContainerSize = (Get-ChildItem -Path $ContainerDir | Measure-Object Length -Sum).Sum / 1Gb
    Write-Log -LogPath $LogPath -LogName $LogName -LogMessage ("Processing $UserName ({0:N2} GB)." -f $ContainerSize) -LogLevel "Info"

    if ($False -eq $ADUser -and $True -eq $DeleteRemoved) {
        Write-Log -LogPath $LogPath -LogName $LogName -LogMessage "Account for $UserName does not exist." -LogLevel "Info"

        if ($True -eq $WhatIf) {
            Write-Log -LogPath $LogPath -LogName $LogName -LogMessage "Deleting container for $UserName based on removed/non-existent state of account." -LogLevel "Info"
            
            try {
                Remove-Item -Path $ContainerDir -Recurse -Force -ErrorAction Stop
            }
            catch {
                Write-Log -LogPath $LogPath -LogName $LogName -LogMessage "Could not delete container for $UserName`: $($_)." -LogLevel "Warning"
                Continue
            }

            $SpaceRemoved = $SpaceRemoved + $ContainerSize
        }
        else {
            Write-Log -LogPath $LogPath -LogName $LogName -LogMessage "WhatIf: Deleting container for $UserName based on removed/non-existent state of account." -LogLevel "Info"
            $SpaceRemoved = $SpaceRemoved + $ContainerSize
        }
        Write-Log -LogPath $LogPath -LogName $LogName -LogMessage "Container deleted for $UserName."  -LogLevel "Success"
        Continue
    }

    if ($False -eq $ADUser.Enabled -and $True -eq $DeleteDisabled) {
        Write-Log -LogPath $LogPath -LogName $LogName -LogMessage "Account for $UserName is disabled." -LogLevel "Info"

        if ($True -eq $WhatIf) {
            Write-Log -LogPath $LogPath -LogName $LogName -LogMessage "Deleting container for $UserName based on disabled state of account." -LogLevel "Info"

            try {
                Remove-Item -Path $ContainerDir -Recurse -Force -ErrorAction Stop
            }
            catch {
                Write-Log -LogPath $LogPath -LogName $LogName -LogMessage "Could not delete container for $UserName`: $($_)." -LogLevel "Warning"
                Continue
            }

            $SpaceDisabled = $SpaceDisabled + $ContainerSize
        }
        else {
            Write-Log -LogPath $LogPath -LogName $LogName -LogMessage "WhatIf: Deleting container for $UserName based on disabled state of account." -LogLevel "Info"
            $SpaceDisabled = $SpaceDisabled + $ContainerSize
        }
        Write-Log -LogPath $LogPath -LogName $LogName -LogMessage "Container deleted for $UserName." -LogLevel "Success"
        Continue
    }
    
    if ($ADUser.lastLogonDate -lt ((Get-Date).AddDays( - ($InactiveDays))) -and $True -eq $DeleteInactive) {
        Write-Log -LogPath $LogPath -LogName $LogName -LogMessage "Account for $UserName has been inactive for more than $InactiveDays." -LogLevel "Info"

        if ($True -eq $WhatIf) {
            Write-Log -LogPath $LogPath -LogName $LogName -LogMessage "Deleting container for $UserName based on inactive state of account." -LogLevel "Info"

            try {
                Remove-Item -Path $ContainerDir -Recurse -Force -ErrorAction Stop
            }
            catch {
                Write-Log -LogPath $LogPath -LogName $LogName -LogMessage "Could not delete container for $UserName`: $($_)." -LogLevel "Warning"
                Continue
            }

            $SpaceInactive = $SpaceInactive + $ContainerSize
        }
        else {
            Write-Log -LogPath $LogPath -LogName $LogName -LogMessage "WhatIf: Deleting container for $UserName based on inactive state of account." -LogLevel "Info"
            $SpaceInactive = $SpaceInactive + $ContainerSize
        }
        Write-Log -LogPath $LogPath -LogName $LogName -LogMessage "Container deleted for $UserName." -LogLevel "Success"
        Continue
    }
    Write-Log -LogPath $LogPath -LogName $LogName -LogMessage "No action needed for $UserName." -LogLevel "Success"
}

Write-Log -LogPath $LogPath -LogName $LogName -LogMessage "Script execution completed" -LogLevel "Success"
Write-Log -LogPath $LogPath -LogName $LogName -LogMessage "$ContainerCount containers processed." -LogLevel "Info"
Write-Log -LogPath $LogPath -LogName $LogName -LogMessage "$("{0:N2} GB" -f $SpaceRemoved) reclaimed from removed/non-existent users." -LogLevel "Info"
Write-Log -LogPath $LogPath -LogName $LogName -LogMessage "$("{0:N2} GB" -f $SpaceDisabled) reclaimed from disabled users." -LogLevel "Info"
Write-Log -LogPath $LogPath -LogName $LogName -LogMessage "$("{0:N2} GB" -f $SpaceInactive) reclaimed from inactive users." -LogLevel "Info"
Write-Log -LogPath $LogPath -LogName $LogName -LogMessage "$("{0:N2} GB" -f ($SpaceRemoved+$SpaceDisabled+$SpaceInactive)) reclaimed in total." -LogLevel "Info"
