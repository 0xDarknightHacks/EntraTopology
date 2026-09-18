$script:EntraTopologyGraphHttpRequestCount = 0L

function Get-EntraTopologyGraphContext {
    [CmdletBinding()] param()
    try { return Get-MgContext -ErrorAction Stop } catch { return $null }
}
function Assert-EntraTopologyGraphConnected {
    [CmdletBinding()] param()
    $context = Get-EntraTopologyGraphContext
    if ($null -eq $context) { throw 'Not connected to Microsoft Graph. Run Connect-EntraTopologyGraph first.' }
    return $context
}
function Get-EntraTopologyGrantedPermissions {
    [CmdletBinding()] param()
    $ctx = Get-EntraTopologyGraphContext
    if ($null -eq $ctx) { return @() }
    return @($ctx.Scopes | ForEach-Object {[string]$_} | Where-Object {$_} | Sort-Object -Unique)
}
function Test-EntraTopologyPermission {
    [CmdletBinding()] param([Parameter(Mandatory)][string[]]$AnyOf)
    $granted = @(Get-EntraTopologyGrantedPermissions)
    foreach($p in $AnyOf){ if($granted -contains $p){ return $true } }
    return $false
}
function Test-EntraTopologyMayProbePermission {
    [CmdletBinding()] param([Parameter(Mandatory)][string[]]$AnyOf)
    $ctx = Get-EntraTopologyGraphContext
    if ($ctx -and [string](Get-EntraTopologyProperty $ctx 'AuthType') -eq 'AppOnly') {
        # Get-MgContext scope introspection is not authoritative for every application-permission
        # combination. Read-only optional capabilities should probe Graph and preserve the real
        # 403/404 response rather than being suppressed locally.
        return $true
    }
    Test-EntraTopologyPermission -AnyOf $AnyOf
}
function Add-EntraTopologyGraphTransportCall {
    [CmdletBinding()] param([ValidateRange(0,1000000)][int]$Count=1)
    $script:EntraTopologyGraphHttpRequestCount += $Count
}
function Get-EntraTopologyGraphTransportCallCount {
    [CmdletBinding()] param()
    [long]$script:EntraTopologyGraphHttpRequestCount
}
function Reset-EntraTopologyGraphTransportCallCount {
    [CmdletBinding()] param()
    $script:EntraTopologyGraphHttpRequestCount = 0L
}

function Get-EntraTopologyDefaultConfigPath {
    [CmdletBinding()] param()
    Join-Path (Join-Path $HOME '.entra-topology') 'config.json'
}

function Get-EntraTopologyStoredAppCredential {
    [CmdletBinding()]
    param(
        [string]$ConfigPath=(Get-EntraTopologyDefaultConfigPath),
        [string]$VaultName='EntraTopologyVault',
        [string]$SecretName='EntraTopologyGraphClientSecret'
    )

    if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
        throw "EntraTopology configuration file was not found: $ConfigPath"
    }

    try { $config = Get-Content -LiteralPath $ConfigPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop }
    catch { throw "EntraTopology configuration file is invalid JSON: $ConfigPath. $($_.Exception.Message)" }

    $tenantId = [string](Get-EntraTopologyProperty $config 'TenantId')
    $clientId = [string](Get-EntraTopologyProperty $config 'ClientId')
    if ([string]::IsNullOrWhiteSpace($tenantId) -or [string]::IsNullOrWhiteSpace($clientId)) {
        throw "EntraTopology configuration must contain non-empty TenantId and ClientId values: $ConfigPath"
    }

    $configPropertyNames=@($config.PSObject.Properties | ForEach-Object {[string]$_.Name})
    foreach ($forbiddenName in @('ClientSecret','Secret','SecretValue','ClientSecretValue')) {
        if ($configPropertyNames -contains $forbiddenName) {
            throw "Do not store client secrets in $ConfigPath. Store the secret in a SecretManagement vault instead."
        }
    }

    if (-not (Get-Command Get-Secret -ErrorAction SilentlyContinue)) {
        try { Import-Module Microsoft.PowerShell.SecretManagement -ErrorAction Stop }
        catch { throw 'Microsoft.PowerShell.SecretManagement is required for stored client-secret authentication. Install it and register a SecretManagement vault first.' }
    }

    try { $secret = Get-Secret -Name $SecretName -Vault $VaultName -ErrorAction Stop }
    catch { throw "Unable to retrieve secret '$SecretName' from vault '$VaultName'. $($_.Exception.Message)" }
    if ($null -eq $secret) { throw "Secret '$SecretName' was not found in vault '$VaultName'." }

    $secureSecret = $null
    if ($secret -is [System.Security.SecureString]) { $secureSecret = $secret }
    elseif ($secret -is [System.Management.Automation.PSCredential]) { $secureSecret = $secret.Password }
    elseif ($secret -is [string]) { $secureSecret = ConvertTo-SecureString -String $secret -AsPlainText -Force }
    else { throw "Secret '$SecretName' must be stored as String, SecureString, or PSCredential." }

    [pscustomobject][ordered]@{
        TenantId=$tenantId
        ClientId=$clientId
        ClientSecretCredential=[System.Management.Automation.PSCredential]::new($clientId,$secureSecret)
        ConfigPath=$ConfigPath
        VaultName=$VaultName
        SecretName=$SecretName
    }
}


