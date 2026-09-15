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
