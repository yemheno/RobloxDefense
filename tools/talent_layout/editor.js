/* Talent tree v3 edge editor — reads DATA from layout_b.js, edits edges and
   node positions, exports a diff (talent_edits.json) for Claude to apply. */
"use strict";

const SVGNS = "http://www.w3.org/2000/svg";
const LS_KEY = "talent_editor_state_v1";
const svg = document.getElementById("svg");
const world = document.getElementById("world");
const edgeLayer = document.getElementById("edgeLayer");
const nodeLayer = document.getElementById("nodeLayer");
const labelLayer = document.getElementById("labelLayer");
const tooltip = document.getElementById("tooltip");

const nodesById = {};
DATA.nodes.forEach(n => { nodesById[n.id] = n; });

const baselineEdges = DATA.edges.map(e => [...e]);
const baselinePos = {};
DATA.nodes.forEach(n => { baselinePos[n.id] = [n.x, n.y]; });

let edges = DATA.edges.map(e => [...e]);       // live edge list [a, b]
let pos = {};                                   // live positions {id: [x, y]}
DATA.nodes.forEach(n => { pos[n.id] = [n.x, n.y]; });

let selected = null;
let undoStack = [];
let view = { x: 0, y: 0, k: 12 };               // pan (screen px) + zoom (px per unit)

const key = (a, b) => (a < b ? a + "|" + b : b + "|" + a);

/* ── persistence ────────────────────────────────────────────────────────── */
function saveLocal() {
  const moved = {};
  for (const id in pos) {
    const [x, y] = pos[id], [bx, by] = baselinePos[id];
    if (Math.abs(x - bx) > 1e-6 || Math.abs(y - by) > 1e-6) moved[id] = [x, y];
  }
  localStorage.setItem(LS_KEY, JSON.stringify({ edges, moved }));
  document.getElementById("autosave").textContent =
    "autosaved " + new Date().toLocaleTimeString();
}
function loadLocal() {
  try {
    const s = JSON.parse(localStorage.getItem(LS_KEY));
    if (!s || !Array.isArray(s.edges)) return false;
    if (s.edges.some(e => !nodesById[e[0]] || !nodesById[e[1]])) return false;
    edges = s.edges.map(e => [...e]);
    for (const id in (s.moved || {})) if (pos[id]) pos[id] = [...s.moved[id]];
    return true;
  } catch (e) { return false; }
}

/* ── undo ───────────────────────────────────────────────────────────────── */
function snapshot() {
  undoStack.push(JSON.stringify({ edges, pos }));
  if (undoStack.length > 200) undoStack.shift();
}
function undo() {
  const s = undoStack.pop();
  if (!s) return;
  const st = JSON.parse(s);
  edges = st.edges; pos = st.pos;
  selected = null;
  render(); saveLocal();
}

