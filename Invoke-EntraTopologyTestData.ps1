#requires -Version 7.2
#requires -Modules Microsoft.Graph.Authentication

<#
.SYNOPSIS
Creates and removes a deterministic Microsoft Entra test dataset for validating EntraTopology.

.DESCRIPTION
Invoke-EntraTopologyTestData.ps1 seeds a small, isolated set of Microsoft Entra objects and
relationships that exercise EntraTopology's core topology and security-context model. Cleanup is
manifest-driven and deletes only the exact object/assignment IDs created by a specific run.

The default dataset intentionally avoids real Microsoft Graph permission grants. Optional app-role
and delegated-consent scenarios target a dummy API created by the simulator. Optional privileged-role
assignment is explicitly opt-in and assigns Application Administrator to a disabled synthetic user.

Run this only in a dedicated test/development tenant. The script performs write operations.

Baseline delegated scopes for Populate:
  User.ReadWrite.All
  Group.ReadWrite.All
  GroupMember.ReadWrite.All
  Application.ReadWrite.All
  Directory.Read.All

Optional delegated scopes:
  AppRoleAssignment.ReadWrite.All          (-IncludeAppRoleGrant)
  DelegatedPermissionGrant.ReadWrite.All  (-IncludeDelegatedGrant)
  RoleManagement.ReadWrite.Directory      (-IncludePrivilegedRoleAssignment)

Microsoft Learn references:
  https://learn.microsoft.com/graph/api/user-post-users
  https://learn.microsoft.com/graph/api/group-post-groups
  https://learn.microsoft.com/graph/api/group-post-members
  https://learn.microsoft.com/graph/api/application-post-applications
  https://learn.microsoft.com/graph/api/serviceprincipal-post-serviceprincipals
  https://learn.microsoft.com/graph/api/application-addpassword
  https://learn.microsoft.com/graph/api/serviceprincipal-post-approleassignedto
  https://learn.microsoft.com/graph/api/serviceprincipal-delete-approleassignedto
  https://learn.microsoft.com/graph/api/oauth2permissiongrant-post
  https://learn.microsoft.com/graph/api/rbacapplication-post-roleassignments
  https://learn.microsoft.com/graph/api/domain-get
  https://learn.microsoft.com/graph/throttling

.PARAMETER Action
Populate creates the synthetic dataset. Remove deletes objects recorded in -ManifestPath.

.PARAMETER TenantId
The exact Microsoft Entra tenant ID. The active Graph context must match this tenant.

.PARAMETER UserPrincipalNameDomain
A verified tenant domain used only for synthetic cloud users. Required for Populate.

.PARAMETER Prefix
Display-name prefix for generated objects. A short random run ID is appended automatically.

.PARAMETER ManifestPath
Populate: optional path for the cleanup manifest. If omitted, the manifest is written under
~/.entra-topology/test-data/.
Remove: required. Cleanup never scans by prefix; it uses only IDs from this manifest.

.PARAMETER Connect
If no Microsoft Graph context exists, connect interactively with only the required delegated scopes.
If a Graph context already exists but is the wrong tenant, app-only, or missing scopes, the script
fails instead of silently replacing that context.

.PARAMETER IncludeAppRoleGrant
Creates a harmless application-permission relationship between two simulator-owned applications.
Requires AppRoleAssignment.ReadWrite.All for the caller. No Microsoft Graph permission is granted.

.PARAMETER IncludeDelegatedGrant
Creates a harmless tenant-wide delegated grant to the simulator's dummy custom API.
Requires DelegatedPermissionGrant.ReadWrite.All for the caller. No Microsoft Graph permission is granted.

.PARAMETER IncludePrivilegedRoleAssignment
Assigns the built-in Application Administrator role to the simulator's disabled synthetic user.
Requires RoleManagement.ReadWrite.Directory and Privileged Role Administrator (or stronger/custom
equivalent) for the signed-in administrator. Use only in a dedicated lab tenant.

.EXAMPLE
Connect-MgGraph -TenantId '<tenant-id>' -Scopes @(
  'User.ReadWrite.All',
  'Group.ReadWrite.All',
  'GroupMember.ReadWrite.All',
  'Application.ReadWrite.All',
  'Directory.Read.All'
) -ContextScope Process

.\Invoke-EntraTopologyTestData.ps1 `
  -Action Populate `
  -TenantId '<tenant-id>' `
  -UserPrincipalNameDomain 'contoso.onmicrosoft.com'

.EXAMPLE
.\Invoke-EntraTopologyTestData.ps1 `
  -Action Populate `
  -TenantId '<tenant-id>' `
  -UserPrincipalNameDomain 'contoso.onmicrosoft.com' `
  -Connect `
  -IncludeAppRoleGrant `
  -IncludeDelegatedGrant `
  -IncludePrivilegedRoleAssignment

.EXAMPLE
.\Invoke-EntraTopologyTestData.ps1 `
  -Action Remove `
  -TenantId '<tenant-id>' `
  -ManifestPath '~/.entra-topology/test-data/EntraTopology-TestData-abc12345.json' `
  -Connect

.NOTES
Generated user passwords are random and never printed or persisted. Application secretText values are
discarded immediately. The uploaded test certificate contains only a public key; its private key is
discarded in memory.

Deletion removes active objects. Microsoft Entra may retain soft-deleted objects in its deleted-items
container according to normal platform retention behavior. The simulator does not hard-delete them.
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Populate', 'Remove')]
    [string]$Action,

    [Parameter(Mandatory)]
    [Guid]$TenantId,

    [string]$UserPrincipalNameDomain,

    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9 ._-]{1,48}$')]
    [string]$Prefix = 'EntraTopology-Sim',

    [string]$ManifestPath,

    [switch]$Connect,

    [switch]$IncludeAppRoleGrant,

    [switch]$IncludeDelegatedGrant,

    [switch]$IncludePrivilegedRoleAssignment
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$GraphRoot = 'https://graph.microsoft.com/v1.0'
$MicrosoftGraphAppId = '00000003-0000-0000-c000-000000000000'
$TenantIdText = $TenantId.ToString()
$script:Manifest = $null
$script:ManifestFilePath = $null
$script:OwnsGraphContext = $false

function Get-TestObjectProperty {
    param(
        [AllowNull()][object]$InputObject,
        [Parameter(Mandatory)][string]$Name
    )

    if ($null -eq $InputObject) {
        return $null
    }

    if ($InputObject -is [System.Collections.IDictionary]) {
        foreach ($key in @($InputObject.Keys)) {
            if ([string]$key -ieq $Name) {
                return $InputObject[$key]
            }
        }
        return $null
    }

    $property = $InputObject.PSObject.Properties | Where-Object Name -IEQ $Name | Select-Object -First 1
    if ($null -eq $property) {
        return $null
    }
    $property.Value
}

function Get-ExceptionStatusCode {
    param([Parameter(Mandatory)]$Exception)

    foreach ($propertyName in @('ResponseStatusCode', 'StatusCode')) {
        $property = $Exception.PSObject.Properties[$propertyName]
        if ($null -ne $property -and $null -ne $property.Value) {
            try { return [int]$property.Value } catch { }
        }
    }

    $responseProperty = $Exception.PSObject.Properties['Response']
    if ($null -ne $responseProperty -and $null -ne $responseProperty.Value) {
        $statusProperty = $responseProperty.Value.PSObject.Properties['StatusCode']
        if ($null -ne $statusProperty -and $null -ne $statusProperty.Value) {
            try { return [int]$statusProperty.Value } catch { }
        }
    }

    if ([string]$Exception.Message -match '\b(400|401|403|404|409|429|500|502|503|504)\b') {
        return [int]$Matches[1]
    }

    return $null
}

