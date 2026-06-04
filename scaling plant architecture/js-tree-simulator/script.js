/* =============================================================
   Tree Architecture Simulator – script.js
   WBE-aware branching simulator with allometric diagnostics.
   ============================================================= */

// ── WBE optimal values (binary bifurcation, n = 2) ───────────
// radius decay = 2^(-1/2) ≈ 0.707  [area-preserving]
// length decay = 2^(-1/3) ≈ 0.794  [volume-filling]
// symmetric branching: pathFraction = 0.5, asymStrength = 0
const WBE = {
  pathFraction: 0.50,
  asymStrength:  0.00,
  lengthDecay:   0.794,
  radiusDecay:   0.707,
  branchProb:    1.00,
  maxDepth:      10,
  minTips:       16,
  maxTips:       128,
  classCount:    4,
  seed:          42
};

// ── UI references ─────────────────────────────────────────────
const UI = {
  pathFraction:      document.getElementById("pathFraction"),
  pathFractionValue: document.getElementById("pathFractionValue"),
  asymStrength:      document.getElementById("asymStrength"),
  asymStrengthValue: document.getElementById("asymStrengthValue"),
  lengthDecay:       document.getElementById("lengthDecay"),
  lengthDecayValue:  document.getElementById("lengthDecayValue"),
  radiusDecay:       document.getElementById("radiusDecay"),
  radiusDecayValue:  document.getElementById("radiusDecayValue"),
  branchProb:        document.getElementById("branchProb"),
  branchProbValue:   document.getElementById("branchProbValue"),
  maxDepth:          document.getElementById("maxDepth"),
  maxDepthValue:     document.getElementById("maxDepthValue"),
  minTips:           document.getElementById("minTips"),
  minTipsValue:      document.getElementById("minTipsValue"),
  maxTips:           document.getElementById("maxTips"),
  maxTipsValue:      document.getElementById("maxTipsValue"),
  classCount:        document.getElementById("classCount"),
  classCountValue:   document.getElementById("classCountValue"),
  seed:              document.getElementById("seed"),
  seedValue:         document.getElementById("seedValue"),
  sizeClassPreview:  document.getElementById("sizeClassPreview"),
  generateBtn:       document.getElementById("generateBtn"),
  wbeSnapBtn:        document.getElementById("wbeSnapBtn"),
  treeSvg:           document.getElementById("treeSvg"),
  treeMeta:          document.getElementById("treeMeta"),
  sizeClassCards:    document.getElementById("sizeClassCards"),
  withinHist:        document.getElementById("withinHist"),
  acrossHist:        document.getElementById("acrossHist"),
  alloStemVol:       document.getElementById("alloStemVol"),
  alloHeight:        document.getElementById("alloHeight"),
  alloMaxPath:       document.getElementById("alloMaxPath"),
  alloMeanPath:      document.getElementById("alloMeanPath"),
  alloTotalLen:      document.getElementById("alloTotalLen"),
  alloPF:            document.getElementById("alloPF"),
  alloStemVol2:      document.getElementById("alloStemVol2"),
  alloHeight2:       document.getElementById("alloHeight2"),
  alloMaxPath2:      document.getElementById("alloMaxPath2"),
  alloMeanPath2:     document.getElementById("alloMeanPath2"),
  alloTotalLen2:     document.getElementById("alloTotalLen2"),
  alloPF2:           document.getElementById("alloPF2")
};

const state = {
  classes:       [],
  selectedIndex: 0,
  alloPoints:    []
};

// ── RNG utilities ─────────────────────────────────────────────
function mulberry32(seed) {
  let t = seed >>> 0;
  return function () {
    t += 0x6D2B79F5;
    let r = Math.imul(t ^ (t >>> 15), 1 | t);
    r ^= r + Math.imul(r ^ (r >>> 7), 61 | r);
    return ((r ^ (r >>> 14)) >>> 0) / 4294967296;
  };
}

function randNorm(rand, mean, sd) {
  const u1 = Math.max(rand(), 1e-12);
  const u2 = rand();
  return mean + sd * Math.sqrt(-2 * Math.log(u1)) * Math.cos(2 * Math.PI * u2);
}

function randBetaApprox(rand, alpha, beta) {
  const x = Math.pow(rand(), 1 / alpha);
  const y = Math.pow(rand(), 1 / beta);
  return x / (x + y);
}

// ── Inputs & slider sync ──────────────────────────────────────
function buildSizeClasses(minTips, maxTips, count) {
  const mn = Math.max(2, Math.round(minTips));
  const mx = Math.max(mn, Math.round(maxTips));
  const n  = Math.max(2, Math.round(count));
  const cls = [];
  for (let i = 0; i < n; i++) {
    const t = i / (n - 1);
    cls.push(Math.max(2, Math.round(mn * Math.pow(mx / mn, t))));
  }
  return [...new Set(cls)].sort((a, b) => a - b);
}

