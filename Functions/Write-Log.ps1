<#
.SYNOPSIS
    Write a log message to a specified file and/or to the host console.

.PARAMETER *
    Parameters are available as specified in the param block below.

.NOTES
    Version:        1.0
    Author:         Tom Schoen
    Creation Date:  01-11-2022
    Purpose/Change: Initial function development
  
.EXAMPLE
    Writes a log entry to "C:\Temp\ScriptExecution.log": 2022-11-05 13:00:00Z [Error] An error message.
    Write-Log -LogPath "C:\Temp" -LogName "ScriptExecution" -LogMessage "An error message." -LogLevel "Error"

.EXAMPLE
    Writes a log entry without timestamp to "C:\Temp\Script.log": [Info] An informational message.
    Write-Log -LogPath "C:\Temp" -LogName "Script" -LogMessage "An informational message." -LogLevel "Info" -NoDate

.EXAMPLE
    Writes a log entry to "C:\Temp\ScriptExecution.log": 2022-11-05 13:00:00Z [Error] An error message.
    Prepends the header "Top of the log" to the log file if it is created during this execution.
    Write-Log -LogPath "C:\Temp" -LogName "ScriptExecution" -LogMessage "An error message." -LogLevel "Error" -LogHeader "Top of the log"
#>

function Write-Log {
    param (
        [Parameter(Mandatory)]
        [string]
        $LogMessage,

        [Parameter(Mandatory)]
        [string]
        $LogLevel,

        [Parameter(Mandatory)]
        $LogPath,

        [Parameter(Mandatory)]
        [string]
        $LogName,

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
        if (-not (Test-Path $File) -and $LogHeader) {
            Add-Content -Path $File -Value ""
        }
        Add-content -Path $File -Value $Message
    }
    
    Write-Output $Message

}