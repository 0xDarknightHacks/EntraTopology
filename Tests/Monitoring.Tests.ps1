Describe 'Optional monitoring integration' {
    BeforeAll {
        $repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
        $monitoring = Join-Path $repo 'Monitoring'
        $notificationCommon = Join-Path $monitoring 'Private\Notification.Common.ps1'
        . $notificationCommon
    }

    It 'ships the monitor as a separate repository directory' {
        foreach ($name in @(
            'Invoke-EntraTopologyMonitor.ps1',
            'Initialize-EntraTopologyMonitor.ps1',
            'Register-EntraTopologyMonitorTask.ps1',
            'New-EntraTopologyMonitorCertificate.ps1',
            'monitor-config.example.json',
            'README.md',
            'Private\Notification.Common.ps1'
        )) {
            Test-Path -LiteralPath (Join-Path $monitoring $name) | Should -BeTrue
        }
    }

    It 'keeps the example configuration tenant-neutral' {
        $raw = Get-Content -LiteralPath (Join-Path $monitoring 'monitor-config.example.json') -Raw
        $raw | Should -Not -Match '(?i)C:\\Users\\'
        $raw | Should -Not -Match '(?i)@m365x'
        $raw | Should -Match '<tenant-id>'
        $raw | Should -Match '<application-client-id>'
        $raw | Should -Match '<certificate-thumbprint>'
    }

    It 'defaults runtime state to ProgramData and the module to the parent repository' {
        $raw = Get-Content -LiteralPath (Join-Path $monitoring 'Invoke-EntraTopologyMonitor.ps1') -Raw
        $raw | Should -Match 'Join-Path \$env:ProgramData ''EntraTopologyMonitor'''
        $raw | Should -Match 'Split-Path -Parent \$PSScriptRoot'
        $raw | Should -Match "'EntraTopology.psd1'"
    }

    It 'fails closed on baseline schema or collection-policy changes' {
        $raw = Get-Content -LiteralPath (Join-Path $monitoring 'Invoke-EntraTopologyMonitor.ps1') -Raw
        $raw | Should -Match 'Monitoring baseline schema mismatch'
        $raw | Should -Match 'Monitoring collection policy changed'
        $raw | Should -Match 'baseline collection policy cannot be proven'
        $raw | Should -Match 'BaselineGraphSchemaVersion'
        $raw | Should -Match 'baseline exists but monitor-state.json is missing'
        $raw | Should -Not -Match 'Legacy monitor-state\.json'
    }

    It 'does not compare, notify, or promote when baseline policy metadata is missing' {
        $raw = Get-Content -LiteralPath (Join-Path $monitoring 'Invoke-EntraTopologyMonitor.ps1') -Raw
        $missingPolicyCheck = $raw.IndexOf("monitor-state.json does not record ExcludeMicrosoftFirstPartyApps", [System.StringComparison]::Ordinal)
        $compareCall = $raw.IndexOf('Compare-EntraTopologyGraph', [System.StringComparison]::Ordinal)
        $notificationCall = $raw.IndexOf('Send-EntraTopologyMonitorNotification', [System.StringComparison]::Ordinal)
        $baselinePromotion = $raw.IndexOf('$tempBaselinePath = "$baselinePath.new"', [System.StringComparison]::Ordinal)

        $missingPolicyCheck | Should -BeGreaterOrEqual 0
        $compareCall | Should -BeGreaterThan $missingPolicyCheck
        $notificationCall | Should -BeGreaterThan $missingPolicyCheck
        $baselinePromotion | Should -BeGreaterThan $missingPolicyCheck
    }

    It 'preserves matching-policy continuation and explicit mismatch rejection' {
        $raw = Get-Content -LiteralPath (Join-Path $monitoring 'Invoke-EntraTopologyMonitor.ps1') -Raw
        $raw | Should -Match '\$previousExclude = \[bool\]\$previousState\.ExcludeMicrosoftFirstPartyApps'
        $raw | Should -Match '\$previousExclude -ne \$excludeMicrosoftFirstParty'
        $raw | Should -Match 'Monitoring collection policy changed'
        $raw | Should -Match 'Compare-EntraTopologyGraph -ReferenceGraph \$baseline -DifferenceGraph \$graph'
    }

    It 'registers the monitor as SYSTEM in a no-profile PowerShell process' {
        $raw = Get-Content -LiteralPath (Join-Path $monitoring 'Register-EntraTopologyMonitorTask.ps1') -Raw
        $raw | Should -Match "-UserId 'SYSTEM'"
        $raw | Should -Match "'-NoProfile'"
        $raw | Should -Match 'WorkingDirectory'
        $raw | Should -Match 'Scope AllUsers'
    }

    It 'rejects common private-key container formats from release packages' {
        $releaseGate = Get-Content -LiteralPath (Join-Path $repo 'Scripts\Test-EntraTopologyRelease.ps1') -Raw
        foreach ($pattern in @('*.pfx','*.p12','*.pem','*.key','*.cer','*.log','baseline-topology.json','last-delta.json','last-alert.json','monitor-state.json','monitor-config.json','run-*')) {
            $releaseGate | Should -Match ([regex]::Escape($pattern))
        }
    }

    It 'ships semantic HTML notification presentation separately from monitor orchestration' {
        $monitorRaw = Get-Content -LiteralPath (Join-Path $monitoring 'Invoke-EntraTopologyMonitor.ps1') -Raw
        $notificationRaw = Get-Content -LiteralPath (Join-Path $monitoring 'Private\Notification.Common.ps1') -Raw

        $monitorRaw | Should -Match 'New-EntraTopologyMonitorNotification'
        $monitorRaw | Should -Match 'Send-EntraTopologyMonitorNotification'
        $monitorRaw | Should -Not -Match 'EntraTopology change notification</h2>'
        $notificationRaw | Should -Match 'Microsoft Entra topology change detected'
        $notificationRaw | Should -Match 'Monitoring context'
        $notificationRaw | Should -Match 'last-delta.json'
        $notificationRaw | Should -Match 'HtmlEncode'
    }

    It 'merges a derived high-privilege signal into its concrete role-assignment change for email presentation' {
        $principal = [pscustomobject]@{
            Key='node:user';Id='user';Kind='user';DisplayName='Admin User';
            Properties=[pscustomobject]@{portalUri='https://entra.microsoft.com/tenant/#view/user'}
        }
        $role = [pscustomobject]@{
            Key='node:role';Id='role';Kind='directoryRole';DisplayName='Global Administrator';
            Properties=[pscustomobject]@{portalUri='https://entra.microsoft.com/tenant/#view/role'}
        }
        $edge = [pscustomobject]@{
            Key='edge:role';From='node:user';To='node:role';Relationship='assignedDirectoryRole';Qualifier='/';
            State=[pscustomobject]@{assignmentType='active';directoryScopeId='/'}
        }
        $graph = [pscustomobject]@{
            Nodes=@($principal,$role);Edges=@($edge);Signals=@();Coverage=@([pscustomobject]@{Status='Complete'})
        }
        $baseline = [pscustomobject]@{Nodes=@($principal,$role);Edges=@();Signals=@();Coverage=@([pscustomobject]@{Status='Complete'})}
        $lookup = New-EntraTopologyMonitorLookup -Graph $graph -Baseline $baseline

        $edgeChange = [pscustomobject]@{Change='Added';Kind='Edge';Key='edge:role';Before=$null;After=$edge}
        $signal = [pscustomobject]@{
            Key='signal:role';TargetKey='edge:role';Type='highPrivilegeRoleAssignment';Severity='High';
            Reason="The principal has an active assignment to the high-impact directory role 'Global Administrator'.";
            State=[pscustomobject]@{roleName='Global Administrator';principalKey='node:user';roleKey='node:role'}
        }
        $signalChange = [pscustomobject]@{Change='Added';Kind='Signal';Key='signal:role';Before=$null;After=$signal}

        $edgeAlert = New-EntraTopologyMonitorAlert -Change $edgeChange -Severity Critical -Lookup $lookup
        $signalAlert = New-EntraTopologyMonitorAlert -Change $signalChange -Severity Critical -Lookup $lookup
        $merged = @(Merge-EntraTopologyMonitorAlerts -Alerts @($edgeAlert,$signalAlert))

        $merged.Count | Should -Be 1
        $merged[0].Title | Should -Be 'Directory role assignment added'
        $merged[0].Primary | Should -Be 'Admin User → Global Administrator'
        $merged[0].Reason | Should -Match 'high-impact directory role'
    }

    It 'builds a professional bounded HTML notification with semantic context' {
        $principal = [pscustomobject]@{Key='node:user';Id='user';Kind='user';DisplayName='Admin User';Properties=[pscustomobject]@{}}
        $role = [pscustomobject]@{Key='node:role';Id='role';Kind='directoryRole';DisplayName='Global Administrator';Properties=[pscustomobject]@{}}
        $edge = [pscustomobject]@{Key='edge:role';From='node:user';To='node:role';Relationship='assignedDirectoryRole';Qualifier='/';State=[pscustomobject]@{assignmentType='active';directoryScopeId='/'}}
        $graph = [pscustomobject]@{Nodes=@($principal,$role);Edges=@($edge);Signals=@();Coverage=@([pscustomobject]@{Collector='Roles';Status='Complete'})}
        $lookup = New-EntraTopologyMonitorLookup -Graph $graph -Baseline $graph
        $change = [pscustomobject]@{Change='Added';Kind='Edge';Key='edge:role';Before=$null;After=$edge}
        $alert = New-EntraTopologyMonitorAlert -Change $change -Severity Critical -Lookup $lookup
        $delta = [pscustomobject]@{ComparedAtUtc='2026-09-16T09:15:00Z';Summary=[pscustomobject]@{Added=1;Removed=0;Changed=0}}
        $notification = [pscustomobject]@{TenantDisplayName='Contoso';MaxItems=12;SaveToSentItems=$true}
        $state = [pscustomobject]@{LastSuccessfulRunUtc='2026-09-16T09:00:00Z'}

        $message = New-EntraTopologyMonitorNotification -Notification $notification -Alerts @($alert) -Delta $delta -TenantId 'tenant-id' -Graph $graph -Baseline $graph -PreviousState $state

        $message.Subject | Should -Be '[EntraTopology] CRITICAL · 1 significant change detected'
        $message.SignificantChangeCount | Should -Be 1
        $message.HtmlBody | Should -Match 'Directory role assignment added'
        $message.HtmlBody | Should -Match 'Admin User'
        $message.HtmlBody | Should -Match 'Global Administrator'
        $message.HtmlBody | Should -Match 'Contoso'
        $message.HtmlBody | Should -Match 'Topology delta:'
        $message.HtmlBody | Should -Not -Match '\*\*Tenant:\*\*'
    }

    It 'exposes notification presentation controls in generated and example configuration' {
        $example = Get-Content -LiteralPath (Join-Path $monitoring 'monitor-config.example.json') -Raw | ConvertFrom-Json
        $example.Notification.PSObject.Properties.Name | Should -Contain 'TenantDisplayName'
        $example.Notification.PSObject.Properties.Name | Should -Contain 'MaxItems'
        $example.Notification.PSObject.Properties.Name | Should -Contain 'SaveToSentItems'

        $initializer = Get-Content -LiteralPath (Join-Path $monitoring 'Initialize-EntraTopologyMonitor.ps1') -Raw
        $initializer | Should -Match 'NotificationMaxItems'
        $initializer | Should -Match 'TenantDisplayName'
        $initializer | Should -Match 'SaveToSentItems'
    }

}