/* ── rendering ──────────────────────────────────────────────────────────── */
function degreeMap() {
  const d = {};
  edges.forEach(([a, b]) => { d[a] = (d[a] || 0) + 1; d[b] = (d[b] || 0) + 1; });
  return d;
}
function applyView() {
  world.setAttribute("transform",
    `translate(${view.x},${view.y}) scale(${view.k})`);
  labelLayer.style.display = view.k >= 14 ? "" : "none";
  document.getElementById("stZoom").textContent =
    "zoom " + Math.round(view.k * 100 / 12) + "%";
}
function render() {
  edgeLayer.textContent = ""; nodeLayer.textContent = ""; labelLayer.textContent = "";
  const baseSet = new Set(baselineEdges.map(e => key(e[0], e[1])));
  edges.forEach(([a, b], i) => {
    const l = document.createElementNS(SVGNS, "line");
    const [x1, y1] = pos[a], [x2, y2] = pos[b];
    l.setAttribute("x1", x1); l.setAttribute("y1", y1);
    l.setAttribute("x2", x2); l.setAttribute("y2", y2);
    let cls = "edge";
    if (a !== "start" && b !== "start" &&
        nodesById[a].branch !== nodesById[b].branch) cls += " xbranch";
    if (!baseSet.has(key(a, b))) cls += " new";
    l.setAttribute("class", cls);
    l.addEventListener("click", ev => {
      ev.stopPropagation();
      snapshot(); edges.splice(i, 1); render(); saveLocal();
      setStatus(`removed ${a} — ${b}`);
    });
    edgeLayer.appendChild(l);
  });
  const deg = degreeMap();
  DATA.nodes.forEach(n => {
    const [x, y] = pos[n.id];
    let el;
    if (n.type === "keystone") {
      el = document.createElementNS(SVGNS, "rect");
      const s = 1.3;
      el.setAttribute("x", -s / 2); el.setAttribute("y", -s / 2);
      el.setAttribute("width", s); el.setAttribute("height", s);
      el.setAttribute("transform", `translate(${x},${y}) rotate(45)`);
    } else {
      el = document.createElementNS(SVGNS, "circle");
      el.setAttribute("cx", x); el.setAttribute("cy", y);
      el.setAttribute("r", n.type === "origin" ? 0.95
                        : n.type === "notable" ? 0.62 : 0.42);
    }
    el.setAttribute("fill", n.color);
    let cls = "node";
    if (n.id === selected) cls += " selected";
    if (n.id !== "start" && (deg[n.id] || 0) > 4) cls += " overdeg";
    if (n.id !== "start" && !(deg[n.id] > 0)) cls += " orphan";
    el.setAttribute("class", cls);
    el.dataset.id = n.id;
    wireNode(el, n);
    nodeLayer.appendChild(el);
    if (n.id !== "start") {
      const t = document.createElementNS(SVGNS, "text");
      t.setAttribute("x", x + 0.55); t.setAttribute("y", y + 0.9);
      t.setAttribute("class", "nodelabel");
      t.textContent = n.id;
      labelLayer.appendChild(t);
    }
  });
  updateStatus();
  applyView();
}
function setStatus(msg) { document.getElementById("stSel").textContent = msg; }
function updateStatus() {
  const baseSet = new Set(baselineEdges.map(e => key(e[0], e[1])));
  const curSet = new Set(edges.map(e => key(e[0], e[1])));
  let added = 0, removed = 0;
  curSet.forEach(k => { if (!baseSet.has(k)) added++; });
  baseSet.forEach(k => { if (!curSet.has(k)) removed++; });
  const moved = Object.keys(pos).filter(id => {
    const [x, y] = pos[id], [bx, by] = baselinePos[id];
    return Math.abs(x - bx) > 1e-6 || Math.abs(y - by) > 1e-6;
  }).length;
  document.getElementById("stCounts").textContent =
    `${edges.length} edges · ${DATA.nodes.length} nodes`;
  document.getElementById("stDiff").innerHTML =
    `<span class="add">+${added} added</span> · ` +
    `<span class="rem">−${removed} removed</span> · ${moved} moved`;
}

/* ── node interaction (click = select/connect, drag = move) ─────────────── */
function wireNode(el, n) {
  el.addEventListener("mousedown", ev => {
    ev.stopPropagation();
    const start = { mx: ev.clientX, my: ev.clientY, px: [...pos[n.id]] };
    let dragging = false;
    const move = e2 => {
      const dx = (e2.clientX - start.mx), dy = (e2.clientY - start.my);
      if (!dragging && Math.hypot(dx, dy) > 4) { dragging = true; snapshot(); }
      if (dragging) {
        pos[n.id] = [start.px[0] + dx / view.k, start.px[1] + dy / view.k];
        render();
      }
    };
    const up = () => {
      window.removeEventListener("mousemove", move);
      window.removeEventListener("mouseup", up);
      if (dragging) { saveLocal(); setStatus(`moved ${n.id}`); return; }
      onNodeClick(n.id);
    };
    window.addEventListener("mousemove", move);
    window.addEventListener("mouseup", up);
  });
  el.addEventListener("mouseenter", ev => {
    tooltip.style.display = "block";
    tooltip.innerHTML = `<div class="nm">${n.name}</div>` +
      `<div class="meta">${n.id} · ${n.branch} · ${n.type}</div>`;
  });
  el.addEventListener("mousemove", ev => {
    tooltip.style.left = (ev.clientX + 14) + "px";
    tooltip.style.top = (ev.clientY + 10) + "px";
  });
  el.addEventListener("mouseleave", () => { tooltip.style.display = "none"; });
}
function onNodeClick(id) {
  if (selected === null || selected === id) {
    selected = (selected === id) ? null : id;
    render();
    setStatus(selected ? `selected ${selected} — click another node to connect`
                       : "");
    return;
  }
  const a = selected, b = id;
  const i = edges.findIndex(e => key(e[0], e[1]) === key(a, b));
  snapshot();
  if (i >= 0) { edges.splice(i, 1); setStatus(`removed ${a} — ${b}`); }
  else { edges.push([a, b]); setStatus(`connected ${a} — ${b}`); }
  selected = b;                       // chain
  render(); saveLocal();
}