function Get-EntraTopologyResponseHeaderValue {
    param([AllowNull()][object]$Headers,[Parameter(Mandatory)][string]$Name)
    if ($null -eq $Headers) { return $null }
    try {
        if ($Headers -is [System.Collections.IDictionary]) {
            foreach ($key in $Headers.Keys) { if ([string]$key -ieq $Name) { return [string]$Headers[$key] } }
        }
        if ($Headers.PSObject.Methods.Name -contains 'Contains') {
            if ($Headers.Contains($Name)) { return [string](($Headers.GetValues($Name) | Select-Object -First 1)) }
        }
        $property = $Headers.PSObject.Properties | Where-Object Name -IEQ $Name | Select-Object -First 1
        if ($property) { return [string]$property.Value }
    } catch {}
    return $null
}

function Get-EntraTopologyRetryDelaySeconds {
    param([AllowNull()][object]$Headers,[int]$RetryIndex=0)
    $raw = Get-EntraTopologyResponseHeaderValue -Headers $Headers -Name 'Retry-After'
    if (-not [string]::IsNullOrWhiteSpace($raw)) {
        [double]$seconds = 0
        if ([double]::TryParse($raw, [ref]$seconds)) { return [math]::Max(0, $seconds) }
        [datetime]$when = [datetime]::MinValue
        if ([datetime]::TryParse($raw, [ref]$when)) {
            return [math]::Max(0, ($when.ToUniversalTime() - [datetime]::UtcNow).TotalSeconds)
        }
    }
    return [math]::Min([math]::Pow(2, [math]::Min($RetryIndex, 6)) + (Get-Random -Minimum 0 -Maximum 1000) / 1000.0, 60)
}

function ConvertFrom-EntraTopologyGraphErrorContent {
    param([AllowNull()][string]$Raw)
    $result = [ordered]@{ Code=$null; Message=$null; RequestId=$null; Details=$null }
    if ([string]::IsNullOrWhiteSpace($Raw)) { return [pscustomobject]$result }
    try {
        $content = $Raw | ConvertFrom-Json -Depth 20
        $errorObject = if ($content.PSObject.Properties['error']) { $content.error } else { $content }
        if ($errorObject.PSObject.Properties['code']) { $result.Code = [string]$errorObject.code }
        if ($errorObject.PSObject.Properties['message']) { $result.Message = [string]$errorObject.message }
        if ($errorObject.PSObject.Properties['innerError']) {
            $inner = $errorObject.innerError
            if ($inner.PSObject.Properties['request-id']) { $result.RequestId = [string]$inner.'request-id' }
            elseif ($inner.PSObject.Properties['requestId']) { $result.RequestId = [string]$inner.requestId }
        }
        $result.Details = $content
    } catch {
        $result.Message = $Raw
    }
    [pscustomobject]$result
}