function getInputs() {
  const minTips    = Number(UI.minTips.value);
  const maxTips    = Number(UI.maxTips.value);
  const classCount = Number(UI.classCount.value);
  return {
    pathFraction: Number(UI.pathFraction.value),
    asymStrength:  Number(UI.asymStrength.value),
    lengthDecay:   Number(UI.lengthDecay.value),
    radiusDecay:   Number(UI.radiusDecay.value),
    branchProb:    Number(UI.branchProb.value),
    maxDepth:      Math.round(Number(UI.maxDepth.value)),
    minTips, maxTips, classCount,
    sizeClasses:   buildSizeClasses(minTips, maxTips, classCount),
    seed:          Math.round(Number(UI.seed.value))
  };
}

function syncSliderOutputs() {
  UI.pathFractionValue.value = Number(UI.pathFraction.value).toFixed(2);
  UI.asymStrengthValue.value  = Number(UI.asymStrength.value).toFixed(2);
  UI.lengthDecayValue.value   = Number(UI.lengthDecay.value).toFixed(2);
  UI.radiusDecayValue.value   = Number(UI.radiusDecay.value).toFixed(2);
  UI.branchProbValue.value    = Number(UI.branchProb.value).toFixed(2);
  UI.maxDepthValue.value      = String(Math.round(Number(UI.maxDepth.value)));
  UI.seedValue.value          = String(Math.round(Number(UI.seed.value)));
  let mn = Math.round(Number(UI.minTips.value));
  let mx = Math.round(Number(UI.maxTips.value));
  if (mn > mx) { mx = mn; UI.maxTips.value = String(mx); }
  UI.minTipsValue.value    = String(mn);
  UI.maxTipsValue.value    = String(mx);
  UI.classCountValue.value = String(Math.round(Number(UI.classCount.value)));
  const preview = buildSizeClasses(mn, mx, Number(UI.classCount.value));
  UI.sizeClassPreview.textContent = `Classes: ${preview.join(", ")}`;
}

// ── WBE tick markers (orange vertical line on slider track) ───
function positionWbeTicks() {
  document.querySelectorAll(".slider-wrap[data-wbe]").forEach(wrap => {
    const wbeVal = parseFloat(wrap.dataset.wbe);
    const minVal = parseFloat(wrap.dataset.min);
    const maxVal = parseFloat(wrap.dataset.max);
    const tick   = wrap.querySelector(".wbe-tick");
    if (!tick || isNaN(wbeVal) || isNaN(minVal) || isNaN(maxVal)) return;
    const pct = ((wbeVal - minVal) / (maxVal - minVal)) * 100;
    // Clamp to valid range
    tick.style.left = `calc(${Math.min(100, Math.max(0, pct)).toFixed(2)}% - 1px)`;
  });
}

// ── WBE snap ──────────────────────────────────────────────────
function snapToWbe() {
  UI.pathFraction.value = String(WBE.pathFraction);
  UI.asymStrength.value  = String(WBE.asymStrength);
  UI.lengthDecay.value   = String(WBE.lengthDecay);
  UI.radiusDecay.value   = String(WBE.radiusDecay);
  UI.branchProb.value    = String(WBE.branchProb);
  UI.maxDepth.value      = String(WBE.maxDepth);
  syncSliderOutputs();
}

