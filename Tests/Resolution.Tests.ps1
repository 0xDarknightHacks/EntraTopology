BeforeAll { Import-Module (Join-Path $PSScriptRoot '..' 'EntraTopology.psd1') -Force }

Describe 'Relationship endpoint resolution' {
    InModuleScope EntraTopology {
        It 'resolves unknown directory-object principals with directoryObjects/getByIds' {
            Mock Test-EntraTopologyPermission { $true }
            Mock Get-EntraTopologyGraphContext { $null }
            Mock Invoke-EntraTopologyGraphRequest {
                param($Uri,$Method,$Body,$RequiredPermission,$Telemetry)
                $Uri | Should -Be '/v1.0/directoryObjects/getByIds'
                $Method | Should -Be 'POST'
                $Body.ids | Should -Contain 'u1'
                [pscustomobject]@{SourceEndpoint=$Uri;RequiredPermission=$RequiredPermission;Status='Success';StatusCode=200;Items=@([pscustomobject]@{'@odata.type'='#microsoft.graph.user';id='u1';displayName='Resolved User';userPrincipalName='user@contoso.com'});CollectionTime='';Limitations=@();ErrorCode=$null;ErrorMessage=$null;RequestId='req1';RetryCount=0;PageCount=1}
            }
            $base=@([pscustomobject]@{Name='DirectoryRoles';Status='Complete';RequiredPermissions=@();Capabilities=@();Warnings=@();Metrics=@{};Evidence=@();Objects=@([pscustomobject]@{Kind='directoryRole';Object=[pscustomobject]@{id='r1';displayName='Role'}});Relations=@([pscustomobject]@{FromId='u1';ToId='r1';Relationship='assignedDirectoryRole';Qualifier='/';State=@{};EvidenceRefs=@()})})
            $result=Resolve-EntraTopologyDirectoryObjects -TenantId 'tenant' -Collectors $base
            $result.Status | Should -Be 'Complete'
            $result.Objects.Count | Should -Be 1
            $result.Objects[0].Kind | Should -Be 'user'
            $result.Metrics.UnresolvedDirectoryObjectCount | Should -Be 0
            $result.Metrics.RequestedDirectoryRoleDefinitionCount | Should -Be 0
        }

        It 'resolves missing assignedDirectoryRole targets through the role-definition API instead of getByIds' {
            Mock Test-EntraTopologyPermission { $true }
            Mock Get-EntraTopologyGraphContext { $null }
            $script:seenUris=@()
            Mock Invoke-EntraTopologyGraphRequest {
                param($Uri,$Method,$Body,$RequiredPermission,$Telemetry)
                $script:seenUris += $Uri
                [pscustomobject]@{SourceEndpoint=$Uri;RequiredPermission=$RequiredPermission;Status='Success';StatusCode=200;Items=@([pscustomobject]@{id='missing-role';displayName='Custom Privileged Role';description='Test';isBuiltIn=$false;isEnabled=$true;templateId=$null});CollectionTime='';Limitations=@();ErrorCode=$null;ErrorMessage=$null;RequestId='req-role';RetryCount=0;PageCount=1}
            }
            $base=@([pscustomobject]@{Name='DirectoryRoles';Status='Complete';RequiredPermissions=@();Capabilities=@();Warnings=@();Metrics=@{};Evidence=@();Objects=@([pscustomobject]@{Kind='user';Object=[pscustomobject]@{id='u1';displayName='User'}});Relations=@([pscustomobject]@{FromId='u1';ToId='missing-role';Relationship='assignedDirectoryRole';Qualifier='/';State=@{};EvidenceRefs=@()})})
            $result=Resolve-EntraTopologyDirectoryObjects -TenantId 'tenant' -Collectors $base
            $result.Objects.Count | Should -Be 1
            $result.Objects[0].Kind | Should -Be 'directoryRole'
            $script:seenUris.Count | Should -Be 1
            $script:seenUris[0] | Should -Match '/roleManagement/directory/roleDefinitions/missing-role'
            $script:seenUris[0] | Should -Not -Match 'getByIds'
            $result.Metrics.ResolvedDirectoryRoleDefinitionCount | Should -Be 1
            $result.Metrics.UnresolvedAfterResolution | Should -Be 0
        }

        It 'probes read-only resolution endpoints in app-only mode instead of trusting context scope introspection' {
            Mock Test-EntraTopologyPermission { $false }
            Mock Get-EntraTopologyGraphContext { [pscustomobject]@{AuthType='AppOnly';Scopes=@('User.Read.All')} }
            Mock Invoke-EntraTopologyGraphRequest {
                param($Uri,$Method,$Body,$RequiredPermission,$Telemetry)
                [pscustomobject]@{SourceEndpoint=$Uri;RequiredPermission=$RequiredPermission;Status='Success';StatusCode=200;Items=@([pscustomobject]@{'@odata.type'='#microsoft.graph.user';id='u1';displayName='Resolved'});CollectionTime='';Limitations=@();ErrorCode=$null;ErrorMessage=$null;RequestId='req';RetryCount=0;PageCount=1}
            }
            $base=@([pscustomobject]@{Name='Groups';Objects=@([pscustomobject]@{Kind='group';Object=[pscustomobject]@{id='g1';displayName='Group'}});Relations=@([pscustomobject]@{FromId='u1';ToId='g1';Relationship='memberOf'})})
            $result=Resolve-EntraTopologyDirectoryObjects -TenantId 'tenant' -Collectors $base
            $result.Metrics.ResolvedDirectoryObjectCount | Should -Be 1
            ($result.Warnings -join ' ') | Should -Not -Match 'Directory.Read.All is not granted'
        }


        It 'serializes POST bodies to plain JSON before handing them to Invoke-MgGraphRequest' {
            Mock Assert-EntraTopologyGraphConnected { [pscustomobject]@{TenantId='tenant'} }
            Mock Invoke-MgGraphRequest {
                param($Uri,$Method,$Body,$ContentType,$OutputType,$ErrorAction)
                $script:capturedResolverBody=$Body
                $response=[System.Net.Http.HttpResponseMessage]::new([System.Net.HttpStatusCode]::OK)
                $response.Content=[System.Net.Http.StringContent]::new('{"value":[]}')
                return $response
            }
            $result=Invoke-EntraTopologyGraphRequest -Uri '/v1.0/directoryObjects/getByIds' -Method POST -Body @{ids=[string[]]@('u1','u2')}
            $result.Status | Should -Be 'Success'
            $script:capturedResolverBody | Should -BeOfType ([string])
            $parsed=$script:capturedResolverBody | ConvertFrom-Json
            @($parsed.ids).Count | Should -Be 2
            $parsed.ids | Should -Contain 'u1'
            $parsed.ids | Should -Contain 'u2'
        }

        It 'keeps unresolved role definitions typed as directoryRole placeholders during normalization' {
            $snapshot=[pscustomobject]@{TenantId='tenant';SnapshotId='s1';CollectedAtUtc='2026-01-01T00:00:00Z';Collectors=@(
                [pscustomobject]@{Name='DirectoryRoles';Status='Complete';RequiredPermissions=@();Warnings=@();Metrics=@{};Capabilities=@();Evidence=@();Objects=@([pscustomobject]@{Kind='user';Object=[pscustomobject]@{id='u1';displayName='User'}});Relations=@([pscustomobject]@{FromId='u1';ToId='missing-role';Relationship='assignedDirectoryRole';Qualifier='/';State=@{};EvidenceRefs=@()})}
            )}
            $graph=New-EntraTopologyGraph -Snapshot $snapshot
            $role=@($graph.Nodes|Where-Object Id -eq 'missing-role')[0]
            $role.Kind | Should -Be 'directoryRole'
            $role.Properties.unresolvedType | Should -Be 'roleDefinition'
            $graph.Metadata.UnresolvedDirectoryObjectCount | Should -Be 0
            $graph.Metadata.UnresolvedDirectoryRoleCount | Should -Be 1
            $graph.Metadata.UnresolvedObjectCount | Should -Be 1
        }
    }
}

