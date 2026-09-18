function ConvertTo-EntraTopologyStateHashtable {
    param([AllowNull()][object]$InputObject)
    $result=@{}
    if($null -eq $InputObject){return $result}
    if($InputObject -is [System.Collections.IDictionary]){
        foreach($key in $InputObject.Keys){$result[[string]$key]=$InputObject[$key]}
        return $result
    }
    foreach($property in $InputObject.PSObject.Properties){$result[[string]$property.Name]=$property.Value}
    $result
}

function Add-EntraTopologyAppRoleState {
    param([Parameter(Mandatory)][hashtable]$State,[Parameter(Mandatory)][object]$ResourceNode)
    $appRoleId=[string]$State['appRoleId']
    $State['resourceDisplayName']=[string]$ResourceNode.DisplayName
    $resourceAppId=Get-EntraTopologyProperty $ResourceNode.Properties 'appId'
    if($resourceAppId){$State['resourceAppId']=[string]$resourceAppId}
    $State['appRoleResolved']=$false
    if([string]::IsNullOrWhiteSpace($appRoleId)){return}

    if($appRoleId -eq '00000000-0000-0000-0000-000000000000'){
        $State['appRoleValue']='DefaultAccess'
        $State['appRoleDisplayName']='Default access'
        $State['appRoleResolved']=$true
        return
    }

    foreach($role in @(Get-EntraTopologyProperty $ResourceNode.Properties 'appRoles')){
        if([string](Get-EntraTopologyProperty $role 'id') -ne $appRoleId){continue}
        $State['appRoleValue']=[string](Get-EntraTopologyProperty $role 'value')
        $State['appRoleDisplayName']=[string](Get-EntraTopologyProperty $role 'displayName')
        $State['appRoleDescription']=[string](Get-EntraTopologyProperty $role 'description')
        $State['appRoleIsEnabled']=[bool](Get-EntraTopologyProperty $role 'isEnabled')
        $State['appRoleAllowedMemberTypes']=@(Get-EntraTopologyProperty $role 'allowedMemberTypes')
        $State['appRoleResolved']=$true
        break
    }
}


function Add-EntraTopologyRequestedPermissionState {
    param([Parameter(Mandatory)][hashtable]$State,[Parameter(Mandatory)][object]$ResourceNode)
    $permissionId=[string]$State['resourceAccessId']
    $permissionType=[string]$State['permissionType']
    $State['resourceDisplayName']=[string]$ResourceNode.DisplayName
    $resourceAppId=Get-EntraTopologyProperty $ResourceNode.Properties 'appId'
    if($resourceAppId){$State['resourceAppId']=[string]$resourceAppId}
    $State['permissionResolved']=$false
    if([string]::IsNullOrWhiteSpace($permissionId)){return}

    $candidates=if($permissionType -eq 'Role'){@(Get-EntraTopologyProperty $ResourceNode.Properties 'appRoles')}else{@(Get-EntraTopologyProperty $ResourceNode.Properties 'oauth2PermissionScopes')}
    foreach($permission in $candidates){
        if([string](Get-EntraTopologyProperty $permission 'id') -ne $permissionId){continue}
        $State['permissionValue']=[string](Get-EntraTopologyProperty $permission 'value')
        $State['permissionDisplayName']=[string](Get-EntraTopologyProperty $permission 'adminConsentDisplayName')
        if([string]::IsNullOrWhiteSpace([string]$State['permissionDisplayName'])){$State['permissionDisplayName']=[string](Get-EntraTopologyProperty $permission 'displayName')}
        $State['permissionDescription']=[string](Get-EntraTopologyProperty $permission 'adminConsentDescription')
        if([string]::IsNullOrWhiteSpace([string]$State['permissionDescription'])){$State['permissionDescription']=[string](Get-EntraTopologyProperty $permission 'description')}
        $State['permissionResolved']=$true
        break
    }
}