// ── Tree simulation ───────────────────────────────────────────
function simulateTree(params, targetTips, seedOffset) {
  const rand = mulberry32(((params.seed + (seedOffset | 0)) >>> 0));
  const baseLength = Number.isFinite(params.baseLength) ? params.baseLength : 1;
  const baseRadius = Number.isFinite(params.baseRadius) ? params.baseRadius : 0.1;

  const nodes = [{ id: 1, x: 0, y: 0, depth: 0 }];
  const edges = [];
  let nextId  = 2;

  // Enforce single trunk (no base furcation)
  const trunkAngle  = 90 + randNorm(rand, 0, 3);
  const trunkLen    = baseLength;
  const trunkRad    = baseRadius;
  const tn = {
    id: nextId++,
    x: trunkLen * Math.cos(trunkAngle * Math.PI / 180),
    y: trunkLen * Math.sin(trunkAngle * Math.PI / 180),
    depth: 1
  };
  nodes.push(tn);
  edges.push({ from: 1, to: tn.id, depth: 1, length: trunkLen, radius: trunkRad, angle: trunkAngle, isMain: true });

  const frontier = [{
    nodeId: tn.id, depth: 2, angle: trunkAngle,
    length: trunkLen * params.lengthDecay,
    radius: trunkRad * params.radiusDecay,
    mainSteps: 1, steps: 1
  }];

  while (frontier.length > 0) {
    if (countTips(edges) >= targetTips) break;
    const cur = frontier.shift();
    if (cur.depth > params.maxDepth) continue;
    if (rand() > params.branchProb && cur.depth > 2) continue;

    const u     = randBetaApprox(rand, 2.5, 2.5);
    const pMain = (1 - params.asymStrength) * 0.5 + params.asymStrength * (params.pathFraction * 0.7 + 0.3 * u);
    const skew  = (pMain - 0.5) * 2;

    const mainLen = Math.max(cur.length * (1 + 0.35 * skew), 1e-4);
    const sideLen = Math.max(cur.length * (1 - 0.35 * skew), 1e-4);
    const mainRad = Math.max(cur.radius * (1 + 0.22 * skew), 1e-4);
    const sideRad = Math.max(cur.radius * (1 - 0.22 * skew), 1e-4);

    const mainAngle = cur.angle + randNorm(rand, 0, 4);
    const sideSign  = rand() < 0.5 ? -1 : 1;
    const sideAngle = cur.angle + sideSign * (34 + randNorm(rand, 0, 9));

    const parent = nodes.find(n => n.id === cur.nodeId);
    if (!parent) continue;

    const mn2 = { id: nextId++, x: parent.x + mainLen * Math.cos(mainAngle * Math.PI / 180), y: parent.y + mainLen * Math.sin(mainAngle * Math.PI / 180), depth: cur.depth };
    const sn  = { id: nextId++, x: parent.x + sideLen * Math.cos(sideAngle * Math.PI / 180), y: parent.y + sideLen * Math.sin(sideAngle * Math.PI / 180), depth: cur.depth };
    nodes.push(mn2, sn);
    edges.push({ from: parent.id, to: mn2.id, depth: cur.depth, length: mainLen, radius: mainRad, angle: mainAngle, isMain: true });
    edges.push({ from: parent.id, to: sn.id,  depth: cur.depth, length: sideLen, radius: sideRad, angle: sideAngle, isMain: false });

    frontier.push({ nodeId: mn2.id, depth: cur.depth + 1, angle: mainAngle, length: mainLen * params.lengthDecay, radius: mainRad * params.radiusDecay, mainSteps: cur.mainSteps + 1, steps: cur.steps + 1 });
    frontier.push({ nodeId: sn.id,  depth: cur.depth + 1, angle: sideAngle, length: sideLen * params.lengthDecay, radius: sideRad * params.radiusDecay, mainSteps: cur.mainSteps, steps: cur.steps + 1 });
  }

  const pathStats = computePathStats(nodes, edges);
  return { nodes, edges, pathStats, targetTips };
}

function countTips(edges) {
  if (!edges.length) return 0;
  const from = new Set(edges.map(e => e.from));
  const to   = new Set(edges.map(e => e.to));
  let tips = 0;
  to.forEach(id => { if (!from.has(id)) tips++; });
  return tips;
}

function computePathStats(nodes, edges) {
  const childMap = new Map();
  for (const e of edges) {
    if (!childMap.has(e.from)) childMap.set(e.from, []);
    childMap.get(e.from).push(e);
  }
  const tips = [];
  function dfs(nodeId, pathLen, mainSteps, steps) {
    const children = childMap.get(nodeId) || [];
    if (children.length === 0 && nodeId !== 1) {
      tips.push({ nodeId, pathLength: pathLen, pathFraction: steps > 0 ? mainSteps / steps : 0 });
      return;
    }
    for (const e of children) dfs(e.to, pathLen + e.length, mainSteps + (e.isMain ? 1 : 0), steps + 1);
  }
  dfs(1, 0, 0, 0);
  return tips;
}

