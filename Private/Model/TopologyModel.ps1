function Get-EntraTopologyStableId {
    [CmdletBinding()] param([Parameter(Mandatory)][string]$InputString)
    $sha=[System.Security.Cryptography.SHA256]::Create(); try{$bytes=[Text.Encoding]::UTF8.GetBytes($InputString);$hash=$sha.ComputeHash($bytes);([BitConverter]::ToString($hash)-replace'-','').ToLowerInvariant().Substring(0,24)}finally{$sha.Dispose()}
}
function New-EntraTopologyNode {
    [CmdletBinding()] param([Parameter(Mandatory)][string]$TenantId,[Parameter(Mandatory)][string]$ObjectId,[Parameter(Mandatory)][string]$Kind,[string]$DisplayName,[hashtable]$Properties=@{},[string[]]$EvidenceKeys=@())
    [pscustomobject][ordered]@{SchemaVersion='1.1.0';Key="tenant:${TenantId}:object:${ObjectId}";Id=$ObjectId;TenantId=$TenantId;Kind=$Kind;DisplayName=$DisplayName;Properties=$Properties;EvidenceKeys=@($EvidenceKeys)}
}
function New-EntraTopologyEdge {
    [CmdletBinding()] param([Parameter(Mandatory)][string]$TenantId,[Parameter(Mandatory)][string]$From,[Parameter(Mandatory)][string]$To,[Parameter(Mandatory)][string]$Relationship,[string]$Qualifier='',[hashtable]$State=@{},[string[]]$EvidenceKeys=@())
    # Identity intentionally excludes mutable state: state changes become temporal changes, not delete+add churn.
    $id=Get-EntraTopologyStableId "$TenantId|$From|$Relationship|$To|$Qualifier"
    [pscustomobject][ordered]@{SchemaVersion='1.1.0';Key="edge:$id";Id=$id;TenantId=$TenantId;From=$From;To=$To;Relationship=$Relationship;Qualifier=$Qualifier;State=$State;EvidenceKeys=@($EvidenceKeys)}
}
function New-EntraTopologyEvidence {
    [CmdletBinding()] param([Parameter(Mandatory)][string]$TenantId,[Parameter(Mandatory)][string]$Collector,[Parameter(Mandatory)][string]$Endpoint,[Parameter(Mandatory)][string]$SourceObjectId,[hashtable]$Fields=@{},[ValidateSet('Complete','Partial','NotRun','Unavailable')][string]$Completeness='Complete')
    $id=Get-EntraTopologyStableId "$TenantId|$Collector|$Endpoint|$SourceObjectId"
    [pscustomobject][ordered]@{SchemaVersion='1.1.0';Key="evidence:$id";Id=$id;TenantId=$TenantId;Collector=$Collector;Endpoint=$Endpoint;SourceObjectId=$SourceObjectId;Completeness=$Completeness;Fields=$Fields;ObservedAtUtc=[datetime]::UtcNow.ToString('o')}
}
function New-EntraTopologySignal {
    [CmdletBinding()] param([Parameter(Mandatory)][string]$TenantId,[Parameter(Mandatory)][string]$TargetKey,[Parameter(Mandatory)][string]$Type,[ValidateSet('Info','Low','Medium','High','Critical')][string]$Severity='Info',[Parameter(Mandatory)][string]$Reason,[hashtable]$State=@{})
    $id=Get-EntraTopologyStableId "$TenantId|$TargetKey|$Type"
    [pscustomobject][ordered]@{SchemaVersion='1.1.0';Key="signal:$id";Id=$id;TenantId=$TenantId;TargetKey=$TargetKey;Type=$Type;Severity=$Severity;Reason=$Reason;State=$State}
}
