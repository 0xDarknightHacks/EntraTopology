BeforeAll { Import-Module (Join-Path $PSScriptRoot '..' 'EntraTopology.psd1') -Force }

Describe 'Security-context recommendations' {
    InModuleScope EntraTopology {
        It 'creates deterministic remediation guidance linked to the source signal' {
            $signal=New-EntraTopologySignal -TenantId 't' -TargetKey 'object:a' -Type 'credentialExpiring' -Severity Medium -Reason 'Credential expires soon.'
            $graph=[pscustomobject]@{TenantId='t';Signals=@($signal)}
            $result=@(Add-EntraTopologyRecommendations -Graph $graph)
            $result.Count | Should -Be 1
            $result[0].SignalKey | Should -Be $signal.Key
            $result[0].TargetKey | Should -Be 'object:a'
            $result[0].Title | Should -Match 'credential'
            $result[0].Action | Should -Not -BeNullOrEmpty
            $result[0].References[0].Url | Should -Match '^https://learn\.microsoft\.com/'
        }

        It 'does not fabricate recommendations for an unknown signal type' {
            $signal=New-EntraTopologySignal -TenantId 't' -TargetKey 'object:a' -Type 'customObservation' -Severity Info -Reason 'Custom.'
            $graph=[pscustomobject]@{TenantId='t';Signals=@($signal)}
            @(Add-EntraTopologyRecommendations -Graph $graph).Count | Should -Be 0
        }
    }
}
