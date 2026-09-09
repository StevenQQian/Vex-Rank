const API_ROOT = 'https://events.vex.com/api/v2';

async function readCache(request:Request){try{return await (globalThis as any).caches?.default?.match(request)}catch{return undefined}}
async function writeCache(request:Request,response:Response){try{await (globalThis as any).caches?.default?.put(request,response.clone())}catch{}}

const wait = (milliseconds:number) => new Promise(resolve => setTimeout(resolve,milliseconds));

async function fetchJson(url:string, headers:Record<string,string>, attempts=4) {
  for (let attempt=0;attempt<attempts;attempt++) {
    try {
      const response=await fetch(url,{headers});
      if(response.ok)return await response.json() as any;
      if(response.status!==429&&response.status<500)return null;
      const retryAfter=Number(response.headers.get('retry-after'));
      await wait(Number.isFinite(retryAfter)&&retryAfter>0?retryAfter*1000:250*2**attempt);
    } catch {
      if(attempt===attempts-1)return null;
      await wait(250*2**attempt);
    }
  }
  return null;
}

async function mapLimit<T,R>(items:T[], limit:number, mapper:(item:T,index:number)=>Promise<R>) {
  const results=new Array<R>(items.length);
  let cursor=0;
  await Promise.all(Array.from({length:Math.min(limit,items.length)},async()=>{
    while(true){
      const index=cursor++;
      if(index>=items.length)break;
      results[index]=await mapper(items[index],index);
    }
  }));
  return results;
}

async function getAllTeams(id:string, headers:Record<string,string>) {
  const first = await fetchJson(`${API_ROOT}/events/${id}/teams?per_page=250`,headers) as { data:any[]; meta:{last_page:number} } | null;
  if (!first) return [];
  const pages = Array.from({length:Math.max(0,first.meta.last_page - 1)},(_,index)=>index + 2);
  const rest = await Promise.all(pages.map(async page => {
    const response = await fetchJson(`${API_ROOT}/events/${id}/teams?per_page=250&page=${page}`,headers) as {data:any[]} | null;
    return response?.data ?? [];
  }));
  return [...first.data,...rest.flat()];
}

async function getAll(url:string, headers:Record<string,string>) {
  const firstUrl=`${API_ROOT}${url}${url.includes('?') ? '&' : '?'}per_page=250`;
  const first = await fetchJson(firstUrl,headers) as { data:any[]; meta?:{last_page?:number} } | null;
  if (!first) return [];
  const pages = Array.from({length:Math.max(0,(first.meta?.last_page ?? 1) - 1)},(_,index)=>index + 2);
  const rest = await Promise.all(pages.map(async page => {
    const response = await fetchJson(`${firstUrl}&page=${page}`,headers) as {data:any[]} | null;
    return response?.data ?? [];
  }));
  return [...first.data,...rest.flat()];
}

