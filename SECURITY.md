# Security Policy

## Supported versions

Security fixes are provided for the latest released version of EntraTopology.

| Version | Supported |
|---|---|
| 1.x | Yes |
| < 1.0 | No |

## Reporting a vulnerability

Please do **not** disclose suspected vulnerabilities through a public GitHub issue.

Use GitHub private vulnerability reporting for this repository when available. Include enough information to reproduce and assess the issue:

- affected EntraTopology version;
- affected component or command;
- reproduction steps;
- expected and observed behavior;
- potential security impact;
- a minimal sanitized proof of concept when useful.

Do not include real tenant data, access tokens, client secrets, private keys, certificates containing private keys, customer identifiers, or other credentials.

## Security model

EntraTopology is designed as a read-only Microsoft Entra inventory and topology engine.

The project:

- uses Microsoft Graph read permissions for normal operation;
- supports app-only authentication;
- keeps Microsoft Graph collection separate from downstream topology processing;
- builds topology, signals, recommendations, queries, comparison and reports from collected state;
- treats missing/failed collection coverage explicitly rather than silently assuming absence;
- produces local artifacts that may contain sensitive tenant metadata.

Generated snapshots, topology files, reports, diagnostics, monitoring baselines, deltas, alerts, logs and tenant-specific monitor configuration should therefore be handled as sensitive administrative data and must not be committed to source control or published with releases. The optional monitor stores these artifacts under `C:\ProgramData\EntraTopologyMonitor` and its initializer restricts that directory to `SYSTEM` and local Administrators.

## Credentials and local configuration

Never commit:

- client secrets;
- access or refresh tokens;
- certificates containing private keys;
- SecretStore/SecretManagement vault contents;
- tenant-specific authentication configuration that should remain private;
- tenant snapshots, topology exports, reports or diagnostics.
- monitoring baselines, deltas, alerts, logs, or tenant-specific `monitor-config.json`.

Use PowerShell SecretManagement/SecretStore or another appropriate secret-management solution for secrets.

## Permission model

New Microsoft Graph permissions should follow least privilege. Optional enrichment must remain optional when it is not required for the core topology.

Write permissions are outside the normal EntraTopology operating model. A change that introduces a Graph write operation requires explicit architectural and security review.

## Tenant-data handling

Synthetic fixtures should be used for public tests and examples. Before publishing a release, run:

```powershell
.\Scripts\Test-EntraTopologyRelease.ps1
```

This gate is intended to catch known tenant-derived runtime artifacts and local configuration that should not be included in a public repository/package.

## Third-party vulnerabilities

Security issues in Microsoft Graph, Microsoft Entra ID, PowerShell, Microsoft Graph PowerShell, SecretManagement or other third-party dependencies should also be reported to the relevant vendor or maintainer when the issue is not caused by EntraTopology itself.
