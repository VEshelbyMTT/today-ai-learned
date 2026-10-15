export const areas = [
  ["spawn",46,54,26,34],["area1",34,46,39,46],["area2",24,34,50,56],
  ["area3",44,56,50,56],["area4",14,25,38,44],["area5",64,79,33,40],
  ["area6",66,76,47,53],["area7",82,92,43,49],["area8",88,99,28,35],
  ["area9",28,41,27,34],["area10",9,24,17,27],["area11",1,20,6,12],
  ["area12",42,62,14,21],["area13",30,37,14,20],["area14",38,47,4,10],
  ["area15",51,58,3,9],["area16",64,72,6,12],["area17",70,83,18,24],
].map(([name,x0,x1,y0,y1]) => ({name,x0,x1,y0,y1,cx:(x0+x1)/2,cy:(y0+y1)/2}));
export const connections = [
  ["spawn","area1"],["spawn","area5"],["spawn","area9"],["spawn","area12"],
  ["area1","area2"],["area1","area3"],["area1","area4"],["area5","area6"],
  ["area5","area7"],["area5","area8"],["area9","area10"],["area10","area11"],
  ["area12","area13"],["area12","area14"],["area12","area15"],["area12","area16"],["area12","area17"],
];
export const colors = ["#bba8ff","#7dd9f5","#61d5b3","#b1e878","#e8cb6b","#ffa87c","#f29dba","#cc8fe0","#97b9ff"];
export const areaLabel = name => name === "spawn" ? "Spawn" : `Area ${name.slice(4).padStart(2,"0")}`;
export const timestamp = seconds => `${String(Math.floor(seconds/60)).padStart(2,"0")}:${String(Math.floor(seconds%60)).padStart(2,"0")}`;

export function parseCSV(text) {
  const [header,...lines] = text.trim().split(/\r?\n/);
  const columns = header.split(",");
  for (const column of ["player_id","elapsed_minutes","x","y","name","movement_state"]) {
    if (!columns.includes(column)) throw new Error(`Dataset missing column: ${column}`);
  }
  const rows = lines.map(line => {
    const values = line.split(",");
    if(values.length !== columns.length) throw new Error("Dataset contains an invalid row.");
    const record = Object.fromEntries(columns.map((column,index) => [column,values[index]]));
    for(const key of ["player_id","elapsed_minutes","x","y"]) {
      if(record[key].trim() === "") throw new Error(`Dataset has an empty ${key}.`);
      record[key] = Number(record[key]);
      if(!Number.isFinite(record[key])) throw new Error(`Dataset has invalid ${key}.`);
    }
    if(!areas.some(area => area.name === record.name)) throw new Error("Dataset has an unknown area.");
    if(!["walking","dwelling"].includes(record.movement_state)) throw new Error("Dataset has an unknown movement state.");
    return {...record,seconds:record.elapsed_minutes*60};
  });
  if(!rows.length) throw new Error("Dataset contains no positions.");
  return rows.sort((a,b) => a.player_id-b.player_id || a.seconds-b.seconds);
}
export function selection(rows, players, seconds) {
  return rows.filter(row => players.has(row.player_id) && row.seconds <= seconds + 1e-7);
}
export function statistics(rows) {
  const players = new Set(), visited = new Set(), counts = new Map(), previous = new Map();
  let distance = 0;
  for(const row of rows) {
    players.add(row.player_id);
    const prior = previous.get(row.player_id);
    if(prior) distance += Math.hypot(row.x-prior.x,row.y-prior.y);
    previous.set(row.player_id,row);
    if(row.name !== "spawn" && row.movement_state === "dwelling") {
      visited.add(row.name);
      counts.set(row.name,(counts.get(row.name) || 0)+1);
    }
  }
  const busiest = [...counts].sort((a,b) => b[1]-a[1] || a[0].localeCompare(b[0],undefined,{numeric:true}))[0]?.[0] ?? null;
  return {players:players.size,areas:visited.size,distance,busiest};
}
export function positionAt(path, seconds) {
  const index = path.findIndex(row => row.seconds > seconds);
  if(index === 0) return path[0];
  if(index === -1) return path.at(-1);
  const a = path[index-1], b = path[index], fraction = (seconds-a.seconds)/(b.seconds-a.seconds);
  return {...a,x:a.x+(b.x-a.x)*fraction,y:a.y+(b.y-a.y)*fraction};
}
export function densityCells(rows) {
  const cells = new Map();
  for(const row of rows) {
    const x = Math.floor(row.x/4)*4, y = Math.floor(row.y/4)*4, key = `${x},${y}`;
    if(!cells.has(key)) cells.set(key,{x,y,count:0});
    cells.get(key).count++;
  }
  return [...cells.values()];
}
