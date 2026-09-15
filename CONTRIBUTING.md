# Contributing to EntraTopology

Thank you for your interest in contributing.

EntraTopology is intentionally focused on **read-only Microsoft Entra inventory, relationship topology, security context and offline exploration**. Contributions should preserve that scope and the deterministic graph contract.

## Development requirements

- PowerShell 7.2+
- `Microsoft.Graph.Authentication` 2.0.0+
- Pester 5+
- access to an appropriate test Microsoft Entra tenant for changes that affect live collectors

Optional authentication workflows may also use PowerShell SecretManagement and SecretStore.

## Architectural boundaries

Please preserve these boundaries:

1. Raw Microsoft Graph access belongs in the Graph transport/collection layer.
2. Snapshots form the collection boundary; normalization, topology construction, signals, recommendations, query, comparison and reporting must be able to operate offline.
3. No downstream feature should silently introduce post-snapshot Graph calls.
4. Collection coverage is fail-closed: missing permissions and failed reads must not be represented as successful empty collections.
5. Security observations must be deterministic, evidence-backed where applicable, and scoped to what the collected data can support.
6. Normal operation remains read-only.
7. Tenant-specific runtime data must never be committed.

## Testing

Run the full suite before submitting a change:

```powershell
Invoke-Pester -Path .\Tests -Output Detailed
```

Before preparing a public release, also run:

```powershell
.\Scripts\Test-EntraTopologyRelease.ps1
```

Both should complete successfully.

Collector changes should include tests for successful collection and relevant failure/coverage behavior. Reporting changes should preserve the self-contained offline report and include focused regression tests for the changed contract or interaction.

## Pull requests

Keep pull requests focused. Include:

- the purpose of the change;
- affected components;
- new Microsoft Graph permissions, if any, and why they are necessary;
- tests added or updated;
- impact on canonical graph/schema compatibility;
- screenshots for material reporting/UI changes when useful.

Avoid combining unrelated refactoring with functional changes.

## Microsoft Graph permissions

New permissions require explicit justification. Prefer the least-privileged application permission that supports the collector.

Do not increase the baseline permission set merely to support optional enrichment. Optional capabilities should degrade to explicit coverage states when their permissions or licensing are unavailable.

## Canonical graph contract

Changes to canonical nodes, edges, evidence, signals, recommendations, coverage or metadata must consider compatibility with existing graph consumers.

The module version and graph schema version are independent. Do not increment `SchemaVersion` for implementation-only or documentation changes.

Stable node and edge identity semantics should not be changed without a deliberate schema migration.

## Signals and recommendations

Signals describe observed security or operational context; they are not compliance controls or risk scores.

Recommendations should be deterministic remediation guidance attached to supported signals. Avoid claims such as **over-privileged** unless an explicit expected-access/business-need baseline makes that conclusion defensible.

## Reporting

The HTML report must remain:

- fully offline after graph generation;
- self-contained and free of runtime CDN dependencies;
- safe when rendering tenant-controlled strings;
- topology-first rather than an exhaustive assessment dump;
- readable at common desktop sizes and usable at narrower widths;
- consistent with the existing object/relationship visual taxonomy.

## Sensitive data

Never submit real:

- tenant snapshots;
- topology exports;
- HTML reports or diagnostics;
- tenant/customer identifiers;
- client IDs when they identify a private environment;
- UPNs or other tenant identities;
- secrets, tokens or private keys.

Use synthetic fixtures and sanitized examples.

## Coding style

Follow the existing repository structure and PowerShell style. Prefer small deterministic functions, explicit contracts and focused error handling over unnecessary abstraction.

## Security issues

Do not disclose suspected vulnerabilities in public issues or pull requests. Follow [SECURITY.md](SECURITY.md).
