[CmdletBinding()]
param(
    [Parameter(Mandatory=$true,HelpMessage="The full (UNC) path to the FSLogix container directory.")]
    [string]
    $ContainerPath,

    [Parameter(HelpMessage="If set, enables dry-run mode.")]
    [switch]
    $WhatIf,

    [Parameter(HelpMessage="Array of strings with folder names to exclude in recursion.")]
    [string[]]
    $ExcludeFolders,

    [Parameter(HelpMessage="Number of days a user must have not logged into Active Directory to be considered inactive.")]
    [int]
    $InactiveDays = 90,

    [Parameter(HelpMessage="If set, containers belonging to disabled users will be deleted.")]
    [switch]
    $DeleteDisabled,

    [Parameter(HelpMessage="If set, containers belonging to removed/non-existing users will be deleted.")]
    [switch]
    $DeleteRemoved,

    [Parameter(HelpMessage="If set, containers belonging to inactive users will be deleted.")]
    [switch]
    $DeleteInactive,

    [Parameter(HelpMessage="If set, don't ask for confirmation before execution.")]
    [switch]
    $Confirm,

    [Parameter(HelpMessage="If set, don't use the FlipFlop name convention (%username%_%sid%) but use the default (%sid%_%username%)")]
    [switch]
    $NoFlipFlop
)

function Show-ConsoleMessage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [string]$Indicator = "*",

        [bool]$FullWidth = $False,

        [ValidateScript({ $_ -in [enum]::GetValues([System.ConsoleColor]) })]  
        [string]$IndicatorTextColor = "Black",

        [ValidateScript({ $_ -in [enum]::GetValues([System.ConsoleColor]) })]  
        [string]$IndicatorBackgroundColor = "White",

        [ValidateScript({ $_ -in [enum]::GetValues([System.ConsoleColor]) })] 
        [string]$MessageTextColor = "Black",

        [ValidateScript({ $_ -in [enum]::GetValues([System.ConsoleColor]) })] 
        [string]$MessageBackgroundColor = "Blue"
    )

    Write-Host " $Indicator " -NoNewline -ForegroundColor $IndicatorTextColor -BackgroundColor $IndicatorBackgroundColor
    
    If($FullWidth){
        Write-Host " $Message ".PadRight($Host.UI.RawUI.WindowSize.Width-($Indicator.Length)-2," ") -ForegroundColor $MessageTextColor -BackgroundColor $MessageBackgroundColor
    }else{
        Write-Host " $Message " -ForegroundColor $MessageTextColor -BackgroundColor $MessageBackgroundColor
    }
}

[decimal]$SpaceDisabled = 0
[decimal]$SpaceRemoved = 0
[decimal]$SpaceInactive = 0
[int]$ContainerCount = 0

Show-ConsoleMessage -Message "Info: Starting execution" -MessageTextColor "White" -Indicator ":)"
Show-ConsoleMessage -Message "    Container Path:       $ContainerPath" -MessageTextColor "White" -Indicator "  "
Show-ConsoleMessage -Message "    Excluded folders:     $ExcludeFolders" -MessageTextColor "White" -Indicator "  "
Show-ConsoleMessage -Message "    Deletion options" -MessageTextColor "White" -Indicator "  "
Show-ConsoleMessage -Message "        Removed Users:    $DeleteRemoved" -MessageTextColor "White" -Indicator "  "
Show-ConsoleMessage -Message "        Disabled Users:   $DeleteDisabled" -MessageTextColor "White" -Indicator "  "
Show-ConsoleMessage -Message "        Inactive Users:   $DeleteInactive ($InactiveDays days)" -MessageTextColor "White" -Indicator "  "

If(-not (Test-Path -Path $ContainerPath)){
    Show-ConsoleMessage -Message "Error: Container Path not accessible or does not exist." -MessageBackgroundColor "Red" -MessageTextColor "White" -Indicator ":("
    Exit
}

If($WhatIf -eq $true){
    Show-ConsoleMessage -Message "Info: Executing with WhatIf switch set. No changes will be made." -MessageTextColor "White" -Indicator ":)"
}Elseif($False -eq $Confirm){
    Show-ConsoleMessage -Message "Info: Executing without WhatIf switch set. Specified containers will be deleted." -MessageTextColor "White" -Indicator ":)"
    
    $ConfirmTitle    = 'Confirm execution'
    $ConfirmQuestion = 'Do you want to continue?'
    $ConfirmChoices  = '&Yes', '&No'

    $ConfirmDecision = $Host.UI.PromptForChoice($ConfirmTitle, $ConfirmQuestion, $ConfirmChoices, 1)
    if($ConfirmDecision -eq 1){
        Show-ConsoleMessage -Message "Info: Execution stopped by user." -MessageTextColor "White" -Indicator ":)"
        Exit
    }
}

$ContainerDirs = Get-ChildItem -Path $ContainerPath -Directory -Exclude $ExcludeFolders

