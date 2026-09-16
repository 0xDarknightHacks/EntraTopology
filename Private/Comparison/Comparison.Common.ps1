function Get-EntraTopologyIndex {
    param([object[]]$Item)
    $h=@{};foreach($x in @($Item)){if($x.Key){$h[[string]$x.Key]=$x}};$h
}

function ConvertTo-EntraTopologyCanonicalComparisonValue {
    [CmdletBinding()]
    param([AllowNull()][object]$Value)

    if ($null -eq $Value) { return $null }

    if ($Value -is [datetime]) {
        return ([datetime]$Value).ToUniversalTime().ToString('o', [System.Globalization.CultureInfo]::InvariantCulture)
    }

    if ($Value -is [datetimeoffset]) {
        return ([datetimeoffset]$Value).ToUniversalTime().ToString('o', [System.Globalization.CultureInfo]::InvariantCulture)
    }

    if ($Value -is [string]) {
        # Graph/JSON round-trips can render the same instant with different
        # fractional-second precision (for example .274Z vs .2740000Z).
        # Normalize only strings that are unambiguously ISO-8601 timestamps.
        if ($Value -match '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$') {
            $parsed = [datetimeoffset]::MinValue
            if ([datetimeoffset]::TryParse(
                $Value,
                [System.Globalization.CultureInfo]::InvariantCulture,
                [System.Globalization.DateTimeStyles]::None,
                [ref]$parsed
            )) {
                return $parsed.ToUniversalTime().ToString('o', [System.Globalization.CultureInfo]::InvariantCulture)
            }
        }

        return $Value
    }

    if ($Value -is [System.Collections.IDictionary]) {
        $canonical = [ordered]@{}
        $keys = [string[]]@($Value.Keys | ForEach-Object { [string]$_ })
        [array]::Sort($keys, [System.StringComparer]::Ordinal)
        foreach ($key in $keys) {
            $canonical[$key] = ConvertTo-EntraTopologyCanonicalComparisonValue -Value $Value[$key]
        }
        return $canonical
    }

    if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])) {
        $items = @($Value | ForEach-Object { ConvertTo-EntraTopologyCanonicalComparisonValue -Value $_ })
        if ($items.Count -le 1) { return ,$items }

        # Collections exposed by the canonical Entra graph are semantic sets
        # (credentials, app roles, scopes, inherited roles, names, etc.). Graph
        # does not promise stable ordering, so sort canonical item JSON before
        # fingerprinting to avoid order-only drift between otherwise equal runs.
        $orderedItems = @(
            $items |
                ForEach-Object {
                    [pscustomobject]@{
                        Json  = ($_ | ConvertTo-Json -Compress -Depth 50)
                        Value = $_
                    }
                } |
                Sort-Object -Property Json -CaseSensitive |
                ForEach-Object { $_.Value }
        )
        return ,$orderedItems
    }

    $properties = @(
        $Value.PSObject.Properties |
            Where-Object { $_.MemberType -in @('NoteProperty','Property','AliasProperty') }
    )

    if ($properties.Count -gt 0 -and -not ($Value.GetType().IsPrimitive) -and -not ($Value -is [decimal])) {
        $canonical = [ordered]@{}
        $names = [string[]]@($properties.Name)
        [array]::Sort($names, [System.StringComparer]::Ordinal)
        foreach ($name in $names) {
            $canonical[$name] = ConvertTo-EntraTopologyCanonicalComparisonValue -Value $Value.PSObject.Properties[$name].Value
        }
        return $canonical
    }

    return $Value
}

