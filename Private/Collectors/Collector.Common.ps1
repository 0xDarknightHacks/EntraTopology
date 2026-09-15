function Get-EntraTopologyProperty {
    param([AllowNull()][object]$InputObject,[Parameter(Mandatory)][string]$Name)
    if ($null -eq $InputObject) { return $null }
    if ($InputObject -is [System.Collections.IDictionary]) {
        foreach ($key in $InputObject.Keys) { if ([string]$key -ieq $Name) { return $InputObject[$key] } }
        return $null
    }
    $p = $InputObject.PSObject.Properties | Where-Object Name -IEQ $Name | Select-Object -First 1
    if ($null -eq $p) { return $null }
    $p.Value
}

function New-EntraTopologyCollectorResult {
    param([Parameter(Mandatory)][string]$Name)
    [pscustomobject][ordered]@{
        Name=$Name; Status='Complete'; RequiredPermissions=@(); Objects=@(); Relations=@(); Evidence=@();
        Capabilities=@(); Warnings=@(); Metrics=@{}
    }
}

function Set-EntraTopologyCollectorNotRun {
    param([object]$Result,[string[]]$RequiredPermissions,[string]$Reason)
    $Result.Status='NotRun'; $Result.RequiredPermissions=@($RequiredPermissions); $Result.Warnings=@($Reason); $Result
}

function Set-EntraTopologyCollectorCapability {
    param(
        [Parameter(Mandatory)][object]$Result,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][ValidateSet('Complete','Partial','NotRun','Unavailable')][string]$Status,
        [string[]]$RequiredPermissions=@(),
        [string[]]$Endpoints=@(),
        [string[]]$Warnings=@()
    )
    $existing = @($Result.Capabilities | Where-Object { [string]$_.Name -eq $Name } | Select-Object -First 1)
    if ($existing.Count -gt 0) {
        $cap = $existing[0]
        $cap.Status=$Status; $cap.RequiredPermissions=@($RequiredPermissions); $cap.Endpoints=@($Endpoints); $cap.Warnings=@($Warnings)
    } else {
        $Result.Capabilities += [pscustomobject][ordered]@{
            Name=$Name; Status=$Status; RequiredPermissions=@($RequiredPermissions); Endpoints=@($Endpoints); Warnings=@($Warnings)
        }
    }
    $Result
}

function Add-EntraTopologyCollectorEvidence {
    param(
        [Parameter(Mandatory)][object]$Result,
        [Parameter(Mandatory)][string]$Capability,
        [Parameter(Mandatory)][string]$Endpoint,
        [Parameter(Mandatory)][string]$Status,
        [string]$RequiredPermission='Unknown',
        [int]$Count=0,
        [string[]]$Limitations=@(),
        [AllowNull()][string]$ErrorCode,
        [AllowNull()][string]$ErrorMessage,
        [AllowNull()][string]$RequestId,
        [int]$PageCount=0,
        [int]$RetryCount=0
    )
    $Result.Evidence += [pscustomobject][ordered]@{
        Capability=$Capability; Endpoint=$Endpoint; Status=$Status; RequiredPermission=$RequiredPermission; Count=$Count
        Limitations=@($Limitations); ErrorCode=$ErrorCode; ErrorMessage=$ErrorMessage; RequestId=$RequestId
        PageCount=$PageCount; RetryCount=$RetryCount; ObservedAtUtc=[datetime]::UtcNow.ToString('o')
    }
    $Result
}

function Add-EntraTopologyGraphResponseEvidence {
    param([Parameter(Mandatory)][object]$Result,[Parameter(Mandatory)][string]$Capability,[Parameter(Mandatory)][object]$Response)
    Add-EntraTopologyCollectorEvidence -Result $Result -Capability $Capability -Endpoint ([string]$Response.SourceEndpoint) `
        -Status ([string]$Response.Status) -RequiredPermission ([string]$Response.RequiredPermission) -Count @($Response.Items).Count `
        -Limitations @($Response.Limitations) -ErrorCode ([string]$Response.ErrorCode) -ErrorMessage ([string]$Response.ErrorMessage) `
        -RequestId ([string]$Response.RequestId) -PageCount ([int]$Response.PageCount) -RetryCount ([int]$Response.RetryCount) | Out-Null
}

function Add-EntraTopologyBatchEvidence {
    param([Parameter(Mandatory)][object]$Result,[Parameter(Mandatory)][string]$Capability,[Parameter(Mandatory)][object]$BatchResult,[string]$RequiredPermission='Unknown')
    $limitations = @()
    if ($BatchResult.ErrorMessage) { $limitations += [string]$BatchResult.ErrorMessage }
    Add-EntraTopologyCollectorEvidence -Result $Result -Capability $Capability -Endpoint ([string]$BatchResult.SourceEndpoint) `
        -Status ([string]$BatchResult.Status) -RequiredPermission $RequiredPermission -Count @($BatchResult.Items).Count `
        -Limitations $limitations -ErrorCode ([string]$BatchResult.ErrorCode) -ErrorMessage ([string]$BatchResult.ErrorMessage) `
        -RequestId ([string]$BatchResult.RequestId) -PageCount ([int]$BatchResult.PageCount) -RetryCount ([int]$BatchResult.RetryCount) | Out-Null
}

function Format-EntraTopologyBatchFailure {
    param([Parameter(Mandatory)][object]$BatchResult,[string]$Prefix='Graph batch request failed')
    $uri = if ($BatchResult.SourceEndpoint) { [string]$BatchResult.SourceEndpoint } else { '<unknown request>' }
    $parts = @("${Prefix}: $uri")
    if ($BatchResult.StatusCode) { $parts += "HTTP $($BatchResult.StatusCode)" }
    if ($BatchResult.ErrorCode) { $parts += "code=$($BatchResult.ErrorCode)" }
    if ($BatchResult.ErrorMessage) { $parts += [string]$BatchResult.ErrorMessage }
    if ($BatchResult.RequestId) { $parts += "request-id=$($BatchResult.RequestId)" }
    $parts -join '; '
}
