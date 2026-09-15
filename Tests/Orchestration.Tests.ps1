BeforeAll { Import-Module (Join-Path $PSScriptRoot '..' 'EntraTopology.psd1') -Force }

Describe 'One-command orchestration contract' {
    It 'owns authentication, stages, diagnostics and disconnect behavior' {
        $source=Get-Content -LiteralPath (Join-Path $PSScriptRoot '..' 'Public' 'Invoke-EntraTopology.ps1') -Raw
        $source | Should -Match 'Connect-EntraTopologyGraph\s+-UseStoredAppCredentials'
        $source | Should -Match '\$ownsConnection'
        $source | Should -Match 'finally\s*\{'
        $source | Should -Match 'Disconnect-MgGraph'
        $source | Should -Match 'Write-EntraTopologyStage'
        $source | Should -Match 'Save-EntraTopologyDiagnostics'
        $source | Should -Match 'RuntimeTelemetry'
    }

    It 'retains explicit escape hatches for caller-owned sessions and automation' {
        $source=Get-Content -LiteralPath (Join-Path $PSScriptRoot '..' 'Public' 'Invoke-EntraTopology.ps1') -Raw
        foreach($name in @('SkipConnect','NoDisconnect','NoBanner','NoProgress','NoReport','PassThru')){$source | Should -Match ('\[switch\]\$'+$name)}
    }
}