// ── Tree metrics for allometry plots ──────────────────────────
// Returns per-tree summary for scatter plotting.
// All quantities > 0 so log-log plots are safe (except meanPathFrac).
function computeTreeMetrics(tree, sizeIdx) {
  const { nodes, edges, pathStats } = tree;

  // Structural volumes and lengths
  const networkVolume = edges.reduce((s, e) => s + Math.PI * e.radius * e.radius * e.length, 0);
  const totalStemLen = edges.reduce((s, e) => s + e.length, 0);
  const trunkRadius   = edges.length > 0 ? edges[0].radius : 1e-6;
  const trunkDiameter = Math.max(1e-6, 2 * trunkRadius);
  const trunkLength   = edges.length > 0 ? edges[0].length : 1e-6;
  const stemVolume    = Math.PI * trunkRadius * trunkRadius * trunkLength;
  const leafCount     = Math.max(1, pathStats.length);
  const totalBiomass  = networkVolume + 0.02 * leafCount;

  // Height: vertical extent of crown
  const ys    = nodes.map(n => n.y);
  const height = Math.max(1e-6, Math.max(...ys) - Math.min(...ys));

  // Path lengths
  const pathLens   = pathStats.map(p => p.pathLength);
  const nTips      = leafCount;
  const maxPathLen = pathLens.length ? Math.max(...pathLens) : 1e-6;
  const meanPathLen = pathLens.length ? pathLens.reduce((s, v) => s + v, 0) / pathLens.length : 1e-6;

  // Mean path fraction (bounded 0–1; use linear scale in plots)
  const meanPathFrac = pathStats.reduce((s, p) => s + p.pathFraction, 0) / nTips;

  return {
    nTips,
    leafCount,
    trunkDiameter,
    trunkRadius,
    stemVolume,
    networkVolume,
    totalBiomass,
    totalStemLen,
    height,
    maxPathLen,
    meanPathLen,
    meanPathFrac,
    targetTips: tree.targetTips,
    sizeIdx: sizeIdx || 0
  };
}

// Build allometry dataset: 12 log-spaced size classes × 4 replicates
function buildAllometryPoints(params) {
  const minT = Math.max(4, params.minTips);
  const maxT = Math.min(512, params.maxTips * 3);
  const nCls = 12;
  const reps = 4;
  const pts  = [];

  for (let i = 0; i < nCls; i++) {
    const t      = i / (nCls - 1);
    const target = Math.max(4, Math.round(minT * Math.pow(maxT / minT, t)));
    const sizeFactor = target / minT;
    const scaledParams = {
      ...params,
      baseLength: (Number.isFinite(params.baseLength) ? params.baseLength : 1) * Math.pow(sizeFactor, 1 / 3),
      baseRadius: (Number.isFinite(params.baseRadius) ? params.baseRadius : 0.1) * Math.pow(sizeFactor, 1 / 2)
    };
    for (let rep = 0; rep < reps; rep++) {
      const tree = simulateTree(scaledParams, target, rep * 137 + i * 23);
      pts.push(computeTreeMetrics(tree, i));
    }
  }
  return pts;
}

// ── Tree drawing ──────────────────────────────────────────────
function fitToBox(points, width, height, pad) {
  const xs = points.map(p => p.x);
  const ys = points.map(p => p.y);
  const minX = Math.min(...xs), maxX = Math.max(...xs);
  const minY = Math.min(...ys), maxY = Math.max(...ys);
  const s = Math.min(
    (width  - pad * 2) / Math.max(maxX - minX, 1e-9),
    (height - pad * 2) / Math.max(maxY - minY, 1e-9)
  );
  return {
    tx: x => pad + (x - minX) * s,
    ty: y => height - (pad + (y - minY) * s)
  };
}

function drawTreeSvg(svg, tree) {
  svg.innerHTML = "";
  const vb = svg.viewBox.baseVal;
  const W  = vb.width  || 900;
  const H  = vb.height || 480;
  const tf = fitToBox(tree.nodes, W, H, 18);
  const nb = new Map(tree.nodes.map(n => [n.id, n]));

  for (const e of tree.edges) {
    const from = nb.get(e.from), to = nb.get(e.to);
    if (!from || !to) continue;
    const line = document.createElementNS("http://www.w3.org/2000/svg", "line");
    line.setAttribute("x1", tf.tx(from.x));
    line.setAttribute("y1", tf.ty(from.y));
    line.setAttribute("x2", tf.tx(to.x));
    line.setAttribute("y2", tf.ty(to.y));
    line.setAttribute("stroke", e.isMain ? "#1f252a" : "#7f9298");
    line.setAttribute("stroke-linecap", "round");
    line.setAttribute("stroke-width", Math.max(0.6, Math.sqrt(e.radius) * 8));
    svg.appendChild(line);
  }
}

function drawMiniTree(svgEl, tree) {
  svgEl.innerHTML = "";
  const W  = svgEl.clientWidth  || 180;
  const H  = svgEl.clientHeight || 72;
  const tf = fitToBox(tree.nodes, W, H, 6);
  const nb = new Map(tree.nodes.map(n => [n.id, n]));

  for (const e of tree.edges) {
    const from = nb.get(e.from), to = nb.get(e.to);
    if (!from || !to) continue;
    const line = document.createElementNS("http://www.w3.org/2000/svg", "line");
    line.setAttribute("x1", tf.tx(from.x));
    line.setAttribute("y1", tf.ty(from.y));
    line.setAttribute("x2", tf.tx(to.x));
    line.setAttribute("y2", tf.ty(to.y));
    line.setAttribute("stroke", e.isMain ? "#223036" : "#8ea19a");
    line.setAttribute("stroke-linecap", "round");
    line.setAttribute("stroke-width", Math.max(0.4, Math.sqrt(e.radius) * 4));
    svgEl.appendChild(line);
  }
}

