function Get-EntraTopologyMonitorPropertyValue {
    [CmdletBinding()]
    param(
        [AllowNull()][object]$InputObject,
        [Parameter(Mandatory)][string]$Name
    )

    if ($null -eq $InputObject) { return $null }

    if ($InputObject -is [System.Collections.IDictionary]) {
        if ($InputObject.Contains($Name)) { return $InputObject[$Name] }
        return $null
    }

    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -ne $property) { return $property.Value }
    return $null
}

function ConvertTo-EntraTopologyMonitorHtmlEncoded {
    [CmdletBinding()]
    param([AllowNull()][object]$Value)

    if ($null -eq $Value) { return '' }
    return [System.Net.WebUtility]::HtmlEncode([string]$Value)
}

function ConvertTo-EntraTopologyMonitorDisplayDate {
    [CmdletBinding()]
    param([AllowNull()][object]$Value)

    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) { return '' }

    $parsed = [datetimeoffset]::MinValue
    if ([datetimeoffset]::TryParse(
        [string]$Value,
        [System.Globalization.CultureInfo]::InvariantCulture,
        [System.Globalization.DateTimeStyles]::AllowWhiteSpaces,
        [ref]$parsed
    )) {
        return $parsed.ToUniversalTime().ToString('dd MMM yyyy HH:mm ''UTC''', [System.Globalization.CultureInfo]::InvariantCulture)
    }

    return [string]$Value
}

function Limit-EntraTopologyMonitorText {
    [CmdletBinding()]
    param(
        [AllowNull()][string]$Text,
        [int]$MaximumLength = 220
    )

    if ([string]::IsNullOrWhiteSpace($Text)) { return '' }
    $normalized = ($Text -replace '\s+', ' ').Trim()
    if ($normalized.Length -le $MaximumLength) { return $normalized }
    return $normalized.Substring(0, [Math]::Max(1, $MaximumLength - 1)).TrimEnd() + '…'
}

function Get-EntraTopologyMonitorSeverityRank {
    [CmdletBinding()]
    param([AllowNull()][string]$Severity)

    switch ($Severity) {
        'Critical' { return 4 }
        'High'     { return 3 }
        'Medium'   { return 2 }
        'Low'      { return 1 }
        default    { return 0 }
    }
}

function New-EntraTopologyMonitorLookup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Graph,
        [AllowNull()][object]$Baseline
    )

    $nodeByKey = @{}
    $nodeById = @{}
    $edgeByKey = @{}

    foreach ($source in @($Baseline, $Graph)) {
        if ($null -ne $source) {
            foreach ($node in @(Get-EntraTopologyMonitorPropertyValue -InputObject $source -Name 'Nodes')) {
                if ($null -ne $node) {
                    $key = [string](Get-EntraTopologyMonitorPropertyValue -InputObject $node -Name 'Key')
                    $id = [string](Get-EntraTopologyMonitorPropertyValue -InputObject $node -Name 'Id')
                    if (-not [string]::IsNullOrWhiteSpace($key)) { $nodeByKey[$key] = $node }
                    if (-not [string]::IsNullOrWhiteSpace($id)) { $nodeById[$id] = $node }
                }
            }

            foreach ($edge in @(Get-EntraTopologyMonitorPropertyValue -InputObject $source -Name 'Edges')) {
                if ($null -ne $edge) {
                    $key = [string](Get-EntraTopologyMonitorPropertyValue -InputObject $edge -Name 'Key')
                    if (-not [string]::IsNullOrWhiteSpace($key)) { $edgeByKey[$key] = $edge }
                }
            }
        }
    }

    [pscustomobject][ordered]@{
        NodeByKey = $nodeByKey
        NodeById  = $nodeById
        EdgeByKey = $edgeByKey
    }
}

function Get-EntraTopologyMonitorNodeDisplayName {
    [CmdletBinding()]
    param(
        [AllowNull()][string]$Key,
        [Parameter(Mandatory)][object]$Lookup
    )

    if ([string]::IsNullOrWhiteSpace($Key)) { return 'Unknown object' }
    if (-not $Lookup.NodeByKey.ContainsKey($Key)) { return $Key }

    $node = $Lookup.NodeByKey[$Key]
    $displayName = [string](Get-EntraTopologyMonitorPropertyValue -InputObject $node -Name 'DisplayName')
    if (-not [string]::IsNullOrWhiteSpace($displayName)) { return $displayName }

    $id = [string](Get-EntraTopologyMonitorPropertyValue -InputObject $node -Name 'Id')
    if (-not [string]::IsNullOrWhiteSpace($id)) { return $id }
    return $Key
}

function Get-EntraTopologyMonitorPortalUri {
    [CmdletBinding()]
    param([AllowNull()][object]$Node)

    if ($null -eq $Node) { return '' }
    $properties = Get-EntraTopologyMonitorPropertyValue -InputObject $Node -Name 'Properties'
    $portalUri = [string](Get-EntraTopologyMonitorPropertyValue -InputObject $properties -Name 'portalUri')
    if ($portalUri -match '^https://entra\.microsoft\.com/') { return $portalUri }
    return ''
}