function Get-EntraTopologyExceptionResponseInfo {
    param([Parameter(Mandatory)][object]$ErrorRecord)
    $exception = if ($ErrorRecord.PSObject.Properties['Exception']) { $ErrorRecord.Exception } else { $ErrorRecord }
    $response = $null
    try { if ($exception.PSObject.Properties['Response']) { $response = $exception.Response } } catch {}
    if ($null -eq $response) { try { if ($exception.InnerException -and $exception.InnerException.PSObject.Properties['Response']) { $response = $exception.InnerException.Response } } catch {} }

    $statusCode = 0; $headers = $null; $raw = $null; $requestId = $null
    if ($null -ne $response) {
        try { $statusCode = [int]$response.StatusCode } catch {}
        try { $headers = $response.Headers } catch {}
        try { if ($response.Content) { $raw = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult() } } catch {}
    }
    if ([string]::IsNullOrWhiteSpace([string]$raw)) {
        try { if ($exception.PSObject.Properties['ResponseBody']) { $raw = [string]$exception.ResponseBody } } catch {}
    }
    if ([string]::IsNullOrWhiteSpace([string]$raw)) {
        try { if ($ErrorRecord.PSObject.Properties['ErrorDetails'] -and $ErrorRecord.ErrorDetails) { $raw = [string]$ErrorRecord.ErrorDetails.Message } } catch {}
    }
    $parsed = ConvertFrom-EntraTopologyGraphErrorContent -Raw ([string]$raw)
    $requestId = if ($parsed.RequestId) { [string]$parsed.RequestId } else { Get-EntraTopologyResponseHeaderValue -Headers $headers -Name 'request-id' }
    $message = if ($parsed.Message) { [string]$parsed.Message } else { [string]$exception.Message }
    [pscustomobject][ordered]@{StatusCode=$statusCode;Headers=$headers;Raw=$raw;ErrorCode=$parsed.Code;ErrorMessage=$message;RequestId=$requestId}
}