Describe 'Application-role semantic enrichment' {
    It 'adds readable permission metadata from the resource service principal appRoles collection' {
        $snapshot=[pscustomobject]@{TenantId='tenant';SnapshotId='s1';CollectedAtUtc='2026-01-01T00:00:00Z';Collectors=@(
            [pscustomobject]@{Name='Applications';Status='Complete';RequiredPermissions=@('Application.Read.All');Warnings=@();Metrics=@{};Capabilities=@();Evidence=@();Objects=@(
                [pscustomobject]@{Kind='servicePrincipal';Object=[pscustomobject]@{id='client';displayName='Client';appId='client-app';appRoles=@()}},
                [pscustomobject]@{Kind='servicePrincipal';Object=[pscustomobject]@{id='resource';displayName='Microsoft Graph';appId='00000003-0000-0000-c000-000000000000';appRoles=@([pscustomobject]@{id='role1';value='User.Read.All';displayName='Read all users';description='Read users';isEnabled=$true;allowedMemberTypes=@('Application')})}}
            );Relations=@([pscustomobject]@{FromId='client';ToId='resource';Relationship='hasAppRoleAssignment';Qualifier='role1';State=@{appRoleId='role1';principalType='ServicePrincipal'};EvidenceRefs=@()})}
        )}
        $graph=New-EntraTopologyGraph -Snapshot $snapshot
        $edge=@($graph.Edges|Where-Object Relationship -eq 'hasAppRoleAssignment')[0]
        $edge.State.appRoleResolved | Should -BeTrue
        $edge.State.appRoleValue | Should -Be 'User.Read.All'
        $edge.State.resourceDisplayName | Should -Be 'Microsoft Graph'
        $graph.Metadata.ResolvedAppRoleAssignmentCount | Should -Be 1
        $graph.Metadata.UnresolvedDirectoryObjectCount | Should -Be 0
    }
}
