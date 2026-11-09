#requires -Version 5.1
<#
Shared logic for Export-ManagerDeviceList.ps1. Dot-source this file; it only
defines functions. Graph access goes through the caller's existing
Connect-MgGraph session (Invoke-MgGraphRequest); no credentials are handled.

Primary sources (Microsoft Graph v1.0):
  directReports  https://learn.microsoft.com/en-us/graph/api/user-list-directreports?view=graph-rest-1.0
  managedDevices https://learn.microsoft.com/en-us/graph/api/intune-devices-manageddevice-list?view=graph-rest-1.0
  managedDevice  https://learn.microsoft.com/en-us/graph/api/resources/intune-devices-manageddevice?view=graph-rest-1.0
  device         https://learn.microsoft.com/en-us/graph/api/resources/device?view=graph-rest-1.0
  JSON batching  https://learn.microsoft.com/en-us/graph/json-batching
#>

Set-StrictMode -Version 3.0

$script:MdeRetryableStatusCodes = @(429, 500, 502, 503, 504)
$script:MdeMaxGraphAttempts = 5
$script:MdeGraphBase = 'https://graph.microsoft.com/v1.0'

function Get-MdeProperty {
    # StrictMode-safe property read for PSCustomObject and dictionaries.
    param($InputObject, [Parameter(Mandatory)] [string] $Name)
    if ($null -eq $InputObject) { return $null }
    if ($InputObject -is [System.Collections.IDictionary]) {
        if ($InputObject.Contains($Name)) { return $InputObject[$Name] }
        return $null
    }
    $property = $InputObject.PSObject.Properties[$Name]
    if ($property) { return $property.Value }
    return $null
}

function ConvertTo-MdeGuid {
    # Canonical lowercase 'D' form, or '' for missing, malformed, or empty GUIDs.
    param($Value)
    $parsed = [guid]::Empty
    if (-not [guid]::TryParse([string]$Value, [ref]$parsed) -or $parsed -eq [guid]::Empty) { return '' }
    return $parsed.ToString('D')
}

function ConvertTo-MdeCsvValue {
    # Prevents values supplied by Graph from becoming formulas when the CSV is
    # opened in Excel (leading = + - @ tab CR).
    param([AllowNull()] $Value)
    if ($null -eq $Value) { return '' }
    $text = [string]$Value
    if ($text -match '^[=+\-@\t\r]') { return "'$text" }
    return $text
}

function ConvertFrom-MdeRetryAfter {
    # Retry-After is either delta-seconds or an HTTP-date (RFC 9110 10.2.3).
    param($Value)
    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) { return 0 }
    $seconds = 0
    if ([int]::TryParse($text.Trim(), [ref]$seconds)) { return [Math]::Max(0, $seconds) }
    $date = [DateTimeOffset]::MinValue
    if ([DateTimeOffset]::TryParse($text, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AssumeUniversal, [ref]$date)) {
        return [int][Math]::Max(0, [Math]::Ceiling(($date - [DateTimeOffset]::UtcNow).TotalSeconds))
    }
    return 0
}

function Get-MdeRetryDelay {
    # Never shorten the service's Retry-After; bounded exponential fallback.
    param([int] $Attempt, [int] $RetryAfter = 0)
    if ($RetryAfter -gt 0) { return $RetryAfter }
    return [int][Math]::Min(60, 5 * [Math]::Pow(2, $Attempt - 1))
}

function Initialize-MdeGraphSession {
    # Uses the caller's existing Connect-MgGraph session. Throws when there is
    # none; warns (does not throw) when the delegated scopes look insufficient,
    # because an admin-consented superset or app-only roles can still work.
    [CmdletBinding()]
    param()

    $context = Get-MgContext
    if ($null -eq $context) {
        throw 'No Microsoft Graph session. Run Connect-MgGraph -Scopes User.Read.All,DeviceManagementManagedDevices.Read.All,Device.Read.All first.'
    }

    $environment = [string](Get-MdeProperty $context 'Environment')
    if ($environment -and $environment -ne 'Global') {
        $endpoint = [string](Get-MdeProperty (Get-MgEnvironment -Name $environment) 'GraphEndpoint')
        if ($endpoint) { $script:MdeGraphBase = $endpoint.TrimEnd('/') + '/v1.0' }
    }

    $scopes = @(Get-MdeProperty $context 'Scopes')
    $needs = [ordered]@{
        'directReports (users)'          = @('User.Read.All', 'User.ReadWrite.All', 'Directory.Read.All', 'Directory.ReadWrite.All')
        'managedDevices (Intune)'        = @('DeviceManagementManagedDevices.Read.All', 'DeviceManagementManagedDevices.ReadWrite.All')
        'devices (Entra object lookup)'  = @('Device.Read.All', 'Device.ReadWrite.All', 'Directory.Read.All', 'Directory.ReadWrite.All')
    }
    foreach ($area in $needs.Keys) {
        $hit = @($needs[$area] | Where-Object { $scopes -contains $_ })
        if ($hit.Count -eq 0) {
            Write-Warning ("Current Graph session has none of [{0}] for {1}. Calls may fail with 403." -f ($needs[$area] -join ', '), $area)
        }
    }

    [pscustomobject]@{
        Account   = [string](Get-MdeProperty $context 'Account')
        TenantId  = [string](Get-MdeProperty $context 'TenantId')
        GraphBase = $script:MdeGraphBase
    }
}

