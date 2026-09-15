function Get-EntraTopologyUsers {
    [CmdletBinding()] param([Parameter(Mandatory)][string]$TenantId,[object]$Telemetry)
    $r = New-EntraTopologyCollectorResult 'Users'
    $r.RequiredPermissions=@('User.Read.All','Directory.Read.All')
    $baseEndpoint='/v1.0/users?$select=id,displayName,userPrincipalName,userType,accountEnabled,createdDateTime'
    $activityEndpoint='/v1.0/users?$select=id,signInActivity'
    $riskyEndpoint='/v1.0/identityProtection/riskyUsers?$select=id,userPrincipalName,userDisplayName,riskLevel,riskState,riskDetail,riskLastUpdatedDateTime,isDeleted'

    Set-EntraTopologyCollectorCapability -Result $r -Name 'UserInventory' -Status 'Complete' -RequiredPermissions $r.RequiredPermissions -Endpoints @($baseEndpoint) | Out-Null
    Set-EntraTopologyCollectorCapability -Result $r -Name 'UserSignInActivity' -Status 'NotRun' -RequiredPermissions @('AuditLog.Read.All') -Endpoints @($activityEndpoint) -Warnings @('Optional signInActivity enrichment was not requested or permission is unavailable.') | Out-Null
    Set-EntraTopologyCollectorCapability -Result $r -Name 'RiskyUserContext' -Status 'NotRun' -RequiredPermissions @('IdentityRiskyUser.Read.All') -Endpoints @($riskyEndpoint) -Warnings @('Optional risky-user enrichment is unavailable unless IdentityRiskyUser.Read.All is granted. Microsoft Entra ID P2 is also required for risky-user data.') | Out-Null

    if (-not (Test-EntraTopologyPermission -AnyOf $r.RequiredPermissions)) {
        Set-EntraTopologyCollectorCapability -Result $r -Name 'UserInventory' -Status 'NotRun' -RequiredPermissions $r.RequiredPermissions -Endpoints @($baseEndpoint) -Warnings @('User collection permission not granted.') | Out-Null
        return Set-EntraTopologyCollectorNotRun $r $r.RequiredPermissions 'User collection permission not granted.'
    }

    $g = Invoke-EntraTopologyGraphRequest -Uri $baseEndpoint -RequiredPermission 'User.Read.All or Directory.Read.All' -Telemetry $Telemetry
    Add-EntraTopologyGraphResponseEvidence -Result $r -Capability 'UserInventory' -Response $g
    if ($g.Status -ne 'Success') {
        $r.Status='Partial'; $r.Warnings += @($g.Limitations)
        Set-EntraTopologyCollectorCapability -Result $r -Name 'UserInventory' -Status 'Partial' -RequiredPermissions $r.RequiredPermissions -Endpoints @($baseEndpoint) -Warnings @($g.Limitations) | Out-Null
        return $r
    }

    $users = @($g.Items)
    if (Test-EntraTopologyPermission -AnyOf @('AuditLog.Read.All')) {
        $activity = Invoke-EntraTopologyGraphRequest -Uri $activityEndpoint -RequiredPermission 'AuditLog.Read.All (Entra ID P1/P2 required for signInActivity)' -Telemetry $Telemetry
        Add-EntraTopologyGraphResponseEvidence -Result $r -Capability 'UserSignInActivity' -Response $activity
        if ($activity.Status -eq 'Success') {
            $byId=@{}
            foreach ($a in @($activity.Items)) {
                $activityUserId = Get-EntraTopologyProperty $a 'id'
                if ($activityUserId) { $byId[[string]$activityUserId] = Get-EntraTopologyProperty $a 'signInActivity' }
            }
            foreach ($u in $users) {
                $userId = Get-EntraTopologyProperty $u 'id'
                if ($userId -and $byId.ContainsKey([string]$userId)) { $u | Add-Member -NotePropertyName signInActivity -NotePropertyValue $byId[[string]$userId] -Force }
            }
            Set-EntraTopologyCollectorCapability -Result $r -Name 'UserSignInActivity' -Status 'Complete' -RequiredPermissions @('AuditLog.Read.All') -Endpoints @($activityEndpoint) | Out-Null
        } else {
            $warning = "Optional signInActivity enrichment unavailable: $(@($activity.Limitations) -join '; ')"
            $r.Warnings += $warning
            Set-EntraTopologyCollectorCapability -Result $r -Name 'UserSignInActivity' -Status 'Unavailable' -RequiredPermissions @('AuditLog.Read.All') -Endpoints @($activityEndpoint) -Warnings @($warning) | Out-Null
        }
    }

    if (Test-EntraTopologyPermission -AnyOf @('IdentityRiskyUser.Read.All')) {
        $risk = Invoke-EntraTopologyGraphRequest -Uri $riskyEndpoint -RequiredPermission 'IdentityRiskyUser.Read.All (Microsoft Entra ID P2 required)' -Telemetry $Telemetry
        Add-EntraTopologyGraphResponseEvidence -Result $r -Capability 'RiskyUserContext' -Response $risk
        if ($risk.Status -eq 'Success') {
            $riskById=@{}
            foreach($item in @($risk.Items)){
                $riskId=[string](Get-EntraTopologyProperty $item 'id')
                if($riskId){$riskById[$riskId]=$item}
            }
            foreach($u in $users){
                $userId=[string](Get-EntraTopologyProperty $u 'id')
                if(-not$userId -or -not$riskById.ContainsKey($userId)){continue}
                $ri=$riskById[$userId]
                foreach($propertyName in @('riskLevel','riskState','riskDetail','riskLastUpdatedDateTime')){
                    $value=Get-EntraTopologyProperty $ri $propertyName
                    if($null -ne $value){$u | Add-Member -NotePropertyName $propertyName -NotePropertyValue $value -Force}
                }
                $isDeleted=Get-EntraTopologyProperty $ri 'isDeleted'
                if($null -ne $isDeleted){$u | Add-Member -NotePropertyName riskUserIsDeleted -NotePropertyValue $isDeleted -Force}
            }
            Set-EntraTopologyCollectorCapability -Result $r -Name 'RiskyUserContext' -Status 'Complete' -RequiredPermissions @('IdentityRiskyUser.Read.All') -Endpoints @($riskyEndpoint) | Out-Null
        } else {
            $warning="Optional risky-user enrichment unavailable: HTTP $($risk.StatusCode); $(@($risk.Limitations)-join '; ')"
            $r.Warnings += $warning
            Set-EntraTopologyCollectorCapability -Result $r -Name 'RiskyUserContext' -Status 'Unavailable' -RequiredPermissions @('IdentityRiskyUser.Read.All') -Endpoints @($riskyEndpoint) -Warnings @($warning) | Out-Null
        }
    }

    $r.Objects=@($users | ForEach-Object {[pscustomobject]@{Kind='user';Object=$_}})
    $r.Metrics=@{
        Count=$users.Count
        SignInActivityCoverage=([string](@($r.Capabilities | Where-Object Name -eq 'UserSignInActivity')[0].Status))
        RiskyUserCoverage=([string](@($r.Capabilities | Where-Object Name -eq 'RiskyUserContext')[0].Status))
        ActiveRiskyUserCount=@($users | Where-Object {[string](Get-EntraTopologyProperty $_ 'riskState') -in @('atRisk','confirmedCompromised')}).Count
    }
    $r
}
