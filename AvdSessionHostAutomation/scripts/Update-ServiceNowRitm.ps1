#Requires -Version 7.2

<#
.SYNOPSIS
    Writes a build status, host name, and work note to one ServiceNow RITM.

.DESCRIPTION
    Authenticates with ServiceNow OAuth client credentials (preferred) or a
    Basic-auth integration account and PATCHes exactly one sc_req_item record.
    Only the configured status and hostname fields plus work_notes are
    written. Undefined Azure DevOps $(MACRO) values are treated as absent so
    one variable group can define either credential pair.

    With -WhatIf, the update is only reported; no authentication or request
    is sent.

.PARAMETER InstanceUrl
    ServiceNow instance URL, for example https://example.service-now.com.

.PARAMETER RitmSysId
    sys_id of the RITM to update, exactly 32 hexadecimal characters.

.PARAMETER Status
    Lifecycle value written to the status field: Queued, In Progress, Ready,
    Failed, or Timed Out.

.PARAMETER Message
    Work note appended to the RITM.

.PARAMETER HostName
    Optional host name written to the hostname field.

.PARAMETER Platform
    Optional platform label written to the platform field.

.PARAMETER StatusField
    RITM column receiving the status.

.PARAMETER HostNameField
    RITM column receiving the host name.

.PARAMETER PlatformField
    RITM column receiving the platform label.

.PARAMETER ClientId
    OAuth client ID. Used with ClientSecret.

.PARAMETER ClientSecret
    OAuth client secret. Used with ClientId.

.PARAMETER UserName
    Basic-auth integration user. Used with Password when OAuth is not set.

.PARAMETER Password
    Basic-auth password.

.EXAMPLE
    ./Update-ServiceNowRitm.ps1 -InstanceUrl https://example.service-now.com -RitmSysId 0123456789abcdef0123456789abcdef -Status 'In Progress' -Message 'Build started.' -ClientId $id -ClientSecret $secret -WhatIf
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', 'Password', Justification = 'The value arrives from a protected Azure DevOps secret variable through the environment; a SecureString parameter adds no protection in a non-interactive pipeline step.')]
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [Parameter(Mandatory)][string]$InstanceUrl,
    [Parameter(Mandatory)][ValidatePattern('^[0-9a-fA-F]{32}$')][string]$RitmSysId,
    [Parameter(Mandatory)][ValidateSet('Queued', 'In Progress', 'Ready', 'Failed', 'Timed Out')][string]$Status,
    [Parameter(Mandatory)][string]$Message,
    [string]$HostName,
    [string]$Platform,
    [string]$StatusField = 'u_avd_build_status',
    [string]$HostNameField = 'u_avd_hostname',
    [string]$PlatformField = 'u_avd_platform',
    [string]$ClientId,
    [string]$ClientSecret,
    [string]$UserName,
    [string]$Password
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$baseUrl = $InstanceUrl.TrimEnd('/')
$headers = @{ Accept = 'application/json' }

# Azure DevOps leaves an undefined $(VARIABLE_NAME) macro unchanged. Treat those
# literal values as absent so one variable group can define either credential
# pair without dummy values for the other.
$ClientId = if ($ClientId -match '^\$\([A-Za-z0-9_.-]+\)$') { '' } else { $ClientId }
$ClientSecret = if ($ClientSecret -match '^\$\([A-Za-z0-9_.-]+\)$') { '' } else { $ClientSecret }
$UserName = if ($UserName -match '^\$\([A-Za-z0-9_.-]+\)$') { '' } else { $UserName }
$Password = if ($Password -match '^\$\([A-Za-z0-9_.-]+\)$') { '' } else { $Password }

if (-not (($ClientId -and $ClientSecret) -or ($UserName -and $Password))) {
    throw 'Provide either ServiceNow OAuth client credentials or a basic-auth integration account.'
}

if (-not $PSCmdlet.ShouldProcess("sc_req_item/$($RitmSysId.ToLowerInvariant())", "Set '$StatusField' to '$Status' and append a work note")) {
    Write-Output "Would update RITM sys_id '$($RitmSysId.ToLowerInvariant())' to status '$Status'. Nothing was sent."
    return
}

if ($ClientId -and $ClientSecret) {
    $token = Invoke-RestMethod -Method Post -Uri "$baseUrl/oauth_token.do" -ContentType 'application/x-www-form-urlencoded' -Body @{
        grant_type = 'client_credentials'
        client_id = $ClientId
        client_secret = $ClientSecret
    }
    $headers.Authorization = "Bearer $($token.access_token)"
}
else {
    $credentialBytes = [Text.Encoding]::UTF8.GetBytes("${UserName}:$Password")
    $headers.Authorization = "Basic $([Convert]::ToBase64String($credentialBytes))"
}

$body = [ordered]@{
    work_notes = $Message
}
$body[$StatusField] = $Status
if ($HostName) { $body[$HostNameField] = $HostName }
if ($Platform) { $body[$PlatformField] = $Platform }

$response = Invoke-RestMethod -Method Patch `
    -Uri "$baseUrl/api/now/table/sc_req_item/$RitmSysId" `
    -Headers $headers `
    -ContentType 'application/json' `
    -Body ($body | ConvertTo-Json -Compress)
if (-not $response.result.sys_id) {
    throw "ServiceNow did not confirm the update for RITM sys_id '$RitmSysId'."
}
Write-Output "Updated ServiceNow RITM status to '$Status'."