function Invoke-MdeGraph {
    # One Graph call with bounded retry on throttling/transient errors.
    # Returns the parsed JSON body ($null when empty); throws on other errors.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [ValidateSet('GET', 'POST')] [string] $Method,
        [Parameter(Mandatory)] [string] $Uri,
        [object] $Body
    )
    $resolvedUri = if ($Uri.StartsWith('https://')) { $Uri } else { "$script:MdeGraphBase$Uri" }
    $requestArgs = @{
        Method             = $Method
        Uri                = $resolvedUri
        OutputType         = 'HttpResponseMessage'
        SkipHttpErrorCheck = $true
    }
    if ($null -ne $Body) {
        $requestArgs.Body = ($Body | ConvertTo-Json -Depth 10 -Compress)
        $requestArgs.ContentType = 'application/json'
    }

    for ($attempt = 1; ; $attempt++) {
        $response = Invoke-MgGraphRequest @requestArgs
        try {
            $status = [int]$response.StatusCode
            $content = ''
            if ($null -ne $response.Content) {
                $content = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
            }
            $retryAfter = 0
            $headers = $response.Headers
            if ($null -ne $headers -and $null -ne $headers.RetryAfter) {
                if ($null -ne $headers.RetryAfter.Delta) { $retryAfter = [int][Math]::Ceiling($headers.RetryAfter.Delta.TotalSeconds) }
                elseif ($null -ne $headers.RetryAfter.Date) { $retryAfter = [int][Math]::Max(0, [Math]::Ceiling(($headers.RetryAfter.Date - [DateTimeOffset]::UtcNow).TotalSeconds)) }
            }
        }
        finally {
            $response.Dispose()
        }

        if ($status -ge 200 -and $status -lt 300) {
            if ([string]::IsNullOrWhiteSpace($content)) { return $null }
            return ($content | ConvertFrom-Json)
        }
        if ($script:MdeRetryableStatusCodes -contains $status -and $attempt -lt $script:MdeMaxGraphAttempts) {
            $delay = Get-MdeRetryDelay -Attempt $attempt -RetryAfter $retryAfter
            Write-Warning ('Graph {0} {1} returned HTTP {2}; retry {3} of {4} in {5}s.' -f $Method, $resolvedUri, $status, $attempt, ($script:MdeMaxGraphAttempts - 1), $delay)
            Start-Sleep -Seconds $delay
            continue
        }

        $message = $content
        try {
            $errorBody = Get-MdeProperty ($content | ConvertFrom-Json) 'error'
            if ($errorBody) { $message = '{0}: {1}' -f (Get-MdeProperty $errorBody 'code'), (Get-MdeProperty $errorBody 'message') }
        }
        catch {
            Write-Verbose 'Graph error body was not JSON.'
        }
        $exception = New-Object System.Exception ('Graph {0} {1} failed with HTTP {2}. {3}' -f $Method, $resolvedUri, $status, $message)
        $exception.Data['StatusCode'] = $status
        throw $exception
    }
}

function Get-MdeGraphPaged {
    # Walks @odata.nextLink and returns every item in the 'value' collections.
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Uri)
    $items = New-Object 'System.Collections.Generic.List[object]'
    $nextUri = $Uri
    while ($nextUri) {
        $response = Invoke-MdeGraph -Method GET -Uri $nextUri
        if ($null -eq $response -or -not $response.PSObject.Properties['value']) {
            throw "Unexpected Graph response from $nextUri (no 'value' collection)."
        }
        foreach ($item in @($response.value)) { $items.Add($item) }
        $nextUri = [string](Get-MdeProperty $response '@odata.nextLink')
    }
    # Unrolled on purpose: callers wrap the result in @().
    return $items.ToArray()
}