function Get-RetryAfterSeconds {
    param(
        [Parameter(Mandatory)]$Exception,
        [ValidateRange(1, 300)][int]$FallbackSeconds = 1
    )

    $headerSources = [System.Collections.Generic.List[object]]::new()

    foreach ($propertyName in @('ResponseHeaders', 'Headers')) {
        $property = $Exception.PSObject.Properties[$propertyName]
        if ($null -ne $property -and $null -ne $property.Value) {
            $headerSources.Add($property.Value)
        }
    }

    $responseProperty = $Exception.PSObject.Properties['Response']
    if ($null -ne $responseProperty -and $null -ne $responseProperty.Value) {
        $headersProperty = $responseProperty.Value.PSObject.Properties['Headers']
        if ($null -ne $headersProperty -and $null -ne $headersProperty.Value) {
            $headerSources.Add($headersProperty.Value)
        }
    }

    foreach ($headers in $headerSources) {
        try {
            if ($headers -is [System.Collections.IDictionary]) {
                foreach ($key in @($headers.Keys)) {
                    if ([string]$key -ieq 'Retry-After') {
                        $value = [string]$headers[$key]
                        if ($value -match '^\s*(\d+)\s*$') {
                            return [Math]::Min(300, [Math]::Max(1, [int]$Matches[1]))
                        }
                    }
                }
            }

            $retryAfterProperty = $headers.PSObject.Properties['RetryAfter']
            if ($null -ne $retryAfterProperty -and $null -ne $retryAfterProperty.Value) {
                $retryAfter = $retryAfterProperty.Value
                $deltaProperty = $retryAfter.PSObject.Properties['Delta']
                if ($null -ne $deltaProperty -and $null -ne $deltaProperty.Value) {
                    $seconds = [int][Math]::Ceiling(([TimeSpan]$deltaProperty.Value).TotalSeconds)
                    if ($seconds -gt 0) {
                        return [Math]::Min(300, $seconds)
                    }
                }
            }
        }
        catch {
            Write-Verbose "Could not parse Retry-After response metadata: $($_.Exception.Message)"
        }
    }

    if ([string]$Exception.Message -match '(?i)Retry-After\s*[:=]\s*(\d+)') {
        return [Math]::Min(300, [Math]::Max(1, [int]$Matches[1]))
    }

    return $FallbackSeconds
}

function Get-GraphErrorDetail {
    param(
        [Parameter(Mandatory)]$Exception,
        [Parameter(Mandatory)][string]$Method,
        [Parameter(Mandatory)][string]$Uri
    )

    $details = [System.Collections.Generic.List[string]]::new()
    $statusCode = Get-ExceptionStatusCode -Exception $Exception
    if ($statusCode) {
        $details.Add("HTTP $statusCode")
    }

    foreach ($propertyName in @('ErrorDetails', 'ResponseBody')) {
        $property = $Exception.PSObject.Properties[$propertyName]
        if ($null -ne $property -and -not [string]::IsNullOrWhiteSpace([string]$property.Value)) {
            $details.Add([string]$property.Value)
        }
    }

    $responseProperty = $Exception.PSObject.Properties['Response']
    if ($null -ne $responseProperty -and $null -ne $responseProperty.Value) {
        $contentProperty = $responseProperty.Value.PSObject.Properties['Content']
        if ($null -ne $contentProperty -and -not [string]::IsNullOrWhiteSpace([string]$contentProperty.Value)) {
            $details.Add([string]$contentProperty.Value)
        }
    }

    $message = [string]$Exception.Message
    if (-not [string]::IsNullOrWhiteSpace($message)) {
        $details.Add($message)
    }

    "Graph request failed: $Method $Uri. $($details -join ' | ')"
}

function Invoke-TestGraphRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('GET', 'POST', 'PATCH', 'DELETE')]
        [string]$Method,

        [Parameter(Mandatory)]
        [string]$Uri,

        [hashtable]$Body,

        [int[]]$RetryStatusCodes = @(429, 500, 502, 503, 504),

        [ValidateRange(1, 12)]
        [int]$MaxAttempts = 6,

        [switch]$IgnoreNotFound
    )

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        try {
            $parameters = @{
                Method      = $Method
                Uri         = $Uri
                ErrorAction = 'Stop'
            }

            $bodyJson = $null
            if ($null -ne $Body) {
                $bodyJson = ($Body | ConvertTo-Json -Depth 30 -Compress)
                $parameters['Body'] = $bodyJson
                $parameters['ContentType'] = 'application/json'
            }

            return Invoke-MgGraphRequest @parameters
        }
        catch {
            $statusCode = Get-ExceptionStatusCode -Exception $_.Exception

            if ($IgnoreNotFound -and $statusCode -eq 404) {
                return $null
            }

            if (($RetryStatusCodes -contains $statusCode) -and $attempt -lt $MaxAttempts) {
                $fallbackSeconds = [Math]::Min(20, [int][Math]::Pow(2, $attempt - 1))
                $delaySeconds = Get-RetryAfterSeconds -Exception $_.Exception -FallbackSeconds $fallbackSeconds
                Write-Verbose "Graph returned HTTP $statusCode for $Method $Uri. Retrying in $delaySeconds second(s)."
                Start-Sleep -Seconds $delaySeconds
                continue
            }

            throw (Get-GraphErrorDetail -Exception $_.Exception -Method $Method -Uri $Uri)
        }
    }
}

function Save-TestManifest {
    if ($null -eq $script:Manifest -or [string]::IsNullOrWhiteSpace($script:ManifestFilePath)) {
        return
    }

    $directory = Split-Path -Parent $script:ManifestFilePath
    if (-not [string]::IsNullOrWhiteSpace($directory)) {
        $null = New-Item -ItemType Directory -Path $directory -Force
    }

    $script:Manifest['updatedAtUtc'] = [DateTimeOffset]::UtcNow.ToString('o')
    $script:Manifest | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $script:ManifestFilePath -Encoding utf8NoBOM
}

function Add-TestManifestObject {
    param(
        [Parameter(Mandatory)][string]$Type,
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$DisplayName,
        [string]$AppId,
        [string]$UserPrincipalName
    )

    $entry = [ordered]@{
        type        = $Type
        id          = $Id
        displayName = $DisplayName
    }

    if (-not [string]::IsNullOrWhiteSpace($AppId)) {
        $entry['appId'] = $AppId
    }

    if (-not [string]::IsNullOrWhiteSpace($UserPrincipalName)) {
        $entry['userPrincipalName'] = $UserPrincipalName
    }

    $script:Manifest['objects'] += [pscustomobject]$entry
    Save-TestManifest
}

function Add-TestManifestRelationship {
    param(
        [Parameter(Mandatory)][string]$Kind,
        [Parameter(Mandatory)][string]$SourceId,
        [Parameter(Mandatory)][string]$TargetId,
        [string]$Description
    )

    $script:Manifest['relationships'] += [pscustomobject][ordered]@{
        kind        = $Kind
        sourceId    = $SourceId
        targetId    = $TargetId
        description = $Description
    }
    Save-TestManifest
}

function Add-TestManifestAssignment {
    param(
        [Parameter(Mandatory)][string]$Type,
        [Parameter(Mandatory)][string]$Id,
        [string]$PrincipalId,
        [string]$ResourceId,
        [string]$RoleDefinitionId,
        [string]$Description
    )

    $script:Manifest['assignments'] += [pscustomobject][ordered]@{
        type             = $Type
        id               = $Id
        principalId      = $PrincipalId
        resourceId       = $ResourceId
        roleDefinitionId = $RoleDefinitionId
        description      = $Description
    }
    Save-TestManifest
}

function Add-TestManifestCredential {
    param(
        [Parameter(Mandatory)][string]$ApplicationId,
        [Parameter(Mandatory)][string]$CredentialType,
        [Parameter(Mandatory)][string]$DisplayName,
        [Parameter(Mandatory)][string]$EndDateTime,
        [string]$KeyId
    )

    $script:Manifest['credentials'] += [pscustomobject][ordered]@{
        applicationId = $ApplicationId
        type          = $CredentialType
        displayName   = $DisplayName
        keyId         = $KeyId
        endDateTime   = $EndDateTime
    }
    Save-TestManifest
}

