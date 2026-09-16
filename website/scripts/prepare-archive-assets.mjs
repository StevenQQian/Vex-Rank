import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { RANKING_SEASONS,validateArchive } from '../lib/ranking-seasons.mjs';
await mkdir('archive-assets',{recursive:true});
const manifest=[];
for(const [label,config] of Object.entries(RANKING_SEASONS)){
  if(!config.archive)continue;
  let source;try{source=await readFile(`public${config.archive}`,'utf8')}catch(error){if(process.argv.includes('--available')&&error.code==='ENOENT')continue;throw error}
  const data=validateArchive(JSON.parse(source),label);
  // Keep concise recent-event history in the public leaderboard; the rebuild cache retains source matches.
  for(const team of data.rankings){team.form=team.form.map(({eventId,event,eventDate,change,rating,tier,champion})=>({eventId,event,eventDate,change,rating,tier,champion}));delete team.displayedStrength}
  const content=JSON.stringify(data);
  if(Buffer.byteLength(content)>25*1024*1024)throw new Error(`Archive exceeds asset limit: ${config.archive}`);
  await writeFile(`archive-assets${config.archive}`,content);
  manifest.push({seasonId:config.id,season:label,path:config.archive,modelVersion:data.modelVersion,teams:data.rankings.length,events:data.eventsProcessed,matches:data.matchesProcessed,coverage:data.coverage,asOf:data.asOf,sha256:createHash('sha256').update(content).digest('hex'),bytes:Buffer.byteLength(content)});
}
await writeFile('archive-assets/manifest.json',JSON.stringify({archives:manifest},null,2));
await mkdir('work',{recursive:true});
await writeFile('work/archive-manifest.json',JSON.stringify({archives:manifest},null,2));
console.log(manifest.map(m=>`${m.season}: ${m.teams} teams / ${m.events} events / ${m.matches} matches`).join('\n'));

