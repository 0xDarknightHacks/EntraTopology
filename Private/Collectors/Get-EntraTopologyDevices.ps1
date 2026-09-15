function Get-EntraTopologyDevices {
    [CmdletBinding()] param([Parameter(Mandatory)][string]$TenantId,[object]$Telemetry,[ValidateRange(1,20)][int]$BatchSize=20)
    $r=New-EntraTopologyCollectorResult 'Devices'; $r.RequiredPermissions=@('Device.Read.All','Directory.Read.All')
    $ep='/v1.0/devices?$select=id,deviceId,displayName,accountEnabled,operatingSystem,operatingSystemVersion,trustType,approximateLastSignInDateTime,isCompliant,isManaged,registrationDateTime'
    Set-EntraTopologyCollectorCapability -Result $r -Name 'DeviceInventory' -Status 'Complete' -RequiredPermissions $r.RequiredPermissions -Endpoints @($ep) | Out-Null
    Set-EntraTopologyCollectorCapability -Result $r -Name 'DeviceRegisteredOwners' -Status 'Complete' -RequiredPermissions $r.RequiredPermissions | Out-Null
    if(-not(Test-EntraTopologyPermission -AnyOf $r.RequiredPermissions)){
        foreach($cap in @('DeviceInventory','DeviceRegisteredOwners')){Set-EntraTopologyCollectorCapability -Result $r -Name $cap -Status 'NotRun' -RequiredPermissions $r.RequiredPermissions -Warnings @('Device collection permission not granted.') | Out-Null}
        return Set-EntraTopologyCollectorNotRun $r $r.RequiredPermissions 'Device collection permission not granted.'
    }
    $g=Invoke-EntraTopologyGraphRequest -Uri $ep -RequiredPermission 'Device.Read.All or Directory.Read.All' -Telemetry $Telemetry
    Add-EntraTopologyGraphResponseEvidence -Result $r -Capability 'DeviceInventory' -Response $g
    if($g.Status-ne'Success'){
        $r.Status='Partial';$r.Warnings+=@($g.Limitations)
        Set-EntraTopologyCollectorCapability -Result $r -Name 'DeviceInventory' -Status 'Partial' -RequiredPermissions $r.RequiredPermissions -Endpoints @($ep) -Warnings @($g.Limitations) | Out-Null
        Set-EntraTopologyCollectorCapability -Result $r -Name 'DeviceRegisteredOwners' -Status 'NotRun' -RequiredPermissions $r.RequiredPermissions -Warnings @('Parent device inventory was not collected successfully.') | Out-Null
        return $r
    }
    $r.Objects=@($g.Items|ForEach-Object{[pscustomobject]@{Kind='device';Object=$_}})
    $req=@(); foreach($d in @($g.Items)){$req += [pscustomobject]@{Uri="/devices/$($d.id)/registeredOwners?`$select=id,displayName";Target=[string]$d.id;Capability='DeviceRegisteredOwners'}}
    $failed=$false
    foreach($b in @(Invoke-EntraTopologyGraphBatch -Requests $req -BatchSize $BatchSize -Telemetry $Telemetry)){
        Add-EntraTopologyBatchEvidence -Result $r -Capability 'DeviceRegisteredOwners' -BatchResult $b -RequiredPermission 'Device.Read.All or Directory.Read.All'
        if($b.Status-ne'Success'){$failed=$true;$r.Status='Partial';$r.Warnings+=(Format-EntraTopologyBatchFailure -BatchResult $b -Prefix 'Device registered-owner request failed');continue}
        $target=[string](Get-EntraTopologyProperty $b.Request 'Target')
        foreach($o in @($b.Items)){$r.Relations += [pscustomobject]@{FromId=[string]$o.id;ToId=$target;Relationship='registeredOwnerOf';Qualifier='';State=@{};EvidenceRefs=@([pscustomobject]@{Capability='DeviceRegisteredOwners';Endpoint=[string]$b.SourceEndpoint})}}
    }
    if($failed){Set-EntraTopologyCollectorCapability -Result $r -Name 'DeviceRegisteredOwners' -Status 'Partial' -RequiredPermissions $r.RequiredPermissions | Out-Null}
    $r.Metrics=@{Count=$g.Items.Count;RelationCount=$r.Relations.Count}; $r
}
