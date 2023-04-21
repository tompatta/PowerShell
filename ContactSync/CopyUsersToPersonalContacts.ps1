Write-Host "$(Get-Date -Format "u") [INFO] Checking Exchange Online PowerShell Module v3" -ForegroundColor Cyan
If (-not (Get-Module -ListAvailable -Name "ExchangeOnlineManagement" | Where-Object Version -ge 3.0.0)) {
    throw "Cannot load Exchange Online PowerShell Module v3: It is not installed."
    Exit 1
}

Write-Host "$(Get-Date -Format "u") [ OK ] Exchange Online PowerShell Module v3 is installed" -ForegroundColor Green

try {
    Write-Host "$(Get-Date -Format "u") [INFO] Importing Exchange Online PowerShell Module v3" -ForegroundColor Cyan
    Import-Module "ExchangeOnlineManagement" -MinimumVersion 3.0.0
}
catch {
    throw "Cannot load Exchange Online PowerShell Module v3: $($_.Exception.Message)"
    Exit 1
}

Write-Host "$(Get-Date -Format "u") [ OK ] Loaded Exchange Online PowerShell Module v3" -ForegroundColor Green

try {
    Write-Host "$(Get-Date -Format "u") [INFO] Connecting to Exchange Online" -ForegroundColor Cyan
    Connect-ExchangeOnline -ShowBanner:$false
}
catch {
    throw "Cannot connect to Exchange Online: $($_.Exception.Message)"
    Exit 1
}

Write-Host "$(Get-Date -Format "u") [ OK ] Connected to Exchange Online" -ForegroundColor Green

Write-Host "$(Get-Date -Format "u") [INFO] Checking Microsoft Graph Authentication PowerShell Module v1" -ForegroundColor Cyan
If (-not (Get-Module -ListAvailable -Name "Microsoft.Graph.Authentication" | Where-Object Version -ge 1.0.0)) {
    throw "Cannot load Microsoft Graph Authentication PowerShell Module v1: It is not installed."
    Exit 1
}

Write-Host "$(Get-Date -Format "u") [ OK ] Microsoft Graph Authentication PowerShell Module v1 is installed" -ForegroundColor Green

try {
    Write-Host "$(Get-Date -Format "u") [INFO] Importing Microsoft Graph Authentication PowerShell Module v1" -ForegroundColor Cyan
    Import-Module "Microsoft.Graph.Authentication" -MinimumVersion 1.0.0
}
catch {
    throw "Cannot load Microsoft Graph Authentication PowerShell Module v1: $($_.Exception.Message)"
    Exit 1
}

Write-Host "$(Get-Date -Format "u") [INFO] Checking Microsoft Graph PersonalContacts PowerShell Module v1" -ForegroundColor Cyan
If (-not (Get-Module -ListAvailable -Name "Microsoft.Graph.PersonalContacts" | Where-Object Version -ge 1.0.0)) {
    throw "Cannot load Microsoft Graph PersonalContacts PowerShell Module v1: It is not installed."
    Exit 1
}

Write-Host "$(Get-Date -Format "u") [ OK ] Microsoft Graph PersonalContacts PowerShell Module v1 is installed" -ForegroundColor Green

try {
    Write-Host "$(Get-Date -Format "u") [INFO] Microsoft Graph PersonalContacts PowerShell Module v1" -ForegroundColor Cyan
    Import-Module "Microsoft.Graph.PersonalContacts" -MinimumVersion 1.0.0
}
catch {
    throw "Cannot load Microsoft Graph PersonalContacts PowerShell Module v1: $($_.Exception.Message)"
    Exit 1
}

Write-Host "$(Get-Date -Format "u") [ OK ] Loaded Microsoft Graph PersonalContacts PowerShell Module v1" -ForegroundColor Green

$applicationId = "91e37786-8a76-4343-80c6-5e051a46bb38"
$applicationSecret = "TPw8Q~KLYZ9Mz.ZmHogDUq5gMHGBhoye63Q.Pc0-"
$applicationTenantId = "fc82ac7a-3afc-43d9-9d43-a41fa3f6e85f"

