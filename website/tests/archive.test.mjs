import test from 'node:test';
import assert from 'node:assert/strict';
import { historicalMatches } from '../lib/archive-matches.mjs';
import { RANKING_SEASONS, validateArchive } from '../lib/ranking-seasons.mjs';
const match=(id,a,b,scored=false)=>({id,round:2,scored,alliances:[a,b].map(score=>({score,teams:[{team:{id:1}}]}))});
test('historical scores remain usable when the upstream scored flag is false',()=>{
  const played=match(1,35,20),placeholder=match(2,0,0),unplayed=match(3,-1,-1),tie=match(4,0,0,true);
  assert.deepEqual(historicalMatches([{matches:[played,placeholder,unplayed,tie,played]}]).map(m=>m.id),[1,4]);
});
test('each season has its own archive and incomplete or wrong-season results are rejected',()=>{
  const paths=Object.values(RANKING_SEASONS).map(s=>s.archive).filter(Boolean);assert.equal(new Set(paths).size,4);
  const good={seasonId:197,modelVersion:'VCR-3.0-candidate.2',rankings:[{rating:1500}],coverage:{loadedEvents:20,expectedEvents:20,failures:[]}};
  assert.equal(validateArchive(good,'2025–26 Push Back'),good);
  assert.throws(()=>validateArchive(good,'2024–25 High Stakes'));
  assert.throws(()=>validateArchive({...good,coverage:{...good.coverage,loadedEvents:19}},'2025–26 Push Back'));
});

