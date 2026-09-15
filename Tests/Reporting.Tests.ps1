BeforeAll { Import-Module (Join-Path $PSScriptRoot '..' 'EntraTopology.psd1') -Force }

Describe 'Offline HTML reporting' {
    BeforeAll {
        $script:reportGraph = [pscustomobject]@{
            SchemaVersion = '1.2.0'
            GraphId = 'report-test'
            TenantId = 'tenant'
            BuiltAtUtc = '2026-01-01T00:00:00Z'
            SourceSnapshotId = 'snapshot-test'
            Nodes = @(
                @{ Key='user:u'; Id='u'; Kind='user'; DisplayName='</script><img src=x onerror=alert(1)>'; Properties=@{ accountEnabled=$false; userPrincipalName='user@example.test'; portalUri='https://entra.microsoft.com/tenant/#view/user' }; EvidenceKeys=@('ev:user') }
                @{ Key='sp:a'; Id='a'; Kind='servicePrincipal'; DisplayName='Automation'; Properties=@{ appId='app-id'; enterpriseAppCategory='TenantOwned'; topologyReferenceOnly=$false; portalUri='https://entra.microsoft.com/tenant/#view/sp' }; EvidenceKeys=@('ev:sp') }
                @{ Key='group:g'; Id='g'; Kind='group'; DisplayName='Admins'; Properties=@{}; EvidenceKeys=@() }
                @{ Key='role:r'; Id='r'; Kind='directoryRole'; DisplayName='Global Administrator'; Properties=@{}; EvidenceKeys=@() }
                @{ Key='unknown:x'; Id='x'; Kind='directoryObject'; DisplayName='Unresolved'; Properties=@{ resolution='unresolved' }; EvidenceKeys=@() }
            )
            Edges = @(
                @{ Key='edge:p'; From='sp:a'; To='user:u'; Relationship='hasAppRoleAssignment'; State=@{ appRoleValue='User.Read.All'; appRoleResolved=$true; resourceDisplayName='Microsoft Graph' }; EvidenceKeys=@('ev:edge') }
                @{ Key='edge:m'; From='user:u'; To='group:g'; Relationship='memberOf'; State=@{}; EvidenceKeys=@('ev:edge') }
                @{ Key='edge:r'; From='user:u'; To='role:r'; Relationship='assignedDirectoryRole'; State=@{}; EvidenceKeys=@('ev:edge') }
            )
            Signals = @(
                @{ Key='signal:n'; TargetKey='user:u'; Type='disabledIdentity'; Severity='Low'; Reason='Disabled identity' }
                @{ Key='signal:e'; TargetKey='edge:p'; Type='highImpactApplicationPermission'; Severity='High'; Reason='Relationship context' }
                @{ Key='signal:r'; TargetKey='edge:r'; Type='highPrivilegeRoleAssignment'; Severity='High'; Reason='Privileged relationship' }
            )
            Recommendations = @(
                @{ Key='recommendation:1'; SignalKey='signal:e'; TargetKey='edge:p'; Priority='High'; Title='Review high-impact application permission'; Action='Reduce the permission if unnecessary.'; Rationale='Least privilege.'; References=@(@{Title='Microsoft Learn';Url='https://learn.microsoft.com/test';Source='Microsoft Learn'}) }
            )
            Evidence = @(
                @{ Key='ev:user'; Collector='Users'; Endpoint='/users'; Completeness='Complete' }
                @{ Key='ev:edge'; Collector='Applications'; Endpoint='/servicePrincipals/a/appRoleAssignments'; Completeness='Complete' }
            )
            Coverage = @(
                @{ Collector='Applications'; Status='Complete'; RequiredPermissions=@('Application.Read.All'); Warnings=@(); Capabilities=@(@{Name='AppRoleAssignments';Status='Complete'}) }
            )
            Metadata = @{ UnresolvedObjectCount=1; UnresolvedDirectoryObjectCount=1; UnresolvedDirectoryRoleCount=0; ResolvedAppRoleAssignmentCount=1; RuntimeTelemetry=@{DurationMs=1234;GraphLogicalRequests=20;GraphHttpRequests=4;BatchingEfficiency=5;Retries=0;Throttles=0;Stages=@{Collection=@{Status='Success';DurationMs=500;Message=$null}}}; Diagnostics=@(@{TimestampUtc='2026-01-01T00:00:00Z';Level='Info';Stage='Collection';Event='Completed';Message='Done'}) }
        }
    }

    It 'generates a self-contained report without Graph calls or runtime network dependencies' {
        InModuleScope EntraTopology -Parameters @{ ReportGraph = $script:reportGraph } {
            param($ReportGraph)
            Mock Invoke-MgGraphRequest { throw 'Graph must not be called by report generation.' }
            $path = Join-Path $TestDrive 'report.html'
            $file = New-EntraTopologyReport -Graph $ReportGraph -Path $path
            $file.Exists | Should -BeTrue
            $content = Get-Content -LiteralPath $path -Raw
            $content | Should -Match 'EntraTopology Tenant Topology Report'
            $content | Should -Match 'application/json'
            $content | Should -Match "connect-src 'none'"
            $content | Should -Not -Match '<script\b[^>]*\bsrc\s*='
            $content | Should -Not -Match '<link\b|@import|\bfetch\s*\(|XMLHttpRequest|\beval\s*\(|new\s+Function'
            Should -Invoke Invoke-MgGraphRequest -Times 0 -Exactly
        }
    }

    It 'uses the Entra Object Inspector visual language without carrying its assessment UX' {
        $path = Join-Path $TestDrive 'theme.html'
        New-EntraTopologyReport -Graph $script:reportGraph -Path $path | Out-Null
        $html = Get-Content -LiteralPath $path -Raw
        $html | Should -Match '--brand:\s*#0f6cbd'
        $html | Should -Match 'Segoe UI Variable Text'
        $html | Should -Match 'class="brand-accent"'
        $html | Should -Match 'id="themeToggle"'
        foreach($id in @('overview','quick-answers','composition','topology-section','security-context','coverage','runtime-diagnostics','evidence')) { $html | Should -Match ('id="'+$id+'"') }
        $html | Should -Not -Match 'Identity / Privilege|Applications & Permissions|Temporal Comparison|Tenant workspace'
    }

    It 'round-trips hostile tenant strings without terminating the embedded JSON element' {
        $path = Join-Path $TestDrive 'hostile.html'
        New-EntraTopologyReport -Graph $script:reportGraph -Path $path -Title '<unsafe> __GRAPH_JSON__' | Out-Null
        $html = Get-Content -LiteralPath $path -Raw
        $match = [regex]::Match($html, '(?s)<script type="application/json" id="graph-data">(.*?)</script>')
        $match.Success | Should -BeTrue
        $match.Groups[1].Value | Should -Not -Match '<'
        $parsed = $match.Groups[1].Value | ConvertFrom-Json
        $parsed.Nodes[0].DisplayName | Should -BeExactly $script:reportGraph.Nodes[0].DisplayName
        $html | Should -Match '<title>&lt;unsafe&gt; __GRAPH_JSON__</title>'
        ([regex]::Matches($html, '</script>').Count) | Should -Be 2
    }

    It 'preserves node and edge signals, readable permissions, coverage and evidence' {
        $path = Join-Path $TestDrive 'semantics.html'
        New-EntraTopologyReport -Graph $script:reportGraph -Path $path | Out-Null
        $html = Get-Content -LiteralPath $path -Raw
        $json = [regex]::Match($html, '(?s)id="graph-data">(.*?)</script>').Groups[1].Value | ConvertFrom-Json
        $json.Signals.TargetKey | Should -Contain 'user:u'
        $json.Signals.TargetKey | Should -Contain 'edge:p'
        $json.Edges[0].State.appRoleValue | Should -Be 'User.Read.All'
        $json.Coverage[0].Status | Should -Be 'Complete'
        $json.Evidence[0].Completeness | Should -Be 'Complete'
        (@($json.Nodes | Where-Object Key -eq 'unknown:x')[0]).Kind | Should -Be 'directoryObject'
        $html | Should -Match 'Permission:'
        $html | Should -Match 'Evidence / provenance'
        $html | Should -Match 'marker-end'
        $html | Should -Match 'relationshipLabel'
        $html | Should -Match 'Member of'
        $html | Should -Match 'Has permission:'
        $html | Should -Match 'kindIcon'
        $html | Should -Match 'High-impact application permission'
        $html | Should -Match 'signal-high'
        $html | Should -Match 'Review high-impact application permission'
        $html | Should -Match 'Open in Entra'
        $html | Should -Match 'Quick answers'
        $html | Should -Match 'Tenant composition'
        $html | Should -Match 'Relationship flow'
        $html | Should -Not -Match 'A searchable inventory of the objects and relationships'
        $html | Should -Match 'Run details'
        $html | Should -Match 'Logical Graph calls'
    }

    It 'includes topology navigation, enterprise-app filtering, hover detail and security-context filters' {
        $path = Join-Path $TestDrive 'interaction.html'
        New-EntraTopologyReport -Graph $script:reportGraph -Path $path | Out-Null
        $html = Get-Content -LiteralPath $path -Raw
        foreach($id in @('zoomIn','zoomOut','fitGraph','graphTooltip','enterpriseCategory','signalSearch','signalSeverity','signalType','signalTargetType','questionGrid','relationshipSankey','evidenceSearch')) { $html | Should -Match ('id="'+$id+'"') }
        $html | Should -Match "addEventListener\('wheel'"
        $html | Should -Match "addEventListener\('pointerdown'"
        $html | Should -Match 'nodeHoverText'
        $html | Should -Match 'inspectorBack'
        $html | Should -Match 'Focus in topology'
        $html | Should -Match 'Copy object ID'
        $html | Should -Match 'enterpriseCategoryMatches'
        $html | Should -Match 'topologyEnterpriseNodeVisible'
        $html | Should -Match 'topologyEnterpriseEdgeVisible'
        $html | Should -Match 'topologyReferenceOnly'
        $html | Should -Match 'topologyEnterpriseEdgeVisible\(e,key\)'
        $html | Should -Match 'requiresApiPermission'
        $html | Should -Match 'hasDelegatedPermission'
        $html | Should -Match 'hasCredential'
        $html | Should -Match 'Credential expired'
        $html | Should -Match 'const signalTargetKinds=signals\.map'
        $html | Should -Not -Match 'new Set\([^;\r\n]+\)\.filter\(Boolean\)'
    }


    It 'keeps the report topology-first with compact summaries and deterministic quick answers' {
        $path = Join-Path $TestDrive 'product.html'
        New-EntraTopologyReport -Graph $script:reportGraph -Path $path | Out-Null
        $html = Get-Content -LiteralPath $path -Raw
        $html | Should -Match 'Common administrator questions answered from this topology'
        $html | Should -Match 'Which privileged identities own applications\?'
        $html | Should -Match 'Which applications hold high-impact permissions\?'
        $html | Should -Match 'Which credentials need attention\?'
        $html | Should -Match 'renderRelationshipSankey'
        $html | Should -Match 'Object type → relationship → object type'
        $html | Should -Match 'id="sankeyLegend"'
        $html | Should -Match 'RELATIONSHIP_COLORS'
        $html | Should -Match 'KIND_COLORS'
        $html | Should -Match 'relationshipColor\(f\.relationship\)'
        $html | Should -Match 'sankey-legend-swatch'
        $html | Should -Match 'security-table'
        $html | Should -Match 'security-recommendation-action'
        $html | Should -Match "for\(const h of \['Security context','Affected','Recommendation',''\]\)"
        $html | Should -Not -Match "for\(const h of \['Severity','Security context','Affected','Examples','Recommendation',''\]\)"
        $html | Should -Match 'data-label'
        $html | Should -Match 'groupedCounts'
        $html | Should -Match 'exploreQuestion'
        $html | Should -Match 'exploreSignalGroup'
        $html | Should -Match 'Stage timings & diagnostics'
        $html | Should -Match 'Evidence & provenance'
        $html | Should -Not -Match 'id="inventoryObjectsTable"'
        $html | Should -Not -Match 'id="inventoryEdgesTable"'
    }

}
