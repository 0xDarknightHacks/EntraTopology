function Invoke-EntraTopology {
    [CmdletBinding()]
    param(
        [string]$OutputDirectory=(Join-Path (Get-Location) 'entra-topology-output'),
        [switch]$IncludeSignals,
        [switch]$GenerateReport,
        [switch]$NoSignals,
        [switch]$NoReport,
        [string]$ReportPath,
        [ValidateRange(1,20)][int]$BatchSize=20,
        [switch]$ExcludeMicrosoftFirstPartyApps,

        [switch]$SkipConnect,
        [switch]$NoDisconnect,
        [switch]$NoBanner,
        [switch]$NoProgress,
        [switch]$OpenReport,
        [switch]$PassThru,

        [string]$ConfigPath=(Get-EntraTopologyDefaultConfigPath),
        [string]$VaultName='EntraTopologyVault',
        [string]$SecretName='EntraTopologyGraphClientSecret'
    )

    $includeSignalsEffective = if($PSBoundParameters.ContainsKey('IncludeSignals')){$IncludeSignals.IsPresent}else{-not $NoSignals}
    if($NoSignals){$includeSignalsEffective=$false}
    $generateReportEffective = if($PSBoundParameters.ContainsKey('GenerateReport')){$GenerateReport.IsPresent}else{-not $NoReport}
    if($NoReport){$generateReportEffective=$false}

    New-Item -ItemType Directory -Force -Path $OutputDirectory|Out-Null
    $snapshotPath=Join-Path $OutputDirectory 'tenant-snapshot.json'
    $graphPath=Join-Path $OutputDirectory 'tenant-topology.json'
    $diagnosticsPath=Join-Path $OutputDirectory 'run-diagnostics.jsonl'
    $resolvedReportPath=if($ReportPath){$ReportPath}else{Join-Path $OutputDirectory 'tenant-topology.html'}

    $telemetry=New-EntraTopologyTelemetry
    $diagnostics=New-EntraTopologyDiagnostics
    $ownsConnection=$false
    $graph=$null
    $snapshot=$null
    $result=$null
    $stage='Initialize'
    $totalStages=5

    if(-not $NoBanner){Write-EntraTopologyBanner}
    Reset-EntraTopologyGraphTransportCallCount

    try {
        $stage='Authentication'
        Write-EntraTopologyStage -Step 1 -Total $totalStages -Message 'Authenticating to Microsoft Graph' -NoProgress:$NoProgress
        Start-EntraTopologyTelemetryStage -Telemetry $telemetry -Name $stage|Out-Null
        Add-EntraTopologyDiagnosticEvent -Diagnostics $diagnostics -Stage $stage -Event 'AuthenticationStarted' -Message 'Preparing Microsoft Graph connection.'|Out-Null

        $existing=Get-EntraTopologyGraphContext
        if($SkipConnect){
            $ctx=Assert-EntraTopologyGraphConnected
            Write-Verbose 'Using caller-owned Microsoft Graph connection because -SkipConnect was specified.'
            Add-EntraTopologyDiagnosticEvent -Diagnostics $diagnostics -Stage $stage -Event 'AuthenticationSkipped' -Message 'Caller-owned Microsoft Graph session is in use.'|Out-Null
        } elseif($null -ne $existing){
            $ctx=$existing
            Write-Verbose 'Reusing an existing Microsoft Graph connection; Invoke-EntraTopology will not disconnect it.'
            Add-EntraTopologyDiagnosticEvent -Diagnostics $diagnostics -Stage $stage -Event 'AuthenticationReused' -Message 'Existing Microsoft Graph session reused.'|Out-Null
        } else {
            $connection=Connect-EntraTopologyGraph -UseStoredAppCredentials -ConfigPath $ConfigPath -VaultName $VaultName -SecretName $SecretName -NoWelcome
            $ownsConnection=$true
            $ctx=Assert-EntraTopologyGraphConnected
            Write-Verbose "Connected to Microsoft Graph using stored app credentials for tenant $($connection.TenantId)."
            Add-EntraTopologyDiagnosticEvent -Diagnostics $diagnostics -Stage $stage -Event 'AuthenticationCompleted' -Message 'Microsoft Graph app-only connection established.' -Data @{AuthType=[string]$connection.AuthType}|Out-Null
        }
        Stop-EntraTopologyTelemetryStage -Telemetry $telemetry -Name $stage -Status Success|Out-Null

        $stage='Collection'
        Write-EntraTopologyStage -Step 2 -Total $totalStages -Message 'Collecting Entra inventory and relationships' -NoProgress:$NoProgress
        Start-EntraTopologyTelemetryStage -Telemetry $telemetry -Name $stage|Out-Null
        Add-EntraTopologyDiagnosticEvent -Diagnostics $diagnostics -Stage $stage -Event 'CollectionStarted' -Message 'Tenant collection started.'|Out-Null
        $snapshot=New-EntraTopologySnapshot -Path $snapshotPath -BatchSize $BatchSize -ExcludeMicrosoftFirstPartyApps:$ExcludeMicrosoftFirstPartyApps -Telemetry $telemetry
        Stop-EntraTopologyTelemetryStage -Telemetry $telemetry -Name $stage -Status Success|Out-Null
        Add-EntraTopologyDiagnosticEvent -Diagnostics $diagnostics -Stage $stage -Event 'CollectionCompleted' -Message "Collected $(@($snapshot.Collectors).Count) collector result(s)."|Out-Null
        Write-Verbose "Collection completed with $(@($snapshot.Collectors).Count) collector result(s); snapshot written to $snapshotPath."

        $stage='Topology'
        Write-EntraTopologyStage -Step 3 -Total $totalStages -Message 'Building offline topology and security context' -NoProgress:$NoProgress
        Start-EntraTopologyTelemetryStage -Telemetry $telemetry -Name $stage|Out-Null
        $graph=New-EntraTopologyGraph -Snapshot $snapshot -IncludeSignals:$includeSignalsEffective
        Stop-EntraTopologyTelemetryStage -Telemetry $telemetry -Name $stage -Status Success|Out-Null
        Add-EntraTopologyDiagnosticEvent -Diagnostics $diagnostics -Stage $stage -Event 'TopologyCompleted' -Message "Built $(@($graph.Nodes).Count) nodes, $(@($graph.Edges).Count) relationships, and $(@($graph.Signals).Count) security-context signal(s)."|Out-Null
        Write-Verbose "Topology contains $(@($graph.Nodes).Count) nodes, $(@($graph.Edges).Count) relationships, $(@($graph.Signals).Count) signals, and $(@($graph.Recommendations).Count) recommendations."

        $authContext=Get-EntraTopologyGraphContext
        $graph.Metadata.RuntimeTelemetry=$telemetry
        $graph.Metadata.Diagnostics=@($diagnostics)
        $graph.Metadata.Execution=[ordered]@{
            AuthType=[string](Get-EntraTopologyProperty $authContext 'AuthType')
            ConnectionOwnedByInvoke=$ownsConnection
            BatchSize=$BatchSize
            IncludeSignals=$includeSignalsEffective
            GenerateReport=$generateReportEffective
            ExcludeMicrosoftFirstPartyApps=[bool]$ExcludeMicrosoftFirstPartyApps
        }
        $graph.Metadata.DiagnosticsPath=$diagnosticsPath

        $stage='Artifacts'
        Write-EntraTopologyStage -Step 4 -Total $totalStages -Message 'Writing structured artifacts' -NoProgress:$NoProgress
        Start-EntraTopologyTelemetryStage -Telemetry $telemetry -Name $stage|Out-Null
        Save-EntraTopologyJson -InputObject $graph -Path $graphPath|Out-Null
        Stop-EntraTopologyTelemetryStage -Telemetry $telemetry -Name $stage -Status Success|Out-Null
        Add-EntraTopologyDiagnosticEvent -Diagnostics $diagnostics -Stage $stage -Event 'GraphWritten' -Message 'Canonical topology JSON written.'|Out-Null

        if($generateReportEffective){
            $stage='Report'
            Write-EntraTopologyStage -Step 5 -Total $totalStages -Message 'Generating offline HTML report' -NoProgress:$NoProgress
            Start-EntraTopologyTelemetryStage -Telemetry $telemetry -Name $stage|Out-Null
            New-EntraTopologyReport -Graph $graph -Path $resolvedReportPath|Out-Null
            Stop-EntraTopologyTelemetryStage -Telemetry $telemetry -Name $stage -Status Success|Out-Null
            Add-EntraTopologyDiagnosticEvent -Diagnostics $diagnostics -Stage $stage -Event 'ReportCompleted' -Message 'Offline HTML report generated.'|Out-Null
            Write-Verbose "HTML report written to $resolvedReportPath."
        } else {
            Write-EntraTopologyStage -Step 5 -Total $totalStages -Message 'Report generation skipped' -NoProgress:$NoProgress
            Start-EntraTopologyTelemetryStage -Telemetry $telemetry -Name 'Report'|Out-Null
            Stop-EntraTopologyTelemetryStage -Telemetry $telemetry -Name 'Report' -Status Skipped -Message 'Report generation disabled.'|Out-Null
            $resolvedReportPath=$null
        }

        Complete-EntraTopologyTelemetry -Telemetry $telemetry|Out-Null
        $artifactMeta=[ordered]@{
            SnapshotPath=$snapshotPath
            SnapshotBytes=$(if(Test-Path -LiteralPath $snapshotPath){(Get-Item -LiteralPath $snapshotPath).Length}else{0})
            GraphPath=$graphPath
            GraphBytes=$(if(Test-Path -LiteralPath $graphPath){(Get-Item -LiteralPath $graphPath).Length}else{0})
            ReportPath=$resolvedReportPath
            ReportBytes=$(if($resolvedReportPath -and (Test-Path -LiteralPath $resolvedReportPath)){(Get-Item -LiteralPath $resolvedReportPath).Length}else{0})
            DiagnosticsPath=$diagnosticsPath
        }
        $graph.Metadata.RuntimeTelemetry=$telemetry
        $graph.Metadata.Diagnostics=@($diagnostics)
        $graph.Metadata.Artifacts=$artifactMeta
        Save-EntraTopologyDiagnostics -Diagnostics $diagnostics -Path $diagnosticsPath|Out-Null
        Save-EntraTopologyJson -InputObject $graph -Path $graphPath|Out-Null
        if($generateReportEffective){New-EntraTopologyReport -Graph $graph -Path $resolvedReportPath|Out-Null}

        $result=[pscustomobject][ordered]@{
            SnapshotPath=$snapshotPath
            GraphPath=$graphPath
            ReportPath=$resolvedReportPath
            DiagnosticsPath=$diagnosticsPath
            OutputDirectory=(Resolve-Path -LiteralPath $OutputDirectory).Path
            TenantId=$graph.TenantId
            NodeCount=@($graph.Nodes).Count
            EdgeCount=@($graph.Edges).Count
            SignalCount=@($graph.Signals).Count
            RecommendationCount=@($graph.Recommendations).Count
            UnresolvedObjectCount=[int](Get-EntraTopologyProperty $graph.Metadata 'UnresolvedObjectCount')
            UnresolvedDirectoryObjectCount=[int](Get-EntraTopologyProperty $graph.Metadata 'UnresolvedDirectoryObjectCount')
            UnresolvedDirectoryRoleCount=[int](Get-EntraTopologyProperty $graph.Metadata 'UnresolvedDirectoryRoleCount')
            ResolvedAppRoleAssignmentCount=[int](Get-EntraTopologyProperty $graph.Metadata 'ResolvedAppRoleAssignmentCount')
            UnresolvedAppRoleAssignmentCount=[int](Get-EntraTopologyProperty $graph.Metadata 'UnresolvedAppRoleAssignmentCount')
            CredentialCount=[int](Get-EntraTopologyProperty $graph.Metadata 'CredentialCount')
            RequestedApiPermissionCount=[int](Get-EntraTopologyProperty $graph.Metadata 'RequestedApiPermissionCount')
            DelegatedPermissionGrantCount=[int](Get-EntraTopologyProperty $graph.Metadata 'DelegatedPermissionGrantCount')
            ExcludedMicrosoftFirstPartyApps=[bool]$ExcludeMicrosoftFirstPartyApps
            GraphLogicalRequests=[long]$telemetry.GraphLogicalRequests
            GraphHttpRequests=[long]$telemetry.GraphHttpRequests
            BatchingEfficiency=[double]$telemetry.BatchingEfficiency
            Retries=[long]$telemetry.Retries
            Throttles=[long]$telemetry.Throttles
            DurationMs=[long]$telemetry.DurationMs
            GraphCallsAfterSnapshot=[long](Get-EntraTopologyProperty $graph.Metadata 'GraphCallsAfterSnapshot')
            Coverage=$graph.Coverage
            Graph=$(if($PassThru){$graph}else{$null})
        }

        if(-not $NoProgress){Write-Progress -Activity 'EntraTopology' -Completed}
        Write-EntraTopologyCompletion -Result $result
        if($OpenReport -and $resolvedReportPath -and (Test-Path -LiteralPath $resolvedReportPath)){
            try{Start-Process -FilePath $resolvedReportPath|Out-Null}catch{Write-Warning "Report generated but could not be opened automatically: $($_.Exception.Message)"}
        }
        $result
    } catch {
        try{
            Add-EntraTopologyDiagnosticEvent -Diagnostics $diagnostics -Stage $stage -Event 'RunFailed' -Level Error -Message $_.Exception.Message|Out-Null
            if($telemetry.Stages.Contains($stage) -and $telemetry.Stages[$stage].Status -eq 'Running'){Stop-EntraTopologyTelemetryStage -Telemetry $telemetry -Name $stage -Status Failed -Message $_.Exception.Message|Out-Null}
            Complete-EntraTopologyTelemetry -Telemetry $telemetry|Out-Null
            Save-EntraTopologyDiagnostics -Diagnostics $diagnostics -Path $diagnosticsPath|Out-Null
        } catch {}
        throw
    } finally {
        if($ownsConnection -and -not $NoDisconnect){
            try{
                Write-Verbose 'Disconnecting Microsoft Graph session created by Invoke-EntraTopology.'
                Disconnect-MgGraph -ErrorAction Stop|Out-Null
            } catch { Write-Verbose "Microsoft Graph disconnect returned: $($_.Exception.Message)" }
        }
        if(-not $NoProgress){Write-Progress -Activity 'EntraTopology' -Completed}
    }
}