function Invoke-EntraTopologyGraphRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Uri,
        [ValidateSet('GET','POST')][string]$Method = 'GET',
        [AllowNull()][object]$Body,
        [string]$RequiredPermission = 'Unknown',
        [ValidateRange(0,10)][int]$MaxRetries = 5,
        [AllowNull()][object]$Telemetry
    )

    Assert-EntraTopologyGraphConnected | Out-Null
    $originalUri = $Uri
    $currentMethod = $Method
    $currentBody = $Body
    $items = [System.Collections.Generic.List[object]]::new()
    $retryCount = 0
    $pageCount = 0

    while (-not [string]::IsNullOrWhiteSpace($Uri)) {
        try {
            if ($Telemetry) { Add-EntraTopologyTelemetryRequest -Telemetry $Telemetry }
            Add-EntraTopologyGraphTransportCall
            $requestParams = @{ Uri=$Uri; Method=$currentMethod; OutputType='HttpResponseMessage'; ErrorAction='Stop' }
            if ($null -ne $currentBody) {
                # Invoke-MgGraphRequest may hand PowerShell-adapted objects to Newtonsoft.Json,
                # which can recurse into adapted properties (for example String.Chars). Serialize
                # request bodies here so POST payloads are plain JSON on the transport boundary.
                $requestParams.Body = if ($currentBody -is [string]) { $currentBody } else { $currentBody | ConvertTo-Json -Depth 50 -Compress }
                $requestParams.ContentType = 'application/json'
            }
            $response = Invoke-MgGraphRequest @requestParams
            $status = [int]$response.StatusCode
            $raw = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
            $errorInfo = if ($response.IsSuccessStatusCode) { $null } else { ConvertFrom-EntraTopologyGraphErrorContent -Raw $raw }

            if ($status -in @(429,500,502,503,504)) {
                if ($retryCount -ge $MaxRetries) {
                    $message = if ($errorInfo -and $errorInfo.Message) { $errorInfo.Message } else { "HTTP $status after $retryCount retries." }
                    return [pscustomobject][ordered]@{
                        SourceEndpoint=$originalUri; RequiredPermission=$RequiredPermission; Status='Failed'; StatusCode=$status
                        Items=@($items); CollectionTime=[datetime]::UtcNow.ToString('o'); Limitations=@($message)
                        ErrorCode=$(if($errorInfo){$errorInfo.Code}else{$null}); ErrorMessage=$message
                        RequestId=$(if($errorInfo -and $errorInfo.RequestId){$errorInfo.RequestId}else{Get-EntraTopologyResponseHeaderValue -Headers $response.Headers -Name 'request-id'})
                        RetryCount=$retryCount; PageCount=$pageCount
                    }
                }
                $delay = Get-EntraTopologyRetryDelaySeconds -Headers $response.Headers -RetryIndex $retryCount
                $retryCount++
                if ($Telemetry) { $Telemetry.Retries++; if($status -eq 429){$Telemetry.Throttles++} }
                Start-Sleep -Seconds $delay
                continue
            }

            if (-not $response.IsSuccessStatusCode) {
                $message = if ($errorInfo -and $errorInfo.Message) { $errorInfo.Message } else { "HTTP $status" }
                return [pscustomobject][ordered]@{
                    SourceEndpoint=$originalUri; RequiredPermission=$RequiredPermission
                    Status=$(switch($status){403{'InsufficientPermission'};404{'NotFound'};default{'Failed'}}); StatusCode=$status
                    Items=@($items); CollectionTime=[datetime]::UtcNow.ToString('o'); Limitations=@($message)
                    ErrorCode=$(if($errorInfo){$errorInfo.Code}else{$null}); ErrorMessage=$message
                    RequestId=$(if($errorInfo -and $errorInfo.RequestId){$errorInfo.RequestId}else{Get-EntraTopologyResponseHeaderValue -Headers $response.Headers -Name 'request-id'})
                    RetryCount=$retryCount; PageCount=$pageCount
                }
            }

            $content = if ([string]::IsNullOrWhiteSpace($raw)) { $null } else { $raw | ConvertFrom-Json -Depth 50 }
            $pageCount++
            if ($null -eq $content) { $Uri = $null; continue }

            $value = $content.PSObject.Properties['value']
            if ($null -ne $value) {
                foreach ($x in @($value.Value)) { if ($null -ne $x) { $items.Add($x) } }
            } else {
                $items.Add($content)
            }
            $next = $content.PSObject.Properties['@odata.nextLink']
            $Uri = if ($null -ne $next) { [string]$next.Value } else { $null }
            if ($Uri) { $currentMethod='GET'; $currentBody=$null }
        } catch {
            $exceptionInfo = Get-EntraTopologyExceptionResponseInfo -ErrorRecord $_
            $exceptionStatus = [int]$exceptionInfo.StatusCode
            $retriable = $exceptionStatus -in @(429,500,502,503,504) -or $exceptionStatus -eq 0
            if ($retriable -and $retryCount -lt $MaxRetries) {
                $delay = if ($exceptionStatus -gt 0) { Get-EntraTopologyRetryDelaySeconds -Headers $exceptionInfo.Headers -RetryIndex $retryCount } else { [math]::Min([math]::Pow(2, [math]::Min($retryCount + 1, 6)), 30) }
                $retryCount++
                if ($Telemetry) { $Telemetry.Retries++; if($exceptionStatus -eq 429){$Telemetry.Throttles++} }
                Start-Sleep -Seconds $delay
                continue
            }
            $statusName = if ($exceptionStatus -eq 403) { 'InsufficientPermission' } elseif ($exceptionStatus -eq 404) { 'NotFound' } else { 'Failed' }
            return [pscustomobject][ordered]@{
                SourceEndpoint=$originalUri; RequiredPermission=$RequiredPermission; Status=$statusName; StatusCode=$exceptionStatus
                Items=@($items); CollectionTime=[datetime]::UtcNow.ToString('o'); Limitations=@($exceptionInfo.ErrorMessage)
                ErrorCode=$(if($exceptionInfo.ErrorCode){$exceptionInfo.ErrorCode}else{$_.Exception.GetType().FullName}); ErrorMessage=$exceptionInfo.ErrorMessage; RequestId=$exceptionInfo.RequestId
                RetryCount=$retryCount; PageCount=$pageCount
            }
        }
    }

    [pscustomobject][ordered]@{
        SourceEndpoint=$originalUri; RequiredPermission=$RequiredPermission; Status='Success'; StatusCode=200
        Items=@($items); CollectionTime=[datetime]::UtcNow.ToString('o'); Limitations=@()
        ErrorCode=$null; ErrorMessage=$null; RequestId=$null; RetryCount=$retryCount; PageCount=$pageCount
    }
}


