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