function New-SafeAlias {
    param([Parameter(Mandatory)][string]$Value)

    $alias = ($Value.ToLowerInvariant() -replace '[^a-z0-9]', '')
    if ($alias.Length -gt 56) {
        $alias = $alias.Substring(0, 56)
    }
    if ($alias.Length -lt 3) {
        $alias = "etsim$alias"
    }
    return $alias
}

function New-RandomPassword {
    $lower = 'abcdefghijkmnopqrstuvwxyz'.ToCharArray()
    $upper = 'ABCDEFGHJKLMNPQRSTUVWXYZ'.ToCharArray()
    $digits = '23456789'.ToCharArray()
    $special = '!@#$%*-_+'.ToCharArray()
    $all = @($lower + $upper + $digits + $special)

    $characters = [System.Collections.Generic.List[char]]::new()
    $characters.Add($lower[[System.Security.Cryptography.RandomNumberGenerator]::GetInt32($lower.Length)])
    $characters.Add($upper[[System.Security.Cryptography.RandomNumberGenerator]::GetInt32($upper.Length)])
    $characters.Add($digits[[System.Security.Cryptography.RandomNumberGenerator]::GetInt32($digits.Length)])
    $characters.Add($special[[System.Security.Cryptography.RandomNumberGenerator]::GetInt32($special.Length)])

    while ($characters.Count -lt 30) {
        $characters.Add($all[[System.Security.Cryptography.RandomNumberGenerator]::GetInt32($all.Count)])
    }

    for ($i = $characters.Count - 1; $i -gt 0; $i--) {
        $j = [System.Security.Cryptography.RandomNumberGenerator]::GetInt32($i + 1)
        $temporary = $characters[$i]
        $characters[$i] = $characters[$j]
        $characters[$j] = $temporary
    }

    return -join $characters
}

function Get-RequiredScopes {
    param(
        [Parameter(Mandatory)][string]$Operation,
        $LoadedManifest
    )

    if ($Operation -eq 'Populate') {
        $scopes = [System.Collections.Generic.List[string]]::new()
        foreach ($scope in @(
            'User.ReadWrite.All',
            'Group.ReadWrite.All',
            'GroupMember.ReadWrite.All',
            'Application.ReadWrite.All',
            'Directory.Read.All'
        )) {
            $scopes.Add($scope)
        }

        if ($IncludeAppRoleGrant) {
            $scopes.Add('AppRoleAssignment.ReadWrite.All')
        }
        if ($IncludeDelegatedGrant) {
            $scopes.Add('DelegatedPermissionGrant.ReadWrite.All')
        }
        if ($IncludePrivilegedRoleAssignment) {
            $scopes.Add('RoleManagement.ReadWrite.Directory')
        }

        return @($scopes | Sort-Object -Unique)
    }

    $removeScopes = [System.Collections.Generic.List[string]]::new()
    foreach ($scope in @('User.ReadWrite.All', 'Group.ReadWrite.All', 'Application.ReadWrite.All')) {
        $removeScopes.Add($scope)
    }

    if ($null -ne $LoadedManifest) {
        $assignmentTypes = @(Get-TestObjectProperty $LoadedManifest 'assignments' | ForEach-Object { [string](Get-TestObjectProperty $_ 'type') })
        if ($assignmentTypes -contains 'appRoleAssignment') {
            $removeScopes.Add('AppRoleAssignment.ReadWrite.All')
        }
        if ($assignmentTypes -contains 'oauth2PermissionGrant') {
            $removeScopes.Add('DelegatedPermissionGrant.ReadWrite.All')
        }
        if ($assignmentTypes -contains 'unifiedRoleAssignment') {
            $removeScopes.Add('RoleManagement.ReadWrite.Directory')
        }
    }

    return @($removeScopes | Sort-Object -Unique)
}

function Resolve-TestManifestPathArgument {
    if (-not [string]::IsNullOrWhiteSpace($ManifestPath)) {
        return $ManifestPath
    }

    $remaining = @($args)
    for ($i = 0; $i -lt $remaining.Count; $i++) {
        if ([string]$remaining[$i] -ieq '-ManifestPath' -and ($i + 1) -lt $remaining.Count) {
            return [string]$remaining[$i + 1]
        }
        if ([string]$remaining[$i] -match '(?i)EntraTopology-TestData-[A-Fa-f0-9]{8}\.json$') {
            return [string]$remaining[$i]
        }
    }

    $candidateRoots = [System.Collections.Generic.List[string]]::new()
    if (-not [string]::IsNullOrWhiteSpace($HOME)) {
        $candidateRoots.Add((Join-Path $HOME '.entra-topology/test-data'))
        $candidateRoots.Add("$HOME.entra-topology\test-data")
    }
    $candidateRoots.Add((Join-Path (Get-Location).Path '.entra-topology-test-data'))

    $candidates = @(
        $candidateRoots |
            Select-Object -Unique |
            Where-Object { Test-Path -LiteralPath $_ } |
            ForEach-Object { Get-ChildItem -LiteralPath $_ -Filter 'EntraTopology-TestData-*.json' -File -ErrorAction SilentlyContinue } |
            ForEach-Object {
                try {
                    $manifest = Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json -Depth 30
                    if ([string](Get-TestObjectProperty $manifest 'tenantId') -eq $TenantIdText -and [string](Get-TestObjectProperty $manifest 'state') -ne 'Removed') {
                        $_
                    }
                }
                catch {
                    Write-Verbose "Skipping unreadable test-data manifest '$($_.FullName)': $($_.Exception.Message)"
                }
            } |
            Sort-Object LastWriteTimeUtc -Descending
    )

    if ($candidates.Count -eq 1) {
        Write-Warning "ManifestPath was not bound; using the only matching manifest for this tenant: $($candidates[0].FullName)"
        return $candidates[0].FullName
    }

    if ($candidates.Count -gt 1) {
        $list = ($candidates | Select-Object -First 8 | ForEach-Object { "  - $($_.FullName)" }) -join [Environment]::NewLine
        throw "-ManifestPath was not bound, and multiple matching manifests were found. Run Remove as one line and choose one manifest:$([Environment]::NewLine)$list"
    }

    $received = if ($remaining.Count) { " Remaining arguments received: $($remaining -join ' ')" } else { '' }
    throw "-ManifestPath is required for Remove. Cleanup is deliberately manifest-driven.$received"
}

function Assert-GraphContext {
    param([Parameter(Mandatory)][string[]]$RequiredScopes)

    Import-Module Microsoft.Graph.Authentication -MinimumVersion 2.0.0 -ErrorAction Stop

    $context = Get-MgContext
    if ($null -eq $context) {
        if (-not $Connect) {
            $scopeLiteral = ($RequiredScopes | ForEach-Object { "'$_'" }) -join ', '
            throw "No Microsoft Graph context is active. Connect first with: Connect-MgGraph -TenantId '$($TenantIdText)' -Scopes @($scopeLiteral) -ContextScope Process"
        }

        Write-Host "Connecting to tenant $($TenantIdText) with delegated scopes:" -ForegroundColor Cyan
        $RequiredScopes | ForEach-Object { Write-Host "  - $_" }
        Connect-MgGraph -TenantId $TenantIdText -Scopes $RequiredScopes -ContextScope Process -NoWelcome | Out-Null
        $script:OwnsGraphContext = $true
        $context = Get-MgContext
    }

    if ([string]$context.TenantId -ne $TenantIdText) {
        throw "The active Graph context targets tenant '$($context.TenantId)', not '$($TenantIdText)'. Disconnect/reconnect explicitly; the simulator will not replace an existing context."
    }

    if ([string]$context.AuthType -ne 'Delegated') {
        throw "The simulator requires a delegated Graph context. Current AuthType is '$($context.AuthType)'."
    }

    $grantedScopes = @($context.Scopes)
    $missingScopes = @($RequiredScopes | Where-Object { $grantedScopes -notcontains $_ })
    if ($missingScopes.Count -gt 0) {
        $scopeLiteral = ($RequiredScopes | ForEach-Object { "'$_'" }) -join ', '
        throw "The active Graph context is missing: $($missingScopes -join ', '). Reconnect explicitly with: Connect-MgGraph -TenantId '$($TenantIdText)' -Scopes @($scopeLiteral) -ContextScope Process"
    }
}

