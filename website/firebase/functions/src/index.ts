import { onRequest } from 'firebase-functions/v2/https';
import { defineSecret } from 'firebase-functions/params';
import { createHash } from 'node:crypto';
import { gzipSync, gunzipSync } from 'node:zlib';
import { database } from './database';
import { GET as events } from '../../../app/api/events/route';
import { GET as event } from '../../../app/api/events/[id]/route';
import { GET as team } from '../../../app/api/teams/[number]/route';
import { GET as rankings } from '../../../app/api/rankings/route';
import { GET as skills } from '../../../app/api/skills/route';

const token=defineSecret('ROBOT_EVENTS_API_TOKEN');
const inflight=new Map<string,Promise<{body:string;status:number}>>();
const hot=new Map<string,{body:string;expires:number}>();

function canonicalPath(path:string, query:URLSearchParams){
  const normalized=path.startsWith('/api/')?path:`/api${path}`;
  if(!/^\/api\/(events(?:\/\d{1,10})?|teams\/[0-9]{1,8}[A-Za-z0-9-]{0,12}|rankings|skills)$/.test(normalized))return null;
  const clean=new URL(`https://vexrank.invalid${normalized}`);
  for(const key of ['season','teamId']){
    const value=query.get(key);
    if(value){if(!/^\d{1,10}$/.test(value))return null;clean.searchParams.set(key,value)}
  }
  if(normalized==='/api/events'||normalized==='/api/skills'){
    const season=clean.searchParams.get('season')??'204';
    if(!['181','190','197','204'].includes(season))return null;
    clean.searchParams.set('season',season);
  }
  return clean;
}

async function dispatch(url:URL){
  const request=new Request(url);
  if(url.pathname==='/api/events')return events(request);
  if(url.pathname==='/api/rankings')return rankings(request);
  if(url.pathname==='/api/skills')return skills(request);
  if(url.pathname.startsWith('/api/events/'))return event(request,{params:Promise.resolve({id:url.pathname.split('/').at(-1)!})});
  return team(request,{params:Promise.resolve({number:url.pathname.split('/').at(-1)!})});
}

async function readThrough(url:URL,key:string){
  const ref=database().collection('api_cache').doc(key);
  const saved=(await ref.get()).data();
  if(saved?.expiresAt>Date.now()&&saved.payload){
    const body=gunzipSync(saved.payload).toString('utf8');
    if(hot.size>=100)hot.delete(hot.keys().next().value!);
    hot.set(key,{body,expires:Date.now()+60000});return{body,status:200};
  }
  const response=await dispatch(url);
  const body=await response.text();
  if(response.ok){
    const compressed=gzipSync(body);
    // Firestore has a 1 MiB document limit. Oversized responses remain uncached.
    if(compressed.length<850000)await ref.set({path:url.pathname,query:url.search,payload:compressed,updatedAt:Date.now(),expiresAt:Date.now()+900000});
    if(hot.size>=100)hot.delete(hot.keys().next().value!);
    hot.set(key,{body,expires:Date.now()+60000});
  }
  return{body,status:response.status};
}

export const api=onRequest({region:'us-central1',memory:'512MiB',timeoutSeconds:120,minInstances:0,maxInstances:1,concurrency:8,secrets:[token],cors:['https://easonli29.github.io'],invoker:'public'},async(req,res)=>{
  res.set('X-Content-Type-Options','nosniff');
  if(req.method!=='GET'){res.status(405).set('Allow','GET').json({error:'Method not allowed'});return}
  if(['/health','/api/health'].includes(req.path)){res.json({status:'ok',environment:'test',project:'vexrank-test'});return}
  const url=canonicalPath(req.path,new URL(req.originalUrl,'https://vexrank.invalid').searchParams);
  if(!url){res.status(400).json({error:'Unsupported route or query'});return}
  const key=createHash('sha256').update(`v1:${url.pathname}${url.search}`).digest('hex');
  try{
    const cached=hot.get(key);
    if(cached&&cached.expires>Date.now()){res.type('json').set('Cache-Control','public,max-age=60').send(cached.body);return}
    let pending=inflight.get(key);
    if(!pending){
      if(inflight.size>=2){res.status(503).set('Retry-After','10').json({error:'Data is refreshing. Please retry shortly.'});return}
      pending=readThrough(url,key).finally(()=>inflight.delete(key));inflight.set(key,pending);
    }
    const result=await pending;
    res.status(result.status).type('json').set('Cache-Control',result.status===200?'public,max-age=60':'no-store').send(result.body);
  }catch(error){console.error('Test API request failed',error instanceof Error?error.message:'unknown');res.status(502).set('Cache-Control','no-store').json({error:'Official data is temporarily unavailable. Please retry.'})}
});