// ── Path distribution charts ──────────────────────────────────
function makeHist(values, bins, lo, hi) {
  const arr = new Array(bins).fill(0);
  const bw  = (hi - lo) / bins;
  for (const v of values) {
    if (!Number.isFinite(v)) continue;
    let idx = Math.floor((v - lo) / bw);
    arr[Math.min(bins - 1, Math.max(0, idx))]++;
  }
  return arr;
}

function drawBaseAxes(ctx, cw, ch, pad, xLabel, yLabel) {
  ctx.strokeStyle = "#33404a";
  ctx.lineWidth = 1;
  ctx.beginPath();
  ctx.moveTo(pad.l, pad.t);
  ctx.lineTo(pad.l, ch - pad.b);
  ctx.lineTo(cw - pad.r, ch - pad.b);
  ctx.stroke();
  ctx.fillStyle = "#33404a";
  ctx.font = "9px sans-serif";
  ctx.textBaseline = "alphabetic";
  ctx.fillText(xLabel, cw / 2 - 16, ch - 3);
  ctx.save();
  ctx.translate(10, ch / 2 + 12);
  ctx.rotate(-Math.PI / 2);
  ctx.fillText(yLabel, 0, 0);
  ctx.restore();
}

function drawWithinHistogram(tree) {
  const canvas = UI.withinHist;
  const ctx    = canvas.getContext("2d");
  ctx.clearRect(0, 0, canvas.width, canvas.height);

  const vals   = tree.pathStats.map(d => d.pathFraction);
  const bins   = 16;
  const counts = makeHist(vals, bins, 0, 1);
  const maxC   = Math.max(...counts, 1);
  const pad    = { l: 34, r: 8, t: 10, b: 26 };
  const w      = canvas.width  - pad.l - pad.r;
  const h      = canvas.height - pad.t - pad.b;

  ctx.fillStyle = "#0d6e6e";
  for (let i = 0; i < bins; i++) {
    const bw = w / bins;
    const bh = (counts[i] / maxC) * h;
    ctx.fillRect(pad.l + i * bw + 1, pad.t + h - bh, Math.max(1, bw - 2), bh);
  }
  drawBaseAxes(ctx, canvas.width, canvas.height, pad, "Path fraction", "Freq");
}

function drawAcrossHistogram(classes) {
  const canvas = UI.acrossHist;
  const ctx    = canvas.getContext("2d");
  ctx.clearRect(0, 0, canvas.width, canvas.height);

  const bins   = 14;
  const pad    = { l: 34, r: 12, t: 10, b: 26 };
  const w      = canvas.width  - pad.l - pad.r;
  const h      = canvas.height - pad.t - pad.b;
  const colors = ["#1f252a", "#0d6e6e", "#b85c38", "#6b7c85", "#4a8f78", "#8a5c38", "#385c8a", "#8a385c"];
  const hists  = classes.map(c => makeHist(c.tree.pathStats.map(d => d.pathFraction), bins, 0, 1));
  const maxC   = Math.max(1, ...hists.flat());

  for (let ci = 0; ci < classes.length; ci++) {
    ctx.strokeStyle = colors[ci % colors.length];
    ctx.lineWidth   = 2;
    ctx.beginPath();
    hists[ci].forEach((cnt, i) => {
      const x = pad.l + ((i + 0.5) / bins) * w;
      const y = pad.t + h - (cnt / maxC) * h;
      i === 0 ? ctx.moveTo(x, y) : ctx.lineTo(x, y);
    });
    ctx.stroke();
  }

  drawBaseAxes(ctx, canvas.width, canvas.height, pad, "Path fraction", "Freq");

  ctx.font = "9px sans-serif";
  ctx.textBaseline = "middle";
  classes.forEach((c, i) => {
    const y = 9 + i * 12;
    ctx.fillStyle = colors[i % colors.length];
    ctx.fillRect(canvas.width - 122, y - 3, 9, 7);
    ctx.fillStyle = "#28343a";
    ctx.fillText(`${c.targetTips} tips`, canvas.width - 110, y);
  });
}

// ── Allometry scatter plots ───────────────────────────────────
// 12 size classes × 4 reps = 48 points; color by size class index.
const ALLO_COLORS = [
  "#1a6e5f","#2d8a78","#3faa94","#5ec8b0",
  "#1e4d8c","#2f72c4","#4a96e8","#6db8ff",
  "#8c1e3a","#c42f54","#e8547a","#ff7fa0"
];