function Assert-VerifiedUpnDomain {
    param([Parameter(Mandatory)][string]$Domain)

    $domainObject = Invoke-TestGraphRequest -Method GET -Uri "$GraphRoot/domains/${Domain}?`$select=id,isVerified"
    if ($null -eq $domainObject -or -not [bool]$domainObject.isVerified) {
        throw "The supplied UPN domain '$Domain' is not a verified domain in tenant '$($TenantIdText)'."
    }
}

function New-SimulatorUser {
    param(
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][bool]$Enabled,
        [Parameter(Mandatory)][string]$RunPrefix,
        [Parameter(Mandatory)][string]$Domain
    )

    $alias = New-SafeAlias -Value "$RunPrefix-$Label"
    $displayName = "$RunPrefix $Label"
    $upn = "$alias@$Domain"
    $password = New-RandomPassword

    try {
        $user = Invoke-TestGraphRequest -Method POST -Uri "$GraphRoot/users" -Body @{
            accountEnabled    = $Enabled
            displayName       = $displayName
            mailNickname      = $alias
            userPrincipalName = $upn
            passwordProfile   = @{
                forceChangePasswordNextSignIn = $true
                password                      = $password
            }
        }
    }
    finally {
        $password = $null
    }

    Add-TestManifestObject -Type 'user' -Id ([string]$user.id) -DisplayName $displayName -UserPrincipalName $upn
    return $user
}

function New-SimulatorGroup {
    param(
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][string]$RunPrefix
    )

    $displayName = "$RunPrefix $Label"
    $group = Invoke-TestGraphRequest -Method POST -Uri "$GraphRoot/groups" -Body @{
        displayName     = $displayName
        description     = "Synthetic EntraTopology validation object. Run: $RunPrefix"
        groupTypes      = @()
        mailEnabled     = $false
        mailNickname    = (New-SafeAlias -Value "$RunPrefix-$Label")
        securityEnabled = $true
    }

    Add-TestManifestObject -Type 'group' -Id ([string]$group.id) -DisplayName $displayName
    return $group
}

function New-SimulatorApplication {
    param(
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][string]$RunPrefix,
        [hashtable[]]$RequiredResourceAccess,
        [hashtable[]]$AppRoles,
        [hashtable[]]$OAuth2PermissionScopes,
        [hashtable[]]$KeyCredentials
    )

    $displayName = "$RunPrefix $Label"
    $body = @{
        displayName    = $displayName
        signInAudience = 'AzureADMyOrg'
    }

    if ($null -ne $RequiredResourceAccess -and $RequiredResourceAccess.Count -gt 0) {
        $body['requiredResourceAccess'] = $RequiredResourceAccess
    }

    if ($null -ne $AppRoles -and $AppRoles.Count -gt 0) {
        $body['appRoles'] = $AppRoles
    }

    if ($null -ne $OAuth2PermissionScopes -and $OAuth2PermissionScopes.Count -gt 0) {
        $body['api'] = @{
            oauth2PermissionScopes = $OAuth2PermissionScopes
        }
    }

    if ($null -ne $KeyCredentials -and $KeyCredentials.Count -gt 0) {
        $body['keyCredentials'] = $KeyCredentials
    }

    $application = Invoke-TestGraphRequest -Method POST -Uri "$GraphRoot/applications" -Body $body
    Add-TestManifestObject -Type 'application' -Id ([string]$application.id) -DisplayName $displayName -AppId ([string]$application.appId)
    return $application
}

function New-SimulatorServicePrincipal {
    param(
        [Parameter(Mandatory)][string]$ApplicationAppId,
        [Parameter(Mandatory)][string]$DisplayName
    )

    $servicePrincipal = Invoke-TestGraphRequest `
        -Method POST `
        -Uri "$GraphRoot/servicePrincipals" `
        -Body @{ appId = $ApplicationAppId } `
        -RetryStatusCodes @(400, 404, 429, 500, 502, 503, 504) `
        -MaxAttempts 8

    Add-TestManifestObject -Type 'servicePrincipal' -Id ([string]$servicePrincipal.id) -DisplayName $DisplayName -AppId ([string]$servicePrincipal.appId)
    return $servicePrincipal
}

function Add-DirectoryReference {
    param(
        [Parameter(Mandatory)][ValidateSet('groupMember', 'groupOwner', 'applicationOwner', 'servicePrincipalOwner')][string]$ReferenceType,
        [Parameter(Mandatory)][string]$ContainerId,
        [Parameter(Mandatory)][string]$ObjectId
    )

    switch ($ReferenceType) {
        'groupMember'             { $uri = "$GraphRoot/groups/$ContainerId/members/`$ref" }
        'groupOwner'              { $uri = "$GraphRoot/groups/$ContainerId/owners/`$ref" }
        'applicationOwner'        { $uri = "$GraphRoot/applications/$ContainerId/owners/`$ref" }
        'servicePrincipalOwner'   { $uri = "$GraphRoot/servicePrincipals/$ContainerId/owners/`$ref" }
    }

    $null = Invoke-TestGraphRequest `
        -Method POST `
        -Uri $uri `
        -Body @{ '@odata.id' = "$GraphRoot/directoryObjects/$ObjectId" } `
        -RetryStatusCodes @(400, 404, 429, 500, 502, 503, 504) `
        -MaxAttempts 8
}

function New-EphemeralCertificateKeyCredential {
    param(
        [Parameter(Mandatory)][string]$DisplayName,
        [ValidateRange(2, 365)][int]$DaysValid = 45
    )

    $notBefore = [DateTimeOffset]::UtcNow.AddMinutes(-5)
    $notAfter = [DateTimeOffset]::UtcNow.AddDays($DaysValid)
    $keyId = [Guid]::NewGuid()

    $rsa = [System.Security.Cryptography.RSA]::Create(2048)
    try {
        $subject = [System.Security.Cryptography.X509Certificates.X500DistinguishedName]::new("CN=$DisplayName")
        $request = [System.Security.Cryptography.X509Certificates.CertificateRequest]::new(
            $subject,
            $rsa,
            [System.Security.Cryptography.HashAlgorithmName]::SHA256,
            [System.Security.Cryptography.RSASignaturePadding]::Pkcs1
        )
        $certificate = $request.CreateSelfSigned($notBefore, $notAfter)
        try {
            return [pscustomobject]@{
                KeyCredential = @{
                    customKeyIdentifier = [Convert]::ToBase64String($certificate.GetCertHash())
                    displayName         = $DisplayName
                    endDateTime         = $notAfter.ToString('o')
                    key                 = [Convert]::ToBase64String($certificate.RawData)
                    keyId               = $keyId.ToString()
                    startDateTime       = $notBefore.ToString('o')
                    type                = 'AsymmetricX509Cert'
                    usage               = 'Verify'
                }
                KeyId       = $keyId.ToString()
                EndDateTime = $notAfter.ToString('o')
            }
        }
        finally {
            $certificate.Dispose()
        }
    }
    finally {
        $rsa.Dispose()
    }
}

function Wait-ForCustomResourceDefinitions {
    param(
        [Parameter(Mandatory)][string]$ServicePrincipalId,
        [Parameter(Mandatory)][string]$AppRoleId,
        [Parameter(Mandatory)][string]$ScopeId
    )

    for ($attempt = 1; $attempt -le 12; $attempt++) {
        $resource = Invoke-TestGraphRequest -Method GET -Uri "$GraphRoot/servicePrincipals/${ServicePrincipalId}?`$select=id,appRoles,oauth2PermissionScopes"
        $rolePresent = @(Get-TestObjectProperty $resource 'appRoles' | Where-Object { [string](Get-TestObjectProperty $_ 'id') -eq $AppRoleId }).Count -gt 0
        $scopePresent = @(Get-TestObjectProperty $resource 'oauth2PermissionScopes' | Where-Object { [string](Get-TestObjectProperty $_ 'id') -eq $ScopeId }).Count -gt 0

        if ($rolePresent -and $scopePresent) {
            return
        }

        if ($attempt -lt 12) {
            Start-Sleep -Seconds 2
        }
    }

    throw 'The dummy API service principal did not receive its app-role/OAuth-scope definitions within the replication window.'
}

