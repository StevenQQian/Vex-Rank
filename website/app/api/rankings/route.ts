import { vexCollection, mapLimit } from '@/lib/vex-api';
import seasonGradeOverrides from '@/lib/season-grade-overrides.json';

const API_ROOT='https://events.vex.com/api/v2';
const SEASONS:Record<string,{label:string;start:string;end:string}>={
  '204':{label:'2026–27 Override',start:'2026-04-01T00:00:00Z',end:'2027-06-01T00:00:00Z'},
  '197':{label:'2025–26 Push Back',start:'2025-04-01T00:00:00Z',end:'2026-06-01T00:00:00Z'},
  '190':{label:'2024–25 High Stakes',start:'2024-04-01T00:00:00Z',end:'2025-06-01T00:00:00Z'},
  '181':{label:'2023–24 Over Under',start:'2023-04-01T00:00:00Z',end:'2024-06-01T00:00:00Z'},
  '173':{label:'2022–23 Spin Up',start:'2022-04-01T00:00:00Z',end:'2023-06-01T00:00:00Z'},
};

type TeamState={id:number;number:string;rating:number;matches:number;wins:number;losses:number;ties:number;pointsFor:number;pointsAgainst:number;events:Set<number>;middleGradeEvents:Set<number>;highGradeEvents:Set<number>};
const eventWeight=(event:any)=>event.level==='World'?1.85:event.level==='Signature'?1.35:['National','State'].includes(event.level)?1.15:.82;
const recencyWeight=(date:string,now:Date)=>2**(-Math.max(0,(now.getTime()-new Date(date).getTime())/86400000)/75);
const gradeFromContext=(value:string)=>{const text=String(value??'').toLowerCase().replace(/[_/-]+/g,' ');const middle=/\bmiddle school\b|\bjunior high\b|\bjr\.? high\b|\bms\b/.test(text);const high=/\bhigh school\b|\bsenior high\b|\bhs\b/.test(text);return middle&&!high?'Middle School':high&&!middle?'High School':null};
const gradeFromOrganization=(value:string)=>/\bmiddle school\b|\bjunior high\b|\bjr\.? high\b|\bintermediate school\b|\belementary school\b/i.test(String(value??''))?'Middle School':/\bhigh school\b|\bsenior high\b|\bsecondary school\b/i.test(String(value??''))?'High School':null;
async function fetchWithRetry(url:string,headers:Record<string,string>,attempt=0):Promise<Response>{const response=await fetch(url,{headers});if((response.status===429||response.status>=500)&&attempt<3){await new Promise(resolve=>setTimeout(resolve,500*(attempt+1)));return fetchWithRetry(url,headers,attempt+1)}return response}
async function readCache(request:Request){try{return await (globalThis as any).caches?.default?.match(request)}catch{return undefined}}
async function writeCache(request:Request,response:Response){try{await (globalThis as any).caches?.default?.put(request,response.clone())}catch{}}

