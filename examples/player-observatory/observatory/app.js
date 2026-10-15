import {areas,connections,colors,areaLabel,timestamp,parseCSV,selection,statistics,positionAt,densityCells} from "./model.js";

const $ = id => document.getElementById(id);
const svgNS = "http://www.w3.org/2000/svg";
const embedded = new URLSearchParams(location.search).has("embedded");
if(embedded) document.documentElement.dataset.embedded = "";
let rows = [], ids = [], paths = new Map(), selected = new Set();
let seconds = 0, playing = false, lastFrame = null, mode = "movement", selectedArea = "spawn";
let lastStatsTime = -1;
let frameId = null;
const areaByName = new Map(areas.map(area => [area.name,area]));
const reducedMotion = matchMedia("(prefers-reduced-motion: reduce)");
const layers = {};

function svg(tag, attributes = {}, parent) {
  const node = document.createElementNS(svgNS,tag);
  for(const [key,value] of Object.entries(attributes)) node.setAttribute(key,String(value));
  if(parent) parent.append(node);
  return node;
}
function makeMap() {
  const defs = svg("defs",{},$("world"));
  const grid = svg("pattern",{id:"grid",width:5,height:5,patternUnits:"userSpaceOnUse"},defs);
  svg("path",{d:"M 5 0 L 0 0 0 5",fill:"none",stroke:"#365057","stroke-width":.08},grid);
  svg("rect",{x:0,y:0,width:100,height:60,fill:"url(#grid)"},$("world"));
  for(const [source,target] of connections) {
    const a = areaByName.get(source), b = areaByName.get(target);
    svg("path",{d:`M${a.cx},${60-a.cy} L${b.cx},${60-b.cy}`,class:"connector"},$("world"));
  }
  layers.areas = svg("g",{},$("world"));
  layers.density = svg("g",{"pointer-events":"none"},$("world"));
  layers.trails = svg("g",{},$("world"));
  layers.markers = svg("g",{},$("world"));
  for(const area of areas) {
    const group = svg("g",{class:"region",role:"button",tabindex:0,"aria-label":`Inspect ${areaLabel(area.name)}`,"aria-pressed":area.name === selectedArea,"data-area":area.name},layers.areas);
    if(area.name === "spawn") svg("circle",{cx:area.cx,cy:60-area.cy,r:4,class:"tile"},group);
    else svg("rect",{x:area.x0,y:60-area.y1,width:area.x1-area.x0,height:area.y1-area.y0,rx:.8,class:"tile"},group);
    svg("text",{x:area.cx,y:60-area.cy+.5,"text-anchor":"middle"},group).textContent = areaLabel(area.name).toUpperCase();
    const inspect = () => {
      selectedArea = area.name;
      for(const node of layers.areas.children) node.setAttribute("aria-pressed",String(node.dataset.area === selectedArea));
      renderStatistics();
    };
    group.addEventListener("click",inspect);
    group.addEventListener("keydown",event => {
      if(event.key === "Enter" || event.key === " ") { event.preventDefault(); inspect(); }
    });
  }
}
function makeRoster() {
  ids.forEach((id,index) => {
    const label = document.createElement("label");
    label.className = "player";
    label.style.setProperty("--player-color",colors[index%colors.length]);
    const input = document.createElement("input");
    input.type = "checkbox"; input.checked = true;
    input.setAttribute("aria-label",`Player ${String(id).padStart(2,"0")}`);
    input.addEventListener("change",() => {
      if(input.checked) selected.add(id); else selected.delete(id);
      render(true);
    });
    const swatch = document.createElement("span"); swatch.className = "swatch";
    const name = document.createElement("span"); name.className = "player-name"; name.textContent = `Player ${String(id).padStart(2,"0")}`;
    const state = document.createElement("span"); state.className = "player-state"; state.id = `player-state-${id}`;
    label.append(input,swatch,name,state); $("players").append(label);
  });
}
function renderStatistics() {
  const filtered = selection(rows,selected,seconds), stats = statistics(filtered);
  $("metric-players").textContent = selected.size;
  $("metric-areas").textContent = `${stats.areas} / ${areas.length-1}`;
  $("metric-distance").textContent = stats.distance.toFixed(1);
  $("metric-busiest").textContent = stats.busiest ? areaLabel(stats.busiest) : "None yet";
  const presence = filtered.filter(row => row.name === selectedArea && row.movement_state === "dwelling");
  $("area-title").textContent = areaLabel(selectedArea);
  $("area-description").textContent = selectedArea === "spawn" ? "The shared starting point. Every fictional journey begins here." : "A fictional destination connected by traversable routes.";
  $("area-visitors").textContent = new Set(presence.map(row => row.player_id)).size;
  $("area-samples").textContent = presence.length;
  $("sample-count").textContent = `${filtered.length.toLocaleString()} of ${rows.length.toLocaleString()} recorded positions selected · 00:00–${timestamp(seconds)} · ${selected.size} players. Downloads use this same selection.`;
  $("download").disabled = filtered.length === 0;
  $("select-all").textContent = selected.size === ids.length ? "Clear all" : "Select all";
  $("status").textContent = selected.size ? "FICTIONAL DATA ONLY · No live telemetry · Select a player, scrub the timeline, or inspect a map area." : "No players selected. Select a player or choose Select all to restore the view.";
  if(mode === "density") {
    layers.density.replaceChildren();
    const cells = densityCells(filtered), max = Math.max(1,...cells.map(cell => cell.count));
    for(const cell of cells) {
      const node = svg("rect",{x:cell.x,y:60-cell.y-4,width:4,height:4,rx:.3,fill:"#82c9ff",opacity:.15+.75*cell.count/max},layers.density);
      svg("title",{},node).textContent = `${cell.count} sampled positions`;
    }
    $("map-caption").textContent = `Sampled presence · pale blue = more samples · max ${cells.length ? max : 0}/cell`;
  }
}
function render(force = false) {
  $("clock").textContent = timestamp(seconds);
  $("time").value = Math.floor(seconds);
  layers.trails.replaceChildren(); layers.markers.replaceChildren();
  for(const [index,id] of ids.entries()) {
    const path = paths.get(id), current = positionAt(path,seconds);
    $(`player-state-${id}`).textContent = selected.has(id) ? (current.movement_state === "walking" ? "Travelling" : areaLabel(current.name)) : "Hidden";
    if(!selected.has(id) || mode !== "movement") continue;
    const recent = path.filter(row => row.seconds >= seconds-60 && row.seconds <= seconds);
    const points = [...recent,current].map(row => `${row.x},${60-row.y}`).join(" ");
    svg("polyline",{points,class:"trail",stroke:colors[index%colors.length]},layers.trails);
    const marker = svg("circle",{cx:current.x,cy:60-current.y,r:.65,fill:colors[index%colors.length],class:"marker"},layers.markers);
    svg("title",{},marker).textContent = `Player ${id}`;
  }
  const statsTime = Math.floor(seconds);
  if(force || statsTime !== lastStatsTime) { renderStatistics(); lastStatsTime = statsTime; }
}
function setPlaying(value) {
  if(frameId !== null) cancelAnimationFrame(frameId);
  frameId = null;
  playing = value; lastFrame = null;
  $("play").innerHTML = playing ? "Ⅱ <span>Pause</span>" : "▶ <span>Play</span>";
  $("play").setAttribute("aria-label",playing ? "Pause replay" : "Play replay");
  if(playing) frameId = requestAnimationFrame(tick);
}
function tick(now) {
  if(!playing) return;
  if(lastFrame !== null) seconds = Math.min(600,seconds + Math.min((now-lastFrame)/1000,.25)*Number($("speed").value));
  lastFrame = now;
  render();
  if(seconds >= 600) setPlaying(false);
  else frameId = requestAnimationFrame(tick);
}
function setMode(value) {
  mode = value;
  $("movement").setAttribute("aria-pressed",String(mode === "movement"));
  $("density").setAttribute("aria-pressed",String(mode === "density"));
  $("view-title").textContent = mode === "movement" ? "Movement replay" : "Position density";
  $("map-mode").textContent = mode === "movement" ? "RECORDED PATHS / 60s TRAILS" : "SAMPLED PRESENCE / 4 × 4 UNIT CELLS";
  $("explanation").textContent = mode === "movement" ? "Replay shows the latest positions. Statistics accumulate from the start through the replay cursor." : "Density accumulates recorded positions through the cursor, including travel. This is not unique players or measured time spent.";
  if(mode === "movement") { layers.density.replaceChildren(); $("map-caption").textContent = "Markers interpolate between 5-second samples."; }
  render(true);
}
$("play").addEventListener("click",() => {
  if(seconds >= 600) seconds = 0;
  setPlaying(!playing);
});
$("reset").addEventListener("click",() => {setPlaying(false); seconds = 0; render(true);});
$("time").addEventListener("input",() => {setPlaying(false); seconds = Number($("time").value); render(true);});
$("movement").addEventListener("click",() => setMode("movement"));
$("density").addEventListener("click",() => setMode("density"));
$("select-all").addEventListener("click",() => {
  selected = selected.size === ids.length ? new Set() : new Set(ids);
  [...$("players").querySelectorAll("input")].forEach((input,index) => {input.checked = selected.has(ids[index]);});
  render(true);
});
$("download").addEventListener("click",() => {
  const columns = Object.keys(rows[0]).filter(key => key !== "seconds");
  const csv = [columns.join(","),...selection(rows,selected,seconds).map(row => columns.map(key => row[key]).join(","))].join("\n");
  const url = URL.createObjectURL(new Blob([csv],{type:"text/csv;charset=utf-8"}));
  const anchor = document.createElement("a"); anchor.href = url; anchor.download = "fictional-player-selection.csv";
  anchor.click(); setTimeout(() => URL.revokeObjectURL(url),1000);
});
document.addEventListener("visibilitychange",() => {if(document.hidden) setPlaying(false);});
reducedMotion.addEventListener("change",() => {if(reducedMotion.matches) setPlaying(false);});
if(embedded) {
  new ResizeObserver(() => {
    parent.postMessage({type:"tail-observatory-height",height:Math.ceil(document.body.getBoundingClientRect().height)},location.origin);
  }).observe(document.body);
}

for(const id of ["movement","density","select-all","speed"]) $(id).disabled = true;
try {
  const response = await fetch("../data/fake_player_paths.csv");
  if(!response.ok) throw new Error(`Dataset request failed (${response.status}).`);
  rows = parseCSV(await response.text());
  ids = [...new Set(rows.map(row => row.player_id))];
  selected = new Set(ids);
  paths = new Map(ids.map(id => [id,rows.filter(row => row.player_id === id)]));
  makeMap(); makeRoster(); render(true);
  for(const id of ["play","reset","time","movement","density","select-all","speed"]) $(id).disabled = false;
} catch(error) {
  console.error("Player Observatory could not load:",error);
  $("status").classList.add("error");
  $("status").textContent = `Unable to load the fictional session: ${error.message} Serve the example folder over localhost; opening the HTML as a file is not supported.`;
}
