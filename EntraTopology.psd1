@{
    RootModule        = 'EntraTopology.psm1'
    ModuleVersion     = '1.0.1'
    GUID              = '9f7f25a4-6f56-4fd2-8d24-8a1a0cb6c7fe'
    Author            = 'EntraTopology contributors'
    CompanyName       = 'Community'
    Copyright         = '(c) EntraTopology contributors. MIT License.'
    Description       = 'Read-only Microsoft Entra tenant inventory, topology, security-context, and recommendation engine.'
    PowerShellVersion = '7.2'
    RequiredModules   = @(
        @{ ModuleName = 'Microsoft.Graph.Authentication'; ModuleVersion = '2.0.0' }
    )
    FunctionsToExport = @(
        'Connect-EntraTopologyGraph',
        'New-EntraTopologySnapshot',
        'New-EntraTopologyGraph',
        'Invoke-EntraTopology',
        'Get-EntraTopologyNode',
        'Find-EntraTopologyPath',
        'Compare-EntraTopologyGraph',
        'Export-EntraTopologyGraph',
        'New-EntraTopologyReport'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData = @{
        PSData = @{
            Tags       = @('MicrosoftEntra','MicrosoftGraph','Topology','Identity','Security','Graph')
            LicenseUri = 'https://opensource.org/license/mit'
        }
    }
}