function ConvertTo-EntraTopologyGraphInternal {
    [CmdletBinding()] param([Parameter(Mandatory)][object]$Snapshot,[switch]$IncludeSignals)
    $tenant=[string]$Snapshot.TenantId
    $nodes=[ordered]@{}
    $edges=[ordered]@{}
    $evidence=[System.Collections.Generic.List[object]]::new()
    $evidenceIndex=@{}
    $collectorEvidenceIndex=@{}

    foreach($collector in @($Snapshot.Collectors)){
        $collectorName=[string](Get-EntraTopologyProperty $collector 'Name')
        $collectorStatus=[string](Get-EntraTopologyProperty $collector 'Status')
        $ev=New-EntraTopologyEvidence -TenantId $tenant -Collector $collectorName -Endpoint ('collector:'+$collectorName) -SourceObjectId $collectorName `
            -Fields @{status=$collectorStatus;metrics=(Get-EntraTopologyProperty $collector 'Metrics');warnings=@(Get-EntraTopologyProperty $collector 'Warnings');capabilities=@(Get-EntraTopologyProperty $collector 'Capabilities')} `
            -Completeness $(switch($collectorStatus){'Complete'{'Complete'};'NotRun'{'NotRun'};'Unavailable'{'Unavailable'};default{'Partial'}})
        $evidence.Add($ev)
        $collectorEvidenceIndex[$collectorName]=[string]$ev.Key

        foreach($detail in @(Get-EntraTopologyProperty $collector 'Evidence')){
            $detailStatus=[string](Get-EntraTopologyProperty $detail 'Status')
            $endpoint=[string](Get-EntraTopologyProperty $detail 'Endpoint')
            $capability=[string](Get-EntraTopologyProperty $detail 'Capability')
            $fields=@{}
            if($detail -is [System.Collections.IDictionary]){
                foreach($key in $detail.Keys){if([string]$key -notin @('Endpoint','Status')){$fields[[string]$key]=$detail[$key]}}
            } else {
                foreach($p in $detail.PSObject.Properties){if($p.Name -notin @('Endpoint','Status')){$fields[$p.Name]=$p.Value}}
            }
            $detailEv=New-EntraTopologyEvidence -TenantId $tenant -Collector $collectorName -Endpoint $endpoint -SourceObjectId $(if($capability){$capability}else{$endpoint}) -Fields $fields `
                -Completeness $(switch($detailStatus){'Success'{'Complete'};'Complete'{'Complete'};'NotRun'{'NotRun'};'Unavailable'{'Unavailable'};default{'Partial'}})
            $evidence.Add($detailEv)
            if($capability -and $endpoint){$evidenceIndex["$collectorName|$capability|$endpoint"]=[string]$detailEv.Key}
        }

        foreach($wrapper in @(Get-EntraTopologyProperty $collector 'Objects')){
            $o=Get-EntraTopologyProperty $wrapper 'Object'
            $id=[string](Get-EntraTopologyProperty $o 'id')
            if(-not$id){continue}
            $name=[string](Get-EntraTopologyProperty $o 'displayName')
            if(-not$name){$name=[string](Get-EntraTopologyProperty $o 'userPrincipalName')}
            if(-not$name){$name=$id}
            $kind=[string](Get-EntraTopologyProperty $wrapper 'Kind')
            $props=@{}
            if($o -is [System.Collections.IDictionary]){
                foreach($key in $o.Keys){if([string]$key -notin @('id','displayName')){$props[[string]$key]=$o[$key]}}
            } else {
                foreach($p in $o.PSObject.Properties){if($p.Name -notin @('id','displayName')){$props[$p.Name]=$p.Value}}
            }
            $portalUri=Get-EntraTopologyPortalUri -TenantId $tenant -Kind $kind -ObjectId $id -AppId ([string](Get-EntraTopologyProperty $o 'appId'))
            if($portalUri){$props['portalUri']=$portalUri}
            $n=New-EntraTopologyNode -TenantId $tenant -ObjectId $id -Kind $kind -DisplayName $name -Properties $props -EvidenceKeys @($ev.Key)
            $nodes[$n.Key]=$n
        }
    }

    $byId=@{}
    foreach($n in $nodes.Values){$byId[[string]$n.Id]=[string]$n.Key}

    foreach($collector in @($Snapshot.Collectors)){
        $collectorName=[string](Get-EntraTopologyProperty $collector 'Name')
        foreach($rel in @(Get-EntraTopologyProperty $collector 'Relations')){
            $fromId=[string](Get-EntraTopologyProperty $rel 'FromId')
            $toId=[string](Get-EntraTopologyProperty $rel 'ToId')
            if(-not$fromId -or -not$toId){continue}

            $relationship=[string](Get-EntraTopologyProperty $rel 'Relationship')
            if(-not$byId.ContainsKey($fromId)){
                $n=New-EntraTopologyNode -TenantId $tenant -ObjectId $fromId -Kind 'directoryObject' -DisplayName $fromId -Properties @{resolution='unresolved';unresolvedType='directoryObject'}
                $nodes[$n.Key]=$n
                $byId[$fromId]=$n.Key
            }
            if(-not$byId.ContainsKey($toId)){
                if($relationship -eq 'assignedDirectoryRole'){
                    $n=New-EntraTopologyNode -TenantId $tenant -ObjectId $toId -Kind 'directoryRole' -DisplayName $toId -Properties @{resolution='unresolved';unresolvedType='roleDefinition'}
                } else {
                    $n=New-EntraTopologyNode -TenantId $tenant -ObjectId $toId -Kind 'directoryObject' -DisplayName $toId -Properties @{resolution='unresolved';unresolvedType='directoryObject'}
                }
                $nodes[$n.Key]=$n
                $byId[$toId]=$n.Key
            }

            $edgeEvidence=[System.Collections.Generic.List[string]]::new()
            foreach($ref in @(Get-EntraTopologyProperty $rel 'EvidenceRefs')){
                $capability=[string](Get-EntraTopologyProperty $ref 'Capability')
                $endpoint=[string](Get-EntraTopologyProperty $ref 'Endpoint')
                $indexKey="$collectorName|$capability|$endpoint"
                if($evidenceIndex.ContainsKey($indexKey) -and -not $edgeEvidence.Contains([string]$evidenceIndex[$indexKey])){$edgeEvidence.Add([string]$evidenceIndex[$indexKey])}
            }
            if($edgeEvidence.Count -eq 0 -and $collectorEvidenceIndex.ContainsKey($collectorName)){$edgeEvidence.Add([string]$collectorEvidenceIndex[$collectorName])}

            $state=ConvertTo-EntraTopologyStateHashtable (Get-EntraTopologyProperty $rel 'State')
            if($relationship -eq 'hasAppRoleAssignment'){
                $resourceNode=$nodes[$byId[$toId]]
                if($resourceNode -and [string]$resourceNode.Kind -eq 'servicePrincipal'){Add-EntraTopologyAppRoleState -State $state -ResourceNode $resourceNode}
            }
            if($relationship -eq 'requiresApiPermission'){
                $resourceNode=$nodes[$byId[$toId]]
                if($resourceNode -and [string]$resourceNode.Kind -eq 'servicePrincipal'){
                    Add-EntraTopologyRequestedPermissionState -State $state -ResourceNode $resourceNode
                } elseif($resourceNode){
                    $state['resourceDisplayName']=[string]$resourceNode.DisplayName
                    $state['permissionResolved']=$false
                }
            }

            $e=New-EntraTopologyEdge -TenantId $tenant -From $byId[$fromId] -To $byId[$toId] -Relationship $relationship `
                -Qualifier ([string](Get-EntraTopologyProperty $rel 'Qualifier')) -State $state -EvidenceKeys @($edgeEvidence)
            $edges[$e.Key]=$e
        }
    }

    $coverage=@($Snapshot.Collectors|ForEach-Object{
        [pscustomobject][ordered]@{
            Collector=(Get-EntraTopologyProperty $_ 'Name')
            Status=(Get-EntraTopologyProperty $_ 'Status')
            RequiredPermissions=@(Get-EntraTopologyProperty $_ 'RequiredPermissions')
            Capabilities=@(Get-EntraTopologyProperty $_ 'Capabilities')
            Warnings=@(Get-EntraTopologyProperty $_ 'Warnings')
            Metrics=(Get-EntraTopologyProperty $_ 'Metrics')
        }
    })

    $unresolvedNodes=@($nodes.Values|Where-Object{[string](Get-EntraTopologyProperty $_.Properties 'resolution') -eq 'unresolved'})
    $unresolvedDirectoryObjectCount=@($unresolvedNodes|Where-Object{[string]$_.Kind -eq 'directoryObject'}).Count
    $unresolvedDirectoryRoleCount=@($unresolvedNodes|Where-Object{[string]$_.Kind -eq 'directoryRole'}).Count
    $appRoleEdges=@($edges.Values|Where-Object Relationship -eq 'hasAppRoleAssignment')
    $resolvedAppRoleCount=@($appRoleEdges|Where-Object{[bool](Get-EntraTopologyProperty $_.State 'appRoleResolved')}).Count
    $credentialNodes=@($nodes.Values|Where-Object Kind -eq 'applicationCredential')
    $requestedPermissionEdges=@($edges.Values|Where-Object Relationship -eq 'requiresApiPermission')
    $resolvedRequestedPermissionCount=@($requestedPermissionEdges|Where-Object{[bool](Get-EntraTopologyProperty $_.State 'permissionResolved')}).Count
    $delegatedPermissionEdges=@($edges.Values|Where-Object Relationship -eq 'hasDelegatedPermission')

    $graph=[pscustomobject][ordered]@{
        SchemaVersion='1.2.0'
        GraphId=(Get-EntraTopologyStableId "$tenant|$($Snapshot.CollectedAtUtc)")
        TenantId=$tenant
        BuiltAtUtc=[datetime]::UtcNow.ToString('o')
        SourceSnapshotId=[string]$Snapshot.SnapshotId
        Nodes=@($nodes.Values)
        Edges=@($edges.Values)
        Evidence=@($evidence)
        Signals=@()
        Recommendations=@()
        Coverage=$coverage
        Metadata=@{
            NodeCount=$nodes.Count
            EdgeCount=$edges.Count
            UnresolvedObjectCount=$unresolvedNodes.Count
            UnresolvedDirectoryObjectCount=$unresolvedDirectoryObjectCount
            UnresolvedDirectoryRoleCount=$unresolvedDirectoryRoleCount
            AppRoleAssignmentCount=$appRoleEdges.Count
            ResolvedAppRoleAssignmentCount=$resolvedAppRoleCount
            UnresolvedAppRoleAssignmentCount=($appRoleEdges.Count-$resolvedAppRoleCount)
            CredentialCount=$credentialNodes.Count
            RequestedApiPermissionCount=$requestedPermissionEdges.Count
            ResolvedRequestedApiPermissionCount=$resolvedRequestedPermissionCount
            UnresolvedRequestedApiPermissionCount=($requestedPermissionEdges.Count-$resolvedRequestedPermissionCount)
            DelegatedPermissionGrantCount=$delegatedPermissionEdges.Count
            GraphCallsAfterSnapshot=0
        }
    }
    if($IncludeSignals){
        $graph.Signals=@(Add-EntraTopologySignals -Graph $graph)
        $graph.Recommendations=@(Add-EntraTopologyRecommendations -Graph $graph)
    }
    $graph.Metadata.SignalCount=@($graph.Signals).Count
    $graph.Metadata.RecommendationCount=@($graph.Recommendations).Count
    $graph
}


