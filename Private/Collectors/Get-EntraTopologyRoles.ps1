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
