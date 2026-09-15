Import-Module (Join-Path $PSScriptRoot '..' 'EntraTopology.psd1') -Force

Describe 'Runtime telemetry' {
    InModuleScope EntraTopology {
        It 'tracks stages, requests and batching efficiency' {
            $t=New-EntraTopologyTelemetry
            Start-EntraTopologyTelemetryStage -Telemetry $t -Name 'Collection' | Out-Null
            Add-EntraTopologyTelemetryRequest -Telemetry $t -Logical 20 -Http 4 -Retries 1 -Throttles 1
            Stop-EntraTopologyTelemetryStage -Telemetry $t -Name 'Collection' -Status Success | Out-Null
            Complete-EntraTopologyTelemetry -Telemetry $t | Out-Null
            $t.GraphLogicalRequests | Should -Be 20
            $t.GraphHttpRequests | Should -Be 4
            $t.BatchingEfficiency | Should -Be 5
            $t.Retries | Should -Be 1
            $t.Throttles | Should -Be 1
            $t.Stages.Collection.Status | Should -Be 'Success'
            $t.DurationMs | Should -BeGreaterOrEqual 0
        }
    }
}