// superscript helper for axis tick labels
function sup(n) {
  const m = { "-":"⁻","0":"⁰","1":"¹","2":"²","3":"³","4":"⁴","5":"⁵","6":"⁶","7":"⁷","8":"⁸","9":"⁹" };
  return String(n).split("").map(c => m[c] || c).join("");
}

/**
 * Draw a log-log scatter with OLS fit line and slope annotation.
 * @param {HTMLCanvasElement} canvas
 * @param {object[]}          points    array with .nTips and target yKey
 * @param {string}            xKey      field name for x axis
 * @param {string}            yKey      field name for y axis
 * @param {string}            xLabel
 * @param {string}            yLabel
 * @param {string}            title
 * @param {boolean}           linearY   if true, y axis is linear (for path fraction [0–1])
 */
function drawScatter(canvas, points, xKey, yKey, xLabel, yLabel, title, linearY, expectedSlope) {
  const ctx = canvas.getContext("2d");
  ctx.clearRect(0, 0, canvas.width, canvas.height);

  const valid = points.filter(p => p[xKey] > 0 && (linearY ? p[yKey] >= 0 : p[yKey] > 0));
  if (valid.length < 3) return;

  const pad = { l: 56, r: 14, t: 22, b: 30 };
  const cw  = canvas.width;
  const ch  = canvas.height;
  const w   = cw - pad.l - pad.r;
  const h   = ch - pad.t - pad.b;

  // Axis ranges in log/linear space
  const rawXs = valid.map(p => Math.log10(p[xKey]));
  const rawYs = linearY ? valid.map(p => p[yKey]) : valid.map(p => Math.log10(p[yKey]));

  const xMin = Math.min(...rawXs), xMax = Math.max(...rawXs);
  const yMinRaw = Math.min(...rawYs), yMaxRaw = Math.max(...rawYs);
  const xRange = Math.max(xMax - xMin, 1e-6);
  const yPad   = (yMaxRaw - yMinRaw) * 0.08;
  const yMin   = yMinRaw - yPad;
  const yMax   = yMaxRaw + yPad;
  const yRange = Math.max(yMax - yMin, 1e-6);

  const sx = lx => pad.l + ((lx - xMin) / xRange) * w;
  const sy = v  => pad.t + h - ((v  - yMin) / yRange) * h;

  // Light grid lines
  ctx.strokeStyle = "#e4ede9";
  ctx.lineWidth   = 0.7;
  for (let lx = Math.ceil(xMin); lx <= Math.floor(xMax) + 0.1; lx++) {
    const x = sx(lx);
    ctx.beginPath(); ctx.moveTo(x, pad.t); ctx.lineTo(x, pad.t + h); ctx.stroke();
  }

  // OLS slope in log space (log x always; log y if !linearY)
  const n   = valid.length;
  const mX  = rawXs.reduce((s, v) => s + v, 0) / n;
  const mY  = rawYs.reduce((s, v) => s + v, 0) / n;
  const SSxy = rawXs.reduce((s, v, i) => s + (v - mX) * (rawYs[i] - mY), 0);
  const SSxx = rawXs.reduce((s, v)    => s + (v - mX) ** 2, 0);
  const slope     = SSxx > 1e-9 ? SSxy / SSxx : 0;
  const intercept = mY - slope * mX;

  // Fit line
  ctx.strokeStyle = "#c0392b";
  ctx.lineWidth   = 1.5;
  ctx.setLineDash([5, 3]);
  ctx.beginPath();
  ctx.moveTo(sx(xMin), sy(intercept + slope * xMin));
  ctx.lineTo(sx(xMax), sy(intercept + slope * xMax));
  ctx.stroke();
  ctx.setLineDash([]);

  // Slope label: boxed so the fitted exponent stays readable on the compact canvases.
  const fitText = `fit b = ${slope.toFixed(2)}`;
  const wbeText = `WBE b = ${expectedSlope.toFixed(2)}`;
  ctx.font = "bold 11px sans-serif";
  const labelWidth = Math.max(ctx.measureText(fitText).width, ctx.measureText(wbeText).width);
  const boxX = pad.l + 6;
  const boxY = pad.t + 6;
  const boxW = labelWidth + 12;
  const boxH = 30;
  ctx.fillStyle = "rgba(255,255,255,0.92)";
  ctx.strokeStyle = "#c0392b";
  ctx.lineWidth = 1;
  ctx.beginPath();
  ctx.roundRect(boxX, boxY, boxW, boxH, 4);
  ctx.fill();
  ctx.stroke();
  ctx.textBaseline = "alphabetic";
  ctx.fillStyle = "#c0392b";
  ctx.fillText(fitText, boxX + 6, boxY + 12);
  ctx.fillStyle = "#b85900";
  ctx.fillText(wbeText, boxX + 6, boxY + 24);

  // Data points
  for (const p of valid) {
    const col = ALLO_COLORS[(p.sizeIdx || 0) % ALLO_COLORS.length];
    ctx.fillStyle = col + "cc";
    ctx.beginPath();
    ctx.arc(sx(Math.log10(p[xKey])), sy(linearY ? p[yKey] : Math.log10(p[yKey])), 3.5, 0, Math.PI * 2);
    ctx.fill();
  }

  // Axes
  ctx.strokeStyle = "#33404a";
  ctx.lineWidth   = 1;
  ctx.beginPath();
  ctx.moveTo(pad.l, pad.t);
  ctx.lineTo(pad.l, pad.t + h);
  ctx.lineTo(pad.l + w, pad.t + h);
  ctx.stroke();

  // X tick labels (log)
  ctx.fillStyle    = "#33404a";
  ctx.font         = "9px sans-serif";
  ctx.textBaseline = "top";
  for (let lx = Math.ceil(xMin); lx <= Math.floor(xMax) + 0.1; lx++) {
    ctx.fillText(`10${sup(Math.round(lx))}`, sx(lx) - 7, pad.t + h + 3);
  }

  // Y tick labels
  ctx.textBaseline = "middle";
  if (linearY) {
    const nYTicks = 4;
    for (let i = 0; i <= nYTicks; i++) {
      const v = yMin + (yMax - yMin) * (i / nYTicks);
      ctx.fillText(v.toFixed(2), 2, sy(v));
    }
  } else {
    for (let ly = Math.ceil(yMin); ly <= Math.floor(yMax) + 0.1; ly++) {
      ctx.fillText(`10${sup(Math.round(ly))}`, 2, sy(ly));
    }
  }

  // Title
  ctx.fillStyle    = "#0f2018";
  ctx.font         = "bold 10px sans-serif";
  ctx.textBaseline = "top";
  ctx.fillText(title, pad.l + 2, 2);

  // Axis labels
  ctx.fillStyle = "#33404a";
  ctx.font      = "bold 10px sans-serif";
  ctx.textBaseline = "alphabetic";
  const xLabelWidth = ctx.measureText(xLabel).width;
  ctx.fillText(xLabel, pad.l + w / 2 - xLabelWidth / 2, ch - 4);
  ctx.save();
  ctx.translate(14, pad.t + h / 2 + 14);
  ctx.rotate(-Math.PI / 2);
  ctx.fillText(yLabel, 0, 0);
  ctx.restore();
}

