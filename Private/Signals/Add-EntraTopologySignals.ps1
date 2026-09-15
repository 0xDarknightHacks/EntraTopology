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
