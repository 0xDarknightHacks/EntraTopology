function Connect-EntraTopologyGraph {
    [CmdletBinding(DefaultParameterSetName='Delegated')]
    param(
        [Parameter(ParameterSetName='Delegated')][string]$TenantId,
        [Parameter(ParameterSetName='Delegated')][string[]]$Scopes=@('User.Read.All','Group.Read.All','Application.Read.All','Device.Read.All','RoleManagement.Read.Directory'),
        [Parameter(ParameterSetName='Delegated')][switch]$IncludeSignInActivity,
        [Parameter(ParameterSetName='Delegated')][switch]$IncludeRiskyUsers,
        [Parameter(ParameterSetName='Delegated')][switch]$IncludeDelegatedPermissionGrants,

        [Parameter(Mandatory,ParameterSetName='Certificate')][string]$ClientId,
        [Parameter(Mandatory,ParameterSetName='Certificate')][string]$CertificateThumbprint,
        [Parameter(Mandatory,ParameterSetName='Certificate')][string]$CertificateTenantId,

        [Parameter(Mandatory,ParameterSetName='StoredSecret')][switch]$UseStoredAppCredentials,
        [Parameter(ParameterSetName='StoredSecret')][string]$ConfigPath=(Get-EntraTopologyDefaultConfigPath),
        [Parameter(ParameterSetName='StoredSecret')][string]$VaultName='EntraTopologyVault',
        [Parameter(ParameterSetName='StoredSecret')][string]$SecretName='EntraTopologyGraphClientSecret',

        [switch]$NoWelcome
    )

    $params=@{NoWelcome=$NoWelcome.IsPresent}
    switch($PSCmdlet.ParameterSetName){
        'Certificate' {
            $params.ClientId=$ClientId
            $params.TenantId=$CertificateTenantId
            $params.CertificateThumbprint=$CertificateThumbprint
        }
        'StoredSecret' {
            $stored=Get-EntraTopologyStoredAppCredential -ConfigPath $ConfigPath -VaultName $VaultName -SecretName $SecretName
            $params.TenantId=$stored.TenantId
            $params.ClientSecretCredential=$stored.ClientSecretCredential
        }
        default {
            $effectiveScopes=@($Scopes)
            if($IncludeSignInActivity -and $effectiveScopes -notcontains 'AuditLog.Read.All'){$effectiveScopes += 'AuditLog.Read.All'}
            if($IncludeRiskyUsers -and $effectiveScopes -notcontains 'IdentityRiskyUser.Read.All'){$effectiveScopes += 'IdentityRiskyUser.Read.All'}
            if($IncludeDelegatedPermissionGrants -and $effectiveScopes -notcontains 'Directory.Read.All'){$effectiveScopes += 'Directory.Read.All'}
            $params.Scopes=@($effectiveScopes|Sort-Object -Unique)
            if($TenantId){$params.TenantId=$TenantId}
        }
    }

    Connect-MgGraph @params | Out-Null
    $ctx=Assert-EntraTopologyGraphConnected
    [pscustomobject][ordered]@{
        TenantId=[string]$ctx.TenantId
        ClientId=[string]$ctx.ClientId
        AuthType=[string]$ctx.AuthType
        Scopes=@($ctx.Scopes)
    }
}
