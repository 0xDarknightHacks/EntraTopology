# EntraTopology Architecture

## Design goal

EntraTopology is a read-only Microsoft Entra tenant topology engine. Its core artifact is a deterministic graph that answers three questions:

1. What directory and application objects exist?
2. How are those objects related?
3. What security or operational context is supported by the collected evidence?

The architecture deliberately separates **live collection** from **offline interpretation**.

## Processing pipeline

```text
Authenticate
    ↓
Collect Microsoft Graph facts
    ↓
Create portable snapshot + evidence/coverage
    ↓
Normalize and correlate
    ↓
Build canonical nodes and edges
    ↓
Attach signals and recommendations
    ↓
Query / compare / export / report offline
```

## Layers

### 1. Graph transport

Owns Microsoft Graph request behavior, including authentication context, paging, batching, retry/throttling handling and request diagnostics.

Raw Graph request behavior should not leak into downstream topology/reporting modules.

### 2. Collectors

Collectors retrieve read-only source facts for supported object and relationship types. Each capability reports explicit coverage so consumers can distinguish:

- `Complete` — the capability was successfully observed;
- `Partial` — some relevant data could not be collected;
- `NotRun` — the capability was intentionally or permission-gated out;
- `Unavailable` — the capability could not be obtained.

Missing visibility must never be silently converted to "none exist".

### 3. Snapshot

The snapshot is the portable boundary between live Microsoft Graph collection and downstream processing. It contains collected source state plus the coverage/evidence needed to interpret that state.

Once the snapshot is complete, topology construction and presentation must not require additional Graph requests.

### 4. Normalization and correlation

Normalization converts source-specific objects and relationships into the canonical topology model. It resolves relationship endpoints, creates reference-only nodes where required to preserve understandable relationships, and attaches stable identity/provenance fields.

### 5. Canonical topology

The graph contains canonical nodes, edges, evidence, coverage, signals, recommendations and run/reporting metadata.

A node key is stable for `(tenantId, objectId)`.

An edge key is stable for `(tenantId, from, relationship, to, qualifier)` and deliberately excludes mutable state. Mutable assignment/scope/timestamp information belongs in edge state/properties rather than identity.

Relationship edges retain `EvidenceKeys` references to the evidence that established them.

The graph schema is versioned independently from the PowerShell module version.

### 6. Signals

Signals are deterministic annotations on objects or relationships. They describe observed security/operational context; they are not source-of-truth inventory, compliance controls, attack paths or numerical risk scores.

Absence-derived signals are emitted only when the exact supporting collection capability is complete.

### 7. Recommendations

Recommendations are deterministic remediation guidance derived from supported signals. They remain linked to the originating signal/target and do not create a second assessment engine.

### 8. Query

Query primitives operate on the canonical graph locally. They support object inspection and path/adjacency exploration without Microsoft Graph.

### 9. Comparison

Comparison operates on semantic graph identity/state. Evidence/provenance observation churn is excluded where it does not represent a meaningful topology change.

### 10. Export and presentation

The export layer supports structured graph formats. The reporting layer generates a self-contained offline HTML explorer with composition summaries, relationship flow, Quick Answers, interactive topology, grouped security context, evidence, coverage and runtime diagnostics.

The report must not introduce runtime CDN or Graph dependencies.

## Supported topology domains in v1.0

The v1.0 model includes:

- users;
- groups;
- applications/app registrations;
- service principals/enterprise applications;
- devices;
- directory roles;
- application credentials;
- reference-only API-resource service principals;
- membership and ownership;
- app registration ↔ service-principal instantiation;
- requested API permissions;
- granted app-role/application permissions;
- delegated OAuth consent;
- registered device ownership;
- active directory-role assignment.

Optional enrichment includes sign-in activity and risky-user context when the necessary permission/licensing is available.

## Security boundaries

### Read-only operation

Normal EntraTopology operation uses Microsoft Graph read permissions. Graph write operations are outside the product's intended runtime model.

The root `Invoke-EntraTopologyTestData.ps1` helper is a lab-only exception for seeding and removing deterministic synthetic validation data in dedicated development tenants. It is not part of the normal collection, topology, reporting or export pipeline, and cleanup remains manifest-driven.

### Coverage-aware interpretation

A failed or permission-gated read must propagate as explicit coverage. This prevents downstream signals from treating missing data as proof of absence.

### Offline boundary

Normalization, signals, recommendations, query, comparison, export and reporting consume collected state. This preserves reproducibility and allows a collected graph/snapshot to be inspected without live tenant access.

### Tenant artifacts

Snapshots, topology exports, HTML reports and diagnostics can contain sensitive tenant metadata. They are runtime artifacts, not source files, and must not be committed or included in public release archives.

## Extension principles

Future capabilities should be added only when they strengthen tenant topology or supported context. New collectors should:

1. justify any additional Microsoft Graph permission;
2. preserve read-only operation;
3. expose explicit coverage;
4. emit source facts/evidence before derived interpretation;
5. preserve offline downstream processing;
6. add focused regression tests;
7. update the graph schema only when the canonical contract actually changes.