function Get-EntraTopologyCapabilityStatus {
    param([Parameter(Mandatory)][object]$Graph,[Parameter(Mandatory)][string]$Collector,[Parameter(Mandatory)][string]$Capability)
    $coverage = @($Graph.Coverage | Where-Object { [string]$_.Collector -eq $Collector } | Select-Object -First 1)
    if($coverage.Count -eq 0){ return 'Unknown' }
    $capabilities = @(Get-EntraTopologyProperty $coverage[0] 'Capabilities')
    $cap = @($capabilities | Where-Object { [string]$_.Name -eq $Capability } | Select-Object -First 1)
    if($cap.Count -eq 0){ return 'Unknown' }
    [string]$cap[0].Status
}

function Test-EntraTopologyCapabilityComplete {
    param([Parameter(Mandatory)][object]$Graph,[Parameter(Mandatory)][string]$Collector,[Parameter(Mandatory)][string]$Capability)
    (Get-EntraTopologyCapabilityStatus -Graph $Graph -Collector $Collector -Capability $Capability) -eq 'Complete'
}

function Get-EntraTopologyRiskSeverity {
    param([AllowNull()][string]$RiskLevel,[AllowNull()][string]$RiskState)
    if($RiskState -eq 'confirmedCompromised'){return 'Critical'}
    switch(([string]$RiskLevel).ToLowerInvariant()){
        'high' {'High';break}
        'medium' {'Medium';break}
        'low' {'Low';break}
        default {'Medium'}
    }
}

