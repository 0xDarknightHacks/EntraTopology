function Get-EntraTopologyObjectFingerprint {
    [CmdletBinding()] param([Parameter(Mandatory)][object]$InputObject)
    Get-EntraTopologyStableId ($InputObject | ConvertTo-Json -Compress -Depth 20)
}
function Save-EntraTopologyJson {
    [CmdletBinding()] param([Parameter(Mandatory)][object]$InputObject,[Parameter(Mandatory)][string]$Path)
    $parent=Split-Path -Parent $Path;if($parent){New-Item -ItemType Directory -Force -Path $parent|Out-Null};$InputObject|ConvertTo-Json -Depth 30|Set-Content -LiteralPath $Path -Encoding utf8;Get-Item -LiteralPath $Path
}
function Read-EntraTopologyJson {
    [CmdletBinding()] param([Parameter(Mandatory)][string]$Path)
    if(-not(Test-Path -LiteralPath $Path)){throw "File not found: $Path"};Get-Content -LiteralPath $Path -Raw|ConvertFrom-Json -Depth 40
}
