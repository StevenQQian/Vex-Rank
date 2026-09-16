import { vexCollection, vexJson, mapLimit } from '../lib/vex-api';

const root='https://events.vex.com/api/v2';
const historicalSeasons=new Set([197,190,181,173]);
/** Bounded read-only source for reproducible archives. No arbitrary upstream URLs. */
export async function archiveSource(url:URL) {
  const token=process.env.ROBOT_EVENTS_API_TOKEN;
  if(!token)return Response.json({error:'Official data is not configured'},{status:503});
  const headers={Authorization:`Bearer ${token}`,Accept:'application/json'};
  const id=url.pathname.split('/').at(-1)!;
  if(id==='archive-source') {
    const season=Number(url.searchParams.get('season'));
    if(!historicalSeasons.has(season))return Response.json({error:'Unsupported historical season'},{status:400});
    const events=await vexCollection(`${root}/events?season%5B%5D=${season}`,headers);
    return Response.json({events:events.filter(e=>e.program?.id===1&&e.season?.id===season&&new Date(e.end)<new Date()&&!/cancell?ed/i.test(e.name)).map(e=>({...e,status:'Completed',startsAt:e.start}))});
  }
  const event=await vexJson(`${root}/events/${id}`,headers);
  if(event.program?.id!==1||!historicalSeasons.has(event.season?.id)||new Date(event.end)>=new Date())return Response.json({error:'Not a completed V5 historical event'},{status:400});
  const mode=url.searchParams.get('mode');
  if(mode==='metadata')return Response.json({event});
  if(mode==='teams')return Response.json(await vexJson(`${root}/events/${id}/teams?per_page=250&page=${Number(url.searchParams.get('page')??1)}`,headers));
  if(mode==='matches'){
    const division=Number(url.searchParams.get('division'));
    if(!(event.divisions??[]).some((d:any)=>d.id===division))return Response.json({error:'Unknown division'},{status:400});
    return Response.json(await vexJson(`${root}/events/${id}/divisions/${division}/matches?round%5B%5D=2&round%5B%5D=3&round%5B%5D=4&round%5B%5D=5&round%5B%5D=6&per_page=250&page=${Number(url.searchParams.get('page')??1)}`,headers));
  }
  const [teams,divisions]=await Promise.all([
    vexCollection(`${root}/events/${id}/teams`,headers),
    mapLimit(event.divisions??[],2,async(d:any)=>({...d,matches:await vexCollection(`${root}/events/${id}/divisions/${d.id}/matches?round%5B%5D=2&round%5B%5D=3&round%5B%5D=4&round%5B%5D=5&round%5B%5D=6`,headers)})),
  ]);
  return Response.json({event,divisions,teams:teams.map(t=>({id:t.id,number:t.number,name:t.team_name,organization:t.organization,grade:t.grade,location:t.location}))},{headers:{'Cache-Control':'public,max-age=86400'}});
}