function Get-EntraTopologyBatchProperty {
    param([AllowNull()][object]$InputObject,[Parameter(Mandatory)][string]$Name)
    if ($null -eq $InputObject) { return $null }
    if ($InputObject -is [System.Collections.IDictionary]) {
        foreach ($key in $InputObject.Keys) { if ([string]$key -ieq $Name) { return $InputObject[$key] } }
        return $null
    }
    $property = $InputObject.PSObject.Properties | Where-Object Name -IEQ $Name | Select-Object -First 1
    if ($property) { return $property.Value }
    return $null
}


function Get-EntraTopologyBatchPropertyInfo {
    param([AllowNull()][object]$InputObject,[Parameter(Mandatory)][string]$Name)
    if ($null -eq $InputObject) { return [pscustomobject]@{Exists=$false;Value=$null} }
    if ($InputObject -is [System.Collections.IDictionary]) {
        foreach ($key in $InputObject.Keys) {
            if ([string]$key -ieq $Name) { return [pscustomobject]@{Exists=$true;Value=$InputObject[$key]} }
        }
        return [pscustomobject]@{Exists=$false;Value=$null}
    }
    $property = $InputObject.PSObject.Properties | Where-Object Name -IEQ $Name | Select-Object -First 1
    if ($property) { return [pscustomobject]@{Exists=$true;Value=$property.Value} }
    [pscustomobject]@{Exists=$false;Value=$null}
}

function ConvertTo-EntraTopologyBatchRelativeUrl {
    param([Parameter(Mandatory)][string]$Uri)
    if ($Uri -match '^https://graph\.microsoft\.com/(v1\.0|beta)(/.*)$') { return $Matches[2] }
    if ($Uri -match '^/(v1\.0|beta)(/.*)$') { return $Matches[2] }
    if (-not $Uri.StartsWith('/')) { return "/$Uri" }
    return $Uri
}

function Get-EntraTopologyBatchRetryAfter {
    param([AllowNull()][object]$Headers,[int]$RetryIndex=0)
    $raw = Get-EntraTopologyBatchProperty -InputObject $Headers -Name 'Retry-After'
    if (-not [string]::IsNullOrWhiteSpace([string]$raw)) {
        [double]$seconds = 0
        if ([double]::TryParse([string]$raw, [ref]$seconds)) { return [math]::Max(0, $seconds) }
        [datetime]$when = [datetime]::MinValue
        if ([datetime]::TryParse([string]$raw, [ref]$when)) { return [math]::Max(0, ($when.ToUniversalTime() - [datetime]::UtcNow).TotalSeconds) }
    }
    return [math]::Min([math]::Pow(2, [math]::Min($RetryIndex, 6)) + (Get-Random -Minimum 0 -Maximum 1000) / 1000.0, 60)
}

function New-EntraTopologyBatchResult {
    param(
        [Parameter(Mandatory)][object]$State,
        [Parameter(Mandatory)][string]$Status,
        [int]$StatusCode=0,
        [AllowNull()][string]$ErrorCode,
        [AllowNull()][string]$ErrorMessage,
        [AllowNull()][string]$RequestId
    )
    [pscustomobject][ordered]@{
        Request=$State.Request
        SourceEndpoint=[string]$State.OriginalUri
        LastEndpoint=[string]$State.Uri
        Status=$Status
        StatusCode=$StatusCode
        Items=@($State.Items)
        Error=$ErrorMessage
        ErrorCode=$ErrorCode
        ErrorMessage=$ErrorMessage
        RequestId=$RequestId
        AttemptCount=[int]$State.AttemptCount
        RetryCount=[int]$State.RetryCount
        PageCount=[int]$State.PageCount
    }
}