function Invoke-MdeGraphBatch {
    # Sends GET requests through /$batch in chunks of 20 (the documented batch
    # limit) and returns a hashtable of request id -> { Status; Body }.
    # Throttled or transient sub-requests are retried with Retry-After.
    [CmdletBinding()]
    param([Parameter(Mandatory)] [AllowEmptyCollection()] [object[]] $Requests)
    $results = @{}
    for ($offset = 0; $offset -lt $Requests.Count; $offset += 20) {
        $last = [Math]::Min($offset + 19, $Requests.Count - 1)
        $pending = @($Requests[$offset..$last])
        for ($attempt = 1; $pending.Count -gt 0; $attempt++) {
            $response = Invoke-MdeGraph -Method POST -Uri '/$batch' -Body @{ requests = $pending }
            $responses = @(Get-MdeProperty $response 'responses')
            $byId = @{}
            foreach ($request in $pending) { $byId[[string]$request.id] = $request }
            $retry = New-Object 'System.Collections.Generic.List[object]'
            $delay = 0
            foreach ($item in $responses) {
                $id = [string](Get-MdeProperty $item 'id')
                if (-not $byId.ContainsKey($id)) { throw "Graph batch returned an unexpected response id: $id" }
                $status = [int](Get-MdeProperty $item 'status')
                if ($script:MdeRetryableStatusCodes -contains $status -and $attempt -lt $script:MdeMaxGraphAttempts) {
                    $retry.Add($byId[$id])
                    $delay = [Math]::Max($delay, (ConvertFrom-MdeRetryAfter (Get-MdeProperty (Get-MdeProperty $item 'headers') 'Retry-After')))
                    continue
                }
                $results[$id] = [pscustomobject]@{ Status = $status; Body = (Get-MdeProperty $item 'body') }
            }
            if ($retry.Count -gt 0) {
                $wait = Get-MdeRetryDelay -Attempt $attempt -RetryAfter $delay
                Write-Warning ('{0} batched request(s) throttled; retrying in {1}s.' -f $retry.Count, $wait)
                Start-Sleep -Seconds $wait
            }
            $pending = @($retry.ToArray())
        }
    }
    foreach ($request in $Requests) {
        if (-not $results.ContainsKey([string]$request.id)) {
            throw ('Graph $batch returned no response for request {0} ({1}).' -f $request.id, $request.url)
        }
    }
    return $results
}

function Resolve-MdeManager {
    # Resolves each manager (UPN or object id) to a user. Unknown managers throw:
    # a typo must not silently produce a smaller deployment group.
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string[]] $Identity)
    $managers = New-Object 'System.Collections.Generic.List[object]'
    $seen = @{}
    foreach ($value in $Identity) {
        $trimmed = $value.Trim()
        if (-not $trimmed) { continue }
        $uri = '/users/{0}?$select=id,displayName,userPrincipalName' -f [uri]::EscapeDataString($trimmed)
        try {
            $user = Invoke-MdeGraph -Method GET -Uri $uri
        }
        catch {
            if ($_.Exception.Data['StatusCode'] -eq 404) { throw "Manager '$trimmed' was not found in Entra ID." }
            throw
        }
        $id = ConvertTo-MdeGuid (Get-MdeProperty $user 'id')
        if (-not $id) { throw "Manager '$trimmed' lookup returned no object id." }
        if ($seen.ContainsKey($id)) { continue }
        $seen[$id] = $true
        $managers.Add([pscustomobject]@{
                Id                = $id
                DisplayName       = [string](Get-MdeProperty $user 'displayName')
                UserPrincipalName = [string](Get-MdeProperty $user 'userPrincipalName')
            })
    }
    return , $managers.ToArray()
}

