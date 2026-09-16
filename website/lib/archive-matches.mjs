// Historical upstream records often say scored:false despite recorded scores.
// Use actual score evidence, and exclude ambiguous 0–0 placeholders.
export function historicalMatches(divisions) {
  const seen=new Set();
  return divisions.flatMap(d=>d.matches??[]).filter(m=>{
    if(seen.has(m.id)||Number(m.round)<2||Number(m.round)>6||m.alliances?.length!==2)return false;
    if(!m.alliances.every(a=>Number.isFinite(a.score)&&a.score>=0&&a.teams?.length))return false;
    if(!m.scored&&m.alliances.every(a=>a.score===0))return false;
    seen.add(m.id);return true;
  });
}