Foreach($ContainerDir in $ContainerDirs){
    $ContainerCount++

    If($True -eq $NoFlipFlop){
        $UserName = $ContainerDir.Name.Substring($ContainerDir.Name.IndexOf('_') + 1)
    }Else{
        $UserName = $ContainerDir.Name.Substring(0, $ContainerDir.Name.IndexOf('_S-1-5'))
    }

    $ContainerDir = Join-Path $ContainerPath $ContainerDir
    try{ 
        $ADUser = Get-ADUser -Identity $UserName -Properties sAMAccountName,Enabled,lastLogon,lastLogonDate
    }
    catch [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException]{
        $ADUser = $False
    }

    $ContainerSize = (Get-ChildItem -Path $ContainerDir | Measure-Object Length -Sum).Sum /1Gb
    Show-ConsoleMessage -Message ("Info: Processing $UserName ({0:N2} GB)." -f $ContainerSize) -MessageTextColor "White" -Indicator ":)"

    If($False -eq $ADUser -and $True -eq $DeleteRemoved){
        Show-ConsoleMessage -Message "    Info: Account for $UserName does not exist." -MessageTextColor "White" -Indicator ":)"

        If($WhatIf -ne $true){
            Show-ConsoleMessage -Message "    Info: Deleting container for $UserName based on removed/non-existent state of account." -MessageTextColor "White" -Indicator ":)"
            
            try{
                Remove-Item -Path $ContainerDir -Recurse -Force -ErrorAction Stop
            }
            catch{
                Show-ConsoleMessage -Message "    Warning: Could not delete container for $UserName`: $($_)." -MessageBackgroundColor "Yellow" -Indicator ":|"
                Continue
            }

            $SpaceRemoved = $SpaceRemoved + $ContainerSize
        }Else{
            Show-ConsoleMessage -Message "    WhatIf: Deleting container for $UserName based on removed/non-existent state of account." -MessageTextColor "White" -Indicator ":)"
            $SpaceRemoved = $SpaceRemoved + $ContainerSize
        }
        Show-ConsoleMessage -Message "    Success: Container deleted for $UserName." -MessageBackgroundColor "Green" -Indicator ":D"
        Continue
    }

    If($False -eq $ADUser.Enabled -and $True -eq $DeleteDisabled){
        Show-ConsoleMessage -Message "    Info: Account for $UserName is disabled." -MessageTextColor "White" -Indicator ":)"

        If($WhatIf -ne $true){
            Show-ConsoleMessage -Message "    Info: Deleting container for $UserName based on disabled state of account." -MessageTextColor "White" -Indicator ":)"

            try{
                Remove-Item -Path $ContainerDir -Recurse -Force -ErrorAction Stop
            }
            catch{
                Show-ConsoleMessage -Message "    Warning: Could not delete container for $UserName`: $($_)." -MessageBackgroundColor "Yellow" -Indicator ":|"
                Continue
            }

            $SpaceDisabled = $SpaceDisabled + $ContainerSize
        }Else{
            Show-ConsoleMessage -Message "    WhatIf: Deleting container for $UserName based on disabled state of account." -MessageTextColor "White" -Indicator ":)"
            $SpaceDisabled = $SpaceDisabled + $ContainerSize
        }
        Show-ConsoleMessage -Message "    Success: Container deleted for $UserName." -MessageBackgroundColor "Green" -Indicator ":D"
        Continue
    }
    
    If($ADUser.lastLogonDate -lt ((Get-Date).AddDays(-($InactiveDays))) -and $True -eq $DeleteInactive){
        Show-ConsoleMessage -Message "    Info: Account for $UserName has been inactive for more than $InactiveDays." -MessageTextColor "White" -Indicator ":)"

        If($WhatIf -ne $true){
            Show-ConsoleMessage -Message "    Info: Deleting container for $UserName based on inactive state of account." -MessageTextColor "White" -Indicator ":)"

            try{
                Remove-Item -Path $ContainerDir -Recurse -Force -ErrorAction Stop
            }
            catch{
                Show-ConsoleMessage -Message "    Warning: Could not delete container for $UserName`: $($_)." -MessageBackgroundColor "Yellow" -Indicator ":|"
                Continue
            }

            $SpaceInactive = $SpaceInactive + $ContainerSize
        }Else{
            Show-ConsoleMessage -Message "    WhatIf: Deleting container for $UserName based on inactive state of account." -MessageTextColor "White" -Indicator ":)"
            $SpaceInactive = $SpaceInactive + $ContainerSize
        }
        Show-ConsoleMessage -Message "    Success: Container deleted for $UserName." -MessageBackgroundColor "Green" -Indicator ":D"
        Continue
    }
    Show-ConsoleMessage -Message "    Success: No action needed for $UserName." -MessageBackgroundColor "Green" -Indicator ":D"
}

Show-ConsoleMessage -Message "Success: Script execution completed" -MessageBackgroundColor "Green" -Indicator ":D"
Show-ConsoleMessage -Message "    $ContainerCount containers processed." -MessageBackgroundColor "Green" -Indicator "  "
Show-ConsoleMessage -Message "    $("{0:N2} GB" -f $SpaceRemoved) reclaimed from removed/non-existent users." -MessageBackgroundColor "Green" -Indicator "  "
Show-ConsoleMessage -Message "    $("{0:N2} GB" -f $SpaceDisabled) reclaimed from disabled users." -MessageBackgroundColor "Green" -Indicator "  "
Show-ConsoleMessage -Message "    $("{0:N2} GB" -f $SpaceInactive) reclaimed from inactive users." -MessageBackgroundColor "Green" -Indicator "  "
Show-ConsoleMessage -Message "    $("{0:N2} GB" -f ($SpaceRemoved+$SpaceDisabled+$SpaceInactive)) reclaimed in total." -MessageBackgroundColor "Green" -Indicator "  "
