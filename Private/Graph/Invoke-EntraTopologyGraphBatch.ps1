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
