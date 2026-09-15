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
