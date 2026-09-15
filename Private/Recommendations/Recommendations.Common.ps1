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