function Get-MdeReport {
    # Returns the users reporting to the given managers. Direct reports only by
    # default; -Recurse walks the chain level by level (the API itself returns
    # only one level). Org contacts are skipped. Each user appears once: the
    # first manager that reaches them wins. Managers themselves are excluded.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [object[]] $Managers,
        [switch] $Recurse
    )
    $select = 'id,displayName,userPrincipalName,accountEnabled'
    $reports = New-Object 'System.Collections.Generic.List[object]'
    $visited = @{}
    foreach ($manager in $Managers) { $visited[$manager.Id] = $true }

    $level = 1
    $current = @($Managers)
    while ($current.Count -gt 0) {
        $requests = @(for ($i = 0; $i -lt $current.Count; $i++) {
                @{ id = [string]$i; method = 'GET'; url = "/users/$($current[$i].Id)/directReports?`$select=$select" }
            })
        $results = Invoke-MdeGraphBatch -Requests $requests
        $next = New-Object 'System.Collections.Generic.List[object]'
        for ($i = 0; $i -lt $current.Count; $i++) {
            $parent = $current[$i]
            $result = $results[[string]$i]
            if ($result.Status -ne 200) {
                throw ('directReports for {0} failed with HTTP {1}.' -f $parent.UserPrincipalName, $result.Status)
            }
            $members = New-Object 'System.Collections.Generic.List[object]'
            foreach ($item in @(Get-MdeProperty $result.Body 'value')) { if ($null -ne $item) { $members.Add($item) } }
            $nextLink = [string](Get-MdeProperty $result.Body '@odata.nextLink')
            if ($nextLink) { foreach ($item in @(Get-MdeGraphPaged -Uri $nextLink)) { $members.Add($item) } }

            foreach ($member in $members) {
                if ((Get-MdeProperty $member '@odata.type') -ne '#microsoft.graph.user') { continue }
                $id = ConvertTo-MdeGuid (Get-MdeProperty $member 'id')
                if (-not $id -or $visited.ContainsKey($id)) { continue }
                $visited[$id] = $true
                $root = if ($level -eq 1) { $parent } else { $parent.RootManager }
                $record = [pscustomobject]@{
                    Id                 = $id
                    DisplayName        = [string](Get-MdeProperty $member 'displayName')
                    UserPrincipalName  = [string](Get-MdeProperty $member 'userPrincipalName')
                    AccountEnabled     = Get-MdeProperty $member 'accountEnabled'
                    ReportLevel        = $level
                    DirectManagerUpn   = $parent.UserPrincipalName
                    RootManager        = $root
                }
                $reports.Add($record)
                if ($Recurse) { $next.Add($record) }
            }
        }
        $current = @($next.ToArray())
        $level++
    }
    return , $reports.ToArray()
}

function Get-MdeManagedDeviceIndex {
    # Lists Intune managed devices once and indexes them by userId.
    # A per-user server-side $filter on userId is not documented for
    # managedDevices, so the list is filtered client-side instead.
    [CmdletBinding()]
    param()
    $select = 'id,deviceName,userId,userPrincipalName,azureADDeviceId,operatingSystem,osVersion,managedDeviceOwnerType,complianceState,lastSyncDateTime,serialNumber,manufacturer,model'
    $index = @{}
    foreach ($device in @(Get-MdeGraphPaged -Uri "/deviceManagement/managedDevices?`$select=$select&`$top=1000")) {
        $userId = ConvertTo-MdeGuid (Get-MdeProperty $device 'userId')
        if (-not $userId) { continue }
        if (-not $index.ContainsKey($userId)) { $index[$userId] = New-Object 'System.Collections.Generic.List[object]' }
        $index[$userId].Add($device)
    }
    # Plain arrays for callers; @() over a generic List value is avoided.
    $result = @{}
    foreach ($key in $index.Keys) { $result[$key] = $index[$key].ToArray() }
    return $result
}

function Resolve-MdeEntraDevice {
    # Maps Entra deviceId (Intune azureADDeviceId) -> Entra device object, or
    # $null when no object exists. The object id ('id') is what group
    # membership needs; it is different from deviceId.
    [CmdletBinding()]
    param([Parameter(Mandatory)] [AllowEmptyCollection()] [string[]] $DeviceIds)
    $resolved = @{}
    $unique = @($DeviceIds | Where-Object { $_ } | Select-Object -Unique)
    if ($unique.Count -eq 0) { return $resolved }
    $requests = @(for ($i = 0; $i -lt $unique.Count; $i++) {
            @{ id = [string]$i; method = 'GET'; url = "/devices(deviceId='$($unique[$i])')?`$select=id,deviceId,displayName,accountEnabled" }
        })
    $results = Invoke-MdeGraphBatch -Requests $requests
    for ($i = 0; $i -lt $unique.Count; $i++) {
        $result = $results[[string]$i]
        if ($result.Status -eq 404) { $resolved[$unique[$i]] = $null; continue }
        if ($result.Status -ne 200) { throw ('Entra device lookup for {0} failed with HTTP {1}.' -f $unique[$i], $result.Status) }
        $resolved[$unique[$i]] = $result.Body
    }
    return $resolved
}

