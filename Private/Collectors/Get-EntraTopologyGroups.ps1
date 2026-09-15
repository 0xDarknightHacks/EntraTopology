function Get-EntraTopologyGroups {
    [CmdletBinding()] param([Parameter(Mandatory)][string]$TenantId,[object]$Telemetry,[ValidateRange(1,20)][int]$BatchSize=20)
    $r=New-EntraTopologyCollectorResult 'Groups'; $r.RequiredPermissions=@('Group.Read.All','Directory.Read.All')
    $ep='/v1.0/groups?$select=id,displayName,description,groupTypes,mailEnabled,securityEnabled,isAssignableToRole,createdDateTime'
    Set-EntraTopologyCollectorCapability -Result $r -Name 'GroupInventory' -Status 'Complete' -RequiredPermissions $r.RequiredPermissions -Endpoints @($ep) | Out-Null
    Set-EntraTopologyCollectorCapability -Result $r -Name 'GroupMembers' -Status 'Complete' -RequiredPermissions $r.RequiredPermissions | Out-Null
    Set-EntraTopologyCollectorCapability -Result $r -Name 'GroupOwners' -Status 'Complete' -RequiredPermissions $r.RequiredPermissions | Out-Null

    if (-not(Test-EntraTopologyPermission -AnyOf $r.RequiredPermissions)) {
        foreach($cap in @('GroupInventory','GroupMembers','GroupOwners')) { Set-EntraTopologyCollectorCapability -Result $r -Name $cap -Status 'NotRun' -RequiredPermissions $r.RequiredPermissions -Warnings @('Group collection permission not granted.') | Out-Null }
        return Set-EntraTopologyCollectorNotRun $r $r.RequiredPermissions 'Group collection permission not granted.'
    }

    $g=Invoke-EntraTopologyGraphRequest -Uri $ep -RequiredPermission 'Group.Read.All or Directory.Read.All' -Telemetry $Telemetry
    Add-EntraTopologyGraphResponseEvidence -Result $r -Capability 'GroupInventory' -Response $g
    if($g.Status-ne'Success'){
        $r.Status='Partial'; $r.Warnings+=@($g.Limitations)
        Set-EntraTopologyCollectorCapability -Result $r -Name 'GroupInventory' -Status 'Partial' -RequiredPermissions $r.RequiredPermissions -Endpoints @($ep) -Warnings @($g.Limitations) | Out-Null
        foreach($cap in @('GroupMembers','GroupOwners')) { Set-EntraTopologyCollectorCapability -Result $r -Name $cap -Status 'NotRun' -RequiredPermissions $r.RequiredPermissions -Warnings @('Parent group inventory was not collected successfully.') | Out-Null }
        return $r
    }

    $r.Objects=@($g.Items|ForEach-Object{[pscustomobject]@{Kind='group';Object=$_}})
    $req=@()
    foreach($group in $g.Items){
        $req += [pscustomobject]@{Uri="/groups/$($group.id)/members?`$select=id,displayName";GroupId=[string]$group.id;Relation='memberOf';Capability='GroupMembers'}
        $req += [pscustomobject]@{Uri="/groups/$($group.id)/owners?`$select=id,displayName";GroupId=[string]$group.id;Relation='owns';Capability='GroupOwners'}
    }
    $failedCaps=@{}
    foreach($b in @(Invoke-EntraTopologyGraphBatch -Requests $req -BatchSize $BatchSize -Telemetry $Telemetry)){
        $request=Get-EntraTopologyProperty $b 'Request'; $cap=[string](Get-EntraTopologyProperty $request 'Capability')
        Add-EntraTopologyBatchEvidence -Result $r -Capability $cap -BatchResult $b -RequiredPermission 'Group.Read.All or Directory.Read.All'
        if($b.Status-ne'Success'){
            $r.Status='Partial'; $failedCaps[$cap]=$true; $r.Warnings += (Format-EntraTopologyBatchFailure -BatchResult $b -Prefix 'Group relation request failed'); continue
        }
        $groupId=[string](Get-EntraTopologyProperty $request 'GroupId'); $relation=[string](Get-EntraTopologyProperty $request 'Relation')
        if(-not $groupId -or -not $relation){$r.Status='Partial';$failedCaps[$cap]=$true;$r.Warnings += "Group relation response skipped because correlation metadata was missing: $($b.SourceEndpoint)";continue}
        foreach($o in @($b.Items)){ $r.Relations += [pscustomobject]@{FromId=[string]$o.id;ToId=$groupId;Relationship=$relation;Qualifier='';State=@{source='groupCollection'};EvidenceRefs=@([pscustomobject]@{Capability=$cap;Endpoint=[string]$b.SourceEndpoint})} }
    }
    foreach($cap in @('GroupMembers','GroupOwners')) { if($failedCaps.ContainsKey($cap)){Set-EntraTopologyCollectorCapability -Result $r -Name $cap -Status 'Partial' -RequiredPermissions $r.RequiredPermissions | Out-Null} }
    $r.Metrics=@{Count=$g.Items.Count;RelationCount=$r.Relations.Count}; $r
}