function Get-EntraTopologyMonitorChangeItem {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Change)

    $after = Get-EntraTopologyMonitorPropertyValue -InputObject $Change -Name 'After'
    if ($null -ne $after) { return $after }
    return Get-EntraTopologyMonitorPropertyValue -InputObject $Change -Name 'Before'
}

function Get-EntraTopologyMonitorCredentialTypeName {
    [CmdletBinding()]
    param([AllowNull()][string]$CredentialType)

    switch ($CredentialType) {
        'keyCredential'      { return 'Certificate' }
        'passwordCredential' { return 'Client secret' }
        default {
            if ([string]::IsNullOrWhiteSpace($CredentialType)) { return 'Credential' }
            return $CredentialType
        }
    }
}

function Get-EntraTopologyMonitorSignalTitle {
    [CmdletBinding()]
    param([AllowNull()][string]$SignalType)

    switch ($SignalType) {
        'highPrivilegeRoleAssignment'      { return 'High-impact directory role assignment' }
        'highImpactApplicationPermission'  { return 'High-impact application permission' }
        'highImpactDelegatedPermission'    { return 'High-impact delegated permission' }
        'privilegedOwnerRelationship'      { return 'Privileged owner relationship' }
        'ownerlessObject'                  { return 'Ownerless Entra object' }
        'credentialExpired'                { return 'Expired application credential' }
        'credentialExpiring'               { return 'Expiring application credential' }
        'riskyIdentity'                    { return 'Risky identity' }
        'riskyOwnerRelationship'           { return 'Risky owner relationship' }
        'highImpactRequestedPermission'    { return 'High-impact requested permission' }
        'disabledOwnerRelationship'        { return 'Disabled owner relationship' }
        'disabledIdentity'                 { return 'Disabled identity' }
        'disabledWorkloadIdentity'         { return 'Disabled workload identity' }
        'staleDevice'                      { return 'Stale device' }
        'guestOwnerRelationship'           { return 'Guest owner relationship' }
        'privilegedIdentity'               { return 'Privileged identity' }
        default {
            if ([string]::IsNullOrWhiteSpace($SignalType)) { return 'Security context change' }
            return $SignalType
        }
    }
}

function Get-EntraTopologyMonitorRelationshipTitle {
    [CmdletBinding()]
    param([AllowNull()][string]$Relationship)

    switch ($Relationship) {
        'assignedDirectoryRole'  { return 'Directory role assignment' }
        'hasAppRoleAssignment'   { return 'Application permission assignment' }
        'hasDelegatedPermission' { return 'Delegated permission grant' }
        'hasCredential'          { return 'Application credential relationship' }
        'owns'                   { return 'Ownership relationship' }
        'registeredOwnerOf'      { return 'Registered owner relationship' }
        'memberOf'               { return 'Group membership' }
        'requiresApiPermission'  { return 'Requested API permission' }
        'instantiatedAs'         { return 'Application / service principal relationship' }
        default {
            if ([string]::IsNullOrWhiteSpace($Relationship)) { return 'Relationship' }
            return "$Relationship relationship"
        }
    }
}

function Get-EntraTopologyMonitorChangeVerb {
    [CmdletBinding()]
    param([AllowNull()][string]$Change)

    switch ($Change) {
        'Added'   { return 'added' }
        'Removed' { return 'removed' }
        'Changed' { return 'changed' }
        default   { return 'observed' }
    }
}

