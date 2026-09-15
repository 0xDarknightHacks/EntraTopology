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
