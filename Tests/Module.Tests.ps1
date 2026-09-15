BeforeAll { Import-Module (Join-Path $PSScriptRoot '..' 'EntraTopology.psd1') -Force }
Describe 'EntraTopology module surface' {
    It 'exports only the intended public commands' {
        $names=@(Get-Command -Module EntraTopology|Select-Object -ExpandProperty Name|Sort-Object)
        $names | Should -Be @('Compare-EntraTopologyGraph','Connect-EntraTopologyGraph','Export-EntraTopologyGraph','Find-EntraTopologyPath','Get-EntraTopologyNode','Invoke-EntraTopology','New-EntraTopologyGraph','New-EntraTopologyReport','New-EntraTopologySnapshot')
    }
}