function Get-EntraTopologySemanticFingerprint {
    param([Parameter(Mandatory)][object]$Item,[Parameter(Mandatory)][string]$Kind)
    $semantic=switch($Kind){
        'Node' {
            [ordered]@{Id=$Item.Id;TenantId=$Item.TenantId;Kind=$Item.Kind;DisplayName=$Item.DisplayName;Properties=$Item.Properties}
        }
        'Edge' {
            [ordered]@{From=$Item.From;To=$Item.To;Relationship=$Item.Relationship;Qualifier=$Item.Qualifier;State=$Item.State}
        }
        'Signal' {
            $signalReason = $Item.Reason
            $signalState = $Item.State

            # Credential-expiry signals include time-relative presentation fields
            # (daysRemaining and a human-readable countdown reason). Those values
            # change as time passes even when the credential itself is unchanged.
            # Exclude only that volatile material from semantic comparison while
            # retaining endDateTime, credentialType, expiryWindow and Severity so
            # real expiry/date/window transitions still produce drift.
            if ([string]$Item.Type -in @('credentialExpired','credentialExpiring')) {
                $signalReason = $null
                if ($null -ne $signalState) {
                    $filteredState = [ordered]@{}
                    if ($signalState -is [System.Collections.IDictionary]) {
                        foreach ($entry in $signalState.GetEnumerator()) {
                            if ([string]$entry.Key -ne 'daysRemaining') {
                                $filteredState[[string]$entry.Key] = $entry.Value
                            }
                        }
                    } else {
                        foreach ($property in @(
                            $signalState.PSObject.Properties |
                                Where-Object { $_.MemberType -in @('NoteProperty','Property','AliasProperty') }
                        )) {
                            if ([string]$property.Name -ne 'daysRemaining') {
                                $filteredState[[string]$property.Name] = $property.Value
                            }
                        }
                    }
                    $signalState = $filteredState
                }
            }

            [ordered]@{TargetKey=$Item.TargetKey;Type=$Item.Type;Severity=$Item.Severity;Reason=$signalReason;State=$signalState}
        }
        default { $Item }
    }

    $canonical = ConvertTo-EntraTopologyCanonicalComparisonValue -Value $semantic
    Get-EntraTopologyObjectFingerprint $canonical
}

function Compare-EntraTopologySet {
    param([object[]]$Reference,[object[]]$Difference,[string]$Kind)
    $a=Get-EntraTopologyIndex $Reference;$b=Get-EntraTopologyIndex $Difference;$out=[System.Collections.Generic.List[object]]::new()
    foreach($k in $b.Keys){
        if(-not$a.ContainsKey($k)){$out.Add([pscustomobject]@{Change='Added';Kind=$Kind;Key=$k;Before=$null;After=$b[$k]})}
        elseif((Get-EntraTopologySemanticFingerprint -Item $a[$k] -Kind $Kind)-ne(Get-EntraTopologySemanticFingerprint -Item $b[$k] -Kind $Kind)){$out.Add([pscustomobject]@{Change='Changed';Kind=$Kind;Key=$k;Before=$a[$k];After=$b[$k]})}
    }
    foreach($k in $a.Keys){if(-not$b.ContainsKey($k)){$out.Add([pscustomobject]@{Change='Removed';Kind=$Kind;Key=$k;Before=$a[$k];After=$null})}}
    @($out)
}

function Compare-EntraTopologyGraph {
    [CmdletBinding()] param([Parameter(Mandatory)][object]$ReferenceGraph,[Parameter(Mandatory)][object]$DifferenceGraph)
    if($ReferenceGraph.TenantId-ne$DifferenceGraph.TenantId){throw 'Graphs belong to different tenants.'}
    $changes=@();$changes+=Compare-EntraTopologySet $ReferenceGraph.Nodes $DifferenceGraph.Nodes 'Node';$changes+=Compare-EntraTopologySet $ReferenceGraph.Edges $DifferenceGraph.Edges 'Edge';$changes+=Compare-EntraTopologySet $ReferenceGraph.Signals $DifferenceGraph.Signals 'Signal'
    [pscustomobject][ordered]@{TenantId=$ReferenceGraph.TenantId;ComparedAtUtc=[datetime]::UtcNow.ToString('o');Summary=@{Added=@($changes|Where-Object Change -eq 'Added').Count;Removed=@($changes|Where-Object Change -eq 'Removed').Count;Changed=@($changes|Where-Object Change -eq 'Changed').Count};Changes=@($changes)}
}
