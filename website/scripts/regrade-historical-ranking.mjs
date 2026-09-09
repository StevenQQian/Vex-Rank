import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';

const file=resolve(process.argv[2]??'public/rankings-2025-26.json');
const seasonId=Number(process.argv[3]??197);
const verifiedOverrides=JSON.parse(await readFile(resolve('lib/season-grade-overrides.json'),'utf8'))[String(seasonId)]??{};
if(process.argv.includes('--verified-only')){
  const payload=JSON.parse(await readFile(file,'utf8'));let corrected=0;
  for(const team of payload.rankings??[]){const grade=verifiedOverrides[team.number];if(grade&&grade!==team.grade){team.grade=grade;corrected++}}
  payload.gradeClassification='Season-specific official event rosters, weighted toward Worlds and championships; verified historical overrides; organization fallback';
  payload.gradeClassificationUpdatedAt=new Date().toISOString();
  await writeFile(file,JSON.stringify(payload));
  console.log(JSON.stringify({corrected,sample3150D:payload.rankings?.find(team=>team.number==='3150D')?.grade}));
  process.exit(0);
}
const token=process.env.ROBOT_EVENTS_API_TOKEN;
if(!token)throw new Error('ROBOT_EVENTS_API_TOKEN is required');
const root='https://events.vex.com/api/v2';
const headers={Authorization:`Bearer ${token}`,Accept:'application/json'};
const cacheDir=resolve(`.ranking-cache/${seasonId}/grade-rosters`);
await mkdir(cacheDir,{recursive:true});

const gradeFromContext=value=>{const text=String(value??'').toLowerCase().replace(/[_/-]+/g,' ');const middle=/\bmiddle school\b|\bjunior high\b|\bjr\.? high\b|\bms\b/.test(text);const high=/\bhigh school\b|\bsenior high\b|\bhs\b/.test(text);return middle&&!high?'Middle School':high&&!middle?'High School':null};
const gradeFromOrganization=value=>/\bmiddle school\b|\bjunior high\b|\bjr\.? high\b|\bintermediate school\b|\belementary school\b/i.test(String(value??''))?'Middle School':/\bhigh school\b|\bsenior high\b|\bsecondary school\b/i.test(String(value??''))?'High School':null;
const evidenceWeight=event=>/world championship/i.test(event.name)?20:/national|state|regional|provincial|championship/i.test(`${event.level??''} ${event.name}`)?8:/signature/i.test(`${event.level??''} ${event.name}`)?4:1;
const delay=ms=>new Promise(resolveDelay=>setTimeout(resolveDelay,ms));
let nextRequestAt=0;
async function requestSlot(){const now=Date.now();const wait=Math.max(0,nextRequestAt-now);nextRequestAt=Math.max(now,nextRequestAt)+350;if(wait)await delay(wait)}

async function request(url,attempt=0){
  await requestSlot();
  const response=await fetch(url,{headers});
  if((response.status===429||response.status>=500)&&attempt<30){const retryAfter=Number(response.headers.get('retry-after')??0);const wait=Math.max(retryAfter*1000,Math.min(60000,1000*2**Math.min(6,attempt)));nextRequestAt=Math.max(nextRequestAt,Date.now()+wait);await delay(wait);return request(url,attempt+1)}
  if(!response.ok)throw new Error(`${response.status} ${url}`);
  return response.json();
}
async function allPages(url){const first=await request(url);const rest=await Promise.all(Array.from({length:Math.max(0,(first.meta?.last_page??1)-1)},(_,index)=>request(`${url}&page=${index+2}`).then(payload=>payload.data)));return[...first.data,...rest.flat()]}
async function mapLimit(items,limit,worker){const results=new Array(items.length);let next=0;async function run(){while(next<items.length){const index=next++;results[index]=await worker(items[index],index);if((index+1)%50===0)console.log(`Read ${index+1}/${items.length} grade-specific event rosters`)}}await Promise.all(Array.from({length:Math.min(limit,items.length)},run));return results}
async function eventTeams(event){
  const cacheFile=resolve(cacheDir,`${event.id}.json`);
  try{return JSON.parse(await readFile(cacheFile,'utf8'))}catch{}
  const teams=await allPages(`${root}/events/${event.id}/teams?per_page=250`);
  await writeFile(cacheFile,JSON.stringify(teams));
  return teams;
}

const events=await allPages(`${root}/events?season%5B%5D=${seasonId}&per_page=250`);
const gradedEvents=events.map(event=>({event,grade:gradeFromContext(`${event.name} ${(event.divisions??[]).map(division=>division.name).join(' ')}`)})).filter(item=>item.grade);
const rosters=await mapLimit(gradedEvents.sort((a,b)=>evidenceWeight(b.event)-evidenceWeight(a.event)),8,async item=>({...item,teams:await eventTeams(item.event)}));
const evidence=new Map();
for(const {event,grade,teams} of rosters){
  const weight=evidenceWeight(event);
  for(const team of teams){const item=evidence.get(team.id)??{middle:0,high:0,middleEvents:0,highEvents:0};if(grade==='Middle School'){item.middle+=weight;item.middleEvents++}else{item.high+=weight;item.highEvents++}evidence.set(team.id,item)}
}

const payload=JSON.parse(await readFile(file,'utf8'));
let corrected=0;let eventResolved=0;let organizationResolved=0;
for(const team of payload.rankings??[]){
  const item=evidence.get(team.id);const eventGrade=item&&item.middle!==item.high?(item.middle>item.high?'Middle School':'High School'):null;const organizationGrade=gradeFromOrganization(team.organization);const grade=verifiedOverrides[team.number]??eventGrade??organizationGrade??team.grade;
  if(eventGrade)eventResolved++;else if(organizationGrade)organizationResolved++;
  if(grade!==team.grade){team.grade=grade;corrected++}
}
payload.gradeClassification='Season-specific official event rosters, weighted toward Worlds and championships; verified historical overrides; organization fallback';
payload.gradeClassificationUpdatedAt=new Date().toISOString();
await writeFile(file,JSON.stringify(payload));
const sample=(payload.rankings??[]).find(team=>team.number==='3150D');
console.log(JSON.stringify({corrected,eventResolved,organizationResolved,gradedEvents:gradedEvents.length,sample3150D:sample?.grade}));