/* ── pan / zoom ─────────────────────────────────────────────────────────── */
svg.addEventListener("mousedown", ev => {
  const start = { mx: ev.clientX, my: ev.clientY, vx: view.x, vy: view.y };
  let moved2 = false;
  svg.classList.add("panning");
  const move = e2 => {
    moved2 = true;
    view.x = start.vx + e2.clientX - start.mx;
    view.y = start.vy + e2.clientY - start.my;
    applyView();
  };
  const up = () => {
    svg.classList.remove("panning");
    window.removeEventListener("mousemove", move);
    window.removeEventListener("mouseup", up);
    if (!moved2 && selected) { selected = null; render(); setStatus(""); }
  };
  window.addEventListener("mousemove", move);
  window.addEventListener("mouseup", up);
});
svg.addEventListener("wheel", ev => {
  ev.preventDefault();
  const f = ev.deltaY < 0 ? 1.15 : 1 / 1.15;
  const k2 = Math.min(80, Math.max(4, view.k * f));
  const r = svg.getBoundingClientRect();
  const cx = ev.clientX - r.left, cy = ev.clientY - r.top;
  view.x = cx - (cx - view.x) * (k2 / view.k);
  view.y = cy - (cy - view.y) * (k2 / view.k);
  view.k = k2;
  applyView();
}, { passive: false });

function fitView() {
  const r = svg.getBoundingClientRect();
  let minX = 1e9, maxX = -1e9, minY = 1e9, maxY = -1e9;
  for (const id in pos) {
    minX = Math.min(minX, pos[id][0]); maxX = Math.max(maxX, pos[id][0]);
    minY = Math.min(minY, pos[id][1]); maxY = Math.max(maxY, pos[id][1]);
  }
  const k = Math.min(r.width / (maxX - minX + 8), r.height / (maxY - minY + 8));
  view.k = k;
  view.x = r.width / 2 - k * (minX + maxX) / 2;
  view.y = r.height / 2 - k * (minY + maxY) / 2;
  applyView();
}

/* ── export / import / reset ────────────────────────────────────────────── */
function exportJson() {
  const baseSet = new Set(baselineEdges.map(e => key(e[0], e[1])));
  const curSet = new Set(edges.map(e => key(e[0], e[1])));
  const added = edges.filter(e => !baseSet.has(key(e[0], e[1])));
  const removed = baselineEdges.filter(e => !curSet.has(key(e[0], e[1])));
  const moved = {};
  for (const id in pos) {
    const [x, y] = pos[id], [bx, by] = baselinePos[id];
    if (Math.abs(x - bx) > 1e-6 || Math.abs(y - by) > 1e-6)
      moved[id] = [Math.round(x * 1000) / 1000, Math.round(y * 1000) / 1000];
  }
  const out = { format: "talent_edits_v1", edges, added, removed, moved };
  const blob = new Blob([JSON.stringify(out, null, 1)],
                        { type: "application/json" });
  const a = document.createElement("a");
  a.href = URL.createObjectURL(blob);
  a.download = "talent_edits.json";
  a.click();
  URL.revokeObjectURL(a.href);
  setStatus(`exported: +${added.length} −${removed.length}, ` +
            `${Object.keys(moved).length} moved`);
}
document.getElementById("exportBtn").addEventListener("click", exportJson);
document.getElementById("undoBtn").addEventListener("click", undo);
document.getElementById("fitBtn").addEventListener("click", fitView);
document.getElementById("resetBtn").addEventListener("click", () => {
  if (!confirm("Discard ALL edits and return to the generated baseline?")) return;
  snapshot();
  edges = baselineEdges.map(e => [...e]);
  pos = {};
  DATA.nodes.forEach(n => { pos[n.id] = [...baselinePos[n.id]]; });
  localStorage.removeItem(LS_KEY);
  selected = null;
  render(); setStatus("reset to baseline");
});
document.getElementById("importBtn").addEventListener("click",
  () => document.getElementById("importFile").click());
document.getElementById("importFile").addEventListener("change", ev => {
  const file = ev.target.files[0];
  if (!file) return;
  file.text().then(txt => {
    const s = JSON.parse(txt);
    if (!Array.isArray(s.edges)) throw new Error("bad file");
    snapshot();
    edges = s.edges.map(e => [...e]);
    for (const id in (s.moved || {})) if (pos[id]) pos[id] = [...s.moved[id]];
    render(); saveLocal(); setStatus("imported " + file.name);
  }).catch(() => alert("Could not read that file as talent edits JSON."));
  ev.target.value = "";
});
window.addEventListener("keydown", ev => {
  if (ev.key === "Escape") { selected = null; render(); setStatus(""); }
  if ((ev.ctrlKey || ev.metaKey) && ev.key.toLowerCase() === "z") {
    ev.preventDefault(); undo();
  }
});

/* ── boot ───────────────────────────────────────────────────────────────── */
if (loadLocal()) setStatus("restored autosaved session (Reset to discard)");
render();
fitView();