function Get-MdeDeviceRow {
    # Pure join: report users x Intune devices x Entra objects -> CSV rows.
    # Status values:
    #   OK              Entra device object id resolved; ready for a group.
    #   NoEntraObject   Intune device has an Entra deviceId with no Entra object.
    #   NoEntraDeviceId Intune device reports no Entra deviceId.
    #   NoIntuneDevice  User has no matching Intune device (only with
    #                   -IncludeUsersWithoutDevices).
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [object[]] $Reports,
        [Parameter(Mandatory)] [hashtable] $DeviceIndex,
        [Parameter(Mandatory)] [hashtable] $EntraDevices,
        [string[]] $OperatingSystem,
        [switch] $IncludeUsersWithoutDevices
    )
    $rows = New-Object 'System.Collections.Generic.List[object]'
    foreach ($user in $Reports) {
        $devices = @()
        if ($DeviceIndex.ContainsKey($user.Id)) { $devices = @($DeviceIndex[$user.Id]) }
        if ($OperatingSystem) {
            $devices = @($devices | Where-Object { $OperatingSystem -contains [string](Get-MdeProperty $_ 'operatingSystem') })
        }

        $base = [ordered]@{
            ManagerUPN          = $user.RootManager.UserPrincipalName
            ManagerDisplayName  = $user.RootManager.DisplayName
            ReportLevel         = $user.ReportLevel
            DirectManagerUPN    = $user.DirectManagerUpn
            UserDisplayName     = $user.DisplayName
            UserPrincipalName   = $user.UserPrincipalName
            UserId              = $user.Id
            UserAccountEnabled  = $user.AccountEnabled
        }

        if ($devices.Count -eq 0) {
            if (-not $IncludeUsersWithoutDevices) { continue }
            $row = [ordered]@{}
            foreach ($key in $base.Keys) { $row[$key] = $base[$key] }
            foreach ($name in 'DeviceName', 'OperatingSystem', 'OSVersion', 'Ownership', 'ComplianceState', 'LastSyncDateTime', 'SerialNumber', 'Manufacturer', 'Model', 'IntuneDeviceId', 'EntraDeviceId', 'EntraDeviceObjectId') { $row[$name] = '' }
            $row['Status'] = 'NoIntuneDevice'
            $rows.Add([pscustomobject]$row)
            continue
        }

        foreach ($device in $devices) {
            $entraDeviceId = ConvertTo-MdeGuid (Get-MdeProperty $device 'azureADDeviceId')
            $entraObjectId = ''
            $status = 'NoEntraDeviceId'
            if ($entraDeviceId) {
                $entra = $null
                if ($EntraDevices.ContainsKey($entraDeviceId)) { $entra = $EntraDevices[$entraDeviceId] }
                $entraObjectId = ConvertTo-MdeGuid (Get-MdeProperty $entra 'id')
                $status = if ($entraObjectId) { 'OK' } else { 'NoEntraObject' }
            }
            $row = [ordered]@{}
            foreach ($key in $base.Keys) { $row[$key] = $base[$key] }
            $row['DeviceName'] = [string](Get-MdeProperty $device 'deviceName')
            $row['OperatingSystem'] = [string](Get-MdeProperty $device 'operatingSystem')
            $row['OSVersion'] = [string](Get-MdeProperty $device 'osVersion')
            $row['Ownership'] = [string](Get-MdeProperty $device 'managedDeviceOwnerType')
            $row['ComplianceState'] = [string](Get-MdeProperty $device 'complianceState')
            $row['LastSyncDateTime'] = [string](Get-MdeProperty $device 'lastSyncDateTime')
            $row['SerialNumber'] = [string](Get-MdeProperty $device 'serialNumber')
            $row['Manufacturer'] = [string](Get-MdeProperty $device 'manufacturer')
            $row['Model'] = [string](Get-MdeProperty $device 'model')
            $row['IntuneDeviceId'] = [string](Get-MdeProperty $device 'id')
            $row['EntraDeviceId'] = $entraDeviceId
            $row['EntraDeviceObjectId'] = $entraObjectId
            $row['Status'] = $status
            $rows.Add([pscustomobject]$row)
        }
    }
    return , @($rows.ToArray() | Sort-Object ManagerUPN, UserPrincipalName, DeviceName)
}