function New-EntraTopologyMonitorAlert {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Change,
        [Parameter(Mandatory)][ValidateSet('Info','Low','Medium','High','Critical')][string]$Severity,
        [Parameter(Mandatory)][object]$Lookup
    )

    $item = Get-EntraTopologyMonitorChangeItem -Change $Change
    $changeType = [string](Get-EntraTopologyMonitorPropertyValue -InputObject $Change -Name 'Change')
    $kind = [string](Get-EntraTopologyMonitorPropertyValue -InputObject $Change -Name 'Kind')
    $key = [string](Get-EntraTopologyMonitorPropertyValue -InputObject $Change -Name 'Key')
    $verb = Get-EntraTopologyMonitorChangeVerb -Change $changeType

    $title = "$kind $verb"
    $primary = $key
    $detail = ''
    $reason = ''
    $portalUri = ''
    $groupKey = "$changeType|$kind|$key"
    $relationship = ''
    $signalType = ''

    switch ($kind) {
        'Edge' {
            $relationship = [string](Get-EntraTopologyMonitorPropertyValue -InputObject $item -Name 'Relationship')
            $fromKey = [string](Get-EntraTopologyMonitorPropertyValue -InputObject $item -Name 'From')
            $toKey = [string](Get-EntraTopologyMonitorPropertyValue -InputObject $item -Name 'To')
            $fromName = Get-EntraTopologyMonitorNodeDisplayName -Key $fromKey -Lookup $Lookup
            $toName = Get-EntraTopologyMonitorNodeDisplayName -Key $toKey -Lookup $Lookup
            $state = Get-EntraTopologyMonitorPropertyValue -InputObject $item -Name 'State'

            $title = "$(Get-EntraTopologyMonitorRelationshipTitle -Relationship $relationship) $verb"
            $primary = "$fromName → $toName"
            $groupKey = "$changeType|Edge|$key"

            switch ($relationship) {
                'assignedDirectoryRole' {
                    $assignmentType = [string](Get-EntraTopologyMonitorPropertyValue -InputObject $state -Name 'assignmentType')
                    $scope = [string](Get-EntraTopologyMonitorPropertyValue -InputObject $state -Name 'directoryScopeId')
                    $parts = @()
                    if (-not [string]::IsNullOrWhiteSpace($assignmentType)) { $parts += "Assignment: $assignmentType" }
                    if (-not [string]::IsNullOrWhiteSpace($scope)) { $parts += "Scope: $scope" }
                    $detail = $parts -join ' · '
                }
                'hasAppRoleAssignment' {
                    $permission = [string](Get-EntraTopologyMonitorPropertyValue -InputObject $state -Name 'appRoleValue')
                    if ([string]::IsNullOrWhiteSpace($permission)) {
                        $permission = [string](Get-EntraTopologyMonitorPropertyValue -InputObject $state -Name 'appRoleDisplayName')
                    }
                    $resource = [string](Get-EntraTopologyMonitorPropertyValue -InputObject $state -Name 'resourceDisplayName')
                    $parts = @()
                    if (-not [string]::IsNullOrWhiteSpace($permission)) { $parts += "Permission: $permission" }
                    if (-not [string]::IsNullOrWhiteSpace($resource)) { $parts += "Resource: $resource" }
                    $detail = $parts -join ' · '
                }
                'hasDelegatedPermission' {
                    $scope = Limit-EntraTopologyMonitorText -Text ([string](Get-EntraTopologyMonitorPropertyValue -InputObject $state -Name 'scope')) -MaximumLength 240
                    $consentType = [string](Get-EntraTopologyMonitorPropertyValue -InputObject $state -Name 'consentType')
                    $parts = @()
                    if (-not [string]::IsNullOrWhiteSpace($scope)) { $parts += "Scopes: $scope" }
                    if (-not [string]::IsNullOrWhiteSpace($consentType)) { $parts += "Consent: $consentType" }
                    $detail = $parts -join ' · '
                }
                'hasCredential' {
                    $credentialType = Get-EntraTopologyMonitorCredentialTypeName -CredentialType ([string](Get-EntraTopologyMonitorPropertyValue -InputObject $state -Name 'credentialType'))
                    $expiry = ConvertTo-EntraTopologyMonitorDisplayDate -Value (Get-EntraTopologyMonitorPropertyValue -InputObject $state -Name 'endDateTime')
                    $parts = @($credentialType)
                    if (-not [string]::IsNullOrWhiteSpace($expiry)) { $parts += "Expires $expiry" }
                    $detail = $parts -join ' · '
                }
            }

            $fromNode = if ($Lookup.NodeByKey.ContainsKey($fromKey)) { $Lookup.NodeByKey[$fromKey] } else { $null }
            $toNode = if ($Lookup.NodeByKey.ContainsKey($toKey)) { $Lookup.NodeByKey[$toKey] } else { $null }
            $portalUri = Get-EntraTopologyMonitorPortalUri -Node $fromNode
            if ([string]::IsNullOrWhiteSpace($portalUri)) { $portalUri = Get-EntraTopologyMonitorPortalUri -Node $toNode }
        }
        'Signal' {
            $signalType = [string](Get-EntraTopologyMonitorPropertyValue -InputObject $item -Name 'Type')
            $targetKey = [string](Get-EntraTopologyMonitorPropertyValue -InputObject $item -Name 'TargetKey')
            $reason = Limit-EntraTopologyMonitorText -Text ([string](Get-EntraTopologyMonitorPropertyValue -InputObject $item -Name 'Reason')) -MaximumLength 320
            $state = Get-EntraTopologyMonitorPropertyValue -InputObject $item -Name 'State'
            $title = "$(Get-EntraTopologyMonitorSignalTitle -SignalType $signalType) $verb"

            if (-not [string]::IsNullOrWhiteSpace($targetKey) -and $Lookup.EdgeByKey.ContainsKey($targetKey)) {
                $targetEdge = $Lookup.EdgeByKey[$targetKey]
                $fromKey = [string](Get-EntraTopologyMonitorPropertyValue -InputObject $targetEdge -Name 'From')
                $toKey = [string](Get-EntraTopologyMonitorPropertyValue -InputObject $targetEdge -Name 'To')
                $primary = "$(Get-EntraTopologyMonitorNodeDisplayName -Key $fromKey -Lookup $Lookup) → $(Get-EntraTopologyMonitorNodeDisplayName -Key $toKey -Lookup $Lookup)"
                $groupKey = "$changeType|Edge|$targetKey"
                $fromNode = if ($Lookup.NodeByKey.ContainsKey($fromKey)) { $Lookup.NodeByKey[$fromKey] } else { $null }
                $toNode = if ($Lookup.NodeByKey.ContainsKey($toKey)) { $Lookup.NodeByKey[$toKey] } else { $null }
                $portalUri = Get-EntraTopologyMonitorPortalUri -Node $fromNode
                if ([string]::IsNullOrWhiteSpace($portalUri)) { $portalUri = Get-EntraTopologyMonitorPortalUri -Node $toNode }
            } elseif (-not [string]::IsNullOrWhiteSpace($targetKey) -and $Lookup.NodeByKey.ContainsKey($targetKey)) {
                $targetNode = $Lookup.NodeByKey[$targetKey]
                $primary = Get-EntraTopologyMonitorNodeDisplayName -Key $targetKey -Lookup $Lookup
                $portalUri = Get-EntraTopologyMonitorPortalUri -Node $targetNode
            } elseif (-not [string]::IsNullOrWhiteSpace($targetKey)) {
                $primary = $targetKey
            }

            switch ($signalType) {
                'highPrivilegeRoleAssignment' {
                    $roleName = [string](Get-EntraTopologyMonitorPropertyValue -InputObject $state -Name 'roleName')
                    if (-not [string]::IsNullOrWhiteSpace($roleName)) { $detail = "Role: $roleName" }
                }
                'highImpactApplicationPermission' {
                    $permission = [string](Get-EntraTopologyMonitorPropertyValue -InputObject $state -Name 'appRoleValue')
                    if (-not [string]::IsNullOrWhiteSpace($permission)) { $detail = "Permission: $permission" }
                }
                'highImpactDelegatedPermission' {
                    $scope = Limit-EntraTopologyMonitorText -Text ([string](Get-EntraTopologyMonitorPropertyValue -InputObject $state -Name 'scope')) -MaximumLength 240
                    if (-not [string]::IsNullOrWhiteSpace($scope)) { $detail = "Scopes: $scope" }
                }
                'privilegedOwnerRelationship' {
                    $roles = @(Get-EntraTopologyMonitorPropertyValue -InputObject $state -Name 'roles')
                    if ($roles.Count -gt 0) { $detail = 'Owner roles: ' + (($roles | ForEach-Object { [string]$_ }) -join ', ') }
                }
            }
        }
        'Node' {
            $nodeKind = [string](Get-EntraTopologyMonitorPropertyValue -InputObject $item -Name 'Kind')
            $displayName = [string](Get-EntraTopologyMonitorPropertyValue -InputObject $item -Name 'DisplayName')
            if ([string]::IsNullOrWhiteSpace($displayName)) {
                $displayName = [string](Get-EntraTopologyMonitorPropertyValue -InputObject $item -Name 'Id')
            }
            $properties = Get-EntraTopologyMonitorPropertyValue -InputObject $item -Name 'Properties'
            $groupKey = "$changeType|Node|$key"

            if ($nodeKind -eq 'applicationCredential') {
                $title = "Application credential $verb"
                $parentId = [string](Get-EntraTopologyMonitorPropertyValue -InputObject $properties -Name 'parentId')
                $parentNode = if (-not [string]::IsNullOrWhiteSpace($parentId) -and $Lookup.NodeById.ContainsKey($parentId)) { $Lookup.NodeById[$parentId] } else { $null }
                $parentName = [string](Get-EntraTopologyMonitorPropertyValue -InputObject $parentNode -Name 'DisplayName')
                $primary = if (-not [string]::IsNullOrWhiteSpace($parentName)) { $parentName } else { $displayName }
                $credentialType = Get-EntraTopologyMonitorCredentialTypeName -CredentialType ([string](Get-EntraTopologyMonitorPropertyValue -InputObject $properties -Name 'credentialType'))
                $expiry = ConvertTo-EntraTopologyMonitorDisplayDate -Value (Get-EntraTopologyMonitorPropertyValue -InputObject $properties -Name 'endDateTime')

                $parts = @()
                if (-not [string]::IsNullOrWhiteSpace($displayName)) { $parts += $displayName }
                $parts += $credentialType
                if (-not [string]::IsNullOrWhiteSpace($expiry)) { $parts += "Expires $expiry" }

                if ($changeType -eq 'Changed') {
                    $before = Get-EntraTopologyMonitorPropertyValue -InputObject $Change -Name 'Before'
                    $beforeProperties = Get-EntraTopologyMonitorPropertyValue -InputObject $before -Name 'Properties'
                    $beforeExpiryRaw = Get-EntraTopologyMonitorPropertyValue -InputObject $beforeProperties -Name 'endDateTime'
                    $afterExpiryRaw = Get-EntraTopologyMonitorPropertyValue -InputObject $properties -Name 'endDateTime'
                    $beforeExpiry = ConvertTo-EntraTopologyMonitorDisplayDate -Value $beforeExpiryRaw
                    $afterExpiry = ConvertTo-EntraTopologyMonitorDisplayDate -Value $afterExpiryRaw
                    if (-not [string]::IsNullOrWhiteSpace($beforeExpiry) -and $beforeExpiry -ne $afterExpiry) {
                        $parts = @($displayName, $credentialType, "Expiry changed: $beforeExpiry → $afterExpiry")
                    }
                }

                $detail = ($parts | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }) -join ' · '
                $portalUri = Get-EntraTopologyMonitorPortalUri -Node $parentNode
            } else {
                $friendlyKind = switch ($nodeKind) {
                    'application'      { 'Application registration' }
                    'servicePrincipal' { 'Enterprise application' }
                    'user'             { 'User' }
                    'group'            { 'Group' }
                    'device'           { 'Device' }
                    'directoryRole'    { 'Directory role' }
                    default            { if ([string]::IsNullOrWhiteSpace($nodeKind)) { 'Object' } else { $nodeKind } }
                }
                $title = "$friendlyKind $verb"
                $primary = $displayName
                $portalUri = Get-EntraTopologyMonitorPortalUri -Node $item
            }
        }
    }

    [pscustomobject][ordered]@{
        Severity     = $Severity
        Change       = $changeType
        Kind         = $kind
        Key          = $key
        GroupKey     = $groupKey
        Title        = $title
        Primary      = $primary
        Detail       = $detail
        Reason       = $reason
        PortalUri    = $portalUri
        Relationship = $relationship
        SignalType   = $signalType
    }
}