function Get-MicrosoftGraphServicePrincipal {
    $select = 'id,appId,displayName,appRoles,oauth2PermissionScopes'
    return Invoke-TestGraphRequest -Method GET -Uri "$GraphRoot/servicePrincipals(appId='$MicrosoftGraphAppId')?`$select=$select"
}

function Resolve-GraphApplicationRole {
    param(
        [Parameter(Mandatory)]$GraphServicePrincipal,
        [Parameter(Mandatory)][string]$Value
    )

    $role = @(Get-TestObjectProperty $GraphServicePrincipal 'appRoles' | Where-Object {
        [string](Get-TestObjectProperty $_ 'value') -eq $Value -and @(Get-TestObjectProperty $_ 'allowedMemberTypes') -contains 'Application'
    }) | Select-Object -First 1

    if ($null -eq $role) {
        throw "Microsoft Graph application role '$Value' could not be resolved dynamically."
    }

    return $role
}

function Get-DirectoryRoleDefinitionByDisplayName {
    param([Parameter(Mandatory)][string]$DisplayName)

    $filter = [Uri]::EscapeDataString("displayName eq '$DisplayName'")
    $result = Invoke-TestGraphRequest -Method GET -Uri "$GraphRoot/roleManagement/directory/roleDefinitions?`$filter=$filter&`$select=id,displayName,templateId"
    $definition = @(Get-TestObjectProperty $result 'value') | Select-Object -First 1
    if ($null -eq $definition) {
        throw "Directory role definition '$DisplayName' was not found."
    }
    return $definition
}

