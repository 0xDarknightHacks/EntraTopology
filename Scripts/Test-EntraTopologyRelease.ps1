[CmdletBinding()]
param([string]$RepositoryPath=(Split-Path -Parent $PSScriptRoot))

$root=(Resolve-Path -LiteralPath $RepositoryPath).Path
$forbidden=@(
    'entra-topology-output',
    '.entra-topology'
)
$violations=[System.Collections.Generic.List[string]]::new()
foreach($relative in $forbidden){
    $candidate=Join-Path $root $relative
    if(Test-Path -LiteralPath $candidate){$violations.Add($candidate)}
}
$patterns=@('*tenant-snapshot*.json','*tenant-topology*.json','*tenant-topology*.html','run-diagnostics.jsonl')
foreach($pattern in $patterns){
    foreach($item in @(Get-ChildItem -LiteralPath $root -Recurse -File -Filter $pattern -ErrorAction SilentlyContinue)){
        if($item.FullName -notmatch '[\\/]Tests[\\/]'){$violations.Add($item.FullName)}
    }
}
if($violations.Count -gt 0){
    throw "Release hygiene check failed. Remove tenant/runtime artifacts before packaging:`n$($violations|Sort-Object -Unique|ForEach-Object{' - '+$_}|Out-String)"
}
Write-Host 'EntraTopology release hygiene check passed.' -ForegroundColor Green