function Merge-EntraTopologyMonitorAlerts {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object[]]$Alerts)

    $groups = [ordered]@{}

    foreach ($alert in @($Alerts | Sort-Object @{ Expression = { Get-EntraTopologyMonitorSeverityRank -Severity ([string]$_.Severity) }; Descending = $true }, Change, Key)) {
        $groupKey = [string]$alert.GroupKey
        if ([string]::IsNullOrWhiteSpace($groupKey)) { $groupKey = [string]$alert.Key }

        if (-not $groups.Contains($groupKey)) {
            $groups[$groupKey] = [pscustomobject][ordered]@{
                Severity  = [string]$alert.Severity
                Change    = [string]$alert.Change
                Kind      = [string]$alert.Kind
                Key       = [string]$alert.Key
                Title     = [string]$alert.Title
                Primary   = [string]$alert.Primary
                Detail    = [string]$alert.Detail
                Reason    = [string]$alert.Reason
                PortalUri = [string]$alert.PortalUri
                Records   = 1
            }
        } else {
            $existing = $groups[$groupKey]
            $existing.Records = [int]$existing.Records + 1

            if ((Get-EntraTopologyMonitorSeverityRank -Severity ([string]$alert.Severity)) -gt (Get-EntraTopologyMonitorSeverityRank -Severity ([string]$existing.Severity))) {
                $existing.Severity = [string]$alert.Severity
            }

            # Prefer the concrete topology mutation over a derived signal for the
            # card title/body, but keep the signal reason and severity as context.
            if ([string]$existing.Kind -eq 'Signal' -and [string]$alert.Kind -in @('Edge','Node')) {
                $existing.Kind = [string]$alert.Kind
                $existing.Key = [string]$alert.Key
                $existing.Title = [string]$alert.Title
                $existing.Primary = [string]$alert.Primary
                $existing.Detail = [string]$alert.Detail
                if (-not [string]::IsNullOrWhiteSpace([string]$alert.PortalUri)) { $existing.PortalUri = [string]$alert.PortalUri }
            } elseif ([string]::IsNullOrWhiteSpace([string]$existing.Detail) -and -not [string]::IsNullOrWhiteSpace([string]$alert.Detail)) {
                $existing.Detail = [string]$alert.Detail
            }

            if (-not [string]::IsNullOrWhiteSpace([string]$alert.Reason)) {
                if ([string]::IsNullOrWhiteSpace([string]$existing.Reason)) {
                    $existing.Reason = [string]$alert.Reason
                } elseif ([string]$existing.Reason -notlike "*$([string]$alert.Reason)*") {
                    $existing.Reason = Limit-EntraTopologyMonitorText -Text ("$($existing.Reason) $($alert.Reason)") -MaximumLength 420
                }
            }
        }
    }

    @($groups.Values | Sort-Object @{ Expression = { Get-EntraTopologyMonitorSeverityRank -Severity ([string]$_.Severity) }; Descending = $true }, Change, Title, Primary)
}