// ── Size class cards ──────────────────────────────────────────
function renderSizeCards() {
  UI.sizeClassCards.innerHTML = "";
  state.classes.forEach((item, idx) => {
    const m    = computeTreeMetrics(item.tree, idx);
    const card = document.createElement("article");
    card.className = "card" + (idx === state.selectedIndex ? " selected" : "");
    card.setAttribute("role", "button");
    card.setAttribute("tabindex", "0");

    const h3   = document.createElement("h3");
    h3.textContent = `${item.targetTips} tips`;

    const meta = document.createElement("div");
    meta.className  = "card-meta";
    meta.textContent = `pf=${m.meanPathFrac.toFixed(2)}  h=${m.height.toFixed(1)}`;

    const svgEl = document.createElementNS("http://www.w3.org/2000/svg", "svg");
    svgEl.setAttribute("viewBox", "0 0 180 72");
    svgEl.setAttribute("aria-hidden", "true");

    card.append(h3, meta, svgEl);

    function select() {
      state.selectedIndex = idx;
      renderSizeCards();
      drawTreeSvg(UI.treeSvg, item.tree);
      drawWithinHistogram(item.tree);
      updateTreeMeta(m);
    }
    card.addEventListener("click", select);
    card.addEventListener("keydown", e => { if (e.key === "Enter" || e.key === " ") select(); });

    UI.sizeClassCards.appendChild(card);
    requestAnimationFrame(() => drawMiniTree(svgEl, item.tree));
  });
}

function updateTreeMeta(m) {
  UI.treeMeta.textContent = [
    `Tips: ${m.nTips}`,
    `D: ${m.trunkDiameter.toFixed(3)}`,
    `Stem vol: ${m.stemVolume.toFixed(3)}`,
    `Net vol: ${m.networkVolume.toFixed(3)}`,
    `H: ${m.height.toFixed(2)}`,
    `Max path: ${m.maxPathLen.toFixed(2)}`,
    `Mean path: ${m.meanPathLen.toFixed(2)}`,
    `Pf: ${m.meanPathFrac.toFixed(2)}`
  ].join("  ·  ");
}