function Test-EntraTopologyHighImpactApplicationPermission {
    param([AllowNull()][string]$PermissionValue)
    if([string]::IsNullOrWhiteSpace($PermissionValue)){return $false}
    $highImpact=@(
        'AccessReview.ReadWrite.All',
        'Application.ReadWrite.All',
        'AppRoleAssignment.ReadWrite.All',
        'DelegatedPermissionGrant.ReadWrite.All',
        'Device.ReadWrite.All',
        'Directory.ReadWrite.All',
        'EntitlementManagement.ReadWrite.All',
        'Group.ReadWrite.All',
        'GroupMember.ReadWrite.All',
        'Policy.ReadWrite.ConditionalAccess',
        'PrivilegedAccess.ReadWrite.AzureAD',
        'PrivilegedAssignmentSchedule.ReadWrite.AzureADGroup',
        'PrivilegedEligibilitySchedule.ReadWrite.AzureADGroup',
        'RoleManagement.ReadWrite.Directory',
        'User.ReadWrite.All'
    )
    $highImpact -contains $PermissionValue
}

function Test-EntraTopologyHighPrivilegeRoleName {
    param([AllowNull()][string]$RoleName)
    if([string]::IsNullOrWhiteSpace($RoleName)){return $false}
    $highPrivilegeRoles=@(
        'Global Administrator',
        'Privileged Role Administrator',
        'Privileged Authentication Administrator',
        'Authentication Administrator',
        'Application Administrator',
        'Cloud Application Administrator',
        'Conditional Access Administrator',
        'Security Administrator',
        'User Administrator',
        'Groups Administrator',
        'Exchange Administrator',
        'SharePoint Administrator',
        'Intune Administrator',
        'Hybrid Identity Administrator'
    )
    $highPrivilegeRoles -contains $RoleName
}

