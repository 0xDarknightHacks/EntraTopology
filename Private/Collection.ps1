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


function Get-EntraTopologyUsers {
    [CmdletBinding()] param([Parameter(Mandatory)][string]$TenantId,[object]$Telemetry)
    $r = New-EntraTopologyCollectorResult 'Users'
    $r.RequiredPermissions=@('User.Read.All','Directory.Read.All')
    $baseEndpoint='/v1.0/users?$select=id,displayName,userPrincipalName,userType,accountEnabled,createdDateTime'
    $activityEndpoint='/v1.0/users?$select=id,signInActivity'
    $riskyEndpoint='/v1.0/identityProtection/riskyUsers?$select=id,userPrincipalName,userDisplayName,riskLevel,riskState,riskDetail,riskLastUpdatedDateTime,isDeleted'

    Set-EntraTopologyCollectorCapability -Result $r -Name 'UserInventory' -Status 'Complete' -RequiredPermissions $r.RequiredPermissions -Endpoints @($baseEndpoint) | Out-Null
    Set-EntraTopologyCollectorCapability -Result $r -Name 'UserSignInActivity' -Status 'NotRun' -RequiredPermissions @('AuditLog.Read.All') -Endpoints @($activityEndpoint) -Warnings @('Optional signInActivity enrichment was not requested or permission is unavailable.') | Out-Null
    Set-EntraTopologyCollectorCapability -Result $r -Name 'RiskyUserContext' -Status 'NotRun' -RequiredPermissions @('IdentityRiskyUser.Read.All') -Endpoints @($riskyEndpoint) -Warnings @('Optional risky-user enrichment is unavailable unless IdentityRiskyUser.Read.All is granted. Microsoft Entra ID P2 is also required for risky-user data.') | Out-Null

    if (-not (Test-EntraTopologyPermission -AnyOf $r.RequiredPermissions)) {
        Set-EntraTopologyCollectorCapability -Result $r -Name 'UserInventory' -Status 'NotRun' -RequiredPermissions $r.RequiredPermissions -Endpoints @($baseEndpoint) -Warnings @('User collection permission not granted.') | Out-Null
        return Set-EntraTopologyCollectorNotRun $r $r.RequiredPermissions 'User collection permission not granted.'
    }

    $g = Invoke-EntraTopologyGraphRequest -Uri $baseEndpoint -RequiredPermission 'User.Read.All or Directory.Read.All' -Telemetry $Telemetry
    Add-EntraTopologyGraphResponseEvidence -Result $r -Capability 'UserInventory' -Response $g
    if ($g.Status -ne 'Success') {
        $r.Status='Partial'; $r.Warnings += @($g.Limitations)
        Set-EntraTopologyCollectorCapability -Result $r -Name 'UserInventory' -Status 'Partial' -RequiredPermissions $r.RequiredPermissions -Endpoints @($baseEndpoint) -Warnings @($g.Limitations) | Out-Null
        return $r
    }

    $users = @($g.Items)
    if (Test-EntraTopologyPermission -AnyOf @('AuditLog.Read.All')) {
        $activity = Invoke-EntraTopologyGraphRequest -Uri $activityEndpoint -RequiredPermission 'AuditLog.Read.All (Entra ID P1/P2 required for signInActivity)' -Telemetry $Telemetry
        Add-EntraTopologyGraphResponseEvidence -Result $r -Capability 'UserSignInActivity' -Response $activity
        if ($activity.Status -eq 'Success') {
            $byId=@{}
            foreach ($a in @($activity.Items)) {
                $activityUserId = Get-EntraTopologyProperty $a 'id'
                if ($activityUserId) { $byId[[string]$activityUserId] = Get-EntraTopologyProperty $a 'signInActivity' }
            }
            foreach ($u in $users) {
                $userId = Get-EntraTopologyProperty $u 'id'
                if ($userId -and $byId.ContainsKey([string]$userId)) { $u | Add-Member -NotePropertyName signInActivity -NotePropertyValue $byId[[string]$userId] -Force }
            }
            Set-EntraTopologyCollectorCapability -Result $r -Name 'UserSignInActivity' -Status 'Complete' -RequiredPermissions @('AuditLog.Read.All') -Endpoints @($activityEndpoint) | Out-Null
        } else {
            $warning = "Optional signInActivity enrichment unavailable: $(@($activity.Limitations) -join '; ')"
            $r.Warnings += $warning
            Set-EntraTopologyCollectorCapability -Result $r -Name 'UserSignInActivity' -Status 'Unavailable' -RequiredPermissions @('AuditLog.Read.All') -Endpoints @($activityEndpoint) -Warnings @($warning) | Out-Null
        }
    }

    if (Test-EntraTopologyPermission -AnyOf @('IdentityRiskyUser.Read.All')) {
        $risk = Invoke-EntraTopologyGraphRequest -Uri $riskyEndpoint -RequiredPermission 'IdentityRiskyUser.Read.All (Microsoft Entra ID P2 required)' -Telemetry $Telemetry
        Add-EntraTopologyGraphResponseEvidence -Result $r -Capability 'RiskyUserContext' -Response $risk
        if ($risk.Status -eq 'Success') {
            $riskById=@{}
            foreach($item in @($risk.Items)){
                $riskId=[string](Get-EntraTopologyProperty $item 'id')
                if($riskId){$riskById[$riskId]=$item}
            }
            foreach($u in $users){
                $userId=[string](Get-EntraTopologyProperty $u 'id')
                if(-not$userId -or -not$riskById.ContainsKey($userId)){continue}
                $ri=$riskById[$userId]
                foreach($propertyName in @('riskLevel','riskState','riskDetail','riskLastUpdatedDateTime')){
                    $value=Get-EntraTopologyProperty $ri $propertyName
                    if($null -ne $value){$u | Add-Member -NotePropertyName $propertyName -NotePropertyValue $value -Force}
                }
                $isDeleted=Get-EntraTopologyProperty $ri 'isDeleted'
                if($null -ne $isDeleted){$u | Add-Member -NotePropertyName riskUserIsDeleted -NotePropertyValue $isDeleted -Force}
            }
            Set-EntraTopologyCollectorCapability -Result $r -Name 'RiskyUserContext' -Status 'Complete' -RequiredPermissions @('IdentityRiskyUser.Read.All') -Endpoints @($riskyEndpoint) | Out-Null
        } else {
            $warning="Optional risky-user enrichment unavailable: HTTP $($risk.StatusCode); $(@($risk.Limitations)-join '; ')"
            $r.Warnings += $warning
            Set-EntraTopologyCollectorCapability -Result $r -Name 'RiskyUserContext' -Status 'Unavailable' -RequiredPermissions @('IdentityRiskyUser.Read.All') -Endpoints @($riskyEndpoint) -Warnings @($warning) | Out-Null
        }
    }

    $r.Objects=@($users | ForEach-Object {[pscustomobject]@{Kind='user';Object=$_}})
    $r.Metrics=@{
        Count=$users.Count
        SignInActivityCoverage=([string](@($r.Capabilities | Where-Object Name -eq 'UserSignInActivity')[0].Status))
        RiskyUserCoverage=([string](@($r.Capabilities | Where-Object Name -eq 'RiskyUserContext')[0].Status))
        ActiveRiskyUserCount=@($users | Where-Object {[string](Get-EntraTopologyProperty $_ 'riskState') -in @('atRisk','confirmedCompromised')}).Count
    }
    $r
}