$uri = "https://login.microsoftonline.com/$applicationTenantId/oauth2/v2.0/token"
$requestBody = @{
    client_id     = $applicationId
    scope         = "https://graph.microsoft.com/.default"
    client_secret = $applicationSecret
    grant_type    = "client_credentials"
}

try {
    Write-Host "$(Get-Date -Format "u") [INFO] Getting Microsoft Graph access token" -ForegroundColor Cyan
    $tokenRequest = Invoke-WebRequest -Method Post -Uri $uri -ContentType "application/x-www-form-urlencoded" -Body $requestBody -UseBasicParsing
}
catch {
    throw "Cannot fetch Microsoft Graph access token: $($_.Exception.Message)"
    Exit 1
}

Write-Host "$(Get-Date -Format "u") [ OK ] Access token obtained" -ForegroundColor Green

$token = ($tokenRequest.Content | ConvertFrom-Json).access_token

try {
    Write-Host "$(Get-Date -Format "u") [INFO] Connecting to Microsoft Graph" -ForegroundColor Cyan
    [void](Connect-MgGraph -AccessToken $token)
}
catch {
    throw "Cannot connect to Microsoft Graph: $($_.Exception.Message)"
    Exit 1
}

Write-Host "$(Get-Date -Format "u") [ OK ] Connected to Microsoft Graph" -ForegroundColor Green

#[array]$tenantRecipients = Get-User -ResultSize unlimited | 
#Where-Object { $_.RecipientTypeDetails -in "UserMailbox", "SharedMailbox", "MailContact", "MailUser" -and $_.UserPrincipalName -notlike "*.onmicrosoft.com" } |
#Select-Object Firstname, LastName, MiddleName, Phone, MobilePhone, Company, Department, Title, UserPrincipalName, WindowsEmailAddress, DisplayName

[array]$tenantRecipients = Get-MgUser -All -Property Displayname, GivenName, MiddleName, Surname, CompanyName, Department, UserType, BusinessPhones, MobilePhone, UserPrincipalName, JobTitle, UserPrincipalName, Mail |
Where-Object { $null -ne $_.Mail -and $_.UserType -in "Member" -and $_.UserPrincipalName -notlike "*.onmicrosoft.com" } | 
Select-Object Displayname, GivenName, Surname, CompanyName, Department, UserType, BusinessPhones, MobilePhone, UserPrincipalName, JobTitle, Mail

[array]$tenantMailboxes = Get-ExoMailbox -RecipientTypeDetails UserMailbox -ResultSize unlimited | 
Select-Object ExternalDirectoryObjectId, DisplayName, UserPrincipalName

If (-not $tenantMailboxes) { 
    Write-Host "$(Get-Date -Format "u") [ OK ] No user mailboxes found to sync" -ForegroundColor Green
    Exit 0
}

