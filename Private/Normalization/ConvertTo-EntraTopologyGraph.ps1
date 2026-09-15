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