// ── Tab switching ─────────────────────────────────────────────
function initTabs() {
  document.querySelectorAll(".tab-btn").forEach(btn => {
    btn.addEventListener("click", () => {
      document.querySelectorAll(".tab-btn").forEach(b => b.classList.remove("active"));
      document.querySelectorAll(".tab-content").forEach(t => t.classList.add("hidden"));
      btn.classList.add("active");
      document.getElementById("tab-" + btn.dataset.tab).classList.remove("hidden");
    });
  });
}

function drawDiameterAllometries(pts) {
  const plots = [
    { canvas: UI.alloStemVol,  yKey: "stemVolume",   yLabel: "log10(stem volume)",     title: "Trunk diameter vs stem volume",   expected: 2.67 },
    { canvas: UI.alloHeight,   yKey: "totalBiomass",  yLabel: "log10(total biomass)",    title: "Trunk diameter vs total biomass",  expected: 2.67 },
    { canvas: UI.alloMaxPath,  yKey: "leafCount",    yLabel: "log10(leaf number)",      title: "Trunk diameter vs leaf number",    expected: 2.00 },
    { canvas: UI.alloMeanPath, yKey: "networkVolume", yLabel: "log10(network volume)",   title: "Trunk diameter vs network volume",  expected: 2.67 },
    { canvas: UI.alloTotalLen, yKey: "height",       yLabel: "log10(height)",           title: "Trunk diameter vs height",          expected: 0.67 },
    { canvas: UI.alloPF,       yKey: "maxPathLen",   yLabel: "log10(max path length)",  title: "Trunk diameter vs max path length", expected: 0.67 }
  ];

  plots.forEach(plot => {
    drawScatter(plot.canvas, pts, "trunkDiameter", plot.yKey, "log10(trunk diameter)", plot.yLabel, plot.title, false, plot.expected);
  });
}

function drawLeafAllometries(pts) {
  const plots = [
    { canvas: UI.alloStemVol2,  yKey: "stemVolume",   yLabel: "log10(stem volume)",      title: "Leaf number vs stem volume",        expected: 1.33 },
    { canvas: UI.alloHeight2,   yKey: "totalBiomass",  yLabel: "log10(total biomass)",     title: "Leaf number vs total biomass",      expected: 1.33 },
    { canvas: UI.alloMaxPath2,  yKey: "trunkDiameter", yLabel: "log10(trunk diameter)",   title: "Leaf number vs trunk diameter",     expected: 0.50 },
    { canvas: UI.alloMeanPath2, yKey: "networkVolume", yLabel: "log10(network volume)",    title: "Leaf number vs network volume",     expected: 1.33 },
    { canvas: UI.alloTotalLen2, yKey: "height",        yLabel: "log10(height)",            title: "Leaf number vs height",             expected: 0.33 },
    { canvas: UI.alloPF2,       yKey: "maxPathLen",    yLabel: "log10(max path length)",   title: "Leaf number vs max path length",    expected: 0.33 }
  ];

  plots.forEach(plot => {
    drawScatter(plot.canvas, pts, "leafCount", plot.yKey, "log10(leaf number)", plot.yLabel, plot.title, false, plot.expected);
  });
}

// ── Main simulation run ───────────────────────────────────────
function runSimulation() {
  const params = getInputs();

  state.classes = params.sizeClasses.map((targetTips, idx) => ({
    targetTips,
    tree: simulateTree(params, targetTips, idx * 13)
  }));
  state.selectedIndex = 0;

  const sel = state.classes[0];
  const m   = computeTreeMetrics(sel.tree, 0);
  drawTreeSvg(UI.treeSvg, sel.tree);
  updateTreeMeta(m);
  renderSizeCards();
  drawWithinHistogram(sel.tree);
  drawAcrossHistogram(state.classes);

  // Allometry: wider size range with replicates for meaningful scatter
  state.alloPoints = buildAllometryPoints(params);
  drawDiameterAllometries(state.alloPoints);
  drawLeafAllometries(state.alloPoints);
}

// ── Event listeners & init ────────────────────────────────────
document.querySelectorAll(".controls input[type='range']").forEach(el =>
  el.addEventListener("input", syncSliderOutputs)
);

UI.generateBtn.addEventListener("click", runSimulation);

UI.wbeSnapBtn.addEventListener("click", () => {
  snapToWbe();
  runSimulation();
});

initTabs();
syncSliderOutputs();
positionWbeTicks();
runSimulation();