foreach ( $tenantMailbox in $tenantMailboxes ) {

    $logId = ( -join ((0x30..0x39) + ( 0x61..0x7A) | Get-Random -Count 6  | ForEach-Object { [char]$_ }))

    Write-Host "$(Get-Date -Format "u") [ $logId ] [INFO] Processing $($tenantMailbox.UserPrincipalName)" -ForegroundColor Cyan

    Write-Host "$(Get-Date -Format "u") [ $logId ] [INFO] Fetching existing synced contacts" -ForegroundColor Cyan
    [array]$mailboxContacts = Get-MgUserContact -UserId $tenantMailbox.ExternalDirectoryObjectId -All -Filter "categories/any(a:a eq 'Auto Sync')"
    
    If ($mailboxContacts) {
        $y = 0
        for ($x = 0; $x -lt $mailboxContacts.count; $x += 20) {
        
            $deleteBatch = @{ Requests = @() }
            $i = 0

            $mailboxContactsBatch = $mailboxContacts[$x..($x + 19)]

            foreach ( $mailboxContact in $mailboxContactsBatch ) {
                $deleteBatch.Requests += @{
                    id     = $i
                    method = "DELETE"
                    url    = "/users/$($tenantMailbox.ExternalDirectoryObjectId)/contacts/$($mailboxContact.Id)"
                }

                $i++
            }
            $y++

            try {
                Write-Host "$(Get-Date -Format "u") [ $logId ] [INFO] Deleting existing synced contacts (batch $y)" -ForegroundColor Cyan
                $deleteResponse = Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/v1.0/`$batch" -Body ($deleteBatch | ConvertTo-Json -Depth 100)
            }
            catch {
                Write-Host $_
                throw "Error deleting contact(s) for $($tenantMailbox.UserPrincipalName): $($_.Exception.Message)"
            }

            $deleteResponse.responses | ForEach-Object {                                    
                if ($_.status -eq 204) {
                    Write-Host "$(Get-Date -Format "u") [ $logId ] [ OK ] - Contact $($mailboxContacts[$_.id].DisplayName) deleted" -ForegroundColor Green
                }
                else {
                    $_.body.error
                    Write-Host "$(Get-Date -Format "u") [ $logId ] [ NO ] x Contact $($mailboxContacts[$_.id].DisplayName) could not be deleted" -ForegroundColor Yellow
                }    
            }
        }
    }
    else {
        Write-Host "$(Get-Date -Format "u") [ OK ] No existing synced contacts found" -ForegroundColor Green
    }

    If ($tenantRecipients) {
        $y = 0
        for ($x = 0; $x -lt $tenantRecipients.count; $x += 20) {
        
            $createBatch = @{ Requests = @() }
            $i = 0

            $tenantRecipientsBatch = $tenantRecipients[$x..($x + 19)]

            foreach ( $tenantRecipient in $tenantRecipientsBatch ) {
                $createBatch.Requests += @{
                    id      = $i
                    method  = "POST"
                    url     = "/users/$($tenantMailbox.ExternalDirectoryObjectId)/contacts"
                    headers = @{
                        "Content-Type" = "application/json"
                    }
                    body    = @{
                        
                        BusinessPhones = [array]$tenantRecipient.BusinessPhones
                        MobilePhone    = $tenantRecipient.MobilePhone
                        CompanyName    = $tenantRecipient.CompanyName
                        Department     = $tenantRecipient.Department
                        DisplayName    = $tenantRecipient.DisplayName
                        GivenName      = $tenantRecipient.GivenName
                        Surname        = $tenantRecipient.Surname
                        JobTitle       = $tenantRecipient.JobTitle
                        Categories     = @("Auto Sync")
                        PersonalNotes  = "This contact was automatically synced from the global contacts list. Please do not change or remove."

                        EmailAddresses = @(
                            @{
                                Address = $tenantRecipient.Mail
                                Name    = ""
                            }
                        )
                    }
                }

                $i++
            }
            $y++

            try {
                Write-Host "$(Get-Date -Format "u") [ $logId ] [INFO] Adding synced contacts (batch $y)" -ForegroundColor Cyan
                $createResponse = Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/v1.0/`$batch" -Body ($createBatch | ConvertTo-Json -Depth 100)
            }
            catch {
                Write-Host $_
                throw "Error creating contact(s) for $($tenantMailbox.UserPrincipalName): $($_.Exception.Message)"
            }

            $createResponse.responses | ForEach-Object {                                    
                if ($_.status -eq 201) {
                    Write-Host "$(Get-Date -Format "u") [ $logId ] [ OK ] + Contact $($tenantRecipients[$_.id].DisplayName) created" -ForegroundColor Green
                }
                else {
                    Write-Host "$(Get-Date -Format "u") [ $logId ] [ NO ] x Contact $($tenantRecipients[$_.id].DisplayName) could not be created" -ForegroundColor Yellow
                }    
            }
        }
    }
    else {
        Write-Host "$(Get-Date -Format "u") [ $logId ] [INFO] No contacts found to sync" -ForegroundColor Cyan
    }
}