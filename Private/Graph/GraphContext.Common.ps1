$script:EntraTopologyGraphHttpRequestCount = 0L

function Get-EntraTopologyGraphContext {
    [CmdletBinding()] param()
    try { return Get-MgContext -ErrorAction Stop } catch { return $null }
}
function Assert-EntraTopologyGraphConnected {
    [CmdletBinding()] param()
    $context = Get-EntraTopologyGraphContext
    if ($null -eq $context) { throw 'Not connected to Microsoft Graph. Run Connect-EntraTopologyGraph first.' }
    return $context
}
function Get-EntraTopologyGrantedPermissions {
    [CmdletBinding()] param()
    $ctx = Get-EntraTopologyGraphContext
    if ($null -eq $ctx) { return @() }
    return @($ctx.Scopes | ForEach-Object {[string]$_} | Where-Object {$_} | Sort-Object -Unique)
}
function Test-EntraTopologyPermission {
    [CmdletBinding()] param([Parameter(Mandatory)][string[]]$AnyOf)
    $granted = @(Get-EntraTopologyGrantedPermissions)
    foreach($p in $AnyOf){ if($granted -contains $p){ return $true } }
    return $false
}
function Test-EntraTopologyMayProbePermission {
    [CmdletBinding()] param([Parameter(Mandatory)][string[]]$AnyOf)
    $ctx = Get-EntraTopologyGraphContext
    if ($ctx -and [string](Get-EntraTopologyProperty $ctx 'AuthType') -eq 'AppOnly') {
        # Get-MgContext scope introspection is not authoritative for every application-permission
        # combination. Read-only optional capabilities should probe Graph and preserve the real
        # 403/404 response rather than being suppressed locally.
        return $true
    }
    Test-EntraTopologyPermission -AnyOf $AnyOf
}
function Add-EntraTopologyGraphTransportCall {
    [CmdletBinding()] param([ValidateRange(0,1000000)][int]$Count=1)
    $script:EntraTopologyGraphHttpRequestCount += $Count
}
function Get-EntraTopologyGraphTransportCallCount {
    [CmdletBinding()] param()
    [long]$script:EntraTopologyGraphHttpRequestCount
}
function Reset-EntraTopologyGraphTransportCallCount {
    [CmdletBinding()] param()
    $script:EntraTopologyGraphHttpRequestCount = 0L
}

function Get-EntraTopologyDefaultConfigPath {
    [CmdletBinding()] param()
    Join-Path (Join-Path $HOME '.entra-topology') 'config.json'
}

function Get-EntraTopologyStoredAppCredential {
    [CmdletBinding()]
    param(
        [string]$ConfigPath=(Get-EntraTopologyDefaultConfigPath),
        [string]$VaultName='EntraTopologyVault',
        [string]$SecretName='EntraTopologyGraphClientSecret'
    )

    if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
        throw "EntraTopology configuration file was not found: $ConfigPath"
    }

    try { $config = Get-Content -LiteralPath $ConfigPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop }
    catch { throw "EntraTopology configuration file is invalid JSON: $ConfigPath. $($_.Exception.Message)" }

    $tenantId = [string](Get-EntraTopologyProperty $config 'TenantId')
    $clientId = [string](Get-EntraTopologyProperty $config 'ClientId')
    if ([string]::IsNullOrWhiteSpace($tenantId) -or [string]::IsNullOrWhiteSpace($clientId)) {
        throw "EntraTopology configuration must contain non-empty TenantId and ClientId values: $ConfigPath"
    }

    $configPropertyNames=@($config.PSObject.Properties | ForEach-Object {[string]$_.Name})
    foreach ($forbiddenName in @('ClientSecret','Secret','SecretValue','ClientSecretValue')) {
        if ($configPropertyNames -contains $forbiddenName) {
            throw "Do not store client secrets in $ConfigPath. Store the secret in a SecretManagement vault instead."
        }
    }

    if (-not (Get-Command Get-Secret -ErrorAction SilentlyContinue)) {
        try { Import-Module Microsoft.PowerShell.SecretManagement -ErrorAction Stop }
        catch { throw 'Microsoft.PowerShell.SecretManagement is required for stored client-secret authentication. Install it and register a SecretManagement vault first.' }
    }

    try { $secret = Get-Secret -Name $SecretName -Vault $VaultName -ErrorAction Stop }
    catch { throw "Unable to retrieve secret '$SecretName' from vault '$VaultName'. $($_.Exception.Message)" }
    if ($null -eq $secret) { throw "Secret '$SecretName' was not found in vault '$VaultName'." }

    $secureSecret = $null
    if ($secret -is [System.Security.SecureString]) { $secureSecret = $secret }
    elseif ($secret -is [System.Management.Automation.PSCredential]) { $secureSecret = $secret.Password }
    elseif ($secret -is [string]) { $secureSecret = ConvertTo-SecureString -String $secret -AsPlainText -Force }
    else { throw "Secret '$SecretName' must be stored as String, SecureString, or PSCredential." }

    [pscustomobject][ordered]@{
        TenantId=$tenantId
        ClientId=$clientId
        ClientSecretCredential=[System.Management.Automation.PSCredential]::new($clientId,$secureSecret)
        ConfigPath=$ConfigPath
        VaultName=$VaultName
        SecretName=$SecretName
    }
}