function Get-EntraTopologyGroups {
    [CmdletBinding()] param([Parameter(Mandatory)][string]$TenantId,[object]$Telemetry,[ValidateRange(1,20)][int]$BatchSize=20)
    $r=New-EntraTopologyCollectorResult 'Groups'
    $groupReadPermissions=@('Group.Read.All','Directory.Read.All')
    $servicePrincipalReadPermissions=@('Application.Read.All','Directory.Read.All')
    $r.RequiredPermissions=$groupReadPermissions
    $ep='/v1.0/groups?$select=id,displayName,description,groupTypes,mailEnabled,securityEnabled,isAssignableToRole,createdDateTime,visibility,onPremisesSyncEnabled'
    $spEp='/v1.0/servicePrincipals?$select=id'

    Set-EntraTopologyCollectorCapability -Result $r -Name 'GroupInventory' -Status 'Complete' -RequiredPermissions $groupReadPermissions -Endpoints @($ep) | Out-Null
    Set-EntraTopologyCollectorCapability -Result $r -Name 'GroupMembers' -Status 'Complete' -RequiredPermissions @('Group.Read.All','Directory.Read.All','Application.Read.All') | Out-Null
    Set-EntraTopologyCollectorCapability -Result $r -Name 'GroupOwners' -Status 'Complete' -RequiredPermissions @('Group.Read.All','Directory.Read.All','Application.Read.All') | Out-Null

    if (-not(Test-EntraTopologyPermission -AnyOf $groupReadPermissions)) {
        foreach($cap in @('GroupInventory','GroupMembers','GroupOwners')) { Set-EntraTopologyCollectorCapability -Result $r -Name $cap -Status 'NotRun' -RequiredPermissions $groupReadPermissions -Warnings @('Group collection permission not granted.') | Out-Null }
        return Set-EntraTopologyCollectorNotRun $r $groupReadPermissions 'Group collection permission not granted.'
    }

    $g=Invoke-EntraTopologyGraphRequest -Uri $ep -RequiredPermission 'Group.Read.All or Directory.Read.All' -Telemetry $Telemetry
    Add-EntraTopologyGraphResponseEvidence -Result $r -Capability 'GroupInventory' -Response $g
    if($g.Status-ne'Success'){
        $r.Status='Partial'; $r.Warnings+=@($g.Limitations)
        Set-EntraTopologyCollectorCapability -Result $r -Name 'GroupInventory' -Status 'Partial' -RequiredPermissions $groupReadPermissions -Endpoints @($ep) -Warnings @($g.Limitations) | Out-Null
        foreach($cap in @('GroupMembers','GroupOwners')) { Set-EntraTopologyCollectorCapability -Result $r -Name $cap -Status 'NotRun' -RequiredPermissions $groupReadPermissions -Warnings @('Parent group inventory was not collected successfully.') | Out-Null }
        return $r
    }

    $r.Objects=@($g.Items|ForEach-Object{[pscustomobject]@{Kind='group';Object=$_}})
    $knownGroupIds=[System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach($group in @($g.Items)){if($group.id){[void]$knownGroupIds.Add([string]$group.id)}}
    $relationKeys=[System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    function Add-GroupRelation {
        param([string]$FromId,[string]$ToId,[string]$Relationship,[string]$Capability,[string]$Endpoint,[string]$Source)
        if([string]::IsNullOrWhiteSpace($FromId)-or[string]::IsNullOrWhiteSpace($ToId)-or[string]::IsNullOrWhiteSpace($Relationship)){return}
        $key="$FromId|$ToId|$Relationship"
        if(-not $relationKeys.Add($key)){return}
        $r.Relations += [pscustomobject]@{FromId=$FromId;ToId=$ToId;Relationship=$Relationship;Qualifier='';State=@{source=$Source};EvidenceRefs=@([pscustomobject]@{Capability=$Capability;Endpoint=$Endpoint})}
    }

    $req=@()
    foreach($group in @($g.Items)){
        $req += [pscustomobject]@{Uri="/groups/$($group.id)/members?`$select=id,displayName";GroupId=[string]$group.id;Relation='memberOf';Capability='GroupMembers'}
        $req += [pscustomobject]@{Uri="/groups/$($group.id)/owners?`$select=id,displayName";GroupId=[string]$group.id;Relation='owns';Capability='GroupOwners'}
    }
    $failedCaps=@{}
    $capWarnings=@{GroupMembers=@();GroupOwners=@()}
    foreach($b in @(Invoke-EntraTopologyGraphBatch -Requests $req -BatchSize $BatchSize -Telemetry $Telemetry)){
        $request=Get-EntraTopologyProperty $b 'Request'; $cap=[string](Get-EntraTopologyProperty $request 'Capability')
        Add-EntraTopologyBatchEvidence -Result $r -Capability $cap -BatchResult $b -RequiredPermission 'Group.Read.All or Directory.Read.All'
        if($b.Status-ne'Success'){
            $r.Status='Partial'; $failedCaps[$cap]=$true
            $warning=(Format-EntraTopologyBatchFailure -BatchResult $b -Prefix 'Group relation request failed')
            $r.Warnings += $warning; $capWarnings[$cap] += $warning
            continue
        }
        $groupId=[string](Get-EntraTopologyProperty $request 'GroupId'); $relation=[string](Get-EntraTopologyProperty $request 'Relation')
        if(-not $groupId -or -not $relation){
            $r.Status='Partial';$failedCaps[$cap]=$true
            $warning="Group relation response skipped because correlation metadata was missing: $($b.SourceEndpoint)"
            $r.Warnings += $warning; $capWarnings[$cap] += $warning
            continue
        }
        foreach($o in @($b.Items)){Add-GroupRelation -FromId ([string]$o.id) -ToId $groupId -Relationship $relation -Capability $cap -Endpoint ([string]$b.SourceEndpoint) -Source 'groupCollection'}
    }

    # Microsoft Graph v1.0 currently omits service principals from /groups/{id}/members and
    # /groups/{id}/owners. Close those gaps with supported v1.0 reverse relationships instead
    # of using beta or the non-pageable $expand workaround.
    $spSupplementCount=0
    if(Test-EntraTopologyMayProbePermission -AnyOf $servicePrincipalReadPermissions){
        $sps=Invoke-EntraTopologyGraphRequest -Uri $spEp -RequiredPermission 'Application.Read.All or Directory.Read.All' -Telemetry $Telemetry
        Add-EntraTopologyGraphResponseEvidence -Result $r -Capability 'GroupMembers' -Response $sps
        Add-EntraTopologyGraphResponseEvidence -Result $r -Capability 'GroupOwners' -Response $sps
        if($sps.Status -eq 'Success'){
            $spReq=@()
            foreach($sp in @($sps.Items)){
                $spId=[string](Get-EntraTopologyProperty $sp 'id'); if(-not $spId){continue}
                $spReq += [pscustomobject]@{Uri="/servicePrincipals/$spId/memberOf?`$select=id,displayName";PrincipalId=$spId;Relation='memberOf';Capability='GroupMembers'}
                $spReq += [pscustomobject]@{Uri="/servicePrincipals/$spId/ownedObjects?`$select=id,displayName";PrincipalId=$spId;Relation='owns';Capability='GroupOwners'}
            }
            if($spReq.Count -gt 0){
                foreach($b in @(Invoke-EntraTopologyGraphBatch -Requests $spReq -BatchSize $BatchSize -Telemetry $Telemetry)){
                    $request=Get-EntraTopologyProperty $b 'Request'; $cap=[string](Get-EntraTopologyProperty $request 'Capability')
                    Add-EntraTopologyBatchEvidence -Result $r -Capability $cap -BatchResult $b -RequiredPermission 'Application.Read.All or Directory.Read.All'
                    if($b.Status-ne'Success'){
                        $r.Status='Partial'; $failedCaps[$cap]=$true
                        $warning=(Format-EntraTopologyBatchFailure -BatchResult $b -Prefix 'Service-principal group correlation failed')
                        $r.Warnings += $warning; $capWarnings[$cap] += $warning
                        continue
                    }
                    $spId=[string](Get-EntraTopologyProperty $request 'PrincipalId'); $relation=[string](Get-EntraTopologyProperty $request 'Relation')
                    if(-not $spId -or -not $relation){
                        $r.Status='Partial';$failedCaps[$cap]=$true
                        $warning="Service-principal group correlation skipped because metadata was missing: $($b.SourceEndpoint)"
                        $r.Warnings += $warning; $capWarnings[$cap] += $warning
                        continue
                    }
                    foreach($o in @($b.Items)){
                        $groupId=[string](Get-EntraTopologyProperty $o 'id')
                        if(-not $groupId -or -not $knownGroupIds.Contains($groupId)){continue}
                        $before=$r.Relations.Count
                        Add-GroupRelation -FromId $spId -ToId $groupId -Relationship $relation -Capability $cap -Endpoint ([string]$b.SourceEndpoint) -Source 'servicePrincipalReverseCorrelation'
                        if($r.Relations.Count -gt $before){$spSupplementCount++}
                    }
                }
            }
        } else {
            $parts=@('Service-principal correlation could not be completed')
            if($sps.StatusCode){$parts += "HTTP $($sps.StatusCode)"}
            if($sps.ErrorCode){$parts += "code=$($sps.ErrorCode)"}
            if($sps.ErrorMessage){$parts += [string]$sps.ErrorMessage}
            elseif(@($sps.Limitations).Count -gt 0){$parts += (@($sps.Limitations)-join '; ')}
            if($sps.RequestId){$parts += "request-id=$($sps.RequestId)"}
            $warning=$parts -join '; '
            foreach($cap in @('GroupMembers','GroupOwners')){$failedCaps[$cap]=$true;$capWarnings[$cap]+=$warning}
            $r.Status='Partial'; $r.Warnings += $warning
        }
    } else {
        $warning='Application.Read.All or Directory.Read.All is required to close Microsoft Graph v1.0 service-principal membership and ownership omissions.'
        foreach($cap in @('GroupMembers','GroupOwners')){$failedCaps[$cap]=$true;$capWarnings[$cap]+=$warning}
        $r.Status='Partial'; $r.Warnings += $warning
    }

    $hiddenMembershipGroups=@($g.Items|Where-Object{[string](Get-EntraTopologyProperty $_ 'visibility') -eq 'HiddenMembership'})
    if($hiddenMembershipGroups.Count -gt 0){
        $ctx=Get-EntraTopologyGraphContext
        if($ctx -and [string](Get-EntraTopologyProperty $ctx 'AuthType') -ne 'AppOnly' -and -not(Test-EntraTopologyPermission -AnyOf @('Member.Read.Hidden'))){
            $failedCaps['GroupMembers']=$true; $r.Status='Partial'
            $warning="$($hiddenMembershipGroups.Count) hidden-membership group(s) were discovered. Member.Read.Hidden is required for complete membership visibility."
            $r.Warnings += $warning; $capWarnings['GroupMembers'] += $warning
        }
    }

    # Microsoft documents owner unavailability for synchronized and distribution-style groups.
    # Treat these as a capability limitation so ownerless signals remain fail-closed.
    $ownerUnsupportedGroups=@($g.Items|Where-Object{
        $types=@(Get-EntraTopologyProperty $_ 'groupTypes')
        $isUnified=($types -contains 'Unified')
        $isSynchronized=((Get-EntraTopologyProperty $_ 'onPremisesSyncEnabled') -eq $true)
        $isMailEnabledNonUnified=((Get-EntraTopologyProperty $_ 'mailEnabled') -eq $true -and -not $isUnified)
        $isSynchronized -or $isMailEnabledNonUnified
    })
    if($ownerUnsupportedGroups.Count -gt 0){
        $failedCaps['GroupOwners']=$true; $r.Status='Partial'
        $warning="$($ownerUnsupportedGroups.Count) group(s) are synchronized or mail-enabled non-Microsoft-365 group types for which Microsoft Graph does not guarantee owner availability."
        $r.Warnings += $warning; $capWarnings['GroupOwners'] += $warning
    }

    $memberRequiredPermissions=@('Group.Read.All','Directory.Read.All','Application.Read.All')
    if($hiddenMembershipGroups.Count -gt 0){$memberRequiredPermissions += 'Member.Read.Hidden'}
    foreach($cap in @('GroupMembers','GroupOwners')){
        if($failedCaps.ContainsKey($cap)){
            $requiredPermissions=if($cap -eq 'GroupMembers'){$memberRequiredPermissions}else{@('Group.Read.All','Directory.Read.All','Application.Read.All')}
            Set-EntraTopologyCollectorCapability -Result $r -Name $cap -Status 'Partial' -RequiredPermissions $requiredPermissions -Warnings @($capWarnings[$cap]|Where-Object{$_}) | Out-Null
        }
    }
    $r.Metrics=@{
        Count=$g.Items.Count
        RelationCount=$r.Relations.Count
        ServicePrincipalSupplementRelationCount=$spSupplementCount
        HiddenMembershipGroupCount=$hiddenMembershipGroups.Count
        OwnerUnsupportedGroupCount=$ownerUnsupportedGroups.Count
    }
    $r
}


function Test-EntraTopologyMicrosoftFirstPartyServicePrincipal {
    param([Parameter(Mandatory)][object]$ServicePrincipal)

    # Microsoft first-party service principals are normally owned by the Microsoft Services tenant.
    # Some Microsoft tenant-owned applications (for example Graph Explorer and Microsoft Graph
    # Command Line Tools) are owned by Microsoft's corporate tenant instead, so both documented
    # Microsoft owner tenants are recognized. The small AppId fallback covers cases where
    # appOwnerOrganizationId is absent or inconsistent in tenant inventory.
    $microsoftOwnerTenantIds=@(
        'f8cdef31-a31e-4b4a-93e4-5f571e91255a', # Microsoft Services
        '72f988bf-86f1-41af-91ab-2d7cd011db47'  # Microsoft corporate tenant
    )
    $documentedMicrosoftAppIds=@(
        'de8bc8b5-d9f9-48b1-a8ad-b748da725064', # Graph Explorer
        '14d82eec-204b-4c2f-b7e8-296a70dab67e', # Microsoft Graph Command Line Tools
        '7ae974c5-1af7-4923-af3a-fb1fd14dcb7e', # OutlookUserSettingsConsumer
        '5572c4c0-d078-44ce-b81c-6cbf8d3ed39e'  # Vortex [wsfed enabled]
    )

    $ownerOrg=[string](Get-EntraTopologyProperty $ServicePrincipal 'appOwnerOrganizationId')
    $appId=[string](Get-EntraTopologyProperty $ServicePrincipal 'appId')
    if($ownerOrg -and $microsoftOwnerTenantIds -contains $ownerOrg){return $true}
    if($appId -and $documentedMicrosoftAppIds -contains $appId){return $true}
    return $false
}

function Get-EntraTopologyServicePrincipalCategory {
    param(
        [Parameter(Mandatory)][object]$ServicePrincipal,
        [Parameter(Mandatory)][string]$TenantId
    )
    $spType=[string](Get-EntraTopologyProperty $ServicePrincipal 'servicePrincipalType')
    $ownerOrg=[string](Get-EntraTopologyProperty $ServicePrincipal 'appOwnerOrganizationId')
    if($spType -eq 'ManagedIdentity'){return 'ManagedIdentity'}
    if($ownerOrg -eq $TenantId){return 'TenantOwned'}
    if(Test-EntraTopologyMicrosoftFirstPartyServicePrincipal -ServicePrincipal $ServicePrincipal){return 'MicrosoftFirstParty'}
    if($spType -eq 'Application'){return 'ExternalEnterpriseApp'}
    if([string]::IsNullOrWhiteSpace($spType)){return 'Other'}
    $spType
}

function Add-EntraTopologyServicePrincipalClassification {
    param([Parameter(Mandatory)][object]$ServicePrincipal,[Parameter(Mandatory)][string]$TenantId,[switch]$ReferenceOnly)
    $category=Get-EntraTopologyServicePrincipalCategory -ServicePrincipal $ServicePrincipal -TenantId $TenantId
    $ServicePrincipal | Add-Member -NotePropertyName enterpriseAppCategory -NotePropertyValue $category -Force
    $ServicePrincipal | Add-Member -NotePropertyName isMicrosoftFirstParty -NotePropertyValue ($category -eq 'MicrosoftFirstParty') -Force
    $ServicePrincipal | Add-Member -NotePropertyName topologyReferenceOnly -NotePropertyValue ([bool]$ReferenceOnly) -Force
    $ServicePrincipal
}

function New-EntraTopologyReferenceServicePrincipal {
    param([Parameter(Mandatory)][object]$Source,[Parameter(Mandatory)][string]$TenantId)
    $reference=[pscustomobject][ordered]@{
        id=[string](Get-EntraTopologyProperty $Source 'id')
        appId=[string](Get-EntraTopologyProperty $Source 'appId')
        displayName=[string](Get-EntraTopologyProperty $Source 'displayName')
        accountEnabled=Get-EntraTopologyProperty $Source 'accountEnabled'
        servicePrincipalType=[string](Get-EntraTopologyProperty $Source 'servicePrincipalType')
        appOwnerOrganizationId=[string](Get-EntraTopologyProperty $Source 'appOwnerOrganizationId')
        appRoleAssignmentRequired=Get-EntraTopologyProperty $Source 'appRoleAssignmentRequired'
        appRoles=@(Get-EntraTopologyProperty $Source 'appRoles')
        oauth2PermissionScopes=@(Get-EntraTopologyProperty $Source 'oauth2PermissionScopes')
        preferredTokenSigningKeyThumbprint=[string](Get-EntraTopologyProperty $Source 'preferredTokenSigningKeyThumbprint')
    }
    Add-EntraTopologyServicePrincipalClassification -ServicePrincipal $reference -TenantId $TenantId -ReferenceOnly
}

function New-EntraTopologyCredentialWrapper {
    param(
        [Parameter(Mandatory)][string]$ParentId,
        [Parameter(Mandatory)][ValidateSet('application','servicePrincipal')][string]$ParentKind,
        [Parameter(Mandatory)][ValidateSet('passwordCredential','keyCredential','signingCertificate')][string]$CredentialType,
        [Parameter(Mandatory)][object]$Credential
    )
    $keyId=[string](Get-EntraTopologyProperty $Credential 'keyId')
    if([string]::IsNullOrWhiteSpace($keyId)){$keyId=Get-EntraTopologyStableId "$ParentId|$CredentialType|$([string](Get-EntraTopologyProperty $Credential 'endDateTime'))"}
    $display=[string](Get-EntraTopologyProperty $Credential 'displayName')
    if([string]::IsNullOrWhiteSpace($display)){$display=if($CredentialType -eq 'passwordCredential'){'Client secret'}else{'Certificate'}}
    $object=[pscustomobject][ordered]@{
        id="$ParentId`:$CredentialType`:$keyId"
        displayName=$display
        parentId=$ParentId
        parentKind=$ParentKind
        credentialType=$CredentialType
        keyId=$keyId
        startDateTime=Get-EntraTopologyProperty $Credential 'startDateTime'
        endDateTime=Get-EntraTopologyProperty $Credential 'endDateTime'
        usage=[string](Get-EntraTopologyProperty $Credential 'usage')
        type=[string](Get-EntraTopologyProperty $Credential 'type')
        hint=[string](Get-EntraTopologyProperty $Credential 'hint')
        customKeyIdentifier=[string](Get-EntraTopologyProperty $Credential 'customKeyIdentifier')
    }
    [pscustomobject]@{Kind='applicationCredential';Object=$object}
}

function Get-EntraTopologyApplications {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TenantId,
        [object]$Telemetry,
        [ValidateRange(1,20)][int]$BatchSize=20,
        [switch]$ExcludeMicrosoftFirstPartyApps
    )

    $r=New-EntraTopologyCollectorResult 'Applications'
    $r.RequiredPermissions=@('Application.Read.All','Directory.Read.All')
    $appEp='/v1.0/applications?$select=id,appId,displayName,createdDateTime,passwordCredentials,keyCredentials,signInAudience,requiredResourceAccess'
    $spEp='/v1.0/servicePrincipals?$select=id,appId,displayName,accountEnabled,servicePrincipalType,appOwnerOrganizationId,appRoleAssignmentRequired,appRoles,oauth2PermissionScopes,keyCredentials,preferredTokenSigningKeyThumbprint'
    $grantEp='/v1.0/oauth2PermissionGrants?$select=id,clientId,consentType,principalId,resourceId,scope'

    foreach($cap in @('ApplicationInventory','ServicePrincipalInventory','ApplicationCredentialMetadata','ServicePrincipalCredentialMetadata','ApplicationRequestedPermissions','ApplicationOwnership','ServicePrincipalOwnership','ServicePrincipalAppRoleAssignments')){
        Set-EntraTopologyCollectorCapability -Result $r -Name $cap -Status 'Complete' -RequiredPermissions $r.RequiredPermissions | Out-Null
    }
    Set-EntraTopologyCollectorCapability -Result $r -Name 'DelegatedPermissionGrants' -Status 'NotRun' -RequiredPermissions @('Directory.Read.All','DelegatedPermissionGrant.ReadWrite.All','Directory.ReadWrite.All') -Endpoints @($grantEp) -Warnings @('Optional delegated OAuth consent collection requires one of Directory.Read.All, DelegatedPermissionGrant.ReadWrite.All, or Directory.ReadWrite.All.') | Out-Null

    if(-not(Test-EntraTopologyPermission -AnyOf $r.RequiredPermissions)){
        foreach($cap in @('ApplicationInventory','ServicePrincipalInventory','ApplicationCredentialMetadata','ServicePrincipalCredentialMetadata','ApplicationRequestedPermissions','ApplicationOwnership','ServicePrincipalOwnership','ServicePrincipalAppRoleAssignments')){
            Set-EntraTopologyCollectorCapability -Result $r -Name $cap -Status 'NotRun' -RequiredPermissions $r.RequiredPermissions -Warnings @('Application collection permission not granted.') | Out-Null
        }
        return Set-EntraTopologyCollectorNotRun $r $r.RequiredPermissions 'Application collection permission not granted.'
    }

    $apps=Invoke-EntraTopologyGraphRequest -Uri $appEp -RequiredPermission 'Application.Read.All or Directory.Read.All' -Telemetry $Telemetry
    $sps=Invoke-EntraTopologyGraphRequest -Uri $spEp -RequiredPermission 'Application.Read.All or Directory.Read.All' -Telemetry $Telemetry
    Add-EntraTopologyGraphResponseEvidence -Result $r -Capability 'ApplicationInventory' -Response $apps
    Add-EntraTopologyGraphResponseEvidence -Result $r -Capability 'ApplicationCredentialMetadata' -Response $apps
    Add-EntraTopologyGraphResponseEvidence -Result $r -Capability 'ApplicationRequestedPermissions' -Response $apps
    Add-EntraTopologyGraphResponseEvidence -Result $r -Capability 'ServicePrincipalInventory' -Response $sps
    Add-EntraTopologyGraphResponseEvidence -Result $r -Capability 'ServicePrincipalCredentialMetadata' -Response $sps

    if($apps.Status-ne'Success'){
        $r.Status='Partial';$r.Warnings += "Application inventory failed: $(@($apps.Limitations)-join '; ')"
        foreach($cap in @('ApplicationInventory','ApplicationCredentialMetadata','ApplicationRequestedPermissions')){Set-EntraTopologyCollectorCapability -Result $r -Name $cap -Status 'Partial' -RequiredPermissions $r.RequiredPermissions -Endpoints @($appEp) -Warnings @($apps.Limitations) | Out-Null}
        Set-EntraTopologyCollectorCapability -Result $r -Name 'ApplicationOwnership' -Status 'NotRun' -RequiredPermissions $r.RequiredPermissions -Warnings @('Parent application inventory was not collected successfully.') | Out-Null
    }
    if($sps.Status-ne'Success'){
        $r.Status='Partial';$r.Warnings += "Service principal inventory failed: $(@($sps.Limitations)-join '; ')"
        foreach($cap in @('ServicePrincipalInventory','ServicePrincipalCredentialMetadata')){Set-EntraTopologyCollectorCapability -Result $r -Name $cap -Status 'Partial' -RequiredPermissions $r.RequiredPermissions -Endpoints @($spEp) -Warnings @($sps.Limitations) | Out-Null}
        foreach($cap in @('ServicePrincipalOwnership','ServicePrincipalAppRoleAssignments')){Set-EntraTopologyCollectorCapability -Result $r -Name $cap -Status 'NotRun' -RequiredPermissions $r.RequiredPermissions -Warnings @('Parent service principal inventory was not collected successfully.') | Out-Null}
    }

    $allSps=@($sps.Items)
    foreach($sp in $allSps){Add-EntraTopologyServicePrincipalClassification -ServicePrincipal $sp -TenantId $TenantId | Out-Null}
    $selectedSps=if($ExcludeMicrosoftFirstPartyApps){@($allSps|Where-Object{[string](Get-EntraTopologyProperty $_ 'enterpriseAppCategory') -ne 'MicrosoftFirstParty'})}else{$allSps}
    $excludedMicrosoftSps=if($ExcludeMicrosoftFirstPartyApps){@($allSps|Where-Object{[string](Get-EntraTopologyProperty $_ 'enterpriseAppCategory') -eq 'MicrosoftFirstParty'})}else{@()}

    $r.Objects=@($apps.Items|ForEach-Object{[pscustomobject]@{Kind='application';Object=$_}})+@($selectedSps|ForEach-Object{[pscustomobject]@{Kind='servicePrincipal';Object=$_}})
    $objectIds=[System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach($w in @($r.Objects)){[void]$objectIds.Add([string](Get-EntraTopologyProperty (Get-EntraTopologyProperty $w 'Object') 'id'))}

    $spByAppId=@{};$spById=@{}
    foreach($sp in $allSps){
        if($sp.appId){$spByAppId[[string]$sp.appId]=$sp}
        if($sp.id){$spById[[string]$sp.id]=$sp}
    }
    $selectedSpIds=[System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach($sp in $selectedSps){[void]$selectedSpIds.Add([string]$sp.id)}

    function Add-ReferenceSpIfNeeded([object]$sp){
        if($null -eq $sp){return}
        $id=[string](Get-EntraTopologyProperty $sp 'id')
        if([string]::IsNullOrWhiteSpace($id) -or $objectIds.Contains($id)){return}
        $ref=New-EntraTopologyReferenceServicePrincipal -Source $sp -TenantId $TenantId
        $r.Objects += [pscustomobject]@{Kind='servicePrincipal';Object=$ref}
        [void]$objectIds.Add($id)
    }

    foreach($app in @($apps.Items)){
        if($app.appId -and $spByAppId.ContainsKey([string]$app.appId)){
            $backing=$spByAppId[[string]$app.appId]
            Add-ReferenceSpIfNeeded $backing
            $r.Relations += [pscustomobject]@{FromId=[string]$app.id;ToId=[string]$backing.id;Relationship='instantiatedAs';Qualifier='';State=@{appId=[string]$app.appId};EvidenceRefs=@([pscustomobject]@{Capability='ApplicationInventory';Endpoint=$appEp},[pscustomobject]@{Capability='ServicePrincipalInventory';Endpoint=$spEp})}
        }

        foreach($credential in @($app.passwordCredentials)){
            $wrapper=New-EntraTopologyCredentialWrapper -ParentId ([string]$app.id) -ParentKind application -CredentialType passwordCredential -Credential $credential
            $r.Objects += $wrapper
            $cred=$wrapper.Object
            $r.Relations += [pscustomobject]@{FromId=[string]$app.id;ToId=[string]$cred.id;Relationship='hasCredential';Qualifier=[string]$cred.keyId;State=@{credentialType='passwordCredential';endDateTime=$cred.endDateTime};EvidenceRefs=@([pscustomobject]@{Capability='ApplicationCredentialMetadata';Endpoint=$appEp})}
        }
        foreach($credential in @($app.keyCredentials)){
            $wrapper=New-EntraTopologyCredentialWrapper -ParentId ([string]$app.id) -ParentKind application -CredentialType keyCredential -Credential $credential
            $r.Objects += $wrapper
            $cred=$wrapper.Object
            $r.Relations += [pscustomobject]@{FromId=[string]$app.id;ToId=[string]$cred.id;Relationship='hasCredential';Qualifier=[string]$cred.keyId;State=@{credentialType='keyCredential';endDateTime=$cred.endDateTime};EvidenceRefs=@([pscustomobject]@{Capability='ApplicationCredentialMetadata';Endpoint=$appEp})}
        }

        foreach($resourceAccess in @($app.requiredResourceAccess)){
            $resourceAppId=[string](Get-EntraTopologyProperty $resourceAccess 'resourceAppId')
            if([string]::IsNullOrWhiteSpace($resourceAppId)){continue}
            $resourceTargetId=$null
            if($spByAppId.ContainsKey($resourceAppId)){
                $resourceSp=$spByAppId[$resourceAppId]; Add-ReferenceSpIfNeeded $resourceSp; $resourceTargetId=[string]$resourceSp.id
            } else {
                $resourceTargetId="apiResource:$resourceAppId"
                if(-not $objectIds.Contains($resourceTargetId)){
                    $r.Objects += [pscustomobject]@{Kind='apiResource';Object=[pscustomobject]@{id=$resourceTargetId;displayName=$resourceAppId;resourceAppId=$resourceAppId;resolution='resourceServicePrincipalNotPresent'}}
                    [void]$objectIds.Add($resourceTargetId)
                }
            }
            foreach($permission in @(Get-EntraTopologyProperty $resourceAccess 'resourceAccess')){
                $permissionId=[string](Get-EntraTopologyProperty $permission 'id');$permissionType=[string](Get-EntraTopologyProperty $permission 'type')
                if([string]::IsNullOrWhiteSpace($permissionId)){continue}
                $r.Relations += [pscustomobject]@{FromId=[string]$app.id;ToId=$resourceTargetId;Relationship='requiresApiPermission';Qualifier="$permissionType`:$permissionId";State=@{resourceAppId=$resourceAppId;resourceAccessId=$permissionId;permissionType=$permissionType};EvidenceRefs=@([pscustomobject]@{Capability='ApplicationRequestedPermissions';Endpoint=$appEp})}
            }
        }
    }

    foreach($sp in $selectedSps){
        foreach($credential in @($sp.keyCredentials)){
            $wrapper=New-EntraTopologyCredentialWrapper -ParentId ([string]$sp.id) -ParentKind servicePrincipal -CredentialType signingCertificate -Credential $credential
            $r.Objects += $wrapper
            $cred=$wrapper.Object
            $r.Relations += [pscustomobject]@{FromId=[string]$sp.id;ToId=[string]$cred.id;Relationship='hasCredential';Qualifier=[string]$cred.keyId;State=@{credentialType='signingCertificate';endDateTime=$cred.endDateTime};EvidenceRefs=@([pscustomobject]@{Capability='ServicePrincipalCredentialMetadata';Endpoint=$spEp})}
        }
    }

    $req=@()
    if($apps.Status-eq'Success'){
        foreach($app in @($apps.Items)){$req += [pscustomobject]@{Uri="/applications/$($app.id)/owners?`$select=id,displayName";Target=[string]$app.id;Relationship='owns';Capability='ApplicationOwnership'}}
    }
    if($sps.Status-eq'Success'){
        foreach($sp in $selectedSps){
            $req += [pscustomobject]@{Uri="/servicePrincipals/$($sp.id)/owners?`$select=id,displayName";Target=[string]$sp.id;Relationship='owns';Capability='ServicePrincipalOwnership'}
            $req += [pscustomobject]@{Uri="/servicePrincipals/$($sp.id)/appRoleAssignments";Target=[string]$sp.id;Relationship='hasAppRoleAssignment';Capability='ServicePrincipalAppRoleAssignments'}
        }
    }

    $failedCaps=@{}
    foreach($b in @(Invoke-EntraTopologyGraphBatch -Requests $req -BatchSize $BatchSize -Telemetry $Telemetry)){
        $cap=[string](Get-EntraTopologyProperty $b.Request 'Capability')
        Add-EntraTopologyBatchEvidence -Result $r -Capability $cap -BatchResult $b -RequiredPermission 'Application.Read.All or Directory.Read.All'
        if($b.Status-ne'Success'){$r.Status='Partial';$failedCaps[$cap]=$true;$r.Warnings += (Format-EntraTopologyBatchFailure -BatchResult $b -Prefix "$cap request failed");continue}
        $target=[string](Get-EntraTopologyProperty $b.Request 'Target')
        $relationship=[string](Get-EntraTopologyProperty $b.Request 'Relationship')
        foreach($o in @($b.Items)){
            if($relationship-eq'owns'){
                $r.Relations += [pscustomobject]@{FromId=[string]$o.id;ToId=$target;Relationship='owns';Qualifier='';State=@{};EvidenceRefs=@([pscustomobject]@{Capability=$cap;Endpoint=[string]$b.SourceEndpoint})}
            } else {
                $rid=[string](Get-EntraTopologyProperty $o 'resourceId')
                if($rid -and $spById.ContainsKey($rid)){Add-ReferenceSpIfNeeded $spById[$rid]}
                if($rid){$r.Relations += [pscustomobject]@{FromId=$target;ToId=$rid;Relationship='hasAppRoleAssignment';Qualifier=[string](Get-EntraTopologyProperty $o 'appRoleId');State=@{appRoleId=[string](Get-EntraTopologyProperty $o 'appRoleId');principalType=[string](Get-EntraTopologyProperty $o 'principalType')};EvidenceRefs=@([pscustomobject]@{Capability=$cap;Endpoint=[string]$b.SourceEndpoint})}}
            }
        }
    }
    foreach($cap in $failedCaps.Keys){Set-EntraTopologyCollectorCapability -Result $r -Name $cap -Status 'Partial' -RequiredPermissions $r.RequiredPermissions | Out-Null}

    $delegatedGrantCount=0
    $delegatedGrantPermissions=@('Directory.Read.All','DelegatedPermissionGrant.ReadWrite.All','Directory.ReadWrite.All')
    $delegatedGrantPermissionLabel='Directory.Read.All or DelegatedPermissionGrant.ReadWrite.All or Directory.ReadWrite.All'
    if(Test-EntraTopologyMayProbePermission -AnyOf $delegatedGrantPermissions){
        $grants=Invoke-EntraTopologyGraphRequest -Uri $grantEp -RequiredPermission $delegatedGrantPermissionLabel -Telemetry $Telemetry
        Add-EntraTopologyGraphResponseEvidence -Result $r -Capability 'DelegatedPermissionGrants' -Response $grants
        if($grants.Status -eq 'Success'){
            Set-EntraTopologyCollectorCapability -Result $r -Name 'DelegatedPermissionGrants' -Status 'Complete' -RequiredPermissions $delegatedGrantPermissions -Endpoints @($grantEp) | Out-Null
            foreach($grant in @($grants.Items)){
                $clientId=[string](Get-EntraTopologyProperty $grant 'clientId');$resourceId=[string](Get-EntraTopologyProperty $grant 'resourceId')
                if(-not$clientId -or -not$resourceId){continue}
                if($ExcludeMicrosoftFirstPartyApps -and $spById.ContainsKey($clientId) -and [string](Get-EntraTopologyProperty $spById[$clientId] 'enterpriseAppCategory') -eq 'MicrosoftFirstParty'){continue}
                if($spById.ContainsKey($clientId)){Add-ReferenceSpIfNeeded $spById[$clientId]}
                if($spById.ContainsKey($resourceId)){Add-ReferenceSpIfNeeded $spById[$resourceId]}
                $grantId=[string](Get-EntraTopologyProperty $grant 'id')
                $scope=[string](Get-EntraTopologyProperty $grant 'scope')
                $r.Relations += [pscustomobject]@{FromId=$clientId;ToId=$resourceId;Relationship='hasDelegatedPermission';Qualifier=$grantId;State=@{grantId=$grantId;scope=$scope;consentType=[string](Get-EntraTopologyProperty $grant 'consentType');principalId=[string](Get-EntraTopologyProperty $grant 'principalId')};EvidenceRefs=@([pscustomobject]@{Capability='DelegatedPermissionGrants';Endpoint=$grantEp})}
                $delegatedGrantCount++
            }
        } else {
            $warning="Optional delegated OAuth consent collection unavailable: HTTP $($grants.StatusCode); $(@($grants.Limitations)-join '; ')"
            $r.Warnings += $warning
            Set-EntraTopologyCollectorCapability -Result $r -Name 'DelegatedPermissionGrants' -Status 'Unavailable' -RequiredPermissions $delegatedGrantPermissions -Endpoints @($grantEp) -Warnings @($warning) | Out-Null
        }
    } else {
        $warning='Optional delegated OAuth consent collection was not run because none of the supported delegated-consent read permissions are present in the delegated Graph context.'
        Set-EntraTopologyCollectorCapability -Result $r -Name 'DelegatedPermissionGrants' -Status 'NotRun' -RequiredPermissions $delegatedGrantPermissions -Endpoints @($grantEp) -Warnings @($warning) | Out-Null
    }

    $credentialCount=@($r.Objects|Where-Object{[string](Get-EntraTopologyProperty $_ 'Kind') -eq 'applicationCredential'}).Count
    $requestedPermissionCount=@($r.Relations|Where-Object Relationship -eq 'requiresApiPermission').Count
    $r.Metrics=@{
        ApplicationCount=@($apps.Items).Count
        ServicePrincipalCount=@($selectedSps).Count
        ExcludedMicrosoftFirstPartyServicePrincipalCount=@($excludedMicrosoftSps).Count
        ReferenceOnlyServicePrincipalCount=@($r.Objects|Where-Object{[string](Get-EntraTopologyProperty $_ 'Kind') -eq 'servicePrincipal' -and [bool](Get-EntraTopologyProperty (Get-EntraTopologyProperty $_ 'Object') 'topologyReferenceOnly')}).Count
        CredentialCount=$credentialCount
        RequestedApiPermissionCount=$requestedPermissionCount
        DelegatedPermissionGrantCount=$delegatedGrantCount
        RelationCount=$r.Relations.Count
        ExcludeMicrosoftFirstPartyApps=[bool]$ExcludeMicrosoftFirstPartyApps
    }
    $r
}


function Get-EntraTopologyDevices {
    [CmdletBinding()] param([Parameter(Mandatory)][string]$TenantId,[object]$Telemetry,[ValidateRange(1,20)][int]$BatchSize=20)
    $r=New-EntraTopologyCollectorResult 'Devices'; $r.RequiredPermissions=@('Device.Read.All','Directory.Read.All')
    $ep='/v1.0/devices?$select=id,deviceId,displayName,accountEnabled,operatingSystem,operatingSystemVersion,trustType,approximateLastSignInDateTime,isCompliant,isManaged,registrationDateTime'
    Set-EntraTopologyCollectorCapability -Result $r -Name 'DeviceInventory' -Status 'Complete' -RequiredPermissions $r.RequiredPermissions -Endpoints @($ep) | Out-Null
    Set-EntraTopologyCollectorCapability -Result $r -Name 'DeviceRegisteredOwners' -Status 'Complete' -RequiredPermissions $r.RequiredPermissions | Out-Null
    if(-not(Test-EntraTopologyPermission -AnyOf $r.RequiredPermissions)){
        foreach($cap in @('DeviceInventory','DeviceRegisteredOwners')){Set-EntraTopologyCollectorCapability -Result $r -Name $cap -Status 'NotRun' -RequiredPermissions $r.RequiredPermissions -Warnings @('Device collection permission not granted.') | Out-Null}
        return Set-EntraTopologyCollectorNotRun $r $r.RequiredPermissions 'Device collection permission not granted.'
    }
    $g=Invoke-EntraTopologyGraphRequest -Uri $ep -RequiredPermission 'Device.Read.All or Directory.Read.All' -Telemetry $Telemetry
    Add-EntraTopologyGraphResponseEvidence -Result $r -Capability 'DeviceInventory' -Response $g
    if($g.Status-ne'Success'){
        $r.Status='Partial';$r.Warnings+=@($g.Limitations)
        Set-EntraTopologyCollectorCapability -Result $r -Name 'DeviceInventory' -Status 'Partial' -RequiredPermissions $r.RequiredPermissions -Endpoints @($ep) -Warnings @($g.Limitations) | Out-Null
        Set-EntraTopologyCollectorCapability -Result $r -Name 'DeviceRegisteredOwners' -Status 'NotRun' -RequiredPermissions $r.RequiredPermissions -Warnings @('Parent device inventory was not collected successfully.') | Out-Null
        return $r
    }
    $r.Objects=@($g.Items|ForEach-Object{[pscustomobject]@{Kind='device';Object=$_}})
    $req=@(); foreach($d in @($g.Items)){$req += [pscustomobject]@{Uri="/devices/$($d.id)/registeredOwners?`$select=id,displayName";Target=[string]$d.id;Capability='DeviceRegisteredOwners'}}
    $failed=$false
    foreach($b in @(Invoke-EntraTopologyGraphBatch -Requests $req -BatchSize $BatchSize -Telemetry $Telemetry)){
        Add-EntraTopologyBatchEvidence -Result $r -Capability 'DeviceRegisteredOwners' -BatchResult $b -RequiredPermission 'Device.Read.All or Directory.Read.All'
        if($b.Status-ne'Success'){$failed=$true;$r.Status='Partial';$r.Warnings+=(Format-EntraTopologyBatchFailure -BatchResult $b -Prefix 'Device registered-owner request failed');continue}
        $target=[string](Get-EntraTopologyProperty $b.Request 'Target')
        foreach($o in @($b.Items)){$r.Relations += [pscustomobject]@{FromId=[string]$o.id;ToId=$target;Relationship='registeredOwnerOf';Qualifier='';State=@{};EvidenceRefs=@([pscustomobject]@{Capability='DeviceRegisteredOwners';Endpoint=[string]$b.SourceEndpoint})}}
    }
    if($failed){Set-EntraTopologyCollectorCapability -Result $r -Name 'DeviceRegisteredOwners' -Status 'Partial' -RequiredPermissions $r.RequiredPermissions | Out-Null}
    $r.Metrics=@{Count=$g.Items.Count;RelationCount=$r.Relations.Count}; $r
}


function Get-EntraTopologyRoles {
    [CmdletBinding()] param([Parameter(Mandatory)][string]$TenantId,[object]$Telemetry)
    $r=New-EntraTopologyCollectorResult 'DirectoryRoles'; $r.RequiredPermissions=@('RoleManagement.Read.Directory','Directory.Read.All')
    $defEp='/v1.0/roleManagement/directory/roleDefinitions?$select=id,displayName,description,isBuiltIn,isEnabled,templateId'
    # Keep the directory-provider shape deliberately narrow. appScopeId is valid on the generic
    # unifiedRoleAssignment model but is not accepted by the directory provider in all tenants.
    $assignEp='/v1.0/roleManagement/directory/roleAssignments?$select=id,principalId,roleDefinitionId,directoryScopeId'
    Set-EntraTopologyCollectorCapability -Result $r -Name 'DirectoryRoleDefinitions' -Status 'Complete' -RequiredPermissions $r.RequiredPermissions -Endpoints @($defEp) | Out-Null
    Set-EntraTopologyCollectorCapability -Result $r -Name 'DirectoryRoleAssignments' -Status 'Complete' -RequiredPermissions $r.RequiredPermissions -Endpoints @($assignEp) | Out-Null

    if(-not(Test-EntraTopologyPermission -AnyOf $r.RequiredPermissions)){
        foreach($cap in @('DirectoryRoleDefinitions','DirectoryRoleAssignments')){Set-EntraTopologyCollectorCapability -Result $r -Name $cap -Status 'NotRun' -RequiredPermissions $r.RequiredPermissions -Warnings @('Directory role collection permission not granted.') | Out-Null}
        return Set-EntraTopologyCollectorNotRun $r $r.RequiredPermissions 'Directory role collection permission not granted.'
    }

    $defs=Invoke-EntraTopologyGraphRequest -Uri $defEp -RequiredPermission 'RoleManagement.Read.Directory or Directory.Read.All' -Telemetry $Telemetry
    $assign=Invoke-EntraTopologyGraphRequest -Uri $assignEp -RequiredPermission 'RoleManagement.Read.Directory or Directory.Read.All' -Telemetry $Telemetry
    Add-EntraTopologyGraphResponseEvidence -Result $r -Capability 'DirectoryRoleDefinitions' -Response $defs
    Add-EntraTopologyGraphResponseEvidence -Result $r -Capability 'DirectoryRoleAssignments' -Response $assign

    if($defs.Status-ne'Success'){
        $r.Status='Partial'
        $warning="Directory role definitions failed: HTTP $($defs.StatusCode); $(@($defs.Limitations)-join '; ')"
        if($defs.RequestId){$warning += " request-id=$($defs.RequestId)"}
        $r.Warnings += $warning
        Set-EntraTopologyCollectorCapability -Result $r -Name 'DirectoryRoleDefinitions' -Status 'Partial' -RequiredPermissions $r.RequiredPermissions -Endpoints @($defEp) -Warnings @($warning) | Out-Null
    }
    if($assign.Status-ne'Success'){
        $r.Status='Partial'
        $warning="Directory role assignments failed: HTTP $($assign.StatusCode); $(@($assign.Limitations)-join '; ')"
        if($assign.StatusCode -eq 403){$warning += ' Delegated access also requires the signed-in user to hold a supported Entra role such as Directory Readers, Global Reader, or Privileged Role Administrator.'}
        if($assign.RequestId){$warning += " request-id=$($assign.RequestId)"}
        $r.Warnings += $warning
        Set-EntraTopologyCollectorCapability -Result $r -Name 'DirectoryRoleAssignments' -Status 'Partial' -RequiredPermissions $r.RequiredPermissions -Endpoints @($assignEp) -Warnings @($warning) | Out-Null
    }

    $r.Objects=@($defs.Items|ForEach-Object{[pscustomobject]@{Kind='directoryRole';Object=$_}})
    foreach($a in @($assign.Items)){
        $scope=[string]$a.directoryScopeId
        $r.Relations += [pscustomobject]@{
            FromId=[string]$a.principalId
            ToId=[string]$a.roleDefinitionId
            Relationship='assignedDirectoryRole'
            Qualifier=$scope
            State=@{assignmentId=[string]$a.id;directoryScopeId=$scope;assignmentType='active'}
            EvidenceRefs=@([pscustomobject]@{Capability='DirectoryRoleAssignments';Endpoint=$assignEp})
        }
    }
    $r.Metrics=@{DefinitionCount=@($defs.Items).Count;AssignmentCount=@($assign.Items).Count}; $r
}


function ConvertTo-EntraTopologyDirectoryObjectKind {
    param([AllowNull()][object]$Object)
    $odataType=[string](Get-EntraTopologyProperty $Object '@odata.type')
    switch -Regex ($odataType) {
        'microsoft\.graph\.user$' { 'user'; break }
        'microsoft\.graph\.group$' { 'group'; break }
        'microsoft\.graph\.servicePrincipal$' { 'servicePrincipal'; break }
        'microsoft\.graph\.application$' { 'application'; break }
        'microsoft\.graph\.device$' { 'device'; break }
        'microsoft\.graph\.orgContact$' { 'orgContact'; break }
        default { 'directoryObject' }
    }
}

function Resolve-EntraTopologyDirectoryObjects {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TenantId,
        [Parameter(Mandatory)][object[]]$Collectors,
        [AllowNull()][object]$Telemetry
    )

    $r=New-EntraTopologyCollectorResult 'DirectoryObjectResolution'
    $r.RequiredPermissions=@('Directory.Read.All','RoleManagement.Read.Directory')

    $directoryEndpoint='/v1.0/directoryObjects/getByIds'
    $roleEndpointBase='/v1.0/roleManagement/directory/roleDefinitions'
    Set-EntraTopologyCollectorCapability -Result $r -Name 'DirectoryObjectResolution' -Status 'Complete' -RequiredPermissions @('Directory.Read.All') -Endpoints @($directoryEndpoint) | Out-Null
    Set-EntraTopologyCollectorCapability -Result $r -Name 'DirectoryRoleDefinitionResolution' -Status 'Complete' -RequiredPermissions @('RoleManagement.Read.Directory','Directory.Read.All') -Endpoints @($roleEndpointBase) | Out-Null

    $known=[System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach($collector in @($Collectors)){
        foreach($wrapper in @(Get-EntraTopologyProperty $collector 'Objects')){
            $obj=Get-EntraTopologyProperty $wrapper 'Object'
            $id=[string](Get-EntraTopologyProperty $obj 'id')
            if($id){[void]$known.Add($id)}
        }
    }

    $directoryCandidates=[System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $roleDefinitionCandidates=[System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach($collector in @($Collectors)){
        foreach($relation in @(Get-EntraTopologyProperty $collector 'Relations')){
            $relationship=[string](Get-EntraTopologyProperty $relation 'Relationship')
            $fromId=[string](Get-EntraTopologyProperty $relation 'FromId')
            $toId=[string](Get-EntraTopologyProperty $relation 'ToId')

            if($fromId -and -not $known.Contains($fromId)){
                [void]$directoryCandidates.Add($fromId)
            }
            if($toId -and -not $known.Contains($toId)){
                if($relationship -eq 'assignedDirectoryRole'){
                    [void]$roleDefinitionCandidates.Add($toId)
                } else {
                    [void]$directoryCandidates.Add($toId)
                }
            }
        }
    }

    $directoryRequested=@($directoryCandidates | Sort-Object)
    $roleRequested=@($roleDefinitionCandidates | Sort-Object)
    $directoryResolved=[System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $roleResolved=[System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $requestCount=0

    if($directoryRequested.Count -gt 0){
        if(-not(Test-EntraTopologyMayProbePermission -AnyOf @('Directory.Read.All'))){
            $warning='Directory.Read.All is required to resolve unknown directory-object principals referenced by collected relationships.'
            $r.Status='Partial'; $r.Warnings += $warning
            Set-EntraTopologyCollectorCapability -Result $r -Name 'DirectoryObjectResolution' -Status 'NotRun' -RequiredPermissions @('Directory.Read.All') -Endpoints @($directoryEndpoint) -Warnings @($warning) | Out-Null
        } else {
            for($offset=0;$offset -lt $directoryRequested.Count;$offset+=1000){
                $last=[math]::Min($offset+999,$directoryRequested.Count-1)
                $chunk=[string[]]@($directoryRequested[$offset..$last] | ForEach-Object {[string]$_})
                $requestCount++
                $response=Invoke-EntraTopologyGraphRequest -Uri $directoryEndpoint -Method POST -Body @{ids=$chunk} -RequiredPermission 'Directory.Read.All' -Telemetry $Telemetry
                Add-EntraTopologyGraphResponseEvidence -Result $r -Capability 'DirectoryObjectResolution' -Response $response
                if($response.Status -ne 'Success'){
                    $r.Status='Partial'
                    $warning="Directory object resolution failed: HTTP $($response.StatusCode); $(@($response.Limitations)-join '; ')"
                    if($response.RequestId){$warning += " request-id=$($response.RequestId)"}
                    $r.Warnings += $warning
                    Set-EntraTopologyCollectorCapability -Result $r -Name 'DirectoryObjectResolution' -Status 'Partial' -RequiredPermissions @('Directory.Read.All') -Endpoints @($directoryEndpoint) -Warnings @($warning) | Out-Null
                    continue
                }
                foreach($obj in @($response.Items)){
                    $id=[string](Get-EntraTopologyProperty $obj 'id')
                    if(-not$id){continue}
                    [void]$directoryResolved.Add($id)
                    $resolvedKind=ConvertTo-EntraTopologyDirectoryObjectKind $obj
                    if($resolvedKind -eq 'servicePrincipal' -and (Get-Command Add-EntraTopologyServicePrincipalClassification -ErrorAction SilentlyContinue)){
                        Add-EntraTopologyServicePrincipalClassification -ServicePrincipal $obj -TenantId $TenantId -ReferenceOnly | Out-Null
                    }
                    $obj | Add-Member -NotePropertyName topologyResolution -NotePropertyValue 'resolvedReference' -Force
                    $r.Objects += [pscustomobject]@{Kind=$resolvedKind;Object=$obj}
                }
            }
        }
    }

    if($roleRequested.Count -gt 0){
        if(-not(Test-EntraTopologyMayProbePermission -AnyOf @('RoleManagement.Read.Directory','Directory.Read.All'))){
            $warning='RoleManagement.Read.Directory or Directory.Read.All is required to resolve missing directory role definitions referenced by assignments.'
            $r.Status='Partial'; $r.Warnings += $warning
            Set-EntraTopologyCollectorCapability -Result $r -Name 'DirectoryRoleDefinitionResolution' -Status 'NotRun' -RequiredPermissions @('RoleManagement.Read.Directory','Directory.Read.All') -Endpoints @($roleEndpointBase) -Warnings @($warning) | Out-Null
        } else {
            foreach($roleId in $roleRequested){
                $endpoint="${roleEndpointBase}/${roleId}?`$select=id,displayName,description,isBuiltIn,isEnabled,templateId"
                $requestCount++
                $response=Invoke-EntraTopologyGraphRequest -Uri $endpoint -RequiredPermission 'RoleManagement.Read.Directory or Directory.Read.All' -Telemetry $Telemetry
                Add-EntraTopologyGraphResponseEvidence -Result $r -Capability 'DirectoryRoleDefinitionResolution' -Response $response
                if($response.Status -ne 'Success'){
                    $r.Status='Partial'
                    $warning="Directory role definition resolution failed for ${roleId}: HTTP $($response.StatusCode); $(@($response.Limitations)-join '; ')"
                    if($response.RequestId){$warning += " request-id=$($response.RequestId)"}
                    $r.Warnings += $warning
                    Set-EntraTopologyCollectorCapability -Result $r -Name 'DirectoryRoleDefinitionResolution' -Status 'Partial' -RequiredPermissions @('RoleManagement.Read.Directory','Directory.Read.All') -Endpoints @($roleEndpointBase) -Warnings @($r.Warnings) | Out-Null
                    continue
                }
                foreach($obj in @($response.Items)){
                    $id=[string](Get-EntraTopologyProperty $obj 'id')
                    if(-not$id){continue}
                    [void]$roleResolved.Add($id)
                    $r.Objects += [pscustomobject]@{Kind='directoryRole';Object=$obj}
                }
            }
        }
    }

    $directoryRemaining=@($directoryRequested | Where-Object {-not $directoryResolved.Contains([string]$_)})
    $roleRemaining=@($roleRequested | Where-Object {-not $roleResolved.Contains([string]$_)})
    if($directoryRemaining.Count -gt 0 -and (Get-EntraTopologyProperty (@($r.Capabilities|Where-Object Name -eq 'DirectoryObjectResolution')[0]) 'Status') -eq 'Complete'){
        $r.Warnings += "$($directoryRemaining.Count) directory object ID(s) were not returned by getByIds. They may have been deleted or may no longer be resolvable."
    }
    if($roleRemaining.Count -gt 0 -and (Get-EntraTopologyProperty (@($r.Capabilities|Where-Object Name -eq 'DirectoryRoleDefinitionResolution')[0]) 'Status') -eq 'Complete'){
        $r.Warnings += "$($roleRemaining.Count) directory role definition ID(s) could not be resolved through roleManagement/directory/roleDefinitions. They may reference deleted or unavailable role definitions."
    }

    $r.Metrics=@{
        RequestedDirectoryObjectCount=$directoryRequested.Count
        ResolvedDirectoryObjectCount=$directoryResolved.Count
        UnresolvedDirectoryObjectCount=$directoryRemaining.Count
        RequestedDirectoryRoleDefinitionCount=$roleRequested.Count
        ResolvedDirectoryRoleDefinitionCount=$roleResolved.Count
        UnresolvedDirectoryRoleDefinitionCount=$roleRemaining.Count
        RequestedCount=($directoryRequested.Count+$roleRequested.Count)
        ResolvedCount=($directoryResolved.Count+$roleResolved.Count)
        UnresolvedAfterResolution=($directoryRemaining.Count+$roleRemaining.Count)
        RequestCount=$requestCount
    }
    $r
}


function Invoke-EntraTopologyCollection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TenantId,
        [object]$Telemetry,
        [ValidateRange(1,20)][int]$BatchSize=20,
        [switch]$ExcludeMicrosoftFirstPartyApps
    )

    $collectors=@(
        Get-EntraTopologyUsers -TenantId $TenantId -Telemetry $Telemetry
        Get-EntraTopologyGroups -TenantId $TenantId -Telemetry $Telemetry -BatchSize $BatchSize
        Get-EntraTopologyApplications -TenantId $TenantId -Telemetry $Telemetry -BatchSize $BatchSize -ExcludeMicrosoftFirstPartyApps:$ExcludeMicrosoftFirstPartyApps
        Get-EntraTopologyDevices -TenantId $TenantId -Telemetry $Telemetry -BatchSize $BatchSize
        Get-EntraTopologyRoles -TenantId $TenantId -Telemetry $Telemetry
    )

    # A final read-only resolution pass keeps collectors independent while resolving relation endpoints
    # (for example role-assignment principals) that were not present in the primary inventories.
    $resolver=Resolve-EntraTopologyDirectoryObjects -TenantId $TenantId -Collectors $collectors -Telemetry $Telemetry
    @($collectors)+@($resolver)
}