function Add-EntraTopologySignals {
    [CmdletBinding()] param([Parameter(Mandatory)][object]$Graph)
    $signals=[System.Collections.Generic.List[object]]::new(); $now=[datetime]::UtcNow
    $nodesByKey=@{}; foreach($n in @($Graph.Nodes)){$nodesByKey[[string]$n.Key]=$n}
    $ownerCounts=@{}
    foreach($e in @($Graph.Edges|Where-Object Relationship -eq 'owns')){$ownerCounts[[string]$e.To]=1+([int]($ownerCounts[[string]$e.To]))}

    $ownerCoverageByKind=@{
        application      = @{Collector='Applications';Capability='ApplicationOwnership'}
        servicePrincipal = @{Collector='Applications';Capability='ServicePrincipalOwnership'}
        group            = @{Collector='Groups';Capability='GroupOwners'}
    }

    $userInventoryComplete = Test-EntraTopologyCapabilityComplete -Graph $Graph -Collector 'Users' -Capability 'UserInventory'
    $riskyUserContextComplete = Test-EntraTopologyCapabilityComplete -Graph $Graph -Collector 'Users' -Capability 'RiskyUserContext'
    $deviceInventoryComplete = Test-EntraTopologyCapabilityComplete -Graph $Graph -Collector 'Devices' -Capability 'DeviceInventory'
    $applicationInventoryComplete = Test-EntraTopologyCapabilityComplete -Graph $Graph -Collector 'Applications' -Capability 'ApplicationInventory'
    $applicationCredentialMetadataComplete = Test-EntraTopologyCapabilityComplete -Graph $Graph -Collector 'Applications' -Capability 'ApplicationCredentialMetadata'
    $servicePrincipalCredentialMetadataComplete = Test-EntraTopologyCapabilityComplete -Graph $Graph -Collector 'Applications' -Capability 'ServicePrincipalCredentialMetadata'
    $directoryRoleAssignmentsComplete = Test-EntraTopologyCapabilityComplete -Graph $Graph -Collector 'DirectoryRoles' -Capability 'DirectoryRoleAssignments'
    $appRoleAssignmentsComplete = Test-EntraTopologyCapabilityComplete -Graph $Graph -Collector 'Applications' -Capability 'ServicePrincipalAppRoleAssignments'
    $requestedPermissionsComplete = Test-EntraTopologyCapabilityComplete -Graph $Graph -Collector 'Applications' -Capability 'ApplicationRequestedPermissions'
    $delegatedPermissionsComplete = Test-EntraTopologyCapabilityComplete -Graph $Graph -Collector 'Applications' -Capability 'DelegatedPermissionGrants'
    $servicePrincipalInventoryComplete = Test-EntraTopologyCapabilityComplete -Graph $Graph -Collector 'Applications' -Capability 'ServicePrincipalInventory'

    $riskyUsers=[System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach($n in @($Graph.Nodes)){
        $p=$n.Properties
        if($n.Kind -eq 'user' -and $userInventoryComplete -and $p.accountEnabled -eq $false){
            $signals.Add((New-EntraTopologySignal -TenantId $Graph.TenantId -TargetKey $n.Key -Type 'disabledIdentity' -Severity 'Low' -Reason 'The user account is disabled.'))
        }

        if($n.Kind -eq 'user' -and $riskyUserContextComplete){
            $riskState=[string](Get-EntraTopologyProperty $p 'riskState')
            $riskLevel=[string](Get-EntraTopologyProperty $p 'riskLevel')
            if($riskState -in @('atRisk','confirmedCompromised')){
                [void]$riskyUsers.Add([string]$n.Key)
                $signals.Add((New-EntraTopologySignal -TenantId $Graph.TenantId -TargetKey $n.Key -Type 'riskyIdentity' -Severity (Get-EntraTopologyRiskSeverity -RiskLevel $riskLevel -RiskState $riskState) -Reason "Microsoft Entra ID Protection reports this user as $riskState with risk level $riskLevel." -State @{
                    riskLevel=$riskLevel
                    riskState=$riskState
                    riskDetail=[string](Get-EntraTopologyProperty $p 'riskDetail')
                    riskLastUpdatedDateTime=[string](Get-EntraTopologyProperty $p 'riskLastUpdatedDateTime')
                }))
            }
        }

        if($ownerCoverageByKind.ContainsKey([string]$n.Kind)){
            $coverage=$ownerCoverageByKind[[string]$n.Kind]
            $ownerSignalApplicable=$true
            if($n.Kind -eq 'servicePrincipal'){
                $spType=[string](Get-EntraTopologyProperty $p 'servicePrincipalType')
                $ownerOrg=[string](Get-EntraTopologyProperty $p 'appOwnerOrganizationId')
                $ownerSignalApplicable=($spType -eq 'Application' -and -not [string]::IsNullOrWhiteSpace($ownerOrg) -and $ownerOrg -eq [string]$Graph.TenantId)
            }
            if($ownerSignalApplicable -and (Test-EntraTopologyCapabilityComplete -Graph $Graph -Collector $coverage.Collector -Capability $coverage.Capability) -and -not $ownerCounts.ContainsKey([string]$n.Key)){
                $reason=if($n.Kind -eq 'servicePrincipal'){'Ownership coverage is complete and no owner relationship was observed for this tenant-owned application service principal.'}else{'Ownership coverage is complete and no owner relationship was observed in the collected topology.'}
                $signals.Add((New-EntraTopologySignal -TenantId $Graph.TenantId -TargetKey $n.Key -Type 'ownerlessObject' -Severity 'Medium' -Reason $reason))
            }
        }

        if($n.Kind -eq 'device' -and $deviceInventoryComplete -and $p.approximateLastSignInDateTime){
            try{
                $last=[datetime]$p.approximateLastSignInDateTime
                if(($now-$last.ToUniversalTime()).TotalDays-ge90){
                    $signals.Add((New-EntraTopologySignal -TenantId $Graph.TenantId -TargetKey $n.Key -Type 'staleDevice' -Severity 'Low' -Reason 'The device has not signed in for at least 90 days.' -State @{lastSignInUtc=$last.ToUniversalTime().ToString('o')}))
                }
            }catch{}
        }

        if($n.Kind -eq 'servicePrincipal' -and $servicePrincipalInventoryComplete -and -not [bool](Get-EntraTopologyProperty $p 'topologyReferenceOnly') -and (Get-EntraTopologyProperty $p 'accountEnabled') -eq $false){
            $signals.Add((New-EntraTopologySignal -TenantId $Graph.TenantId -TargetKey $n.Key -Type 'disabledWorkloadIdentity' -Severity 'Low' -Reason 'The service principal is disabled.'))
        }

        if($n.Kind -eq 'applicationCredential'){
            $parentKind=[string](Get-EntraTopologyProperty $p 'parentKind')
            $credentialCoverageComplete=if($parentKind -eq 'servicePrincipal'){$servicePrincipalCredentialMetadataComplete}else{$applicationCredentialMetadataComplete}
            if(-not $credentialCoverageComplete){continue}
            $endValue=Get-EntraTopologyProperty $p 'endDateTime'
            if($endValue){
                try{
                    $end=[datetime]$endValue
                    $days=[math]::Floor(($end.ToUniversalTime()-$now).TotalDays)
                    $credentialType=[string](Get-EntraTopologyProperty $p 'credentialType')
                    $friendlyType=if($credentialType -eq 'passwordCredential'){'client secret'}elseif($credentialType -in @('keyCredential','signingCertificate')){'certificate'}else{'credential'}
                    if($days -lt 0){
                        $signals.Add((New-EntraTopologySignal -TenantId $Graph.TenantId -TargetKey $n.Key -Type 'credentialExpired' -Severity 'High' -Reason "The $friendlyType expired $([math]::Abs($days)) day(s) ago." -State @{endDateTime=$end.ToUniversalTime().ToString('o');credentialType=$credentialType;daysRemaining=$days;expiryWindow='Expired'}))
                    } elseif($days -le 30){
                        $signals.Add((New-EntraTopologySignal -TenantId $Graph.TenantId -TargetKey $n.Key -Type 'credentialExpiring' -Severity 'Medium' -Reason "The $friendlyType expires in $days day(s)." -State @{endDateTime=$end.ToUniversalTime().ToString('o');credentialType=$credentialType;daysRemaining=$days;expiryWindow='30 days'}))
                    } elseif($days -le 60){
                        $signals.Add((New-EntraTopologySignal -TenantId $Graph.TenantId -TargetKey $n.Key -Type 'credentialExpiring' -Severity 'Low' -Reason "The $friendlyType expires in $days day(s)." -State @{endDateTime=$end.ToUniversalTime().ToString('o');credentialType=$credentialType;daysRemaining=$days;expiryWindow='60 days'}))
                    } elseif($days -le 90){
                        $signals.Add((New-EntraTopologySignal -TenantId $Graph.TenantId -TargetKey $n.Key -Type 'credentialExpiring' -Severity 'Info' -Reason "The $friendlyType expires in $days day(s)." -State @{endDateTime=$end.ToUniversalTime().ToString('o');credentialType=$credentialType;daysRemaining=$days;expiryWindow='90 days'}))
                    }
                }catch{}
            }
        }
    }

    $privilegedPrincipals=@{}
    if($directoryRoleAssignmentsComplete){
        foreach($e in @($Graph.Edges|Where-Object Relationship -eq 'assignedDirectoryRole')){
            $principalKey=[string]$e.From
            $role=$nodesByKey[[string]$e.To]
            $roleName=if($role){[string]$role.DisplayName}else{[string]$e.To}
            if(-not$privilegedPrincipals.ContainsKey($principalKey)){$privilegedPrincipals[$principalKey]=[System.Collections.Generic.List[string]]::new()}
            if(-not$privilegedPrincipals[$principalKey].Contains($roleName)){$privilegedPrincipals[$principalKey].Add($roleName)}
            if(Test-EntraTopologyHighPrivilegeRoleName -RoleName $roleName){
                $signals.Add((New-EntraTopologySignal -TenantId $Graph.TenantId -TargetKey $e.Key -Type 'highPrivilegeRoleAssignment' -Severity 'High' -Reason "The principal has an active assignment to the high-impact directory role '$roleName'." -State @{roleName=$roleName;principalKey=$principalKey;roleKey=[string]$e.To}))
            }
        }
        foreach($principalKey in $privilegedPrincipals.Keys){
            $roles=@($privilegedPrincipals[$principalKey])
            $hasHigh=@($roles|Where-Object{Test-EntraTopologyHighPrivilegeRoleName -RoleName $_}).Count -gt 0
            $signals.Add((New-EntraTopologySignal -TenantId $Graph.TenantId -TargetKey $principalKey -Type 'privilegedIdentity' -Severity $(if($hasHigh){'High'}else{'Info'}) -Reason "The identity has $($roles.Count) active Microsoft Entra directory role assignment(s)." -State @{roles=$roles;highPrivilegeRole=$hasHigh}))
        }
    }

    if($appRoleAssignmentsComplete){
        foreach($e in @($Graph.Edges|Where-Object Relationship -eq 'hasAppRoleAssignment')){
            $permission=[string](Get-EntraTopologyProperty $e.State 'appRoleValue')
            if(Test-EntraTopologyHighImpactApplicationPermission -PermissionValue $permission){
                $resource=[string](Get-EntraTopologyProperty $e.State 'resourceDisplayName')
                $signals.Add((New-EntraTopologySignal -TenantId $Graph.TenantId -TargetKey $e.Key -Type 'highImpactApplicationPermission' -Severity 'High' -Reason "The workload identity holds the high-impact application permission '$permission' on '$resource'." -State @{permission=$permission;resourceDisplayName=$resource;principalKey=[string]$e.From;resourceKey=[string]$e.To}))
            }
        }
    }

    if($requestedPermissionsComplete){
        foreach($e in @($Graph.Edges|Where-Object Relationship -eq 'requiresApiPermission')){
            $permission=[string](Get-EntraTopologyProperty $e.State 'permissionValue')
            if(Test-EntraTopologyHighImpactApplicationPermission -PermissionValue $permission){
                $resource=[string](Get-EntraTopologyProperty $e.State 'resourceDisplayName')
                $signals.Add((New-EntraTopologySignal -TenantId $Graph.TenantId -TargetKey $e.Key -Type 'highImpactRequestedPermission' -Severity 'Info' -Reason "The app registration requests the high-impact API permission '$permission' on '$resource'. Requested access is configuration intent and is not evidence that consent was granted." -State @{permission=$permission;resourceDisplayName=$resource;permissionType=[string](Get-EntraTopologyProperty $e.State 'permissionType')}))
            }
        }
    }

    if($delegatedPermissionsComplete){
        foreach($e in @($Graph.Edges|Where-Object Relationship -eq 'hasDelegatedPermission')){
            $scopes=@(([string](Get-EntraTopologyProperty $e.State 'scope') -split '\s+')|Where-Object{$_})
            $high=@($scopes|Where-Object{Test-EntraTopologyHighImpactApplicationPermission -PermissionValue $_})
            if($high.Count -gt 0){
                $signals.Add((New-EntraTopologySignal -TenantId $Graph.TenantId -TargetKey $e.Key -Type 'highImpactDelegatedPermission' -Severity 'High' -Reason "The enterprise application has delegated consent for high-impact scope(s): $($high -join ', ')." -State @{scopes=$scopes;highImpactScopes=$high;consentType=[string](Get-EntraTopologyProperty $e.State 'consentType');principalId=[string](Get-EntraTopologyProperty $e.State 'principalId')}))
            }
        }
    }

    if($userInventoryComplete){
        $disabled=@{}
        $guestUsers=@{}
        foreach($n in @($Graph.Nodes|Where-Object Kind -eq 'user')){
            if($n.Properties.accountEnabled-eq$false){$disabled[$n.Key]=$true}
            if([string](Get-EntraTopologyProperty $n.Properties 'userType') -eq 'Guest'){$guestUsers[$n.Key]=$true}
        }
        foreach($e in @($Graph.Edges|Where-Object Relationship -eq 'owns')){
            $ownerKey=[string]$e.From
            if($disabled.ContainsKey($ownerKey)){
                $signals.Add((New-EntraTopologySignal -TenantId $Graph.TenantId -TargetKey $e.Key -Type 'disabledOwnerRelationship' -Severity 'High' -Reason 'A disabled user owns an Entra object.' -State @{ownerKey=$e.From;targetKey=$e.To}))
            }
            if($guestUsers.ContainsKey($ownerKey)){
                $signals.Add((New-EntraTopologySignal -TenantId $Graph.TenantId -TargetKey $e.Key -Type 'guestOwnerRelationship' -Severity 'Medium' -Reason 'A guest user owns an Entra object.' -State @{ownerKey=$e.From;targetKey=$e.To}))
            }
            if($riskyUsers.Contains($ownerKey)){
                $signals.Add((New-EntraTopologySignal -TenantId $Graph.TenantId -TargetKey $e.Key -Type 'riskyOwnerRelationship' -Severity 'High' -Reason 'A user currently reported at risk by Microsoft Entra ID Protection owns this Entra object.' -State @{ownerKey=$e.From;targetKey=$e.To}))
            }
            if($privilegedPrincipals.ContainsKey($ownerKey)){
                $signals.Add((New-EntraTopologySignal -TenantId $Graph.TenantId -TargetKey $e.Key -Type 'privilegedOwnerRelationship' -Severity 'Medium' -Reason 'An identity with an active Microsoft Entra directory role assignment owns this Entra object.' -State @{ownerKey=$e.From;targetKey=$e.To;roles=@($privilegedPrincipals[$ownerKey])}))
            }
        }
    }
    @($signals)
}


function Get-EntraTopologyRecommendationDefinition {
    [CmdletBinding()] param([Parameter(Mandatory)][string]$SignalType)
    $map=@{
        credentialExpired=@{Title='Replace expired application credential';Action='Create a replacement secret or certificate, update the workload, validate sign-in, then remove the expired credential.';Rationale='Expired credentials can cause workload outages and indicate weak credential lifecycle management.';Priority='High';ReferenceTitle='Microsoft Entra recommendation: Renew expiring application credentials';ReferenceUrl='https://learn.microsoft.com/en-us/entra/identity/monitoring-health/recommendation-renew-expiring-application-credential'}
        credentialExpiring=@{Title='Rotate expiring application credential';Action='Plan and complete credential rotation before expiry, validate the replacement, then retire the old credential.';Rationale='Rotating credentials before expiration reduces avoidable workload outages.';Priority='High';ReferenceTitle='Microsoft Entra recommendation: Renew expiring application credentials';ReferenceUrl='https://learn.microsoft.com/en-us/entra/identity/monitoring-health/recommendation-renew-expiring-application-credential'}
        ownerlessObject=@{Title='Assign accountable owners';Action='Assign at least one appropriate owner and validate that ownership reflects operational responsibility.';Rationale='Ownerless Entra objects are harder to govern, review, and remediate safely.';Priority='Medium';ReferenceTitle='Applications and service principals in Microsoft Entra ID';ReferenceUrl='https://learn.microsoft.com/en-us/entra/identity-platform/app-objects-and-service-principals'}
        highImpactApplicationPermission=@{Title='Review high-impact application permission';Action='Confirm the permission is required. Remove or reduce it where possible and prefer least-privileged permissions.';Rationale='High-impact application permissions can materially increase workload blast radius.';Priority='High';ReferenceTitle='Increase application security with the principle of least privilege';ReferenceUrl='https://learn.microsoft.com/en-us/entra/identity-platform/secure-least-privileged-access'}
        highImpactDelegatedPermission=@{Title='Review high-impact delegated consent';Action='Validate business need, consent scope, and affected users. Revoke or reduce unnecessary delegated consent.';Rationale='Broad delegated permissions can expose user data beyond operational need.';Priority='High';ReferenceTitle='Increase application security with the principle of least privilege';ReferenceUrl='https://learn.microsoft.com/en-us/entra/identity-platform/secure-least-privileged-access'}
        highImpactRequestedPermission=@{Title='Review requested high-impact permission';Action='Validate that the requested permission is necessary before consent is granted and remove unused requests.';Rationale='Requested permissions represent intended access and should align with least privilege.';Priority='Medium';ReferenceTitle='Increase application security with the principle of least privilege';ReferenceUrl='https://learn.microsoft.com/en-us/entra/identity-platform/secure-least-privileged-access'}
        highPrivilegeRoleAssignment=@{Title='Review privileged role assignment';Action='Confirm the active assignment is necessary, time-bound where possible, and aligned with least privilege and PIM practices.';Rationale='Persistent privileged role assignments increase administrative attack surface.';Priority='High';ReferenceTitle='Best practices for Microsoft Entra roles';ReferenceUrl='https://learn.microsoft.com/en-us/entra/identity/role-based-access-control/best-practices'}
        privilegedIdentity=@{Title='Review privileged identity';Action='Validate role necessity, reduce standing privilege, and use just-in-time activation where supported.';Rationale='Privileged identities warrant stronger governance and regular access review.';Priority='Medium';ReferenceTitle='Best practices for Microsoft Entra roles';ReferenceUrl='https://learn.microsoft.com/en-us/entra/identity/role-based-access-control/best-practices'}
        riskyIdentity=@{Title='Investigate risky identity';Action='Investigate the risk event, validate account activity, and remediate or dismiss risk according to incident response procedures.';Rationale='Microsoft Entra ID Protection has identified risk on this identity.';Priority='High';ReferenceTitle='Investigate risk with Microsoft Entra ID Protection';ReferenceUrl='https://learn.microsoft.com/en-us/entra/id-protection/howto-identity-protection-investigate-risk'}
        riskyOwnerRelationship=@{Title='Review risky owner relationship';Action='Investigate the risky identity and transfer ownership if the account should not retain control of the target object.';Rationale='Ownership by a risky identity can create consequential control paths.';Priority='High';ReferenceTitle='Investigate risk with Microsoft Entra ID Protection';ReferenceUrl='https://learn.microsoft.com/en-us/entra/id-protection/howto-identity-protection-investigate-risk'}
        disabledOwnerRelationship=@{Title='Replace disabled owner';Action='Assign an active accountable owner and remove the disabled identity from ownership where appropriate.';Rationale='Disabled identities should not remain operational owners of important Entra objects.';Priority='High';ReferenceTitle='Applications and service principals in Microsoft Entra ID';ReferenceUrl='https://learn.microsoft.com/en-us/entra/identity-platform/app-objects-and-service-principals'}
        guestOwnerRelationship=@{Title='Review guest ownership';Action='Validate that guest ownership is intentional and transfer ownership to an internal accountable identity when possible.';Rationale='External ownership can complicate lifecycle governance and administrative accountability.';Priority='Medium';ReferenceTitle='Secure access control using groups in Microsoft Entra ID';ReferenceUrl='https://learn.microsoft.com/en-us/entra/identity-platform/secure-group-access-control'}
        privilegedOwnerRelationship=@{Title='Review privileged owner relationship';Action='Confirm that privileged identity ownership is necessary and separate administrative privilege from application ownership where practical.';Rationale='Combining privileged directory access and object ownership can increase control concentration.';Priority='Medium';ReferenceTitle='Best practices for Microsoft Entra roles';ReferenceUrl='https://learn.microsoft.com/en-us/entra/identity/role-based-access-control/best-practices'}
        staleDevice=@{Title='Review stale device';Action='Validate whether the device is still in use. Retire or remove stale device objects according to endpoint lifecycle policy.';Rationale='Stale device records reduce inventory accuracy and can retain unnecessary trust relationships.';Priority='Low';ReferenceTitle='Manage stale devices in Microsoft Entra ID';ReferenceUrl='https://learn.microsoft.com/en-us/entra/identity/devices/manage-stale-devices'}
        disabledWorkloadIdentity=@{Title='Review disabled workload identity';Action='Confirm the service principal is intentionally disabled and remove obsolete assignments, credentials, or ownership relationships.';Rationale='Disabled workload identities can leave behind unnecessary permissions and governance artifacts.';Priority='Low';ReferenceTitle='Applications and service principals in Microsoft Entra ID';ReferenceUrl='https://learn.microsoft.com/en-us/entra/identity-platform/app-objects-and-service-principals'}
    }
    if($map.ContainsKey($SignalType)){return $map[$SignalType]}
    $null
}

function New-EntraTopologyRecommendation {
    [CmdletBinding()] param(
        [Parameter(Mandatory)][string]$TenantId,
        [Parameter(Mandatory)][object]$Signal,
        [Parameter(Mandatory)][hashtable]$Definition
    )
    $seed='{0}|{1}|{2}' -f $TenantId,[string]$Signal.Key,[string]$Definition.Title
    $key="recommendation:$(Get-EntraTopologyStableId -InputString $seed)"
    [pscustomobject][ordered]@{
        SchemaVersion='1.0.0'
        Key=$key
        TenantId=$TenantId
        SignalKey=[string]$Signal.Key
        TargetKey=[string]$Signal.TargetKey
        Priority=[string]$Definition.Priority
        Title=[string]$Definition.Title
        Action=[string]$Definition.Action
        Rationale=[string]$Definition.Rationale
        References=@([pscustomobject][ordered]@{Title=[string]$Definition.ReferenceTitle;Url=[string]$Definition.ReferenceUrl;Source='Microsoft Learn'})
    }
}

function Add-EntraTopologyRecommendations {
    [CmdletBinding()] param([Parameter(Mandatory)][object]$Graph)
    $out=[System.Collections.Generic.List[object]]::new()
    foreach($signal in @($Graph.Signals)){
        $definition=Get-EntraTopologyRecommendationDefinition -SignalType ([string]$signal.Type)
        if($definition){$out.Add((New-EntraTopologyRecommendation -TenantId ([string]$Graph.TenantId) -Signal $signal -Definition $definition))}
    }
    @($out)
}