export async function GET(request:Request){
  const token=process.env.ROBOT_EVENTS_API_TOKEN;
  if(!token)return Response.json({error:'RobotEvents API is not configured.'},{status:503});
  const cached=await readCache(request);if(cached)return cached;
  const headers={Authorization:`Bearer ${token}`,Accept:'application/json'};
  const requested=new URL(request.url).searchParams.get('season')??'204';const seasonId=SEASONS[requested]?requested:'204';const season=SEASONS[seasonId];
  const wallClock=new Date();const cutoff=new Date(Math.min(wallClock.getTime(),new Date(season.end).getTime()));
  const eventsUrl=`${API_ROOT}/events?season%5B%5D=${seasonId}&per_page=250`;
  try {
  const eventRows=await vexCollection(eventsUrl,headers);
  const completed=eventRows.filter(event=>event.program?.id===1&&String(event.season?.id)===seasonId&&new Date(event.end)<=cutoff&&event.divisions?.length&&!/cancell?ed/i.test(event.name)).sort((a,b)=>String(a.end).localeCompare(String(b.end))).slice(-36);
  const jobs=completed.flatMap(event=>event.divisions.map((division:any)=>({event,division})));
  const matchGroups=await mapLimit(jobs,3,async({event,division})=>{
    const data=await vexCollection(`${API_ROOT}/events/${event.id}/divisions/${division.id}/matches?round%5B%5D=2&round%5B%5D=3&round%5B%5D=4&round%5B%5D=5&round%5B%5D=6`,headers);
    return data.map(match=>({...match,eventId:event.id,evidenceWeight:eventWeight(event)*recencyWeight(event.end,cutoff),gradeHint:gradeFromContext(`${event.name} ${division.name}`)}));
  });
  const matches=matchGroups.flat().filter(match=>match.alliances?.length===2&&match.alliances.every((alliance:any)=>Number.isFinite(alliance.score)&&alliance.score>=0&&alliance.teams?.length));
  matches.sort((a,b)=>String(a.scheduled??a.updated_at).localeCompare(String(b.scheduled??b.updated_at)));
  const states=new Map<number,TeamState>();
  const stateFor=(team:any)=>{if(!states.has(team.id))states.set(team.id,{id:team.id,number:team.name,rating:1500,matches:0,wins:0,losses:0,ties:0,pointsFor:0,pointsAgainst:0,events:new Set(),middleGradeEvents:new Set(),highGradeEvents:new Set()});return states.get(team.id)!};
  for(const match of matches){
    const red=match.alliances.find((alliance:any)=>alliance.color==='red');const blue=match.alliances.find((alliance:any)=>alliance.color==='blue');if(!red||!blue)continue;
    const redTeams=red.teams.filter((entry:any)=>!entry.sitting).map((entry:any)=>stateFor(entry.team));const blueTeams=blue.teams.filter((entry:any)=>!entry.sitting).map((entry:any)=>stateFor(entry.team));if(!redTeams.length||!blueTeams.length)continue;
    const redRating=redTeams.reduce((sum:number,team:TeamState)=>sum+team.rating,0)/redTeams.length;const blueRating=blueTeams.reduce((sum:number,team:TeamState)=>sum+team.rating,0)/blueTeams.length;
    const expectedRed=1/(1+10**((blueRating-redRating)/400));const actualRed=red.score===blue.score?.5:red.score>blue.score?1:0;const mov=1+.35*Math.tanh(Math.abs(red.score-blue.score)/25);const allianceDelta=20*(actualRed-expectedRed)*mov*Number(match.evidenceWeight??1);
    const update=(team:TeamState,delta:number,score:number,against:number)=>{team.rating+=delta;team.matches++;team.pointsFor+=score;team.pointsAgainst+=against;team.events.add(match.eventId);if(match.gradeHint==='Middle School')team.middleGradeEvents.add(match.eventId);if(match.gradeHint==='High School')team.highGradeEvents.add(match.eventId);if(score>against)team.wins++;else if(score<against)team.losses++;else team.ties++};
    redTeams.forEach((team:TeamState)=>update(team,allianceDelta/redTeams.length,red.score,blue.score));blueTeams.forEach((team:TeamState)=>update(team,-allianceDelta/blueTeams.length,blue.score,red.score));
  }
  const rated=[...states.values()].filter(team=>team.matches>=4).map(team=>{const confidence=Math.max(35,Math.round(120/Math.sqrt(Math.max(1,team.matches/4))));return{...team,events:team.events.size,confidence,displayedStrength:team.rating-confidence}}).sort((a,b)=>b.displayedStrength-a.displayedStrength);
  const groups=Array.from({length:Math.ceil(rated.length/100)},(_,index)=>rated.slice(index*100,index*100+100));
  const detailPayloads=await mapLimit(groups,3,async group=>{const ids=group.map(team=>`id%5B%5D=${team.id}`).join('&');return vexCollection(`${API_ROOT}/teams?${ids}`,headers)});
  const official=new Map(detailPayloads.flat().map(team=>[team.id,team]));
  const rankings=rated.map((team,index)=>{const info=official.get(team.id) as any;const games=Math.max(1,team.matches);const opr=team.pointsFor/games/2;const dpr=team.pointsAgainst/games/2;const eventGrade=team.middleGradeEvents.size===team.highGradeEvents.size?null:team.middleGradeEvents.size>team.highGradeEvents.size?'Middle School':'High School';const number=info?.number??team.number;const verifiedGrade=(seasonGradeOverrides as Record<string,Record<string,string>>)[seasonId]?.[number];const grade=verifiedGrade??eventGrade??gradeFromOrganization(info?.organization)??info?.grade??'Unknown';return{rank:index+1,id:team.id,number,name:info?.team_name??info?.organization??team.number,region:[info?.location?.region,info?.location?.country].filter(Boolean).join(', ')||'Unassigned',eventRegion:info?.location?.region||info?.location?.country||'Unassigned',country:info?.location?.country||'Unassigned',rating:Math.round(team.rating),confidence:team.confidence,change:0,record:`${team.wins}–${team.losses}–${team.ties}`,events:team.events,opr:Number(opr.toFixed(1)),dpr:Number(dpr.toFixed(1)),ccwm:Number((opr-dpr).toFixed(1)),auto:0,ase:0,consistency:Math.max(0,Math.min(100,Math.round(100-team.confidence/2))),skills:0,form:[],seasonId:Number(seasonId),season:season.label,matches:team.matches,grade,organization:info?.organization??'',robot:info?.robot_name??''}});
  const response=Response.json({rankings,eventsProcessed:completed.length,matchesProcessed:matches.length,method:'VCR recency-weighted match model · 75-day evidence half-life',season:season.label,updatedAt:new Date().toISOString()},{headers:{'Cache-Control':'public, max-age=900, s-maxage=1800, stale-while-revalidate=7200'}});
  await writeCache(request,response);return response;
  } catch { return Response.json({error:'Rankings could not be fully loaded. Please retry.'},{status:502,headers:{'Cache-Control':'no-store'}}); }
}