function Get-EntraTopologyMonitorSeverityBadgeStyle {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Severity)

    switch ($Severity) {
        'Critical' { return 'background:#FDECEC;color:#B42318;border:1px solid #F6C7C2;' }
        'High'     { return 'background:#FFF4E5;color:#B54708;border:1px solid #F7D9A6;' }
        'Medium'   { return 'background:#FFF9DB;color:#8A6100;border:1px solid #F1E29A;' }
        'Low'      { return 'background:#EAF3FF;color:#175CD3;border:1px solid #C9DFFF;' }
        default    { return 'background:#F2F4F7;color:#475467;border:1px solid #D0D5DD;' }
    }
}

function New-EntraTopologyMonitorNotification {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Notification,
        [Parameter(Mandatory)][object[]]$Alerts,
        [Parameter(Mandatory)][object]$Delta,
        [Parameter(Mandatory)][string]$TenantId,
        [Parameter(Mandatory)][object]$Graph,
        [AllowNull()][object]$Baseline,
        [AllowNull()][object]$PreviousState
    )

    $presentation = @(Merge-EntraTopologyMonitorAlerts -Alerts $Alerts)
    if ($presentation.Count -eq 0) { throw 'Cannot build a notification without alert-worthy changes.' }

    $highest = [string]($presentation | Sort-Object @{ Expression = { Get-EntraTopologyMonitorSeverityRank -Severity ([string]$_.Severity) }; Descending = $true } | Select-Object -First 1).Severity
    $criticalCount = @($presentation | Where-Object Severity -eq 'Critical').Count
    $highCount = @($presentation | Where-Object Severity -eq 'High').Count

    $tenantDisplayName = [string](Get-EntraTopologyMonitorPropertyValue -InputObject $Notification -Name 'TenantDisplayName')
    if ([string]::IsNullOrWhiteSpace($tenantDisplayName)) { $tenantDisplayName = 'Microsoft Entra tenant' }

    $maxItems = 12
    $configuredMaxItems = Get-EntraTopologyMonitorPropertyValue -InputObject $Notification -Name 'MaxItems'
    if ($null -ne $configuredMaxItems) {
        $parsedMaxItems = 0
        if ([int]::TryParse([string]$configuredMaxItems, [ref]$parsedMaxItems) -and $parsedMaxItems -ge 1 -and $parsedMaxItems -le 25) {
            $maxItems = $parsedMaxItems
        }
    }

    $comparedAt = ConvertTo-EntraTopologyMonitorDisplayDate -Value (Get-EntraTopologyMonitorPropertyValue -InputObject $Delta -Name 'ComparedAtUtc')
    $baselineAt = ConvertTo-EntraTopologyMonitorDisplayDate -Value (Get-EntraTopologyMonitorPropertyValue -InputObject $PreviousState -Name 'LastSuccessfulRunUtc')
    if ([string]::IsNullOrWhiteSpace($baselineAt)) { $baselineAt = 'Previous successful baseline' }

    $nodes = @(Get-EntraTopologyMonitorPropertyValue -InputObject $Graph -Name 'Nodes')
    $edges = @(Get-EntraTopologyMonitorPropertyValue -InputObject $Graph -Name 'Edges')
    $signals = @(Get-EntraTopologyMonitorPropertyValue -InputObject $Graph -Name 'Signals')
    $coverage = @(Get-EntraTopologyMonitorPropertyValue -InputObject $Graph -Name 'Coverage')
    $coverageStatuses = @($coverage | ForEach-Object { [string](Get-EntraTopologyMonitorPropertyValue -InputObject $_ -Name 'Status') } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
    $coverageLabel = if ($coverageStatuses.Count -eq 0) { 'Not reported' } elseif ($coverageStatuses.Count -eq 1) { $coverageStatuses[0] } else { $coverageStatuses -join ' / ' }

    $summary = Get-EntraTopologyMonitorPropertyValue -InputObject $Delta -Name 'Summary'
    $added = [int](Get-EntraTopologyMonitorPropertyValue -InputObject $summary -Name 'Added')
    $removed = [int](Get-EntraTopologyMonitorPropertyValue -InputObject $summary -Name 'Removed')
    $changed = [int](Get-EntraTopologyMonitorPropertyValue -InputObject $summary -Name 'Changed')
    $totalDelta = $added + $removed + $changed

    $displayItems = @($presentation | Select-Object -First $maxItems)
    $itemHtml = foreach ($item in $displayItems) {
        $severity = ConvertTo-EntraTopologyMonitorHtmlEncoded $item.Severity
        $change = ConvertTo-EntraTopologyMonitorHtmlEncoded $item.Change
        $title = ConvertTo-EntraTopologyMonitorHtmlEncoded $item.Title
        $primary = ConvertTo-EntraTopologyMonitorHtmlEncoded $item.Primary
        $detail = ConvertTo-EntraTopologyMonitorHtmlEncoded $item.Detail
        $reason = ConvertTo-EntraTopologyMonitorHtmlEncoded $item.Reason
        $badgeStyle = Get-EntraTopologyMonitorSeverityBadgeStyle -Severity ([string]$item.Severity)

        $detailHtml = if (-not [string]::IsNullOrWhiteSpace([string]$item.Detail)) {
            '<div style="margin-top:6px;color:#475467;font-size:13px;line-height:19px;">{0}</div>' -f $detail
        } else { '' }

        $reasonHtml = if (-not [string]::IsNullOrWhiteSpace([string]$item.Reason)) {
            '<div style="margin-top:8px;padding:9px 11px;background:#F8FAFC;border-radius:6px;color:#344054;font-size:12px;line-height:18px;">{0}</div>' -f $reason
        } else { '' }

        $linkHtml = ''
        if (-not [string]::IsNullOrWhiteSpace([string]$item.PortalUri) -and [string]$item.PortalUri -match '^https://entra\.microsoft\.com/') {
            $href = ConvertTo-EntraTopologyMonitorHtmlEncoded $item.PortalUri
            $linkHtml = '<div style="margin-top:10px;"><a href="{0}" style="color:#175CD3;text-decoration:none;font-size:12px;font-weight:600;">Open in Microsoft Entra &rarr;</a></div>' -f $href
        }

        @"
<tr>
  <td style="padding:0 0 12px 0;">
    <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="border-collapse:separate;border-spacing:0;background:#FFFFFF;border:1px solid #EAECF0;border-radius:10px;">
      <tr>
        <td style="padding:16px 18px;">
          <div style="margin-bottom:9px;">
            <span style="display:inline-block;padding:3px 8px;border-radius:999px;font-size:11px;font-weight:700;letter-spacing:.3px;$badgeStyle">$severity</span>
            <span style="display:inline-block;margin-left:6px;color:#667085;font-size:11px;font-weight:600;text-transform:uppercase;letter-spacing:.3px;">$change</span>
          </div>
          <div style="color:#101828;font-size:15px;font-weight:700;line-height:21px;">$title</div>
          <div style="margin-top:4px;color:#101828;font-size:14px;line-height:20px;">$primary</div>
          $detailHtml
          $reasonHtml
          $linkHtml
        </td>
      </tr>
    </table>
  </td>
</tr>
"@
    }

    $remaining = [Math]::Max(0, $presentation.Count - $displayItems.Count)
    $remainingHtml = if ($remaining -gt 0) {
        '<tr><td style="padding:3px 0 0 0;color:#667085;font-size:12px;line-height:18px;">+{0} additional significant change(s) are retained in <strong>last-alert.json</strong>; complete topology drift remains in <strong>last-delta.json</strong> on the monitoring host.</td></tr>' -f $remaining
    } else { '' }

    $highestBadgeStyle = Get-EntraTopologyMonitorSeverityBadgeStyle -Severity $highest
    $reviewVerb = if ($presentation.Count -eq 1) { 'requires' } else { 'require' }
    $subject = "[EntraTopology] $($highest.ToUpperInvariant()) · $($presentation.Count) significant change$(if ($presentation.Count -eq 1) { '' } else { 's' }) detected"

    $body = @"
<!doctype html>
<html>
<head>
  <meta http-equiv="Content-Type" content="text/html; charset=utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>EntraTopology notification</title>
</head>
<body style="margin:0;padding:0;background:#F2F4F7;font-family:Segoe UI,Arial,sans-serif;color:#101828;">
  <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="border-collapse:collapse;background:#F2F4F7;">
    <tr>
      <td align="center" style="padding:28px 12px;">
        <table role="presentation" width="680" cellspacing="0" cellpadding="0" style="width:100%;max-width:680px;border-collapse:separate;border-spacing:0;">
          <tr>
            <td style="padding:22px 24px;background:#101828;border-radius:12px 12px 0 0;">
              <table role="presentation" width="100%" cellspacing="0" cellpadding="0">
                <tr>
                  <td style="color:#FFFFFF;font-size:13px;font-weight:700;letter-spacing:.4px;">EntraTopology</td>
                  <td align="right"><span style="display:inline-block;padding:4px 9px;border-radius:999px;font-size:11px;font-weight:700;letter-spacing:.4px;$highestBadgeStyle">$(ConvertTo-EntraTopologyMonitorHtmlEncoded $highest)</span></td>
                </tr>
              </table>
              <div style="margin-top:14px;color:#FFFFFF;font-size:22px;font-weight:700;line-height:28px;">Microsoft Entra topology change detected</div>
              <div style="margin-top:6px;color:#D0D5DD;font-size:13px;line-height:19px;">$($presentation.Count) significant change$(if ($presentation.Count -eq 1) { '' } else { 's' }) $reviewVerb review · $(ConvertTo-EntraTopologyMonitorHtmlEncoded $comparedAt)</div>
            </td>
          </tr>
          <tr>
            <td style="padding:22px 24px 26px 24px;background:#FFFFFF;border-radius:0 0 12px 12px;">
              <div style="color:#344054;font-size:12px;font-weight:700;text-transform:uppercase;letter-spacing:.5px;">Summary</div>
              <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="margin-top:10px;border-collapse:separate;border-spacing:8px 0;">
                <tr>
                  <td width="25%" style="padding:12px;background:#F9FAFB;border:1px solid #EAECF0;border-radius:8px;"><div style="font-size:20px;font-weight:700;">$($presentation.Count)</div><div style="margin-top:3px;color:#667085;font-size:11px;">Significant</div></td>
                  <td width="25%" style="padding:12px;background:#F9FAFB;border:1px solid #EAECF0;border-radius:8px;"><div style="font-size:20px;font-weight:700;">$criticalCount</div><div style="margin-top:3px;color:#667085;font-size:11px;">Critical</div></td>
                  <td width="25%" style="padding:12px;background:#F9FAFB;border:1px solid #EAECF0;border-radius:8px;"><div style="font-size:20px;font-weight:700;">$highCount</div><div style="margin-top:3px;color:#667085;font-size:11px;">High</div></td>
                  <td width="25%" style="padding:12px;background:#F9FAFB;border:1px solid #EAECF0;border-radius:8px;"><div style="font-size:20px;font-weight:700;">$totalDelta</div><div style="margin-top:3px;color:#667085;font-size:11px;">Total delta</div></td>
                </tr>
              </table>
              <div style="margin:10px 0 0 0;color:#667085;font-size:12px;">Topology delta: <strong style="color:#344054;">+$added added</strong> · <strong style="color:#344054;">-$removed removed</strong> · <strong style="color:#344054;">~$changed changed</strong></div>

              <div style="margin-top:24px;color:#344054;font-size:12px;font-weight:700;text-transform:uppercase;letter-spacing:.5px;">What changed</div>
              <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="margin-top:10px;border-collapse:collapse;">
                $($itemHtml -join [Environment]::NewLine)
                $remainingHtml
              </table>

              <div style="margin-top:24px;color:#344054;font-size:12px;font-weight:700;text-transform:uppercase;letter-spacing:.5px;">Monitoring context</div>
              <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="margin-top:10px;border-collapse:collapse;border-top:1px solid #EAECF0;">
                <tr><td style="padding:9px 0;color:#667085;font-size:12px;width:155px;">Tenant</td><td style="padding:9px 0;color:#101828;font-size:12px;font-weight:600;">$(ConvertTo-EntraTopologyMonitorHtmlEncoded $tenantDisplayName)</td></tr>
                <tr><td style="padding:9px 0;color:#667085;font-size:12px;border-top:1px solid #F2F4F7;">Tenant ID</td><td style="padding:9px 0;color:#101828;font-size:12px;border-top:1px solid #F2F4F7;">$(ConvertTo-EntraTopologyMonitorHtmlEncoded $TenantId)</td></tr>
                <tr><td style="padding:9px 0;color:#667085;font-size:12px;border-top:1px solid #F2F4F7;">Baseline</td><td style="padding:9px 0;color:#101828;font-size:12px;border-top:1px solid #F2F4F7;">$(ConvertTo-EntraTopologyMonitorHtmlEncoded $baselineAt)</td></tr>
                <tr><td style="padding:9px 0;color:#667085;font-size:12px;border-top:1px solid #F2F4F7;">Current run</td><td style="padding:9px 0;color:#101828;font-size:12px;border-top:1px solid #F2F4F7;">$(ConvertTo-EntraTopologyMonitorHtmlEncoded $comparedAt)</td></tr>
                <tr><td style="padding:9px 0;color:#667085;font-size:12px;border-top:1px solid #F2F4F7;">Current topology</td><td style="padding:9px 0;color:#101828;font-size:12px;border-top:1px solid #F2F4F7;">$($nodes.Count) objects · $($edges.Count) relationships · $($signals.Count) security signals</td></tr>
                <tr><td style="padding:9px 0;color:#667085;font-size:12px;border-top:1px solid #F2F4F7;">Coverage</td><td style="padding:9px 0;color:#101828;font-size:12px;border-top:1px solid #F2F4F7;">$(ConvertTo-EntraTopologyMonitorHtmlEncoded $coverageLabel)</td></tr>
              </table>

              <div style="margin-top:22px;padding-top:16px;border-top:1px solid #EAECF0;color:#98A2B3;font-size:11px;line-height:17px;">EntraTopology · Read-only Microsoft Entra topology monitoring. This email is a concise operational summary; complete machine-readable evidence is retained in <strong>last-delta.json</strong> and <strong>last-alert.json</strong> on the monitoring host.</div>
            </td>
          </tr>
        </table>
      </td>
    </tr>
  </table>
</body>
</html>
"@

    [pscustomobject][ordered]@{
        Subject                = $subject
        HtmlBody               = $body
        HighestSeverity        = $highest
        SignificantChangeCount = $presentation.Count
        DisplayedChangeCount   = $displayItems.Count
        RawAlertRecordCount    = $Alerts.Count
    }
}

