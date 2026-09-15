# Changelog

All notable changes to EntraTopology are documented in this file.

## [1.0.1] - 2026-09-15

Correctness patch for Microsoft Graph group relationship coverage.

### Fixed

- Recover direct service-principal group memberships through the supported v1.0 `servicePrincipals/{id}/memberOf` relationship because `groups/{id}/members` can omit service principals.
- Recover service-principal group ownership through the supported v1.0 `servicePrincipals/{id}/ownedObjects` relationship because `groups/{id}/owners` can omit service principals.
- Mark group membership coverage partial when delegated hidden-membership visibility cannot be proven without `Member.Read.Hidden`.
- Mark group ownership coverage partial for synchronized and mail-enabled non-Microsoft-365 group types where Microsoft Graph does not guarantee owner availability.
- Keep `ownerlessObject` generation fail-closed whenever group-owner coverage is partial.

### Added

- Add `Invoke-EntraTopologyTestData.ps1` for manifest-driven synthetic topology validation in dedicated development tenants.

## [1.0.0] - 2026-09-15

First stable public release.

### Added

- Read-only Microsoft Entra tenant inventory collection.
- Portable tenant snapshot and offline topology-processing boundary.
- Canonical topology for users, groups, applications, service principals, devices and directory roles.
- Group membership and ownership relationships.
- Application/service-principal ownership and app-registration instantiation relationships.
- Device registered-owner relationships.
- Active directory-role assignment topology.
- Application secrets and certificate metadata represented as credential topology.
- Requested API permission relationships.
- Granted application permission/app-role assignment relationships.
- Delegated OAuth consent relationships.
- Typed unresolved directory-object and role-definition resolution.
- Microsoft first-party, tenant-owned, external and managed-identity service-principal classification.
- Optional Microsoft first-party enterprise-application exclusion while retaining referenced API-resource nodes.
- Optional sign-in activity and risky-user enrichment.
- Coverage-aware security and operational signals.
- Privileged identity/ownership and high-impact role/permission context.
- Credential expiry context with 30/60/90-day horizons.
- Deterministic recommendations linked to supported signals.
- Evidence/provenance references for topology relationships and observations.
- Local node/path query primitives.
- Semantic topology comparison.
- JSON, GraphML and OpenGraph-shaped exports.
- Runtime telemetry, diagnostics and batching-efficiency metrics.
- Self-contained offline HTML topology explorer.
- Object/relationship composition summaries and semantic relationship-flow visualization.
- Deterministic administrator Quick Answers.
- Interactive topology zoom, pan, fit, filtering, inspection and Entra portal navigation.
- Grouped security-context/recommendation presentation with affected-object drill-down.
- Release-hygiene validation.
- Pester regression test suite.

### Security

- Read-only Microsoft Graph operating model.
- Explicit fail-closed collection/capability coverage.
- Offline post-snapshot processing boundary.
- Tenant runtime artifacts excluded from public release packages.
- Secrets kept outside snapshots, graphs, reports and normal configuration files.
