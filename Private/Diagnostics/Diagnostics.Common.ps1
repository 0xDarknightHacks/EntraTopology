function New-EntraTopologyDiagnostics {
    [CmdletBinding()] param()
    ,[System.Collections.Generic.List[object]]::new()
}

function Add-EntraTopologyDiagnosticEvent {
    [CmdletBinding()] param(
        [Parameter(Mandatory)][System.Collections.IList]$Diagnostics,
        [Parameter(Mandatory)][string]$Stage,
        [Parameter(Mandatory)][string]$Event,
        [ValidateSet('Info','Warning','Error')][string]$Level='Info',
        [Parameter(Mandatory)][string]$Message,
        [AllowNull()][hashtable]$Data
    )
    $record=[pscustomobject][ordered]@{
        TimestampUtc=[datetime]::UtcNow.ToString('o')
        Stage=$Stage
        Event=$Event
        Level=$Level
        Message=$Message
        Data=$(if($Data){$Data}else{@{}})
    }
    [void]$Diagnostics.Add($record)
    $record
}

function Save-EntraTopologyDiagnostics {
    [CmdletBinding()] param(
        [Parameter(Mandatory)][System.Collections.IEnumerable]$Diagnostics,
        [Parameter(Mandatory)][string]$Path
    )
    $parent=Split-Path -Parent $Path
    if($parent){New-Item -ItemType Directory -Force -Path $parent|Out-Null}
    $lines=@($Diagnostics|ForEach-Object{$_|ConvertTo-Json -Depth 20 -Compress})
    Set-Content -LiteralPath $Path -Value $lines -Encoding utf8
    Get-Item -LiteralPath $Path
}
