<#
.SYNOPSIS
    Show a colourized message on the host console.

.PARAMETER *
    Parameters are available as specified in the param block below.

.NOTES
    Version:        1.0
    Author:         Tom Schoen
    Creation Date:  01-11-2022
    Purpose/Change: Initial function development
  
.EXAMPLE
    Full-width console messages:

    Write-Console -Message "Info: Starting execution" -MessageTextColor "White" -Indicator ":)" -FullWidth $True
    Write-Console -Message "Success: Execution completed" -MessageBackgroundColor "Green" -Indicator ":D" -FullWidth $True
    Write-Console -Message "Warning: Cannot execute" -MessageBackgroundColor "Yellow" -Indicator ":|" -FullWidth $True
    Write-Console -Message "Error: Execution failed" -MessageTextColor "White" -MessageBackgroundColor "Red" -Indicator ":(" -FullWidth $True

.EXAMPLE
    Auto-width console messages:

    Write-Console -Message "Info: Starting execution" -MessageTextColor "White" -Indicator ":)"
    Write-Console -Message "Success: Execution completed" -MessageBackgroundColor "Green" -Indicator ":D"
    Write-Console -Message "Warning: Cannot execute" -MessageBackgroundColor "Yellow" -Indicator ":|"
    Write-Console -Message "Error: Execution failed" -MessageTextColor "White" -MessageBackgroundColor "Red" -Indicator ":("

#>

function Write-Console {
    [CmdletBinding()]
    param (
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
    
    If ($FullWidth) {
        Write-Host " $Message ".PadRight($Host.UI.RawUI.WindowSize.Width - ($Indicator.Length) - 2, " ") -ForegroundColor $MessageTextColor -BackgroundColor $MessageBackgroundColor
    }
    else {
        Write-Host " $Message " -ForegroundColor $MessageTextColor -BackgroundColor $MessageBackgroundColor
    }
}