function Send-EntraTopologyMonitorNotification {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Notification,
        [Parameter(Mandatory)][object]$Message
    )

    $recipients = @((Get-EntraTopologyMonitorPropertyValue -InputObject $Notification -Name 'Recipients') | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    if ($recipients.Count -eq 0) { throw 'Notification.Enabled is true but no recipients are configured.' }

    $sender = [string](Get-EntraTopologyMonitorPropertyValue -InputObject $Notification -Name 'SenderUserId')
    if ([string]::IsNullOrWhiteSpace($sender)) { throw 'Notification.Enabled is true but SenderUserId is empty.' }

    $saveToSentItems = $true
    $configuredSave = Get-EntraTopologyMonitorPropertyValue -InputObject $Notification -Name 'SaveToSentItems'
    if ($null -ne $configuredSave) { $saveToSentItems = [bool]$configuredSave }

    $toRecipients = @(
        foreach ($recipient in $recipients) {
            @{ emailAddress = @{ address = [string]$recipient } }
        }
    )

    $requestBody = @{
        message = @{
            subject = [string]$Message.Subject
            body = @{
                contentType = 'HTML'
                content = [string]$Message.HtmlBody
            }
            toRecipients = $toRecipients
        }
        saveToSentItems = $saveToSentItems
    } | ConvertTo-Json -Depth 10

    $encodedSender = [uri]::EscapeDataString($sender)
    $uri = "https://graph.microsoft.com/v1.0/users/$encodedSender/sendMail"

    Invoke-MgGraphRequest -Method POST -Uri $uri -Body $requestBody -ContentType 'application/json' | Out-Null
}
