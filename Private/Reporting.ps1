function ConvertTo-EntraTopologyGraphML {
    [CmdletBinding()] param([Parameter(Mandatory)][object]$Graph)
    $enc=[System.Security.SecurityElement];$sb=[Text.StringBuilder]::new();[void]$sb.AppendLine('<?xml version="1.0" encoding="UTF-8"?>');[void]$sb.AppendLine('<graphml xmlns="http://graphml.graphdrawing.org/xmlns"><graph edgedefault="directed">')
    foreach($n in @($Graph.Nodes)){[void]$sb.AppendLine(('<node id="{0}"><data key="kind">{1}</data><data key="label">{2}</data></node>' -f $enc::Escape([string]$n.Key), $enc::Escape([string]$n.Kind), $enc::Escape([string]$n.DisplayName)))}
    foreach($e in @($Graph.Edges)){[void]$sb.AppendLine(('<edge id="{0}" source="{1}" target="{2}"><data key="relationship">{3}</data></edge>' -f $enc::Escape([string]$e.Key), $enc::Escape([string]$e.From), $enc::Escape([string]$e.To), $enc::Escape([string]$e.Relationship)))}
    [void]$sb.AppendLine('</graph></graphml>');$sb.ToString()
}


function ConvertTo-EntraTopologyReportHtml {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Graph,

        [string]$Title = 'EntraTopology Tenant Topology Report'
    )

    $json = $Graph | ConvertTo-Json -Depth 60 -Compress
    # Embedded JSON is data, not markup. Prevent tenant-controlled values from
    # terminating the application/json script element.
    $json = $json.Replace('&', '\u0026').Replace('<', '\u003c').Replace('>', '\u003e')

    $safeTitle = [System.Net.WebUtility]::HtmlEncode($Title)
    $generated = [System.Net.WebUtility]::HtmlEncode([datetime]::UtcNow.ToString('u'))

    $html = @'
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; img-src data:; connect-src 'none'; base-uri 'none'; form-action 'none'">
<title>__TITLE__</title>
<style>
:root {
  color-scheme: light;
  --font: "Segoe UI Variable Text","Segoe UI",system-ui,-apple-system,BlinkMacSystemFont,Arial,sans-serif;
  --radius: 8px;
  --radius-sm: 4px;
  --bg: #f5f5f5;
  --panel: #ffffff;
  --panel-soft: #fafafa;
  --panel-strong: #f0f0f0;
  --text: #242424;
  --muted: #616161;
  --faint: #707070;
  --line: #d1d1d1;
  --line-soft: #e0e0e0;
  --brand: #0f6cbd;
  --brand-hover: #115ea3;
  --brand-soft: #ebf3fc;
  --high: #c50f1f;
  --medium: #8a4b08;
  --low: #0f6cbd;
  --info: #0078d4;
  --success: #107c10;
  --high-bg: #fdf3f4;
  --medium-bg: #fff8f0;
  --low-bg: #f0f6fc;
  --info-bg: #f0f6fc;
  --success-bg: #f1faf1;
  --shadow: 0 1.6px 3.6px rgba(0,0,0,.132), 0 .3px .9px rgba(0,0,0,.108);
}
[data-theme="dark"] {
  color-scheme: dark;
  --bg: #1f1f1f;
  --panel: #292929;
  --panel-soft: #242424;
  --panel-strong: #333333;
  --text: #ffffff;
  --muted: #d6d6d6;
  --faint: #adadad;
  --line: #666666;
  --line-soft: #424242;
  --brand: #479ef5;
  --brand-hover: #62abf5;
  --brand-soft: #0e4775;
  --high: #ff99a4;
  --medium: #fce100;
  --low: #62abf5;
  --info: #62abf5;
  --success: #54b054;
  --high-bg: #442726;
  --medium-bg: #4a3d16;
  --low-bg: #0e4775;
  --info-bg: #0e4775;
  --success-bg: #163b16;
  --shadow: 0 2px 8px rgba(0,0,0,.45);
}
* { box-sizing: border-box; }
html { scroll-behavior: smooth; }
body {
  margin: 0;
  font-family: var(--font);
  font-size: 14px;
  line-height: 1.5;
  background: var(--bg);
  color: var(--text);
  -webkit-font-smoothing: antialiased;
}
button, input, select { font: inherit; }
button:focus-visible, input:focus-visible, select:focus-visible, summary:focus-visible {
  outline: 2px solid var(--brand);
  outline-offset: 2px;
}
.hero { background: var(--panel); border-bottom: 1px solid var(--line-soft); }
.hero-grid {
  max-width: 1180px;
  margin: 0 auto;
  padding: 20px 24px 18px;
  display: grid;
  grid-template-columns: minmax(0,1fr) auto;
  gap: 20px;
  align-items: start;
}
.brand-lockup { display:flex; align-items:center; gap:10px; }
.brand-accent { width:4px; height:28px; border-radius:2px; background:var(--brand); flex:0 0 auto; }
.brand { color:var(--muted); font-size:12px; font-weight:600; letter-spacing:.15px; }
.product-label { color:var(--text); font-size:13px; font-weight:600; }
h1 { margin:5px 0 6px; font-size:24px; line-height:1.25; font-weight:600; letter-spacing:-.2px; }
h2 { margin:0 0 12px; font-size:20px; line-height:1.3; font-weight:600; }
h3 { margin:0; font-size:15px; line-height:1.35; font-weight:600; }
.hero p { margin:6px 0 0; max-width:760px; color:var(--muted); }
.hero-meta { display:flex; flex-wrap:wrap; gap:6px; margin-top:12px; }
.toolbar { display:flex; flex-wrap:wrap; gap:6px; justify-content:end; }
button {
  min-height:32px;
  border:1px solid var(--line);
  background:var(--panel);
  color:var(--text);
  border-radius:var(--radius-sm);
  padding:5px 10px;
  font-size:12.5px;
  font-weight:600;
  cursor:pointer;
}
button:hover { border-color:var(--brand); color:var(--brand-hover); background:var(--brand-soft); }
.shell { max-width:1180px; margin:0 auto; padding:24px 24px 72px; }
.section { margin:0 0 30px; }
.section-header { display:flex; justify-content:space-between; gap:12px; align-items:baseline; margin-bottom:10px; }
.section-intro { margin:-4px 0 12px; color:var(--muted); max-width:850px; }
.muted { color:var(--muted); }
.pill {
  display:inline-flex;
  align-items:center;
  border-radius:999px;
  padding:3px 8px;
  font-size:11.5px;
  font-weight:600;
  border:1px solid var(--line);
  white-space:nowrap;
}
.status-success { background:var(--success-bg); color:var(--success); border-color:var(--success); }
.status-warning { background:var(--medium-bg); color:var(--medium); border-color:var(--medium); }
.status-danger { background:var(--high-bg); color:var(--high); border-color:var(--high); }
.status-info { background:var(--info-bg); color:var(--info); border-color:var(--info); }
.status-default { background:var(--panel-strong); color:var(--muted); }
.metric-grid { display:grid; grid-template-columns:repeat(auto-fit,minmax(150px,1fr)); gap:10px; margin:14px 0 0; }
.metric-card, .panel {
  background:var(--panel);
  border:1px solid var(--line-soft);
  border-radius:var(--radius);
  box-shadow:var(--shadow);
}
.metric-card { padding:12px 14px; border-top:3px solid var(--line-soft); }
.metric-card.brand { border-top-color:var(--brand); }
.metric-label { color:var(--muted); font-size:11.5px; font-weight:600; }
.metric-value { margin-top:2px; font-size:22px; font-weight:600; color:var(--text); }
.metric-hint { margin-top:4px; color:var(--faint); font-size:12px; }
.report-grid { display:grid; grid-template-columns:minmax(220px,.72fr) minmax(430px,1.6fr) minmax(260px,.9fr); gap:12px; }
.panel { overflow:hidden; min-width:0; }
.panel-header { padding:12px 14px; border-bottom:1px solid var(--line-soft); display:flex; justify-content:space-between; gap:10px; align-items:center; }
.panel-body { padding:14px; }
.filters { display:grid; grid-template-columns:minmax(220px,1fr) minmax(145px,.32fr) minmax(170px,.4fr) minmax(180px,.42fr); gap:8px; margin-bottom:10px; }
.security-filters { display:grid; grid-template-columns:minmax(220px,1fr) repeat(3,minmax(145px,.35fr)); gap:8px; margin-bottom:10px; }
.security-filters input, .security-filters select { width:100%; min-height:34px; border:1px solid var(--line); border-radius:var(--radius-sm); background:var(--panel); color:var(--text); padding:6px 9px; }
.filters input, .filters select {
  width:100%; min-height:34px; border:1px solid var(--line); border-radius:var(--radius-sm);
  background:var(--panel); color:var(--text); padding:6px 9px;
}
.object-list { height:500px; overflow:auto; }
.object-button { display:block; width:100%; text-align:left; border:0; border-bottom:1px solid var(--line-soft); border-radius:0; padding:10px 12px; background:transparent; }
.object-button:hover, .object-button.is-active { background:var(--brand-soft); color:var(--text); }
.object-meta { display:block; color:var(--muted); font-size:11.5px; margin-top:3px; overflow-wrap:anywhere; }
.empty-state { margin:0; padding:14px; color:var(--muted); background:var(--panel); border:1px dashed var(--line); border-radius:var(--radius); }
.topology-canvas { min-height:500px; background:var(--panel-soft); position:relative; overflow:hidden; }
#topology { display:block; width:100%; height:500px; touch-action:none; cursor:grab; user-select:none; }
#topology.is-panning { cursor:grabbing; }
.graph-controls { position:absolute; z-index:4; top:9px; right:9px; display:flex; gap:5px; padding:5px; border:1px solid var(--line-soft); border-radius:var(--radius); background:var(--panel); box-shadow:var(--shadow); }
.graph-controls button { min-width:32px; padding:4px 8px; }
.graph-tooltip { position:absolute; z-index:6; display:none; max-width:290px; padding:9px 10px; border:1px solid var(--line); border-radius:var(--radius-sm); background:var(--panel); box-shadow:var(--shadow); color:var(--text); font-size:11.5px; line-height:1.45; pointer-events:none; white-space:pre-line; }
.graph-tooltip.is-visible { display:block; }
.graph-note { padding:9px 12px; border-top:1px solid var(--line-soft); color:var(--muted); font-size:12px; min-height:38px; }
.edge { stroke:var(--muted); stroke-width:1.25; opacity:.72; }
.edge.has-signal { stroke-width:2.25; opacity:.95; }
.edge.signal-critical,.edge.signal-high { stroke:var(--high); }
.edge.signal-medium { stroke:var(--medium); }
.edge.signal-low,.edge.signal-info { stroke:var(--info); }
.edge-hit { stroke:transparent; stroke-width:14; cursor:pointer; }
.edge-label { fill:var(--muted); font-family:var(--font); font-size:10px; font-weight:600; text-anchor:middle; pointer-events:none; paint-order:stroke; stroke:var(--panel-soft); stroke-width:4px; stroke-linejoin:round; }
.node { cursor:pointer; color:var(--brand); }
.node circle.node-shell { fill:var(--panel); stroke:var(--node-kind-color,var(--brand)); stroke-width:2; }
.node.center circle.node-shell { fill:var(--brand-soft); stroke-width:3; }
.node.has-signal circle.node-shell { stroke-width:3.25; }
.node.signal-critical circle.node-shell,.node.signal-high circle.node-shell { stroke:var(--high); }
.node.signal-medium circle.node-shell { stroke:var(--medium); }
.node.signal-low circle.node-shell,.node.signal-info circle.node-shell { stroke:var(--info); }
.node.unresolved circle.node-shell { stroke:var(--high); stroke-dasharray:4 3; }
.node text { fill:var(--text); font-family:var(--font); font-size:11px; pointer-events:none; }
.node .kind-glyph { color:var(--text); pointer-events:none; }
.kind-icon { width:16px; height:16px; margin-right:6px; vertical-align:-3px; color:var(--brand); flex:0 0 auto; }
.object-title { display:flex; align-items:center; font-weight:600; overflow-wrap:anywhere; }
.relationship-type { color:var(--muted); font-size:11px; margin-top:3px; }
.inspector { max-height:538px; overflow:auto; }
.inspector h3 { margin:0 0 3px; }
.kv { display:grid; grid-template-columns:95px minmax(0,1fr); gap:7px 10px; margin:12px 0; font-size:12px; }
.kv dt { color:var(--muted); }
.kv dd { margin:0; overflow-wrap:anywhere; }
.relationship-row, .signal-row { padding:8px 0; border-bottom:1px solid var(--line-soft); font-size:12px; }
.relationship-row:last-child, .signal-row:last-child { border-bottom:0; }
.relationship-link { border:0; padding:0; min-height:0; background:transparent; color:var(--brand); text-align:left; font-weight:600; }
.relationship-link:hover { background:transparent; color:var(--brand-hover); }
details { margin-top:10px; border-top:1px solid var(--line-soft); padding-top:9px; }
summary { cursor:pointer; color:var(--brand); font-weight:600; font-size:12.5px; }
pre { white-space:pre-wrap; overflow-wrap:anywhere; font-size:11px; background:var(--panel-soft); border:1px solid var(--line-soft); padding:9px; border-radius:var(--radius-sm); }
.table-wrap { overflow:auto; }
table { width:100%; border-collapse:collapse; font-size:12px; }
th, td { padding:10px 12px; text-align:left; border-bottom:1px solid var(--line-soft); vertical-align:top; overflow-wrap:anywhere; }
th { background:var(--panel-soft); font-weight:600; }
tbody tr:last-child td { border-bottom:0; }
.signal-target { border:0; min-height:0; padding:0; background:transparent; color:var(--brand); text-align:left; font-weight:600; }
.signal-target:hover { background:transparent; color:var(--brand-hover); }
.kind-user { color:#0f6cbd; }.kind-group { color:#038387; }.kind-application { color:#5c2e91; }
.kind-servicePrincipal { color:#8764b8; }.kind-device { color:#498205; }.kind-directoryRole { color:#ca5010; }.kind-directoryObject { color:#c50f1f; }.kind-applicationCredential { color:#a4262c; }.kind-apiResource { color:#0078d4; }

.action-row { display:flex; flex-wrap:wrap; gap:6px; margin:10px 0 12px; }
.action-link { display:inline-flex; align-items:center; min-height:32px; border:1px solid var(--line); border-radius:var(--radius-sm); padding:5px 10px; color:var(--brand); text-decoration:none; font-size:12.5px; font-weight:600; background:var(--panel); }
.action-link:hover { border-color:var(--brand); background:var(--brand-soft); }
.inventory-grid { display:grid; grid-template-columns:1fr 1fr; gap:12px; }
.compact-filters { display:grid; grid-template-columns:minmax(220px,1fr) minmax(150px,.35fr); gap:8px; padding:10px 12px; border-bottom:1px solid var(--line-soft); }
.compact-filters input,.compact-filters select { width:100%; min-height:34px; border:1px solid var(--line); border-radius:var(--radius-sm); background:var(--panel); color:var(--text); padding:6px 9px; }
.runtime-grid { display:grid; grid-template-columns:repeat(6,minmax(0,1fr)); gap:8px; margin-bottom:12px; }
.runtime-card { border:1px solid var(--line-soft); border-radius:var(--radius); padding:10px 12px; background:var(--panel); }
.runtime-card strong { display:block; font-size:17px; font-weight:600; }
.runtime-card span { color:var(--muted); font-size:11.5px; }
.subsection { margin-top:14px; }
.recommendation { margin-top:8px; padding:9px 10px; border-left:3px solid var(--brand); background:var(--panel-soft); }
.recommendation strong { display:block; margin-bottom:3px; }
.small-link { color:var(--brand); text-decoration:none; font-weight:600; }
.small-link:hover { text-decoration:underline; }

.sticky-nav { position:sticky; top:0; z-index:20; background:color-mix(in srgb,var(--panel) 94%,transparent); border-bottom:1px solid var(--line-soft); backdrop-filter:blur(8px); }
.sticky-nav-inner { max-width:1180px; margin:0 auto; padding:7px 24px; display:flex; gap:4px; overflow:auto; }
.sticky-nav a { color:var(--muted); text-decoration:none; font-size:12px; font-weight:600; padding:6px 9px; border-radius:var(--radius-sm); white-space:nowrap; }
.sticky-nav a:hover { color:var(--brand); background:var(--brand-soft); }
.summary-grid { display:grid; grid-template-columns:minmax(0,1fr) minmax(0,1fr); gap:12px; }
.summary-list { display:grid; gap:8px; }
.summary-row { display:grid; grid-template-columns:minmax(120px,.65fr) minmax(140px,1fr) auto; gap:8px; align-items:center; }
.summary-label { font-size:12px; font-weight:600; overflow:hidden; text-overflow:ellipsis; white-space:nowrap; }
.summary-track { height:7px; border-radius:999px; background:var(--panel-strong); overflow:hidden; }
.summary-fill { height:100%; border-radius:inherit; background:var(--brand); min-width:2px; }
.summary-value { color:var(--muted); font-size:11.5px; font-variant-numeric:tabular-nums; }
.question-grid { display:grid; grid-template-columns:repeat(2,minmax(0,1fr)); gap:10px; }
.question-card { background:var(--panel); border:1px solid var(--line-soft); border-radius:var(--radius); box-shadow:var(--shadow); padding:13px 14px; display:grid; gap:7px; }
.question-card h3 { font-size:14px; }
.question-answer { display:flex; align-items:baseline; gap:8px; }
.question-count { font-size:22px; font-weight:600; color:var(--brand); }
.question-copy { color:var(--muted); font-size:12px; }
.question-examples { color:var(--faint); font-size:11.5px; min-height:18px; }
.question-actions { display:flex; gap:6px; }
.sankey-wrap { min-height:330px; overflow:auto; }
#relationshipSankey { display:block; width:100%; min-width:720px; height:330px; }
.sankey-node rect { fill-opacity:.13; stroke-width:1.25; rx:4; }
.sankey-node text { fill:var(--text); font-family:var(--font); font-size:10.5px; font-weight:600; }
.sankey-link { fill:none; stroke-opacity:.32; transition:stroke-opacity .14s ease; }
.sankey-link:hover { stroke-opacity:.72; }
.sankey-count { fill:var(--muted); font-family:var(--font); font-size:9.5px; }
.sankey-legend { display:flex; flex-wrap:wrap; gap:8px 16px; margin-top:10px; padding-top:10px; border-top:1px solid var(--line-soft); }
.sankey-legend-group { display:flex; flex-wrap:wrap; align-items:center; gap:6px; }
.sankey-legend-label { color:var(--muted); font-size:11px; font-weight:600; margin-right:2px; }
.sankey-legend-item { display:inline-flex; align-items:center; gap:5px; color:var(--muted); font-size:11px; white-space:nowrap; }
.sankey-legend-swatch { width:9px; height:9px; border-radius:3px; flex:0 0 auto; }

.security-table { table-layout:fixed; }
.security-table th,.security-table td { vertical-align:top; }
.security-table th:nth-child(1),.security-table td:nth-child(1) { width:28%; }
.security-table th:nth-child(2),.security-table td:nth-child(2) { width:18%; }
.security-table th:nth-child(3),.security-table td:nth-child(3) { width:auto; }
.security-table th:nth-child(4),.security-table td:nth-child(4) { width:92px; text-align:right; }
.security-context-heading { display:flex; flex-wrap:wrap; align-items:center; gap:7px; margin-bottom:5px; }
.security-context-title { font-weight:600; }
.security-context-reason { color:var(--muted); font-size:11.5px; line-height:1.45; }
.security-affected-count { font-size:17px; font-weight:600; color:var(--text); line-height:1.2; }
.security-affected-label { display:block; color:var(--muted); font-size:11px; margin-top:2px; }
.security-affected details { margin-top:7px; padding-top:0; border-top:0; }
.security-affected summary { font-size:11.5px; }
.security-affected-list { max-height:210px; overflow:auto; margin-top:6px; padding-right:4px; }
.security-affected-list .relationship-row { padding:5px 0; }
.security-recommendation-title { display:block; margin-bottom:4px; }
.security-recommendation-action { color:var(--muted); font-size:11.5px; line-height:1.5; max-width:54rem; }
.security-reference { display:inline-flex; margin-top:6px; }
.security-action-cell button { white-space:nowrap; }
.group-examples { color:var(--muted); font-size:11.5px; margin-top:3px; }
.run-summary { display:grid; grid-template-columns:repeat(5,minmax(0,1fr)); gap:8px; }
.compact-details { margin-top:10px; padding:0; border:1px solid var(--line-soft); border-radius:var(--radius); background:var(--panel); overflow:hidden; }
.compact-details > summary { list-style:none; padding:11px 13px; display:flex; justify-content:space-between; align-items:center; color:var(--text); }
.compact-details > summary::-webkit-details-marker { display:none; }
.compact-details > summary::after { content:'+'; color:var(--muted); font-size:16px; }
.compact-details[open] > summary::after { content:'−'; }
.compact-details-body { padding:0 12px 12px; }
@media (max-width:900px) { .summary-grid,.question-grid { grid-template-columns:1fr; } .run-summary { grid-template-columns:repeat(2,minmax(0,1fr)); } }

@media (max-width: 900px) { .inventory-grid { grid-template-columns:1fr; } .runtime-grid { grid-template-columns:repeat(3,minmax(0,1fr)); } }
@media (max-width: 1040px) {
  .report-grid { grid-template-columns:220px minmax(0,1fr); }
  .inspector-panel { grid-column:1/-1; }
  .inspector { max-height:none; }
}
@media (max-width: 800px) {
  .security-table { display:block; table-layout:auto; }
  .security-table thead { display:none; }
  .security-table tbody,.security-table tr,.security-table td { display:block; width:100% !important; }
  .security-table tbody { padding:8px; }
  .security-table tr { margin:0 0 10px; border:1px solid var(--line-soft); border-radius:var(--radius); background:var(--panel); overflow:hidden; }
  .security-table tr:last-child { margin-bottom:0; }
  .security-table td { border-bottom:1px solid var(--line-soft); padding:10px 11px; text-align:left !important; }
  .security-table td:last-child { border-bottom:0; }
  .security-table td::before { content:attr(data-label); display:block; margin-bottom:4px; color:var(--muted); font-size:10.5px; font-weight:600; text-transform:uppercase; letter-spacing:.02em; }
  .security-table .security-action-cell button { width:100%; }
}

@media (max-width: 720px) {
  .hero-grid { grid-template-columns:1fr; }
  .toolbar { justify-content:start; }
  .shell { padding:16px 12px 48px; }
  .filters, .security-filters, .report-grid { display:block; }
  .filters > *, .security-filters > * { margin-bottom:7px; }
  .report-grid > .panel { margin-bottom:12px; }
  .object-list { height:220px; }
  #topology { height:420px; }
  .topology-canvas { min-height:420px; }
}
</style>
</head>
<body>
<header class="hero">
  <div class="hero-grid">
    <div>
      <div class="brand-lockup"><span class="brand-accent" aria-hidden="true"></span><div><div class="brand">Microsoft Entra ID topology</div><div class="product-label">EntraTopology</div></div></div>
      <h1>__TITLE__</h1>
      <div class="hero-meta">
        <span class="pill" id="generatedPill">Generated __GENERATED__ UTC</span>
        <span class="pill" id="schemaPill"></span>
        <span class="pill status-success">Offline · read-only</span>
      </div>
      <p>A readable map of tenant objects, their relationships, security context, and supporting collection evidence.</p>
    </div>
    <div class="toolbar"><button id="themeToggle" type="button">Toggle theme</button></div>
  </div>
</header>
<nav class="sticky-nav" aria-label="Report sections"><div class="sticky-nav-inner">
  <a href="#overview">Overview</a><a href="#quick-answers">Quick answers</a><a href="#composition">Composition</a><a href="#topology-section">Topology</a><a href="#security-context">Security</a><a href="#coverage">Coverage</a><a href="#runtime-diagnostics">Run details</a>
</div></nav>
<main class="shell">
  <section class="section" id="overview">
    <div class="section-header"><h2>Tenant overview</h2><span class="muted" id="tenantLabel"></span></div>
    <div class="metric-grid" id="metrics"></div>
  </section>

  <section class="section" id="quick-answers">
    <div class="section-header"><h2>Quick answers</h2><span class="muted">Common administrator questions answered from this topology</span></div>
    <p class="section-intro">These answers are calculated locally from the embedded graph. Explore an answer to focus the relevant topology and security context.</p>
    <div class="question-grid" id="questionGrid"></div>
  </section>

  <section class="section" id="composition">
    <div class="section-header"><h2>Tenant composition</h2><span class="muted">Inventory at a glance</span></div>
    <p class="section-intro">Compact counts and relationship flows summarize the inventory without turning the report into a long object listing.</p>
    <div class="summary-grid">
      <section class="panel"><div class="panel-header"><h3>Object composition</h3><span class="muted" id="objectCompositionCount"></span></div><div class="panel-body summary-list" id="objectComposition"></div></section>
      <section class="panel"><div class="panel-header"><h3>Relationship composition</h3><span class="muted" id="relationshipCompositionCount"></span></div><div class="panel-body summary-list" id="relationshipComposition"></div></section>
    </div>
    <section class="panel" style="margin-top:12px"><div class="panel-header"><h3>Relationship flow</h3><span class="muted">Object type → relationship → object type</span></div><div class="panel-body sankey-wrap"><svg id="relationshipSankey" viewBox="0 0 980 330" role="img" aria-label="Aggregated tenant relationship Sankey diagram"></svg><div id="sankeyLegend" class="sankey-legend" aria-label="Relationship flow legend"></div></div></section>
  </section>

  <section class="section" id="topology-section">
    <div class="section-header"><h2>Tenant topology</h2><span class="muted">Select an object to inspect its direct relationships</span></div>
    <p class="section-intro">Search or filter the inventory, then select an object. The graph intentionally shows only its direct neighborhood to stay readable.</p>
    <div class="filters">
      <input id="search" type="search" aria-label="Search tenant objects" placeholder="Search name, ID, UPN or app ID">
      <select id="kind" aria-label="Filter by object type"><option value="">All object types</option></select>
      <select id="relationship" aria-label="Filter topology relationship"><option value="">All relationships</option></select>
      <select id="enterpriseCategory" aria-label="Filter enterprise application category"><option value="">All enterprise app categories</option></select>
    </div>
    <div class="report-grid">
      <section class="panel" aria-label="Tenant objects">
        <div class="panel-header"><h3>Objects</h3><span class="muted" id="resultCount"></span></div>
        <div class="object-list" id="objectList"></div>
      </section>
      <section class="panel" aria-label="Relationship topology">
        <div class="panel-header"><h3>Relationship neighborhood</h3><span class="muted">source → destination</span></div>
        <div class="topology-canvas" id="topologyCanvas">
          <div class="graph-controls" aria-label="Topology view controls"><button id="zoomIn" type="button" title="Zoom in" aria-label="Zoom in">+</button><button id="zoomOut" type="button" title="Zoom out" aria-label="Zoom out">−</button><button id="fitGraph" type="button" title="Fit topology" aria-label="Fit topology">Fit</button></div>
          <div class="graph-tooltip" id="graphTooltip" role="tooltip"></div>
          <svg id="topology" viewBox="0 0 760 500" role="group" aria-label="Selected object relationship topology"></svg>
        </div>
        <div class="graph-note" id="graphNote" aria-live="polite">Select an object to view its relationships.</div>
      </section>
      <section class="panel inspector-panel" aria-label="Object and relationship details">
        <div class="panel-header"><h3>Inspector</h3><span class="muted">context & evidence</span></div>
        <div class="panel-body inspector" id="inspector"><p class="muted">Select an object or relationship.</p></div>
      </section>
    </div>
  </section>

  <section class="section" id="security-context">
    <div class="section-header"><h2>Security context & recommendations</h2><span class="muted">Observed conditions with evidence-backed remediation guidance</span></div>
    <p class="section-intro">Signals enrich the topology with operational or security context. Recommendations provide deterministic remediation guidance; they are not a compliance score.</p>
    <div class="security-filters">
      <input id="signalSearch" type="search" aria-label="Search security context" placeholder="Search signal, target or reason">
      <select id="signalSeverity" aria-label="Filter signal severity"><option value="">All severities</option></select>
      <select id="signalType" aria-label="Filter signal type"><option value="">All signal types</option></select>
      <select id="signalTargetType" aria-label="Filter signal target type"><option value="">All target types</option></select>
    </div>
    <div class="panel"><div class="panel-header"><h3>Security context</h3><span class="muted" id="signalResultCount"></span></div><div class="table-wrap" id="signalsTable"></div></div>
  </section>

  <section class="section" id="coverage">
    <div class="section-header"><h2>Collection coverage</h2><span class="muted">Data trust and permissions</span></div>
    <div class="panel"><div class="table-wrap" id="coverageTable"></div></div>
  </section>

  <section class="section" id="runtime-diagnostics">
    <div class="section-header"><h2>Run details</h2><span class="muted">Runtime, evidence and diagnostics</span></div>
    <div class="run-summary" id="runtimeMetrics"></div>
    <details class="compact-details"><summary><span>Stage timings & diagnostics</span><span class="muted" id="diagnosticCount"></span></summary><div class="compact-details-body"><div class="inventory-grid"><section><h3>Stage timings</h3><div class="table-wrap" id="stageTable"></div></section><section><h3>Diagnostics</h3><div class="table-wrap" id="diagnosticsTable"></div></section></div></div></details>
    <details class="compact-details" id="evidence"><summary><span>Evidence & provenance</span><span class="muted" id="evidenceCount"></span></summary><div class="compact-details-body"><div class="compact-filters"><input id="evidenceSearch" type="search" placeholder="Search collector, endpoint or completeness"><select id="evidenceCompleteness"><option value="">All completeness states</option></select></div><div class="table-wrap" id="evidenceTable"></div></div></details>
  </section>
</main>
<script type="application/json" id="graph-data">__GRAPH_JSON__</script>
<script>
(()=>{
'use strict';
const $=id=>document.getElementById(id);
const data=JSON.parse($('graph-data').textContent);
const nodes=Array.isArray(data.Nodes)?data.Nodes:[];
const edges=Array.isArray(data.Edges)?data.Edges:[];
const signals=Array.isArray(data.Signals)?data.Signals:[];
const recommendations=Array.isArray(data.Recommendations)?data.Recommendations:[];
const evidence=Array.isArray(data.Evidence)?data.Evidence:[];
const coverage=Array.isArray(data.Coverage)?data.Coverage:[];
const byKey=new Map(nodes.map(n=>[n.Key,n]));
const edgeByKey=new Map(edges.map(e=>[e.Key,e]));
const evidenceByKey=new Map(evidence.map(e=>[e.Key,e]));
const incident=new Map();
for(const e of edges){for(const key of [e.From,e.To]){if(!incident.has(key))incident.set(key,[]);incident.get(key).push(e)}}
const signalsByTarget=new Map();
for(const s of signals){if(!signalsByTarget.has(s.TargetKey))signalsByTarget.set(s.TargetKey,[]);signalsByTarget.get(s.TargetKey).push(s)}
const recommendationBySignal=new Map(recommendations.map(r=>[r.SignalKey,r]));
const runtime=(data.Metadata&&data.Metadata.RuntimeTelemetry)||{};
const diagnostics=(data.Metadata&&Array.isArray(data.Metadata.Diagnostics))?data.Metadata.Diagnostics:[];

function el(tag,text,className){const x=document.createElement(tag);if(text!==undefined&&text!==null)x.textContent=String(text);if(className)x.className=className;return x}
function button(text,onClick,className){const b=el('button',text,className);b.type='button';b.addEventListener('click',onClick);return b}
function uniquePresent(values){const seen=new Set(),out=[];for(const v of values){if(v&&!seen.has(v)){seen.add(v);out.push(v)}}return out}
function prop(object,name){return object&&Object.prototype.hasOwnProperty.call(object,name)?object[name]:undefined}
function display(v){if(v===null||v===undefined||v==='')return '—';if(Array.isArray(v))return v.join(', ');if(typeof v==='object')return JSON.stringify(v);return String(v)}
function statusClass(status){const s=String(status||'').toLowerCase();if(s==='complete'||s==='success'||s==='resolved')return 'status-success';if(s==='partial'||s==='notrun'||s==='unavailable')return 'status-warning';if(s==='failed')return 'status-danger';return 'status-default'}
function kindLabel(kind){const map={user:'User',group:'Group',application:'Application',servicePrincipal:'Service principal',applicationCredential:'Credential',apiResource:'API resource',device:'Device',directoryRole:'Directory role',directoryObject:'Unresolved object'};return map[kind]||kind||'Object'}
function relationshipLabel(edgeOrRelationship){const e=typeof edgeOrRelationship==='string'?{Relationship:edgeOrRelationship}:edgeOrRelationship||{};const map={memberOf:'Member of',owns:'Owns',instantiatedAs:'Application instance',hasAppRoleAssignment:'Has permission',requiresApiPermission:'Requests API permission',hasDelegatedPermission:'Delegated consent',hasCredential:'Has credential',registeredOwnerOf:'Registered owner of',assignedDirectoryRole:'Assigned directory role'};if(e.Relationship==='hasAppRoleAssignment'&&e.State&&e.State.appRoleResolved&&(e.State.appRoleValue||e.State.appRoleDisplayName))return `Has permission: ${e.State.appRoleValue||e.State.appRoleDisplayName}`;if(e.Relationship==='requiresApiPermission'&&e.State&&(e.State.permissionValue||e.State.permissionDisplayName))return `Requests: ${e.State.permissionValue||e.State.permissionDisplayName}`;if(e.Relationship==='hasDelegatedPermission'&&e.State&&e.State.scope)return `Delegated: ${String(e.State.scope).split(/\s+/).filter(Boolean).slice(0,2).join(', ')}`;if(e.Relationship==='hasCredential'&&e.State&&e.State.credentialType)return `Has ${e.State.credentialType==='passwordCredential'?'client secret':'certificate'}`;return map[e.Relationship]||e.Relationship||'Relationship'}
function severityRank(v){return ({critical:5,high:4,medium:3,low:2,info:1,informational:1})[String(v||'').toLowerCase()]||0}
function targetSeverity(key){const list=signalsByTarget.get(key)||[];let best='';for(const s of list){if(severityRank(s.Severity)>severityRank(best))best=String(s.Severity||'').toLowerCase()}return best}
function nodeName(key){const n=byKey.get(key);return n?(n.DisplayName||n.Id||n.Key):key}
function label(text,max=22){const s=String(text||'');return s.length>max?s.slice(0,max-1)+'…':s}
function signalStatus(severity){const s=String(severity||'').toLowerCase();if(s==='critical'||s==='high')return 'status-danger';if(s==='medium')return 'status-warning';if(s==='low'||s==='info'||s==='informational')return 'status-info';return 'status-default'}
function signalLabel(type){const map={ownerlessObject:'Ownerless object',disabledIdentity:'Disabled identity',disabledWorkloadIdentity:'Disabled workload identity',staleDevice:'Stale device',credentialExpired:'Credential expired',credentialExpiring:'Credential expiring',disabledOwnerRelationship:'Disabled owner relationship',guestOwnerRelationship:'Guest owner relationship',riskyIdentity:'Risky identity',riskyOwnerRelationship:'Risky owner relationship',privilegedIdentity:'Privileged identity',privilegedOwnerRelationship:'Privileged owner relationship',highPrivilegeRoleAssignment:'High-privilege role assignment',highImpactApplicationPermission:'High-impact application permission',highImpactRequestedPermission:'High-impact requested permission',highImpactDelegatedPermission:'High-impact delegated permission'};return map[type]||type||'Security context'}
const KIND_COLORS={user:'#0f6cbd',group:'#038387',application:'#5c2e91',servicePrincipal:'#8764b8',device:'#498205',directoryRole:'#ca5010',directoryObject:'#c50f1f',applicationCredential:'#a4262c',apiResource:'#0078d4'};
const RELATIONSHIP_COLORS={memberOf:'#038387',owns:'#c239b3',instantiatedAs:'#8764b8',hasAppRoleAssignment:'#0078d4',requiresApiPermission:'#5c2e91',hasDelegatedPermission:'#0099bc',hasCredential:'#a4262c',registeredOwnerOf:'#498205',assignedDirectoryRole:'#ca5010'};
function kindColor(kind){return KIND_COLORS[kind]||'#605e5c'}
function relationshipColor(relationship){return RELATIONSHIP_COLORS[relationship]||'#605e5c'}
function appendPill(parent,text,cls='status-default'){parent.append(el('span',text,'pill '+cls))}

function setupTheme(){
  const root=document.documentElement;
  try{const saved=localStorage.getItem('entraTopologyTheme');if(saved==='dark')root.setAttribute('data-theme','dark')}catch{}
  $('themeToggle').addEventListener('click',()=>{
    const dark=root.getAttribute('data-theme')==='dark';
    if(dark)root.removeAttribute('data-theme');else root.setAttribute('data-theme','dark');
    try{localStorage.setItem('entraTopologyTheme',dark?'light':'dark')}catch{}
  });
}

function renderHeader(){
  $('schemaPill').textContent='Schema '+display(data.SchemaVersion);
  $('tenantLabel').textContent='Tenant '+display(data.TenantId);
}

function metric(labelText,value,hint,brand=false){
  const c=el('div',null,'metric-card'+(brand?' brand':''));
  c.append(el('div',labelText,'metric-label'),el('div',Number(value||0).toLocaleString(),'metric-value'),el('div',hint,'metric-hint'));
  return c;
}
function renderMetrics(){
  const meta=data.Metadata||{};
  const unresolved=prop(meta,'UnresolvedObjectCount')??nodes.filter(n=>n.Properties&&n.Properties.resolution==='unresolved').length;
  $('metrics').replaceChildren(
    metric('Objects',nodes.length,'Canonical tenant objects',true),
    metric('Relationships',edges.length,'Typed topology edges',true),
    metric('Security context',signals.length,'Signals on objects or edges'),
    metric('Recommendation themes',new Set(recommendations.map(r=>r.Title||r.Key)).size,'Grouped remediation guidance'),
    metric('Evidence records',evidence.length,'Collection provenance'),
    metric('Unresolved objects',unresolved,'Relationship endpoints not resolved')
  );
}

const kindSelect=$('kind'),relationshipSelect=$('relationship'),enterpriseSelect=$('enterpriseCategory');
const signalSearch=$('signalSearch'),signalSeverity=$('signalSeverity'),signalType=$('signalType'),signalTargetType=$('signalTargetType');
const evidenceSearch=$('evidenceSearch'),evidenceCompleteness=$('evidenceCompleteness');
const topologySvg=$('topology'),graphTooltip=$('graphTooltip');let graphView={x:0,y:0,w:760,h:500},panState=null;
for(const k of uniquePresent(nodes.map(n=>n.Kind)).sort())kindSelect.add(new Option(kindLabel(k),k));
for(const r of uniquePresent(edges.map(e=>e.Relationship)).sort())relationshipSelect.add(new Option(relationshipLabel(r),r));
for(const c of uniquePresent(nodes.filter(n=>n.Kind==='servicePrincipal').map(n=>n.Properties&&n.Properties.enterpriseAppCategory)).sort())enterpriseSelect.add(new Option(c.replace(/([a-z])([A-Z])/g,'$1 $2'),c));
for(const v of uniquePresent(signals.map(s=>s.Severity)).sort((a,b)=>severityRank(b)-severityRank(a)))signalSeverity.add(new Option(v,v));
for(const v of uniquePresent(signals.map(s=>s.Type)).sort())signalType.add(new Option(signalLabel(v),v));
const signalTargetKinds=signals.map(s=>byKey.has(s.TargetKey)?byKey.get(s.TargetKey).Kind:edgeByKey.has(s.TargetKey)?'relationship':'unresolved').filter(Boolean);
for(const v of uniquePresent(signalTargetKinds).sort())signalTargetType.add(new Option(v==='relationship'?'Relationship':kindLabel(v),v));
for(const v of uniquePresent(evidence.map(e=>e.Completeness)).sort())evidenceCompleteness.add(new Option(v,v));
let selectedKey='';
const inspectorHistory=[];let inspectorState=null;

function searchText(n){const p=n.Properties||{};return [n.DisplayName,n.Id,n.Key,p.userPrincipalName,p.appId,p.mail,p.displayName,p.enterpriseAppCategory,p.credentialType].filter(Boolean).join(' ').toLowerCase()}
function enterpriseCategoryMatches(n){const category=enterpriseSelect.value;if(!category)return true;return Boolean(n&&n.Kind==='servicePrincipal'&&n.Properties&&n.Properties.enterpriseAppCategory===category)}
function topologyEnterpriseNodeVisible(n){if(!n||n.Kind!=='servicePrincipal')return true;if(n.Properties&&n.Properties.topologyReferenceOnly===true)return true;return enterpriseCategoryMatches(n)}
function topologyEnterpriseEdgeVisible(e,centerKey){if(!enterpriseSelect.value)return true;const from=byKey.get(e.From),to=byKey.get(e.To),center=byKey.get(centerKey);if(center&&center.Kind==='servicePrincipal'&&!topologyEnterpriseNodeVisible(center))return false;return topologyEnterpriseNodeVisible(from)&&topologyEnterpriseNodeVisible(to)}
function filteredNodes(){const q=$('search').value.trim().toLowerCase(),kind=kindSelect.value;return nodes.filter(n=>(!kind||n.Kind===kind)&&enterpriseCategoryMatches(n)&&(!q||searchText(n).includes(q))).slice(0,300)}
function renderObjectList(){
  const list=$('objectList'),found=filteredNodes();list.replaceChildren();$('resultCount').textContent=found.length.toLocaleString();
  if(!found.length){list.append(el('p','No matching objects.','empty-state'));return}
  for(const n of found){
    const b=button('',()=>selectNode(n.Key),'object-button'+(selectedKey===n.Key?' is-active':''));
    const title=el('span',null,'object-title');title.append(kindIcon(n.Kind,16),document.createTextNode(n.DisplayName||n.Id||n.Key));
    const category=n.Kind==='servicePrincipal'&&n.Properties&&n.Properties.enterpriseAppCategory?` · ${n.Properties.enterpriseAppCategory.replace(/([a-z])([A-Z])/g,'$1 $2')}`:'';const meta=el('span',kindLabel(n.Kind)+category+(signalsByTarget.has(n.Key)?` · ${signalsByTarget.get(n.Key).length} signal(s)`:''),'object-meta');
    b.append(title,meta);list.append(b);
  }
}

function svgEl(name,attrs={}){const x=document.createElementNS('http://www.w3.org/2000/svg',name);for(const [k,v] of Object.entries(attrs))x.setAttribute(k,String(v));return x}
function kindIcon(kind,size=18){
  const svg=svgEl('svg',{viewBox:'0 0 24 24',width:size,height:size,class:`kind-icon kind-${kind}`,'aria-hidden':'true'});const common={fill:'none',stroke:'currentColor','stroke-width':'1.8','stroke-linecap':'round','stroke-linejoin':'round'};
  const add=(name,attrs)=>svg.append(svgEl(name,{...common,...attrs}));
  if(kind==='user'){add('circle',{cx:12,cy:8,r:3});add('path',{d:'M5.5 20c.5-4 3-6 6.5-6s6 2 6.5 6'});}
  else if(kind==='group'){add('circle',{cx:9,cy:9,r:2.5});add('circle',{cx:16.5,cy:8,r:2});add('path',{d:'M3.5 20c.4-3.5 2.6-5.5 5.5-5.5s5.1 2 5.5 5.5'});add('path',{d:'M14.5 14c3.2-.2 5.4 1.5 5.8 4.5'});}
  else if(kind==='application'){for(const [x,y] of [[5,5],[14,5],[5,14],[14,14]])add('rect',{x,y,width:5,height:5,rx:1});}
  else if(kind==='servicePrincipal'){add('circle',{cx:9,cy:12,r:4});add('path',{d:'M13 12h7m-2 0v3m-3-3v2'});}
  else if(kind==='device'){add('rect',{x:4,y:5,width:16,height:11,rx:1.5});add('path',{d:'M9 20h6m-3-4v4'});}
  else if(kind==='directoryRole'){add('path',{d:'M12 3l7 3v5c0 4.5-2.8 7.7-7 10-4.2-2.3-7-5.5-7-10V6l7-3'});add('path',{d:'M9.5 12l1.7 1.7 3.5-4'});}
  else if(kind==='applicationCredential'){add('circle',{cx:8,cy:12,r:4});add('path',{d:'M12 12h8m-2 0v3m-3-3v2'});}
  else if(kind==='apiResource'){add('path',{d:'M5 7h14v10H5z'});add('path',{d:'M8 10h8m-8 4h5'});}
  else {add('circle',{cx:12,cy:12,r:8});const t=svgEl('text',{x:12,y:16,'text-anchor':'middle',fill:'currentColor','font-size':'12','font-weight':'700'});t.textContent='?';svg.append(t);}
  return svg;
}
function graphKindIcon(kind,size){const icon=kindIcon(kind,size);icon.setAttribute('x',String(-size/2));icon.setAttribute('y',String(-size/2));icon.setAttribute('class',`kind-glyph kind-${kind}`);return icon;}
function applyGraphView(){topologySvg.setAttribute('viewBox',`${graphView.x} ${graphView.y} ${graphView.w} ${graphView.h}`)}
function fitGraph(){graphView={x:0,y:0,w:760,h:500};applyGraphView()}
function zoomGraph(factor,cx=graphView.x+graphView.w/2,cy=graphView.y+graphView.h/2){const nw=Math.max(180,Math.min(1520,graphView.w*factor)),nh=nw*(500/760),rx=(cx-graphView.x)/graphView.w,ry=(cy-graphView.y)/graphView.h;graphView={x:cx-rx*nw,y:cy-ry*nh,w:nw,h:nh};applyGraphView()}
function svgPointFromClient(ev){const rect=topologySvg.getBoundingClientRect();return{x:graphView.x+((ev.clientX-rect.left)/rect.width)*graphView.w,y:graphView.y+((ev.clientY-rect.top)/rect.height)*graphView.h}}
function showGraphTooltip(ev,text){if(!text)return;graphTooltip.textContent=text;const canvas=$('topologyCanvas').getBoundingClientRect();graphTooltip.style.left=`${Math.max(8,Math.min(ev.clientX-canvas.left+12,canvas.width-300))}px`;graphTooltip.style.top=`${Math.max(8,Math.min(ev.clientY-canvas.top+12,canvas.height-180))}px`;graphTooltip.classList.add('is-visible')}
function hideGraphTooltip(){graphTooltip.classList.remove('is-visible')}
function nodeHoverText(n){const p=n.Properties||{},lines=[n.DisplayName||n.Id,kindLabel(n.Kind)];if(p.userPrincipalName)lines.push(`UPN: ${p.userPrincipalName}`);if(p.appId)lines.push(`App ID: ${p.appId}`);if(p.enterpriseAppCategory)lines.push(`Category: ${p.enterpriseAppCategory.replace(/([a-z])([A-Z])/g,'$1 $2')}`);if(p.accountEnabled===false)lines.push('State: Disabled');if(p.riskState)lines.push(`Risk: ${p.riskState}${p.riskLevel?` (${p.riskLevel})`:''}`);if(n.Kind==='applicationCredential'){lines.push(`Type: ${p.credentialType==='passwordCredential'?'Client secret':'Certificate'}`);if(p.endDateTime)lines.push(`Expires: ${p.endDateTime}`)}const rels=incident.get(n.Key)||[],owners=rels.filter(e=>e.Relationship==='owns'&&e.To===n.Key).length,permissions=rels.filter(e=>['hasAppRoleAssignment','hasDelegatedPermission','requiresApiPermission'].includes(e.Relationship)&&e.From===n.Key).length,credentials=rels.filter(e=>e.Relationship==='hasCredential'&&e.From===n.Key).length;if(owners)lines.push(`Owners: ${owners}`);if(permissions)lines.push(`Permissions: ${permissions}`);if(credentials){lines.push(`Credentials: ${credentials}`);const credentialNodes=rels.filter(e=>e.Relationship==='hasCredential'&&e.From===n.Key).map(e=>byKey.get(e.To)).filter(Boolean),dated=credentialNodes.map(c=>({c,end:Date.parse(c.Properties&&c.Properties.endDateTime||'')})).filter(x=>Number.isFinite(x.end)).sort((a,b)=>a.end-b.end);if(dated.length)lines.push(`Nearest credential expiry: ${dated[0].c.Properties.endDateTime}`)}const sig=(signalsByTarget.get(n.Key)||[]).sort((a,b)=>severityRank(b.Severity)-severityRank(a.Severity));if(sig.length)lines.push(`Security: ${sig.slice(0,3).map(x=>`${x.Severity} ${signalLabel(x.Type)}`).join(' · ')}`);return lines.join('\n')}
$('zoomIn').addEventListener('click',()=>zoomGraph(.8));$('zoomOut').addEventListener('click',()=>zoomGraph(1.25));$('fitGraph').addEventListener('click',fitGraph);
topologySvg.addEventListener('wheel',ev=>{ev.preventDefault();const p=svgPointFromClient(ev);zoomGraph(ev.deltaY<0?.88:1.14,p.x,p.y)},{passive:false});
topologySvg.addEventListener('pointerdown',ev=>{if(ev.target!==topologySvg)return;const p=svgPointFromClient(ev);panState={start:p,view:{...graphView},id:ev.pointerId};topologySvg.setPointerCapture(ev.pointerId);topologySvg.classList.add('is-panning')});
topologySvg.addEventListener('pointermove',ev=>{if(!panState||panState.id!==ev.pointerId)return;const p=svgPointFromClient(ev);graphView.x=panState.view.x-(p.x-panState.start.x);graphView.y=panState.view.y-(p.y-panState.start.y);applyGraphView()});
function endPan(ev){if(!panState||panState.id!==ev.pointerId)return;panState=null;topologySvg.classList.remove('is-panning')}
topologySvg.addEventListener('pointerup',endPan);topologySvg.addEventListener('pointercancel',endPan);

function rememberInspector(){if(inspectorState)inspectorHistory.push(inspectorState)}
function renderInspectorState(state){if(!state)return;inspectorState=state;if(state.type==='node'&&byKey.has(state.key)){renderNodeInspector(byKey.get(state.key))}else if(state.type==='edge'&&edgeByKey.has(state.key)){renderEdgeInspector(edgeByKey.get(state.key))}}
function selectNode(key,push=true){if(!byKey.has(key))return;if(push)rememberInspector();selectedKey=key;renderObjectList();renderTopology(key);renderInspectorState({type:'node',key});$('topology-section').scrollIntoView({block:'nearest'})}
function selectEdge(edge,push=true){if(!edge)return;if(push)rememberInspector();renderInspectorState({type:'edge',key:edge.Key})}
function inspectorBack(){const previous=inspectorHistory.pop();if(!previous)return;if(previous.type==='node')selectNode(previous.key,false);else if(previous.type==='edge'&&edgeByKey.has(previous.key))selectEdge(edgeByKey.get(previous.key),false)}
function renderTopology(key){
  const svg=topologySvg;svg.replaceChildren();hideGraphTooltip();
  const center=byKey.get(key);if(!center)return;
  const relFilter=relationshipSelect.value;
  let relationships=(incident.get(key)||[]).filter(e=>(!relFilter||e.Relationship===relFilter)&&topologyEnterpriseEdgeVisible(e,key));
  const total=relationships.length,limit=36;relationships=relationships.slice(0,limit);
  const neighborKeys=[...new Set(relationships.map(e=>e.From===key?e.To:e.From))];
  const positions=new Map([[key,{x:380,y:242}]]);
  neighborKeys.forEach((k,i)=>{const angle=(Math.PI*2*i/Math.max(1,neighborKeys.length))-Math.PI/2;const radius=neighborKeys.length<=10?165:195;positions.set(k,{x:380+Math.cos(angle)*radius,y:242+Math.sin(angle)*radius})});
  const defs=svgEl('defs');const marker=svgEl('marker',{id:'arrow',viewBox:'0 0 10 10',refX:'9',refY:'5',markerWidth:'6',markerHeight:'6',orient:'auto-start-reverse'});marker.append(svgEl('path',{d:'M 0 0 L 10 5 L 0 10 z',fill:'var(--muted)'}));defs.append(marker);svg.append(defs);
  for(const e of relationships){
    const a=positions.get(e.From),b=positions.get(e.To);if(!a||!b)continue;
    const severity=targetSeverity(e.Key),hasSignal=Boolean(severity);
    const line=svgEl('line',{x1:a.x,y1:a.y,x2:b.x,y2:b.y,class:'edge'+(hasSignal?' has-signal signal-'+severity:''),'marker-end':'url(#arrow)'});svg.append(line);
    const hit=svgEl('line',{x1:a.x,y1:a.y,x2:b.x,y2:b.y,class:'edge-hit',tabindex:'0'});hit.addEventListener('click',()=>selectEdge(e));hit.addEventListener('keydown',ev=>{if(ev.key==='Enter'||ev.key===' '){ev.preventDefault();selectEdge(e)}});svg.append(hit);
    const edgeText=svgEl('text',{x:(a.x+b.x)/2,y:(a.y+b.y)/2-5,class:'edge-label'});edgeText.textContent=label(relationshipLabel(e),28);svg.append(edgeText);
  }
  for(const k of [key,...neighborKeys]){
    const n=byKey.get(k);if(!n)continue;const p=positions.get(k);const severity=targetSeverity(k),classes=['node'];if(k===key)classes.push('center');if(severity)classes.push('has-signal','signal-'+severity);if(n.Properties&&n.Properties.resolution==='unresolved')classes.push('unresolved');
    const g=svgEl('g',{class:classes.join(' '),transform:`translate(${p.x},${p.y})`,tabindex:'0',role:'button','aria-label':`${kindLabel(n.Kind)} ${n.DisplayName||n.Id}`,style:`--node-kind-color:${kindColor(n.Kind)}`});
    const radius=k===key?24:18;g.append(svgEl('circle',{r:radius,class:'node-shell'}));g.append(graphKindIcon(n.Kind,k===key?22:17));const text=svgEl('text',{'text-anchor':'middle',y:k===key?40:33});text.textContent=label(n.DisplayName||n.Id,k===key?26:20);g.append(text);
    const tips=(signalsByTarget.get(k)||[]).map(s=>`${s.Severity}: ${signalLabel(s.Type)}`).join(' · ');if(tips){const title=svgEl('title');title.textContent=tips;g.append(title)}
    g.addEventListener('mouseenter',ev=>showGraphTooltip(ev,nodeHoverText(n)));g.addEventListener('mousemove',ev=>showGraphTooltip(ev,nodeHoverText(n)));g.addEventListener('mouseleave',hideGraphTooltip);
    g.addEventListener('click',()=>selectNode(k));g.addEventListener('keydown',ev=>{if(ev.key==='Enter'||ev.key===' '){ev.preventDefault();selectNode(k)}});svg.append(g);
  }
  fitGraph();
  $('graphNote').textContent=`${relationships.length} of ${total} direct relationship(s) shown${total>limit?` · limited to ${limit} for readability`:''}. Relationship labels are shown on the graph. Click an edge for state, security context, and evidence.`;
}

function renderSignalsInto(parent,targetKey){
  const list=signalsByTarget.get(targetKey)||[];
  if(!list.length){parent.append(el('p','No attached security context.','muted'));return}
  for(const s of list){const row=el('div',null,'signal-row');appendPill(row,display(s.Severity),signalStatus(s.Severity));row.append(document.createTextNode(' '));const strong=el('strong',signalLabel(s.Type));row.append(strong);if(s.Reason)row.append(el('div',s.Reason,'muted'));const rec=recommendationBySignal.get(s.Key);if(rec){const box=el('div',null,'recommendation');box.append(el('strong',rec.Title),el('div',rec.Action,'muted'));for(const ref of (rec.References||[])){const a=el('a',ref.Title||'Reference','small-link');a.href=ref.Url;a.target='_blank';a.rel='noopener noreferrer';box.append(a)}row.append(box)}parent.append(row)}
}
function evidenceBlock(keys){
  const details=el('details');details.append(el('summary','Evidence / provenance'));const items=(keys||[]).map(k=>evidenceByKey.get(k)).filter(Boolean);
  if(!items.length){details.append(el('p','No evidence object resolved.','muted'));return details}
  for(const ev of items){const row=el('div',null,'relationship-row');row.append(el('strong',display(ev.Collector)));row.append(el('div',display(ev.Endpoint),'muted'));const status=el('div');appendPill(status,display(ev.Completeness),statusClass(ev.Completeness));row.append(status);details.append(row)}
  return details;
}
function propertiesBlock(value,title='Raw properties'){
  const details=el('details');details.append(el('summary',title));details.append(el('pre',JSON.stringify(value||{},null,2)));return details;
}
function copyText(value){const text=String(value||'');if(!text)return;if(navigator.clipboard&&window.isSecureContext){navigator.clipboard.writeText(text).catch(()=>{});return}const ta=document.createElement('textarea');ta.value=text;ta.style.position='fixed';ta.style.opacity='0';document.body.append(ta);ta.select();try{document.execCommand('copy')}catch{}ta.remove()}
function inspectorActions(host,n){const row=el('div',null,'action-row');if(inspectorHistory.length)row.append(button('Back',inspectorBack));row.append(button('Focus in topology',()=>selectNode(n.Key,false)));row.append(button('Copy object ID',()=>copyText(n.Id)));const uri=n.Properties&&n.Properties.portalUri;if(uri){const a=el('a','Open in Entra','action-link');a.href=uri;a.target='_blank';a.rel='noopener noreferrer';row.append(a)}host.append(row)}
function edgeInspectorActions(host,e){const row=el('div',null,'action-row');if(inspectorHistory.length)row.append(button('Back',inspectorBack));row.append(button('Source',()=>selectNode(e.From)));row.append(button('Destination',()=>selectNode(e.To)));host.append(row)}
function renderNodeInspector(n){
  const host=$('inspector');host.replaceChildren();host.append(el('h3',n.DisplayName||n.Id||n.Key));inspectorActions(host,n);const typeRow=el('div');appendPill(typeRow,kindLabel(n.Kind),'status-info');host.append(typeRow);
  const dl=el('dl',null,'kv');for(const [k,v] of [['Object ID',n.Id],['Key',n.Key],['Relationships',(incident.get(n.Key)||[]).length]]){dl.append(el('dt',k),el('dd',display(v)))}host.append(dl);
  if(n.Kind==='application'||n.Kind==='servicePrincipal'){const rels=incident.get(n.Key)||[],credentials=rels.filter(e=>e.Relationship==='hasCredential'&&e.From===n.Key).map(e=>byKey.get(e.To)).filter(Boolean);if(credentials.length){host.append(el('h3','Credentials'));for(const c of credentials.slice(0,8)){const cp=c.Properties||{},row=el('div',null,'relationship-row'),type=cp.credentialType==='passwordCredential'?'Client secret':'Certificate';row.append(el('strong',`${type} · ${c.DisplayName||cp.keyId||'Credential'}`));if(cp.endDateTime)row.append(el('div',`Expires ${cp.endDateTime}`,'muted'));const cs=signalsByTarget.get(c.Key)||[];if(cs.length){const d=el('div');cs.forEach(x=>appendPill(d,`${x.Severity} ${signalLabel(x.Type)}`,signalStatus(x.Severity)));row.append(d)}host.append(row)}}}
  host.append(el('h3','Security context'));renderSignalsInto(host,n.Key);
  const rels=incident.get(n.Key)||[];host.append(el('h3','Relationships'));
  if(!rels.length)host.append(el('p','No relationships in the current topology.','muted'));
  else for(const e of rels.slice(0,30)){const row=el('div',null,'relationship-row');const other=e.From===n.Key?e.To:e.From;const direction=e.From===n.Key?'→':'←';row.append(button(`${direction} ${relationshipLabel(e)} · ${nodeName(other)}`,()=>selectEdge(e),'relationship-link'));host.append(row)}
  if(rels.length>30)host.append(el('p',`${rels.length-30} additional relationship(s) not listed here. Use relationship filtering in the topology view.`,'muted'));
  host.append(propertiesBlock(n.Properties));host.append(evidenceBlock(n.EvidenceKeys||n.EvidenceIds||[]));
}
function renderEdgeInspector(e){
  const host=$('inspector');host.replaceChildren();host.append(el('h3',relationshipLabel(e)));edgeInspectorActions(host,e);host.append(el('div',display(e.Relationship),'relationship-type'));const direction=el('p',`${nodeName(e.From)} → ${nodeName(e.To)}`);host.append(direction);
  if(e.State&&e.State.appRoleResolved){const p=el('p');p.append(el('strong','Permission: '),document.createTextNode(display(e.State.appRoleValue||e.State.appRoleDisplayName)));if(e.State.resourceDisplayName)p.append(document.createTextNode(` · ${e.State.resourceDisplayName}`));host.append(p)}
  if(e.Relationship==='requiresApiPermission'&&e.State){const p=el('p');p.append(el('strong','Requested permission: '),document.createTextNode(display(e.State.permissionValue||e.State.permissionDisplayName||e.State.resourceAccessId)));if(e.State.permissionType)p.append(document.createTextNode(` · ${e.State.permissionType==='Role'?'Application':'Delegated'}`));host.append(p)}
  if(e.Relationship==='hasDelegatedPermission'&&e.State){const p=el('p');p.append(el('strong','Delegated scopes: '),document.createTextNode(display(e.State.scope)));if(e.State.consentType)p.append(document.createTextNode(` · ${e.State.consentType}`));host.append(p)}
  host.append(el('h3','Security context'));renderSignalsInto(host,e.Key);host.append(propertiesBlock(e.State,'Relationship state'));host.append(evidenceBlock(e.EvidenceKeys||e.EvidenceIds||[]));
}

function renderSignalsTable(forcedTypes=null){
  const host=$('signalsTable'),q=(signalSearch.value||'').trim().toLowerCase(),sev=signalSeverity.value,type=signalType.value,targetType=signalTargetType.value,forced=Array.isArray(forcedTypes)&&forcedTypes.length?new Set(forcedTypes):null;
  const filtered=signals.filter(s=>{const node=byKey.get(s.TargetKey),edge=edgeByKey.get(s.TargetKey),actualTarget=node?node.Kind:edge?'relationship':'unresolved';const targetText=node?(node.DisplayName||node.Id):edge?`${nodeName(edge.From)} ${relationshipLabel(edge)} ${nodeName(edge.To)}`:s.TargetKey;const hay=`${signalLabel(s.Type)} ${s.Type||''} ${s.Severity||''} ${targetText||''} ${s.Reason||''}`.toLowerCase();return(!forced||forced.has(s.Type))&&(!q||hay.includes(q))&&(!sev||s.Severity===sev)&&(!type||s.Type===type)&&(!targetType||actualTarget===targetType)});
  $('signalResultCount').textContent=`${filtered.length} of ${signals.length} signal(s)`;
  const groups=new Map();for(const s of filtered){if(!groups.has(s.Type))groups.set(s.Type,[]);groups.get(s.Type).push(s)}
  const rows=[...groups.entries()].map(([signalType,list])=>{const maxSeverity=list.reduce((best,s)=>severityRank(s.Severity)>severityRank(best)?s.Severity:best,'');const examples=list.slice(0,3).map(s=>{const n=byKey.get(s.TargetKey),e=edgeByKey.get(s.TargetKey);return n?(n.DisplayName||n.Id):e?`${nodeName(e.From)} → ${nodeName(e.To)}`:s.TargetKey});const rec=list.map(s=>recommendationBySignal.get(s.Key)).find(Boolean);return{signalType,list,maxSeverity,examples,rec}}).sort((a,b)=>severityRank(b.maxSeverity)-severityRank(a.maxSeverity)||b.list.length-a.list.length);
  const table=el('table',null,'security-table'),thead=el('thead'),tr=el('tr');for(const h of ['Security context','Affected','Recommendation',''])tr.append(el('th',h));thead.append(tr);table.append(thead);const body=el('tbody');
  if(!rows.length){const r=el('tr'),c=el('td','No security-context groups match the current filters.');c.colSpan=4;r.append(c);body.append(r)}
  for(const g of rows){
    const r=el('tr');
    const context=el('td',null,'security-context-cell');context.dataset.label='Security context';const heading=el('div',null,'security-context-heading');appendPill(heading,display(g.maxSeverity),signalStatus(g.maxSeverity));heading.append(el('span',signalLabel(g.signalType),'security-context-title'));context.append(heading);if(g.list[0]&&g.list[0].Reason)context.append(el('div',g.list[0].Reason,'security-context-reason'));
    const affected=el('td',null,'security-affected');affected.dataset.label='Affected';affected.append(el('span',String(g.list.length),'security-affected-count'),el('span','affected item(s)','security-affected-label'));const detail=el('details');const summary=el('summary','View affected');detail.append(summary);const affectedList=el('div',null,'security-affected-list');for(const s of g.list.slice(0,20)){const n=byKey.get(s.TargetKey),e=edgeByKey.get(s.TargetKey),target=n?(n.DisplayName||n.Id):e?`${nodeName(e.From)} → ${nodeName(e.To)}`:s.TargetKey;const row=el('div',null,'relationship-row');row.append(button(target,()=>{if(n)selectNode(n.Key);else if(e){selectedKey=e.From;renderObjectList();renderTopology(e.From);selectEdge(e)}$('topology-section').scrollIntoView({behavior:'smooth',block:'start'})},'relationship-link'));affectedList.append(row)}if(g.list.length>20)affectedList.append(el('div',`+ ${g.list.length-20} more affected item(s)`,'muted'));detail.append(affectedList);affected.append(detail);
    const recCell=el('td',null,'security-recommendation-cell');recCell.dataset.label='Recommendation';if(g.rec){recCell.append(el('strong',g.rec.Title,'security-recommendation-title'),el('div',g.rec.Action,'security-recommendation-action'));const ref=(g.rec.References||[])[0];if(ref){const a=el('a',ref.Title||'Reference','small-link security-reference');a.href=ref.Url;a.target='_blank';a.rel='noopener noreferrer';recCell.append(a)}}else recCell.textContent='—';
    const action=el('td',null,'security-action-cell');action.dataset.label='Action';action.append(button('Explore',()=>exploreSignalGroup(g.signalType,g.list)));r.append(context,affected,recCell,action);body.append(r)
  }table.append(body);host.replaceChildren(table);
}
function exploreSignalGroup(type,list){signalSearch.value='';signalSeverity.value='';signalTargetType.value='';signalType.value=type;renderSignalsTable();const first=list&&list[0];if(first){const n=byKey.get(first.TargetKey),e=edgeByKey.get(first.TargetKey);if(n)selectNode(n.Key);else if(e){selectedKey=e.From;renderObjectList();renderTopology(e.From);selectEdge(e)}}$('topology-section').scrollIntoView({behavior:'smooth',block:'start'})}

function groupedCounts(values,labeler=x=>x){const map=new Map();for(const v of values){const key=labeler(v);map.set(key,(map.get(key)||0)+1)}return [...map.entries()].sort((a,b)=>b[1]-a[1])}
function renderBarSummary(hostId,rows,total,colorForLabel){const host=$(hostId);host.replaceChildren();const max=Math.max(1,...rows.map(x=>x[1]));for(const [name,count] of rows){const row=el('div',null,'summary-row');row.append(el('span',name,'summary-label'));const track=el('div',null,'summary-track'),fill=el('div',null,'summary-fill');fill.style.width=`${Math.max(2,(count/max)*100)}%`;if(colorForLabel)fill.style.background=colorForLabel(name);track.append(fill);row.append(track,el('span',`${count.toLocaleString()} · ${total?Math.round((count/total)*100):0}%`,'summary-value'));host.append(row)}}
function renderComposition(){const objectRows=groupedCounts(nodes,n=>kindLabel(n.Kind)),kindLabelColors=new Map(Object.keys(KIND_COLORS).map(k=>[kindLabel(k),kindColor(k)]));renderBarSummary('objectComposition',objectRows,nodes.length,name=>kindLabelColors.get(name)||'#605e5c');$('objectCompositionCount').textContent=`${nodes.length.toLocaleString()} objects`;const relRows=groupedCounts(edges,e=>relationshipLabel(e.Relationship)),relationshipLabelColors=new Map(Object.keys(RELATIONSHIP_COLORS).map(r=>[relationshipLabel(r),relationshipColor(r)]));renderBarSummary('relationshipComposition',relRows,edges.length,name=>relationshipLabelColors.get(name)||'#605e5c');$('relationshipCompositionCount').textContent=`${edges.length.toLocaleString()} relationships`;renderRelationshipSankey()}
function renderSankeyLegend(flows){const host=$('sankeyLegend');host.replaceChildren();const kindKeys=uniquePresent(flows.flatMap(f=>[f.fromKind,f.toKind])),relationshipKeys=uniquePresent(flows.map(f=>f.relationship));const addGroup=(title,items,labeler,colorer)=>{const group=el('div',null,'sankey-legend-group');group.append(el('span',title,'sankey-legend-label'));for(const item of items){const chip=el('span',null,'sankey-legend-item'),swatch=el('span',null,'sankey-legend-swatch');swatch.style.background=colorer(item);chip.append(swatch,document.createTextNode(labeler(item)));group.append(chip)}host.append(group)};addGroup('Objects',kindKeys,kindLabel,kindColor);addGroup('Relationships',relationshipKeys,r=>relationshipLabel(r),relationshipColor)}
function renderRelationshipSankey(){const svg=$('relationshipSankey');svg.replaceChildren();const flows=new Map();for(const e of edges){const from=byKey.get(e.From),to=byKey.get(e.To);if(!from||!to)continue;const key=`${from.Kind}|${e.Relationship}|${to.Kind}`;flows.set(key,(flows.get(key)||0)+1)}const top=[...flows.entries()].sort((a,b)=>b[1]-a[1]).slice(0,16).map(([key,count])=>{const [fromKind,relationship,toKind]=key.split('|');return{fromKind,relationship,toKind,count}});renderSankeyLegend(top);if(!top.length){svg.append(svgEl('text',{x:20,y:30,fill:'currentColor'}));svg.lastChild.textContent='No relationships available.';return}const left=groupedCounts(top,x=>x.fromKind),mid=groupedCounts(top,x=>x.relationship),right=groupedCounts(top,x=>x.toKind);const sums=new Map();for(const f of top){for(const key of [`L:${f.fromKind}`,`M:${f.relationship}`,`R:${f.toKind}`])sums.set(key,(sums.get(key)||0)+f.count)}const positions=new Map();function layout(items,prefix,x){const gap=8,nodeH=24,totalH=items.length*nodeH+(items.length-1)*gap;let y=Math.max(12,(330-totalH)/2);for(const [name] of items){positions.set(`${prefix}:${name}`,{x,y,w:150,h:nodeH});y+=nodeH+gap}}layout(left,'L',18);layout(mid,'M',415);layout(right,'R',812);const maxFlow=Math.max(...top.map(f=>f.count));for(const f of top){const a=positions.get(`L:${f.fromKind}`),m=positions.get(`M:${f.relationship}`),b=positions.get(`R:${f.toKind}`),width=Math.max(1.3,Math.min(16,2+14*(f.count/maxFlow))),color=relationshipColor(f.relationship);const y1=a.y+a.h/2,ym=m.y+m.h/2,y2=b.y+b.h/2;for(const [x1,yy1,x2,yy2] of [[a.x+a.w,y1,m.x,ym],[m.x+m.w,ym,b.x,y2]]){const path=svgEl('path',{d:`M ${x1} ${yy1} C ${(x1+x2)/2} ${yy1}, ${(x1+x2)/2} ${yy2}, ${x2} ${yy2}`,class:'sankey-link','stroke-width':width,stroke:color});const title=svgEl('title');title.textContent=`${kindLabel(f.fromKind)} → ${relationshipLabel(f.relationship)} → ${kindLabel(f.toKind)}: ${f.count}`;path.append(title);svg.append(path)}}for(const [key,pos] of positions){const prefix=key.slice(0,1),name=key.slice(2),isRelationship=prefix==='M',color=isRelationship?relationshipColor(name):kindColor(name),displayName=isRelationship?relationshipLabel(name):kindLabel(name),g=svgEl('g',{class:'sankey-node'});g.append(svgEl('rect',{x:pos.x,y:pos.y,width:pos.w,height:pos.h,fill:color,stroke:color}));const text=svgEl('text',{x:pos.x+7,y:pos.y+15});text.textContent=label(displayName,22);g.append(text);const count=svgEl('text',{x:pos.x+pos.w-6,y:pos.y+15,'text-anchor':'end',class:'sankey-count'});count.textContent=sums.get(key)||0;g.append(count);svg.append(g)}}
function signalTargets(types){const set=new Set(types);return signals.filter(s=>set.has(s.Type)).map(s=>({signal:s,node:byKey.get(s.TargetKey),edge:edgeByKey.get(s.TargetKey)}))}
function uniqueNodesFromMatches(matches,selector){const out=[],seen=new Set();for(const m of matches){for(const n of selector(m)||[]){if(n&&!seen.has(n.Key)){seen.add(n.Key);out.push(n)}}}return out}
function quickQuestionDefinitions(){return[
{id:'privilegedOwners',title:'Which privileged identities own applications?',copy:'Privileged identities with ownership paths to applications or enterprise apps.',evaluate:()=>{const privilegedKeys=uniquePresent(signalTargets(['privilegedIdentity']).map(x=>x.node&&x.node.Key)),privileged=new Set(privilegedKeys),matches=edges.filter(e=>e.Relationship==='owns'&&privileged.has(e.From)&&['application','servicePrincipal'].includes((byKey.get(e.To)||{}).Kind));return{count:new Set(matches.map(e=>e.From)).size,unit:'privileged owner(s)',examples:matches.slice(0,3).map(e=>`${nodeName(e.From)} → ${nodeName(e.To)}`),focus:matches[0]||null,signalTypes:['privilegedIdentity','privilegedOwnerRelationship']}}},
{id:'highImpactApps',title:'Which applications hold high-impact permissions?',copy:'Workload identities with high-impact granted, requested, or delegated permissions.',evaluate:()=>{const matches=signalTargets(['highImpactApplicationPermission','highImpactRequestedPermission','highImpactDelegatedPermission']).filter(x=>x.edge);const nodes=uniqueNodesFromMatches(matches,m=>[byKey.get(m.edge.From)]);return{count:nodes.length,unit:'workload identity(ies)',examples:nodes.slice(0,3).map(n=>n.DisplayName||n.Id),focus:matches[0]&&matches[0].edge,signalTypes:['highImpactApplicationPermission','highImpactRequestedPermission','highImpactDelegatedPermission']}}},
{id:'expiringCredentials',title:'Which credentials need attention?',copy:'Expired or expiring application secrets and certificates.',evaluate:()=>{const matches=signalTargets(['credentialExpired','credentialExpiring']);const nodes=uniqueNodesFromMatches(matches,m=>[m.node]);return{count:nodes.length,unit:'credential(s)',examples:nodes.slice(0,3).map(n=>`${n.DisplayName||n.Id}${n.Properties&&n.Properties.endDateTime?` · ${n.Properties.endDateTime}`:''}`),focus:matches[0]&&(matches[0].node||matches[0].edge),signalTypes:['credentialExpired','credentialExpiring']}}},
{id:'ownerless',title:'Which important objects have no owner?',copy:'Applications, enterprise apps, or groups currently marked ownerless.',evaluate:()=>{const matches=signalTargets(['ownerlessObject']).filter(x=>x.node&&['application','servicePrincipal','group'].includes(x.node.Kind));return{count:matches.length,unit:'object(s)',examples:matches.slice(0,3).map(x=>x.node.DisplayName||x.node.Id),focus:matches[0]&&matches[0].node,signalTypes:['ownerlessObject']}}},
{id:'disabledOwners',title:'Do disabled identities still own objects?',copy:'Ownership relationships where the owning identity is disabled.',evaluate:()=>{const matches=signalTargets(['disabledOwnerRelationship']).filter(x=>x.edge);return{count:matches.length,unit:'relationship(s)',examples:matches.slice(0,3).map(x=>`${nodeName(x.edge.From)} → ${nodeName(x.edge.To)}`),focus:matches[0]&&matches[0].edge,signalTypes:['disabledOwnerRelationship']}}},
{id:'privilegedRoles',title:'Who currently holds privileged directory roles?',copy:'Principals connected to high-privilege directory role assignments.',evaluate:()=>{const matches=signalTargets(['highPrivilegeRoleAssignment']).filter(x=>x.edge);const principals=uniqueNodesFromMatches(matches,m=>[byKey.get(m.edge.From)]);return{count:principals.length,unit:'principal(s)',examples:principals.slice(0,3).map(n=>n.DisplayName||n.Id),focus:matches[0]&&matches[0].edge,signalTypes:['highPrivilegeRoleAssignment','privilegedIdentity']}}},
{id:'riskyIdentities',title:'Which identities are currently risky?',copy:'Users or workload identities carrying risk context in the collected topology.',evaluate:()=>{const matches=signalTargets(['riskyIdentity']);return{count:matches.length,unit:'identity(ies)',examples:matches.slice(0,3).map(x=>x.node?(x.node.DisplayName||x.node.Id):x.signal.TargetKey),focus:matches[0]&&matches[0].node,signalTypes:['riskyIdentity','riskyOwnerRelationship']}}},
{id:'staleDevices',title:'Which devices appear stale?',copy:'Devices marked stale by the current security-context rules.',evaluate:()=>{const matches=signalTargets(['staleDevice']);return{count:matches.length,unit:'device(s)',examples:matches.slice(0,3).map(x=>x.node?(x.node.DisplayName||x.node.Id):x.signal.TargetKey),focus:matches[0]&&matches[0].node,signalTypes:['staleDevice']}}}
]}
function exploreQuestion(result){if(!result)return;signalSeverity.value='';signalTargetType.value='';if(result.signalTypes&&result.signalTypes.length===1)signalType.value=result.signalTypes[0];else signalType.value='';signalSearch.value='';renderSignalsTable(result.signalTypes||[]);const focus=result.focus;if(focus){if(focus.Relationship){selectedKey=focus.From;renderObjectList();renderTopology(focus.From);selectEdge(focus)}else if(focus.Key)selectNode(focus.Key)}$('topology-section').scrollIntoView({behavior:'smooth',block:'start'})}
function renderQuickAnswers(){const host=$('questionGrid');host.replaceChildren();for(const q of quickQuestionDefinitions()){const result=q.evaluate(),card=el('article',null,'question-card');card.append(el('h3',q.title));const answer=el('div',null,'question-answer');answer.append(el('span',String(result.count),'question-count'),el('span',result.unit,'question-copy'));card.append(answer,el('div',q.copy,'question-copy'),el('div',result.examples&&result.examples.length?result.examples.join(' · '):'No matching objects in this run.','question-examples'));const actions=el('div',null,'question-actions');const b=button('Explore',()=>exploreQuestion(result));if(!result.count)b.disabled=true;actions.append(b);card.append(actions);host.append(card)}}

function renderRuntimeAndDiagnostics(){
  const host=$('runtimeMetrics');host.replaceChildren();const artifacts=(data.Metadata&&data.Metadata.Artifacts)||{},execution=(data.Metadata&&data.Metadata.Execution)||{};const cards=[['Runtime',runtime.DurationMs!==undefined?`${(Number(runtime.DurationMs)/1000).toFixed(2)}s`:'—'],['Logical Graph calls',runtime.GraphLogicalRequests??'—'],['HTTP Graph calls',runtime.GraphHttpRequests??'—'],['Batching efficiency',runtime.BatchingEfficiency!==undefined?`${runtime.BatchingEfficiency}x`:'—'],['Retries',runtime.Retries??0],['Throttles',runtime.Throttles??0],['After snapshot',(data.Metadata&&data.Metadata.GraphCallsAfterSnapshot)??'—'],['Auth type',execution.AuthType||'—'],['Snapshot size',artifacts.SnapshotBytes?`${(artifacts.SnapshotBytes/1024).toFixed(1)} KB`:'—'],['Graph size',artifacts.GraphBytes?`${(artifacts.GraphBytes/1024).toFixed(1)} KB`:'—']];for(const [l,v] of cards){const c=el('div',null,'runtime-card');c.append(el('strong',v),el('span',l));host.append(c)}
  const st=el('table'),sh=el('thead'),shr=el('tr');for(const h of ['Stage','Status','Duration','Message'])shr.append(el('th',h));sh.append(shr);st.append(sh);const sb=el('tbody');for(const [name,value] of Object.entries(runtime.Stages||{})){const r=el('tr');r.append(el('td',name),el('td',value.Status||'—'),el('td',value.DurationMs!==undefined?`${value.DurationMs} ms`:'—'),el('td',value.Message||'—'));sb.append(r)}st.append(sb);$('stageTable').replaceChildren(st);
  $('diagnosticCount').textContent=`${diagnostics.length} event(s)`;const dt=el('table'),dh=el('thead'),dhr=el('tr');for(const h of ['UTC','Level','Stage','Event','Message'])dhr.append(el('th',h));dh.append(dhr);dt.append(dh);const db=el('tbody');for(const d of diagnostics.slice(-100)){const r=el('tr');r.append(el('td',d.TimestampUtc||'—'),el('td',d.Level||'Info'),el('td',d.Stage||'—'),el('td',d.Event||'—'),el('td',d.Message||'—'));db.append(r)}dt.append(db);$('diagnosticsTable').replaceChildren(dt);
}
function renderEvidenceTable(){
  const q=(evidenceSearch.value||'').trim().toLowerCase(),c=evidenceCompleteness.value;const rows=evidence.filter(ev=>{const text=`${ev.Collector||''} ${ev.Endpoint||''} ${ev.SourceObjectId||''} ${ev.Completeness||''}`.toLowerCase();return(!c||ev.Completeness===c)&&(!q||text.includes(q))}).slice(0,1000);
  $('evidenceCount').textContent=`${rows.length} of ${evidence.length} record(s)`;const t=el('table'),h=el('thead'),hr=el('tr');for(const x of ['Collector','Endpoint','Completeness','Source','Observed'])hr.append(el('th',x));h.append(hr);t.append(h);const b=el('tbody');for(const ev of rows){const r=el('tr'),status=el('td');appendPill(status,ev.Completeness||'—',statusClass(ev.Completeness));r.append(el('td',ev.Collector||'—'),el('td',ev.Endpoint||'—'),status,el('td',ev.SourceObjectId||'—'),el('td',ev.ObservedAtUtc||'—'));b.append(r)}t.append(b);$('evidenceTable').replaceChildren(t);
}

function renderCoverageTable(){
  const host=$('coverageTable'),table=el('table'),thead=el('thead'),tr=el('tr');for(const h of ['Collector','Status','Permissions','Warnings'])tr.append(el('th',h));thead.append(tr);table.append(thead);const body=el('tbody');
  for(const c of coverage){const r=el('tr');r.append(el('td',display(c.Collector)));const status=el('td');appendPill(status,display(c.Status),statusClass(c.Status));r.append(status,el('td',display(c.RequiredPermissions||[])),el('td',display(c.Warnings||[])));body.append(r)}
  if(!coverage.length){const r=el('tr'),c=el('td','No coverage metadata was supplied.');c.colSpan=5;r.append(c);body.append(r)}
  table.append(body);host.replaceChildren(table);
}

$('search').addEventListener('input',renderObjectList);
kindSelect.addEventListener('change',renderObjectList);
enterpriseSelect.addEventListener('change',()=>{renderObjectList();const selected=byKey.get(selectedKey);if(selected&&selected.Kind==='servicePrincipal'&&!enterpriseCategoryMatches(selected)){const first=filteredNodes()[0];if(first){selectNode(first.Key);return}}if(selectedKey)renderTopology(selectedKey)});
relationshipSelect.addEventListener('change',()=>{if(selectedKey)renderTopology(selectedKey)});
for(const control of [signalSearch,signalSeverity,signalType,signalTargetType])control.addEventListener(control.tagName==='INPUT'?'input':'change',()=>renderSignalsTable());
for(const control of [evidenceSearch,evidenceCompleteness])control.addEventListener(control.tagName==='INPUT'?'input':'change',renderEvidenceTable);
setupTheme();renderHeader();renderMetrics();renderQuickAnswers();renderComposition();renderSignalsTable();renderCoverageTable();renderRuntimeAndDiagnostics();renderEvidenceTable();renderObjectList();if(nodes.length)selectNode(nodes[0].Key,false);
})();
</script>
</body>
</html>
'@

    $values = @{
        '__TITLE__' = $safeTitle
        '__GENERATED__' = $generated
        '__GRAPH_JSON__' = $json
    }
    return [regex]::Replace($html, '__TITLE__|__GENERATED__|__GRAPH_JSON__', { param($match) $values[$match.Value] })
}