function htmlToText(html:string) {
  return html.replace(/<script[\s\S]*?<\/script>/gi,'').replace(/<style[\s\S]*?<\/style>/gi,'')
    .replace(/<br\s*\/?\s*>/gi,'\n').replace(/<\/td>/gi,' | ').replace(/<\/(p|li|tr|div|h[1-6])>/gi,'\n')
    .replace(/<li[^>]*>/gi,'• ').replace(/<[^>]+>/g,'').replace(/&nbsp;|&#160;/gi,' ').replace(/&amp;/gi,'&')
    .replace(/&quot;/gi,'"').replace(/&#39;|&apos;/gi,"'").replace(/&ndash;/gi,'–').replace(/&mdash;/gi,'—')
    .replace(/&#(\d+);/g,(_,code)=>String.fromCharCode(Number(code))).replace(/[ \t]+\n/g,'\n').replace(/\n{3,}/g,'\n\n').trim();
}

function organizerSections(html:string) {
  const names=['General Info','Agenda','Volunteer','Emergency/Bad Weather Policy','Refund and Payment Policies','Travel Info','Webcast','Judging Format','Teams','Waitlist','Results','Awards'];
  const headings=[...html.matchAll(/<h([1-6])[^>]*>([\s\S]*?)<\/h\1>/gi)].map(match=>({index:match.index ?? 0,end:(match.index ?? 0)+match[0].length,name:htmlToText(match[2]).trim()}));
  const read=(name:string)=>{
    const candidates=headings.filter(heading=>heading.name.toLowerCase()===name.toLowerCase()).map(heading=>{
      const next=headings.find(other=>other.index>heading.end&&names.some(section=>section.toLowerCase()===other.name.toLowerCase()));
      return htmlToText(html.slice(heading.end,next?.index ?? html.length));
    }).filter(Boolean).sort((a,b)=>b.length-a.length);
    return candidates[0] ?? '';
  };
  return {general:read('General Info'),agenda:read('Agenda'),travel:read('Travel Info'),webcast:read('Webcast')};
}

export async function GET(request:Request, context:{params:Promise<{id:string}>}) {
  const token = process.env.ROBOT_EVENTS_API_TOKEN;
  if (!token) return Response.json({error:'RobotEvents API is not configured.'},{status:503});
  const {id} = await context.params;
  if (!/^\d+$/.test(id)) return Response.json({error:'Invalid event.'},{status:400});
  const cached=await readCache(request);if(cached)return cached;
  const headers = {Authorization:`Bearer ${token}`,Accept:'application/json'};
  const teamsPromise=getAllTeams(id,headers);
  const eventResponse = await fetch(`${API_ROOT}/events/${id}`,{headers});
  if (!eventResponse.ok) return Response.json({error:'Event not found.'},{status:404});
  const event = await eventResponse.json() as any;
  const divisions = event.divisions ?? [];
  const officialUrl = `https://events.vex.com/robot-competitions/vex-robotics-competition/${event.sku}.html`;
  const organizerPromise=(async()=>{try{const officialResponse=await fetch(officialUrl,{headers:{Accept:'text/html','User-Agent':'VEXRank/1.0'}});if(officialResponse.ok)return organizerSections(await officialResponse.text())}catch{}return{general:'',agenda:'',travel:'',webcast:''}})();
  const [teams,awards,skills,divisionData,organizer] = await Promise.all([
    teamsPromise,
    getAll(`/events/${id}/awards`,headers),
    getAll(`/events/${id}/skills`,headers),
    mapLimit(divisions,3,async (division:any) => {
      const eliminationRounds='round%5B%5D=3&round%5B%5D=4&round%5B%5D=5&round%5B%5D=6';
      const [rankings,qualificationMatches,eliminationMatches] = await Promise.all([
        getAll(`/events/${id}/divisions/${division.id}/rankings`,headers),
        getAll(`/events/${id}/divisions/${division.id}/matches?round%5B%5D=2`,headers),
        getAll(`/events/${id}/divisions/${division.id}/matches?${eliminationRounds}`,headers),
      ]);
      const matches=[...qualificationMatches,...eliminationMatches].sort((a:any,b:any)=>Number(a.round)-Number(b.round)||Number(a.instance)-Number(b.instance)||Number(a.matchnum)-Number(b.matchnum));
      return {
        id:division.id,name:division.name,
        rankings:rankings.map((row:any)=>({rank:row.rank,team:row.team,wins:row.wins,losses:row.losses,ties:row.ties,wp:row.wp,ap:row.ap,sp:row.sp,highScore:row.high_score})),
        matches:matches.map((match:any)=>({id:match.id,name:match.name,round:Number(match.round),instance:match.instance,matchnum:match.matchnum,scheduled:match.scheduled,started:match.started,field:match.field,scored:Boolean(match.scored),alliances:match.alliances})),
      };
    }),
    organizerPromise,
  ]);
  const response=Response.json({
    event:{
      id:event.id,sku:event.sku,name:event.name,start:event.start,end:event.end,season:event.season,program:event.program,
      location:event.location,locations:event.locations ?? [],divisions:event.divisions ?? [],level:event.level,eventType:event.event_type,
      ongoing:event.ongoing,awardsFinalized:event.awards_finalized,officialUrl,
    },
    teams:teams.map(team=>({id:team.id,number:team.number,name:team.team_name,robot:team.robot_name,organization:team.organization,grade:team.grade,location:team.location})),
    divisions:divisionData,
    awards:awards.map((award:any)=>({id:award.id,title:award.title,designation:award.designation,classification:award.classification,teamWinners:award.teamWinners ?? [],individualWinners:award.individualWinners ?? []})),
    skills:skills.map((skill:any)=>({id:skill.id,team:skill.team,type:skill.type,rank:skill.rank,score:skill.score,attempts:skill.attempts ?? 0})),
    organizer,
  },{headers:{'Cache-Control':'public, max-age=300, s-maxage=300, stale-while-revalidate=1800'}});
  await writeCache(request,response);return response;
}