function Invoke-EntraTopologyGraphBatch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Requests,
        [ValidateRange(1,20)][int]$BatchSize=20,
        [ValidateRange(0,10)][int]$MaxRetries=5,
        [ValidateRange(1,10000)][int]$MaxPagesPerRequest=1000,
        [AllowNull()][object]$Telemetry
    )

    Assert-EntraTopologyGraphConnected | Out-Null
    if ($Requests.Count -eq 0) { return @() }

    $results = [System.Collections.Generic.List[object]]::new()
    $pending = [System.Collections.Generic.List[object]]::new()
    foreach ($request in $Requests) {
        $uri = [string](Get-EntraTopologyBatchProperty -InputObject $request -Name 'Uri')
        if ([string]::IsNullOrWhiteSpace($uri)) {
            $state = [pscustomobject]@{Request=$request;OriginalUri='';Uri='';Items=[System.Collections.Generic.List[object]]::new();AttemptCount=0;RetryCount=0;PageCount=0}
            $results.Add((New-EntraTopologyBatchResult -State $state -Status 'Failed' -ErrorCode 'InvalidBatchRequest' -ErrorMessage 'Batch request is missing Uri.'))
            continue
        }
        $pending.Add([pscustomobject]@{
            Request=$request; OriginalUri=$uri; Uri=$uri; Items=[System.Collections.Generic.List[object]]::new()
            AttemptCount=0; RetryCount=0; PageCount=0
        })
    }
    if ($Telemetry) { Add-EntraTopologyTelemetryRequest -Telemetry $Telemetry -Logical $pending.Count -Http 0 }

    while ($pending.Count -gt 0) {
        $take = [math]::Min($BatchSize, $pending.Count)
        $slice = @($pending.GetRange(0, $take))
        $pending.RemoveRange(0, $take)

        $idMap = @{}
        $batch = @()
        for ($i=0; $i -lt $slice.Count; $i++) {
            $state = $slice[$i]
            $state.AttemptCount++
            $id = [string]($i + 1)
            $idMap[$id] = $state
            $batch += [ordered]@{ id=$id; method='GET'; url=(ConvertTo-EntraTopologyBatchRelativeUrl -Uri ([string]$state.Uri)) }
        }

        if ($Telemetry) { Add-EntraTopologyTelemetryRequest -Telemetry $Telemetry -Logical 0 -Http 1 }
        Add-EntraTopologyGraphTransportCall
        try {
            $response = Invoke-MgGraphRequest -Uri '/v1.0/$batch' -Method POST -Body (@{requests=$batch} | ConvertTo-Json -Depth 12) -ContentType 'application/json' -OutputType PSObject -ErrorAction Stop
        } catch {
            $exceptionInfo = Get-EntraTopologyExceptionResponseInfo -ErrorRecord $_
            $statusCode = [int]$exceptionInfo.StatusCode
            $retriable = $statusCode -in @(429,500,502,503,504) -or $statusCode -eq 0
            $retryStates = @()
            foreach ($state in $slice) {
                if ($retriable -and $state.RetryCount -lt $MaxRetries) {
                    $state.RetryCount++
                    if ($Telemetry) { $Telemetry.Retries++; if($statusCode -eq 429){$Telemetry.Throttles++} }
                    $retryStates += $state
                } else {
                    $statusName = if($statusCode -eq 403){'InsufficientPermission'}elseif($statusCode -eq 404){'NotFound'}else{'Failed'}
                    $results.Add((New-EntraTopologyBatchResult -State $state -Status $statusName -StatusCode $statusCode -ErrorCode $(if($exceptionInfo.ErrorCode){$exceptionInfo.ErrorCode}else{$_.Exception.GetType().FullName}) -ErrorMessage $exceptionInfo.ErrorMessage -RequestId $exceptionInfo.RequestId))
                }
            }
            if ($retryStates.Count -gt 0) {
                $delay = if($statusCode -gt 0){Get-EntraTopologyRetryDelaySeconds -Headers $exceptionInfo.Headers -RetryIndex ($retryStates[0].RetryCount-1)}else{[math]::Min([math]::Pow(2,[math]::Min($retryStates[0].RetryCount,6)),30)}
                Start-Sleep -Seconds $delay
                foreach ($state in $retryStates) { $pending.Add($state) }
            }
            continue
        }

        $parts = @(Get-EntraTopologyBatchProperty -InputObject $response -Name 'responses')
        $seen = @{}
        $maxRetryDelay = 0.0

        foreach ($part in $parts) {
            $partId = [string](Get-EntraTopologyBatchProperty -InputObject $part -Name 'id')
            if ([string]::IsNullOrWhiteSpace($partId) -or -not $idMap.ContainsKey($partId)) { continue }
            $seen[$partId] = $true
            $state = $idMap[$partId]
            $status = [int](Get-EntraTopologyBatchProperty -InputObject $part -Name 'status')
            $body = Get-EntraTopologyBatchProperty -InputObject $part -Name 'body'
            $headers = Get-EntraTopologyBatchProperty -InputObject $part -Name 'headers'
            $requestId = [string](Get-EntraTopologyBatchProperty -InputObject $headers -Name 'request-id')

            if ($status -ge 200 -and $status -lt 300) {
                $state.PageCount++
                $valueInfo = Get-EntraTopologyBatchPropertyInfo -InputObject $body -Name 'value'
                if ($valueInfo.Exists) {
                    foreach ($item in @($valueInfo.Value)) { if ($null -ne $item) { $state.Items.Add($item) } }
                } elseif ($null -ne $body) {
                    $state.Items.Add($body)
                }

                $nextLink = [string](Get-EntraTopologyBatchProperty -InputObject $body -Name '@odata.nextLink')
                if (-not [string]::IsNullOrWhiteSpace($nextLink)) {
                    if ($state.PageCount -ge $MaxPagesPerRequest) {
                        $results.Add((New-EntraTopologyBatchResult -State $state -Status 'Failed' -StatusCode $status -ErrorCode 'BatchPaginationLimitExceeded' -ErrorMessage "Exceeded $MaxPagesPerRequest pages for $($state.OriginalUri)." -RequestId $requestId))
                    } else {
                        $state.Uri = $nextLink
                        $pending.Add($state)
                    }
                } else {
                    $results.Add((New-EntraTopologyBatchResult -State $state -Status 'Success' -StatusCode $status -RequestId $requestId))
                }
                continue
            }

            $errorObject = Get-EntraTopologyBatchProperty -InputObject $body -Name 'error'
            if ($null -eq $errorObject) { $errorObject = Get-EntraTopologyBatchProperty -InputObject $part -Name 'error' }
            $errorCode = [string](Get-EntraTopologyBatchProperty -InputObject $errorObject -Name 'code')
            $errorMessage = [string](Get-EntraTopologyBatchProperty -InputObject $errorObject -Name 'message')
            if ([string]::IsNullOrWhiteSpace($errorMessage)) { $errorMessage = "HTTP $status" }

            if ($status -in @(429,500,502,503,504) -and $state.RetryCount -lt $MaxRetries) {
                $delay = Get-EntraTopologyBatchRetryAfter -Headers $headers -RetryIndex $state.RetryCount
                $maxRetryDelay = [math]::Max($maxRetryDelay, $delay)
                $state.RetryCount++
                if ($Telemetry) { $Telemetry.Retries++; if($status -eq 429){$Telemetry.Throttles++} }
                $pending.Add($state)
                continue
            }

            $finalStatus = if ($status -eq 403) { 'InsufficientPermission' } elseif ($status -eq 404) { 'NotFound' } else { 'Failed' }
            $results.Add((New-EntraTopologyBatchResult -State $state -Status $finalStatus -StatusCode $status -ErrorCode $errorCode -ErrorMessage $errorMessage -RequestId $requestId))
        }

        foreach ($id in $idMap.Keys) {
            if ($seen.ContainsKey($id)) { continue }
            $state = $idMap[$id]
            $results.Add((New-EntraTopologyBatchResult -State $state -Status 'Failed' -ErrorCode 'BatchResponseMissing' -ErrorMessage "The batch response did not contain a correlated response for request id $id ($($state.Uri))."))
        }

        if ($maxRetryDelay -gt 0) { Start-Sleep -Seconds $maxRetryDelay }
    }

    @($results)
}