function Invoke-Populate {
    if ([string]::IsNullOrWhiteSpace($UserPrincipalNameDomain)) {
        throw '-UserPrincipalNameDomain is required for Populate and must be a verified tenant domain.'
    }

    if ($UserPrincipalNameDomain -notmatch '^[A-Za-z0-9.-]+\.[A-Za-z]{2,}$') {
        throw "'$UserPrincipalNameDomain' does not look like a DNS domain."
    }

    $runId = [Guid]::NewGuid().ToString('N').Substring(0, 8)
    $runPrefix = "$Prefix-$runId"

    if ([string]::IsNullOrWhiteSpace($ManifestPath)) {
        $basePath = if (-not [string]::IsNullOrWhiteSpace($HOME)) {
            Join-Path $HOME '.entra-topology/test-data'
        }
        else {
            Join-Path (Get-Location).Path '.entra-topology-test-data'
        }
        $script:ManifestFilePath = Join-Path $basePath "EntraTopology-TestData-$runId.json"
    }
    else {
        $script:ManifestFilePath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ManifestPath)
    }

    if (Test-Path -LiteralPath $script:ManifestFilePath) {
        throw "Manifest path already exists: $script:ManifestFilePath"
    }

    $requiredScopes = Get-RequiredScopes -Operation 'Populate'

    $scenarioTarget = "tenant $($TenantIdText) using prefix '$runPrefix'"
    if (-not $PSCmdlet.ShouldProcess($scenarioTarget, 'Populate EntraTopology synthetic test data')) {
        return
    }

    Assert-GraphContext -RequiredScopes $requiredScopes
    Assert-VerifiedUpnDomain -Domain $UserPrincipalNameDomain

    if ($IncludePrivilegedRoleAssignment) {
        Write-Warning 'Privileged-role scenario enabled: Application Administrator will be assigned to a disabled synthetic user until cleanup.'
    }
    if ($IncludeDelegatedGrant) {
        Write-Warning 'Delegated grant scenario enabled. The caller must hold DelegatedPermissionGrant.ReadWrite.All; the actual grant targets only the simulator dummy API.'
    }
    if ($IncludeAppRoleGrant) {
        Write-Warning 'App-role grant scenario enabled. The caller must hold AppRoleAssignment.ReadWrite.All; the actual grant targets only the simulator dummy API.'
    }

    $script:Manifest = [ordered]@{
        schemaVersion = '1.0'
        tool          = 'EntraTopologyTestDataSimulator'
        state         = 'Populating'
        runId         = $runId
        prefix        = $runPrefix
        tenantId      = $TenantIdText
        upnDomain     = $UserPrincipalNameDomain
        createdAtUtc  = [DateTimeOffset]::UtcNow.ToString('o')
        updatedAtUtc  = [DateTimeOffset]::UtcNow.ToString('o')
        options       = [ordered]@{
            includeAppRoleGrant              = [bool]$IncludeAppRoleGrant
            includeDelegatedGrant            = [bool]$IncludeDelegatedGrant
            includePrivilegedRoleAssignment  = [bool]$IncludePrivilegedRoleAssignment
        }
        objects       = @()
        relationships = @()
        credentials   = @()
        assignments   = @()
        warnings      = @()
        expected      = [ordered]@{
            relationshipKinds = @(
                'memberOf',
                'owns',
                'instantiatedAs',
                'hasCredential',
                'requiresApiPermission'
            )
            signals = @(
                'disabledIdentity',
                'disabledWorkloadIdentity',
                'ownerlessObject',
                'credentialExpiring',
                'disabledOwnerRelationship',
                'highImpactRequestedPermission'
            )
            intentionallyNotSimulated = @(
                'riskyIdentity (Identity Protection generated state)',
                'staleDevice / registeredOwnerOf (device creation and sign-in timestamps are not reliably synthetic via app-only lab seeding)',
                'guestOwnerRelationship (requires an external B2B identity)',
                'PIM schedule instances (governance/licensing-specific)'
            )
        }
    }

    if ($IncludeAppRoleGrant) {
        $script:Manifest.expected.relationshipKinds += 'hasAppRoleAssignment'
    }
    if ($IncludeDelegatedGrant) {
        $script:Manifest.expected.relationshipKinds += 'hasDelegatedPermission'
    }
    if ($IncludePrivilegedRoleAssignment) {
        $script:Manifest.expected.relationshipKinds += 'assignedDirectoryRole'
        $script:Manifest.expected.signals += @('privilegedIdentity', 'highPrivilegeRoleAssignment', 'privilegedOwnerRelationship')
    }

    Save-TestManifest

    try {
        Write-Host '[1/7] Creating synthetic users...' -ForegroundColor Cyan
        $enabledOwner = New-SimulatorUser -Label 'Enabled Owner' -Enabled $true -RunPrefix $runPrefix -Domain $UserPrincipalNameDomain
        $disabledOwner = New-SimulatorUser -Label 'Disabled Owner' -Enabled $false -RunPrefix $runPrefix -Domain $UserPrincipalNameDomain
        $memberUser = New-SimulatorUser -Label 'Member User' -Enabled $true -RunPrefix $runPrefix -Domain $UserPrincipalNameDomain

        Write-Host '[2/7] Creating groups and membership topology...' -ForegroundColor Cyan
        $coreGroup = New-SimulatorGroup -Label 'Core Security Group' -RunPrefix $runPrefix
        $childGroup = New-SimulatorGroup -Label 'Nested Security Group' -RunPrefix $runPrefix

        Add-DirectoryReference -ReferenceType groupOwner -ContainerId ([string]$coreGroup.id) -ObjectId ([string]$enabledOwner.id)
        Add-TestManifestRelationship -Kind 'owns' -SourceId ([string]$enabledOwner.id) -TargetId ([string]$coreGroup.id) -Description 'Enabled synthetic user owns core group.'

        Add-DirectoryReference -ReferenceType groupOwner -ContainerId ([string]$childGroup.id) -ObjectId ([string]$disabledOwner.id)
        Add-TestManifestRelationship -Kind 'owns' -SourceId ([string]$disabledOwner.id) -TargetId ([string]$childGroup.id) -Description 'Disabled synthetic user owns nested group.'

        Add-DirectoryReference -ReferenceType groupMember -ContainerId ([string]$coreGroup.id) -ObjectId ([string]$memberUser.id)
        Add-TestManifestRelationship -Kind 'memberOf' -SourceId ([string]$memberUser.id) -TargetId ([string]$coreGroup.id) -Description 'User membership.'

        Add-DirectoryReference -ReferenceType groupMember -ContainerId ([string]$coreGroup.id) -ObjectId ([string]$childGroup.id)
        Add-TestManifestRelationship -Kind 'memberOf' -SourceId ([string]$childGroup.id) -TargetId ([string]$coreGroup.id) -Description 'Nested group membership.'

        Add-DirectoryReference -ReferenceType groupMember -ContainerId ([string]$childGroup.id) -ObjectId ([string]$disabledOwner.id)
        Add-TestManifestRelationship -Kind 'memberOf' -SourceId ([string]$disabledOwner.id) -TargetId ([string]$childGroup.id) -Description 'Disabled user membership.'

        Write-Host '[3/7] Creating dummy API resource...' -ForegroundColor Cyan
        $customAppRoleId = [Guid]::NewGuid().ToString()
        $customScopeId = [Guid]::NewGuid().ToString()
        $resourceApp = New-SimulatorApplication `
            -Label 'Dummy Resource API' `
            -RunPrefix $runPrefix `
            -AppRoles @(
                @{
                    allowedMemberTypes = @('Application')
                    description        = 'Synthetic application role used only to validate EntraTopology relationships.'
                    displayName        = 'Topology.Read.All'
                    id                 = $customAppRoleId
                    isEnabled          = $true
                    value              = 'Topology.Read.All'
                }
            ) `
            -OAuth2PermissionScopes @(
                @{
                    adminConsentDescription = 'Synthetic delegated scope used only to validate EntraTopology relationships.'
                    adminConsentDisplayName = 'Read synthetic topology data'
                    id                      = $customScopeId
                    isEnabled               = $true
                    type                    = 'Admin'
                    userConsentDescription  = 'Synthetic delegated scope used only to validate EntraTopology relationships.'
                    userConsentDisplayName  = 'Read synthetic topology data'
                    value                   = 'Topology.Read'
                }
            )

        $resourceSp = New-SimulatorServicePrincipal -ApplicationAppId ([string]$resourceApp.appId) -DisplayName "$runPrefix Dummy Resource API"
        Add-TestManifestRelationship -Kind 'instantiatedAs' -SourceId ([string]$resourceApp.id) -TargetId ([string]$resourceSp.id) -Description 'Resource application to enterprise application.'
        Add-DirectoryReference -ReferenceType applicationOwner -ContainerId ([string]$resourceApp.id) -ObjectId ([string]$enabledOwner.id)
        Add-TestManifestRelationship -Kind 'owns' -SourceId ([string]$enabledOwner.id) -TargetId ([string]$resourceApp.id) -Description 'Enabled user owns resource application.'
        Add-DirectoryReference -ReferenceType servicePrincipalOwner -ContainerId ([string]$resourceSp.id) -ObjectId ([string]$enabledOwner.id)
        Add-TestManifestRelationship -Kind 'owns' -SourceId ([string]$enabledOwner.id) -TargetId ([string]$resourceSp.id) -Description 'Enabled user owns resource service principal.'
        Wait-ForCustomResourceDefinitions -ServicePrincipalId ([string]$resourceSp.id) -AppRoleId $customAppRoleId -ScopeId $customScopeId

        Write-Host '[4/7] Creating client application, requested permissions, and credentials...' -ForegroundColor Cyan
        $graphSp = Get-MicrosoftGraphServicePrincipal
        $highImpactRequestedRole = Resolve-GraphApplicationRole -GraphServicePrincipal $graphSp -Value 'Application.ReadWrite.All'

        $clientApp = New-SimulatorApplication `
            -Label 'Client Application' `
            -RunPrefix $runPrefix `
            -RequiredResourceAccess @(
                @{
                    resourceAppId  = $MicrosoftGraphAppId
                    resourceAccess = @(
                        @{ id = [string]$highImpactRequestedRole.id; type = 'Role' }
                    )
                },
                @{
                    resourceAppId  = [string]$resourceApp.appId
                    resourceAccess = @(
                        @{ id = $customAppRoleId; type = 'Role' },
                        @{ id = $customScopeId; type = 'Scope' }
                    )
                }
            )

        $clientSp = New-SimulatorServicePrincipal -ApplicationAppId ([string]$clientApp.appId) -DisplayName "$runPrefix Client Application"
        Add-TestManifestRelationship -Kind 'instantiatedAs' -SourceId ([string]$clientApp.id) -TargetId ([string]$clientSp.id) -Description 'Client application to enterprise application.'
        Add-TestManifestRelationship -Kind 'requiresApiPermission' -SourceId ([string]$clientApp.id) -TargetId ([string]$graphSp.id) -Description 'Requests Microsoft Graph Application.ReadWrite.All but does not grant it.'
        Add-TestManifestRelationship -Kind 'requiresApiPermission' -SourceId ([string]$clientApp.id) -TargetId ([string]$resourceSp.id) -Description 'Requests dummy API app role and delegated scope.'

        Add-DirectoryReference -ReferenceType applicationOwner -ContainerId ([string]$clientApp.id) -ObjectId ([string]$enabledOwner.id)
        Add-TestManifestRelationship -Kind 'owns' -SourceId ([string]$enabledOwner.id) -TargetId ([string]$clientApp.id) -Description 'Enabled user owns client application.'

        Add-DirectoryReference -ReferenceType servicePrincipalOwner -ContainerId ([string]$clientSp.id) -ObjectId ([string]$disabledOwner.id)
        Add-TestManifestRelationship -Kind 'owns' -SourceId ([string]$disabledOwner.id) -TargetId ([string]$clientSp.id) -Description 'Disabled user owns client service principal.'

        Add-DirectoryReference -ReferenceType groupMember -ContainerId ([string]$coreGroup.id) -ObjectId ([string]$clientSp.id)
        Add-TestManifestRelationship -Kind 'memberOf' -SourceId ([string]$clientSp.id) -TargetId ([string]$coreGroup.id) -Description 'Service principal membership in security group.'

        $secretDisplayName = "$runPrefix Expiring Secret"
        $secretEnd = [DateTimeOffset]::UtcNow.AddDays(20)
        $null = Invoke-TestGraphRequest -Method POST -Uri "$GraphRoot/applications/$($clientApp.id)/addPassword" -Body @{
            passwordCredential = @{
                displayName   = $secretDisplayName
                startDateTime = [DateTimeOffset]::UtcNow.AddMinutes(-2).ToString('o')
                endDateTime   = $secretEnd.ToString('o')
            }
        }
        Add-TestManifestCredential -ApplicationId ([string]$clientApp.id) -CredentialType 'password' -DisplayName $secretDisplayName -EndDateTime $secretEnd.ToString('o')
        Add-TestManifestRelationship -Kind 'hasCredential' -SourceId ([string]$clientApp.id) -TargetId 'generated-at-collection' -Description 'Application password credential expires within 30 days. secretText discarded.'

        try {
            $certificateCredential = New-EphemeralCertificateKeyCredential -DisplayName "$runPrefix Expiring Certificate" -DaysValid 45
            $null = Invoke-TestGraphRequest -Method PATCH -Uri "$GraphRoot/applications/$($clientApp.id)" -Body @{
                keyCredentials = @($certificateCredential.KeyCredential)
            }
            Add-TestManifestCredential -ApplicationId ([string]$clientApp.id) -CredentialType 'certificate' -DisplayName "$runPrefix Expiring Certificate" -EndDateTime $certificateCredential.EndDateTime -KeyId $certificateCredential.KeyId
            Add-TestManifestRelationship -Kind 'hasCredential' -SourceId ([string]$clientApp.id) -TargetId $certificateCredential.KeyId -Description 'Public certificate credential expires within 60 days; private key discarded.'
        }
        catch {
            $warning = "Certificate credential seeding was skipped because Microsoft Graph rejected keyCredentials for the synthetic application. Password credential coverage remains available. $($_.Exception.Message)"
            Write-Warning $warning
            $script:Manifest['warnings'] += $warning
            Save-TestManifest
        }

        Write-Host '[5/7] Creating ownerless and disabled workload identities...' -ForegroundColor Cyan
        $ownerlessApp = New-SimulatorApplication -Label 'Ownerless Application' -RunPrefix $runPrefix
        $ownerlessSp = New-SimulatorServicePrincipal -ApplicationAppId ([string]$ownerlessApp.appId) -DisplayName "$runPrefix Ownerless Application"
        Add-TestManifestRelationship -Kind 'instantiatedAs' -SourceId ([string]$ownerlessApp.id) -TargetId ([string]$ownerlessSp.id) -Description 'Ownerless application to service principal.'

        $disabledWorkloadApp = New-SimulatorApplication -Label 'Disabled Workload Application' -RunPrefix $runPrefix
        $disabledWorkloadSp = New-SimulatorServicePrincipal -ApplicationAppId ([string]$disabledWorkloadApp.appId) -DisplayName "$runPrefix Disabled Workload Application"
        Add-TestManifestRelationship -Kind 'instantiatedAs' -SourceId ([string]$disabledWorkloadApp.id) -TargetId ([string]$disabledWorkloadSp.id) -Description 'Disabled workload application to service principal.'
        Add-DirectoryReference -ReferenceType applicationOwner -ContainerId ([string]$disabledWorkloadApp.id) -ObjectId ([string]$enabledOwner.id)
        Add-DirectoryReference -ReferenceType servicePrincipalOwner -ContainerId ([string]$disabledWorkloadSp.id) -ObjectId ([string]$enabledOwner.id)
        Add-TestManifestRelationship -Kind 'owns' -SourceId ([string]$enabledOwner.id) -TargetId ([string]$disabledWorkloadApp.id) -Description 'Enabled user owns disabled workload application.'
        Add-TestManifestRelationship -Kind 'owns' -SourceId ([string]$enabledOwner.id) -TargetId ([string]$disabledWorkloadSp.id) -Description 'Enabled user owns disabled workload service principal.'
        $null = Invoke-TestGraphRequest -Method PATCH -Uri "$GraphRoot/servicePrincipals/$($disabledWorkloadSp.id)" -Body @{ accountEnabled = $false }

        Write-Host '[6/7] Creating optional grant / role scenarios...' -ForegroundColor Cyan
        if ($IncludeAppRoleGrant) {
            $assignment = Invoke-TestGraphRequest -Method POST -Uri "$GraphRoot/servicePrincipals/$($resourceSp.id)/appRoleAssignedTo" -Body @{
                principalId = [string]$clientSp.id
                resourceId  = [string]$resourceSp.id
                appRoleId   = $customAppRoleId
            } -RetryStatusCodes @(400, 404, 429, 500, 502, 503, 504) -MaxAttempts 8

            Add-TestManifestAssignment -Type 'appRoleAssignment' -Id ([string]$assignment.id) -PrincipalId ([string]$clientSp.id) -ResourceId ([string]$resourceSp.id) -Description 'Dummy API Topology.Read.All application role.'
            Add-TestManifestRelationship -Kind 'hasAppRoleAssignment' -SourceId ([string]$clientSp.id) -TargetId ([string]$resourceSp.id) -Description 'Granted only to the simulator dummy API.'
        }

        if ($IncludeDelegatedGrant) {
            $grant = Invoke-TestGraphRequest -Method POST -Uri "$GraphRoot/oauth2PermissionGrants" -Body @{
                clientId    = [string]$clientSp.id
                consentType = 'AllPrincipals'
                resourceId  = [string]$resourceSp.id
                scope       = 'Topology.Read'
            } -RetryStatusCodes @(400, 404, 429, 500, 502, 503, 504) -MaxAttempts 8

            Add-TestManifestAssignment -Type 'oauth2PermissionGrant' -Id ([string]$grant.id) -PrincipalId ([string]$clientSp.id) -ResourceId ([string]$resourceSp.id) -Description 'Dummy API Topology.Read delegated grant.'
            Add-TestManifestRelationship -Kind 'hasDelegatedPermission' -SourceId ([string]$clientSp.id) -TargetId ([string]$resourceSp.id) -Description 'Tenant-wide consent only to the simulator dummy API.'
        }

        if ($IncludePrivilegedRoleAssignment) {
            $roleDefinition = Get-DirectoryRoleDefinitionByDisplayName -DisplayName 'Application Administrator'
            $roleAssignment = Invoke-TestGraphRequest -Method POST -Uri "$GraphRoot/roleManagement/directory/roleAssignments" -Body @{
                '@odata.type'    = '#microsoft.graph.unifiedRoleAssignment'
                roleDefinitionId = [string]$roleDefinition.id
                principalId      = [string]$disabledOwner.id
                directoryScopeId = '/'
            }

            Add-TestManifestAssignment -Type 'unifiedRoleAssignment' -Id ([string]$roleAssignment.id) -PrincipalId ([string]$disabledOwner.id) -RoleDefinitionId ([string]$roleDefinition.id) -Description 'Application Administrator assigned to disabled synthetic user.'
            Add-TestManifestRelationship -Kind 'assignedDirectoryRole' -SourceId ([string]$disabledOwner.id) -TargetId ([string]$roleDefinition.id) -Description 'Privileged role assignment for signal validation.'
        }

        Write-Host '[7/7] Finalizing manifest...' -ForegroundColor Cyan
        $script:Manifest['state'] = 'Populated'
        $script:Manifest['completedAtUtc'] = [DateTimeOffset]::UtcNow.ToString('o')
        Save-TestManifest

        Write-Host ''
        Write-Host 'Synthetic EntraTopology dataset created successfully.' -ForegroundColor Green
        Write-Host "Run prefix : $runPrefix"
        Write-Host "Manifest   : $script:ManifestFilePath"
        Write-Host "Objects    : $(@(Get-TestObjectProperty $script:Manifest 'objects').Count)"
        Write-Host "Relations  : $(@(Get-TestObjectProperty $script:Manifest 'relationships').Count)"
        Write-Host "Assignments: $(@(Get-TestObjectProperty $script:Manifest 'assignments').Count)"
        Write-Host ''
        Write-Host 'Recommended next step:' -ForegroundColor Cyan
        Write-Host '  Run EntraTopology against this tenant, inspect the synthetic prefix, then remove the data using the manifest.'
        Write-Host ''
        Write-Host 'Cleanup command:' -ForegroundColor Cyan
        Write-Host "  .\Invoke-EntraTopologyTestData.ps1 -Action Remove -TenantId '$($TenantIdText)' -ManifestPath '$script:ManifestFilePath'"

        [pscustomobject]@{
            RunId        = $runId
            Prefix       = $runPrefix
            TenantId     = $TenantIdText
            ManifestPath = $script:ManifestFilePath
            ObjectCount  = @(Get-TestObjectProperty $script:Manifest 'objects').Count
            RelationshipCount = @(Get-TestObjectProperty $script:Manifest 'relationships').Count
            AssignmentCount   = @(Get-TestObjectProperty $script:Manifest 'assignments').Count
        }
    }
    catch {
        if ($null -ne $script:Manifest) {
            $script:Manifest['state'] = 'PopulateFailed'
            $script:Manifest['lastError'] = $_.Exception.Message
            Save-TestManifest
        }

        Write-Error "Population failed. The manifest was preserved for cleanup at '$script:ManifestFilePath'. $($_.Exception.Message)"
        throw
    }
}

function Invoke-Remove {
    $resolvedManifestPathArgument = Resolve-TestManifestPathArgument
    $script:ManifestFilePath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($resolvedManifestPathArgument)
    if (-not (Test-Path -LiteralPath $script:ManifestFilePath)) {
        throw "Manifest not found: $script:ManifestFilePath"
    }

    $script:Manifest = Get-Content -LiteralPath $script:ManifestFilePath -Raw | ConvertFrom-Json -Depth 30

    if ([string](Get-TestObjectProperty $script:Manifest 'tool') -ne 'EntraTopologyTestDataSimulator') {
        throw 'The supplied file is not an EntraTopology test-data simulator manifest.'
    }

    $manifestTenantId = [string](Get-TestObjectProperty $script:Manifest 'tenantId')
    if ($manifestTenantId -ne $TenantIdText) {
        throw "Manifest tenant '$manifestTenantId' does not match requested tenant '$($TenantIdText)'."
    }

    if ([string](Get-TestObjectProperty $script:Manifest 'state') -eq 'Removed') {
        Write-Host 'Manifest is already marked Removed. Nothing to do.' -ForegroundColor Yellow
        return
    }

    $requiredScopes = Get-RequiredScopes -Operation 'Remove' -LoadedManifest $script:Manifest

    $target = "tenant $($TenantIdText), simulator run '$(Get-TestObjectProperty $script:Manifest 'runId')'"
    if (-not $PSCmdlet.ShouldProcess($target, 'Remove only IDs recorded in the EntraTopology test-data manifest')) {
        return
    }

    Assert-GraphContext -RequiredScopes $requiredScopes

    $failures = [System.Collections.Generic.List[object]]::new()

    function Remove-RecordedResource {
        param(
            [Parameter(Mandatory)][string]$Description,
            [Parameter(Mandatory)][scriptblock]$Operation
        )

        try {
            & $Operation
            Write-Host "  Removed/absent: $Description"
        }
        catch {
            $failures.Add([pscustomobject]@{ resource = $Description; error = $_.Exception.Message })
            Write-Warning "Failed to remove $Description : $($_.Exception.Message)"
        }
    }

    Write-Host '[1/5] Removing explicit assignments and grants...' -ForegroundColor Cyan
    foreach ($assignment in @(Get-TestObjectProperty $script:Manifest 'assignments')) {
        switch ([string](Get-TestObjectProperty $assignment 'type')) {
            'appRoleAssignment' {
                $resourceId = [string](Get-TestObjectProperty $assignment 'resourceId')
                $assignmentId = [string](Get-TestObjectProperty $assignment 'id')
                Remove-RecordedResource -Description "appRoleAssignment $assignmentId" -Operation {
                    $null = Invoke-TestGraphRequest -Method DELETE -Uri "$GraphRoot/servicePrincipals/$resourceId/appRoleAssignedTo/$assignmentId" -IgnoreNotFound
                }
            }
            'oauth2PermissionGrant' {
                $assignmentId = [string](Get-TestObjectProperty $assignment 'id')
                Remove-RecordedResource -Description "oauth2PermissionGrant $assignmentId" -Operation {
                    $null = Invoke-TestGraphRequest -Method DELETE -Uri "$GraphRoot/oauth2PermissionGrants/$assignmentId" -IgnoreNotFound
                }
            }
            'unifiedRoleAssignment' {
                $assignmentId = [string](Get-TestObjectProperty $assignment 'id')
                Remove-RecordedResource -Description "unifiedRoleAssignment $assignmentId" -Operation {
                    $null = Invoke-TestGraphRequest -Method DELETE -Uri "$GraphRoot/roleManagement/directory/roleAssignments/$assignmentId" -IgnoreNotFound
                }
            }
        }
    }

    Write-Host '[2/5] Removing service principals...' -ForegroundColor Cyan
    foreach ($object in @(Get-TestObjectProperty $script:Manifest 'objects' | Where-Object { [string](Get-TestObjectProperty $_ 'type') -eq 'servicePrincipal' })) {
        $objectId = [string](Get-TestObjectProperty $object 'id')
        $displayName = [string](Get-TestObjectProperty $object 'displayName')
        Remove-RecordedResource -Description "servicePrincipal $displayName [$objectId]" -Operation {
            $null = Invoke-TestGraphRequest -Method DELETE -Uri "$GraphRoot/servicePrincipals/$objectId" -IgnoreNotFound
        }
    }

    Write-Host '[3/5] Removing applications...' -ForegroundColor Cyan
    foreach ($object in @(Get-TestObjectProperty $script:Manifest 'objects' | Where-Object { [string](Get-TestObjectProperty $_ 'type') -eq 'application' })) {
        $objectId = [string](Get-TestObjectProperty $object 'id')
        $displayName = [string](Get-TestObjectProperty $object 'displayName')
        Remove-RecordedResource -Description "application $displayName [$objectId]" -Operation {
            $null = Invoke-TestGraphRequest -Method DELETE -Uri "$GraphRoot/applications/$objectId" -IgnoreNotFound
        }
    }

    Write-Host '[4/5] Removing groups...' -ForegroundColor Cyan
    foreach ($object in @(Get-TestObjectProperty $script:Manifest 'objects' | Where-Object { [string](Get-TestObjectProperty $_ 'type') -eq 'group' })) {
        $objectId = [string](Get-TestObjectProperty $object 'id')
        $displayName = [string](Get-TestObjectProperty $object 'displayName')
        Remove-RecordedResource -Description "group $displayName [$objectId]" -Operation {
            $null = Invoke-TestGraphRequest -Method DELETE -Uri "$GraphRoot/groups/$objectId" -IgnoreNotFound
        }
    }

    Write-Host '[5/5] Removing users...' -ForegroundColor Cyan
    foreach ($object in @(Get-TestObjectProperty $script:Manifest 'objects' | Where-Object { [string](Get-TestObjectProperty $_ 'type') -eq 'user' })) {
        $objectId = [string](Get-TestObjectProperty $object 'id')
        $displayName = [string](Get-TestObjectProperty $object 'displayName')
        Remove-RecordedResource -Description "user $displayName [$objectId]" -Operation {
            $null = Invoke-TestGraphRequest -Method DELETE -Uri "$GraphRoot/users/$objectId" -IgnoreNotFound
        }
    }

    if ($failures.Count -eq 0) {
        $script:Manifest.state = 'Removed'
        $script:Manifest | Add-Member -NotePropertyName removedAtUtc -NotePropertyValue ([DateTimeOffset]::UtcNow.ToString('o')) -Force
        $script:Manifest | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $script:ManifestFilePath -Encoding utf8NoBOM

        Write-Host ''
        Write-Host 'Cleanup completed successfully.' -ForegroundColor Green
        Write-Host "Manifest retained as an audit/cleanup record: $script:ManifestFilePath"
        Write-Host 'Note: Microsoft Entra can retain soft-deleted directory objects according to normal deleted-items retention.'
    }
    else {
        $script:Manifest.state = 'RemovePartial'
        $script:Manifest | Add-Member -NotePropertyName removeFailures -NotePropertyValue @($failures) -Force
        $script:Manifest | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $script:ManifestFilePath -Encoding utf8NoBOM

        throw "Cleanup completed with $($failures.Count) failure(s). Review the manifest and warnings, then rerun Remove."
    }
}

try {
    switch ($Action) {
        'Populate' { Invoke-Populate }
        'Remove'   { Invoke-Remove }
    }
}
finally {
    if ($script:OwnsGraphContext) {
        try {
            Disconnect-MgGraph | Out-Null
        }
        catch {
            Write-Verbose "The simulator-created Graph context could not be disconnected cleanly: $($_.Exception.Message)"
        }
    }
}

