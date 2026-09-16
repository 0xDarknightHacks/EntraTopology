# EntraTopology Monitoring

Optional scheduled monitoring/notification layer over the canonical EntraTopology collection and semantic comparison pipeline.

## Files

- `Initialize-EntraTopologyMonitor.ps1` prepares monitor configuration and state paths.
- `New-EntraTopologyMonitorCertificate.ps1` creates the local machine certificate used for app-only authentication.
- `Register-EntraTopologyMonitorTask.ps1` registers a no-profile PowerShell scheduled task running as `SYSTEM`.
- `Invoke-EntraTopologyMonitor.ps1` performs collection, comparison, alert selection, notification, and baseline promotion.
- `Private/Notification.Common.ps1` contains the HTML notification presentation and send-mail helper.
- `monitor-config.example.json` is a tenant-neutral starting configuration.

## Quick Start

Install the Graph authentication module machine-wide from an elevated PowerShell 7 session:

```powershell
Install-Module Microsoft.Graph.Authentication -MinimumVersion 2.33.0 -Scope AllUsers
```

Create and upload the public certificate to the monitoring app registration, grant the required Microsoft Graph application read permissions, then create `C:\ProgramData\EntraTopologyMonitor\monitor-config.json` from `monitor-config.example.json`.

Register the scheduled task:

```powershell
.\Register-EntraTopologyMonitorTask.ps1 -EveryMinutes 120
```

For manual testing, use a fresh no-profile PowerShell process:

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\Invoke-EntraTopologyMonitor.ps1 -ConfigPath C:\ProgramData\EntraTopologyMonitor\monitor-config.json
```

## Optional Email Notification

Notifications use Microsoft Graph `sendMail` from a dedicated notification mailbox. For production, prefer Exchange Online Application RBAC with the `Application Mail.Send` role scoped only to that mailbox.

When using scoped Exchange Application RBAC, avoid also granting broad Microsoft Entra `Mail.Send` application permission to the same app, because those grants are additive. If scoped RBAC is not configured, Graph mail sending requires the appropriate application mail permission and admin consent.

## Safety Model

The monitor uses app-only read access for EntraTopology collection. Baselines are promoted only after a healthy run, schema compatibility is checked before comparison, and collection-policy changes or missing policy provenance are rejected until the baseline is deliberately reinitialized.

Generated baselines, deltas, alerts, logs, reports, and local configuration contain tenant metadata and must not be committed.
