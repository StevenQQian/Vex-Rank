/**
 * Shared VCR event settlement for API responses, team history and archive builders.
 * Ratings here are internal points centered on 1500, not the VCR 2.0 public scale.
 * Keep all consumers on this module so identical evidence uses identical formulas.
 */
export const VCR_VERSION = 'VCR-3.0-candidate.2';
export const EVENT_WEIGHTS = Object.freeze({ C: .70, B: .82, A: .95, 'Bronze S': 1.15, 'Silver S': 1.35, 'Gold S': 1.60, Worlds: 1.85 });
const clamp=(x,lo,hi)=>Math.max(lo,Math.min(hi,x));
const finite=(x,name,lo=-Infinity,hi=Infinity)=>{if(!Number.isFinite(x)||x<lo||x>hi)throw new RangeError(`Invalid ${name}`);return x};
export const expectedResult=(own,opponent)=>1/(1+10**((finite(opponent,'opponent rating')-finite(own,'own rating'))/400));
// Rating-tier heuristic, separate from the calendar's classifyEvent display labels.
// In particular, this currently treats level=World as Worlds; the calendar treats
// that level as a qualifier flag. Changing this affects ratings and needs review.
export function eventTier(event){
  const text=`${event?.level??''} ${event?.name??''}`;
  if(event?.level==='World'||/world championship/i.test(text))return'Worlds';
  if(event?.level==='Signature'||/signature event/i.test(text))return'Silver S';
  if(['National','State'].includes(event?.level)||/national|state|regional|provincial championship/i.test(text))return'Bronze S';
  return'B';
}
/**
 * actual: loss=0, tie=0.5, win=1; expected and share are probabilities in [0,1].
 * scoreScale is a positive event scoring scale. Margin amplification is bounded
 * by 1.25; 2*share makes an equal two-team split retain the original residual.
 * Reliability is returned separately and applied when evidence is aggregated.
 */
export function matchEvidence({actual,expected,margin,scoreScale,share=.5,reliability=1}){
  if(![0,.5,1].includes(actual))throw new RangeError('Invalid actual');finite(expected,'expected',0,1);finite(margin,'margin');finite(scoreScale,'scoreScale',Number.MIN_VALUE);finite(share,'share',0,1);finite(reliability,'reliability',0,1);
  const mov=actual===.5?1:1+.25*Math.tanh(Math.abs(margin)/scoreScale);
  return{residual:(actual-expected)*mov*2*share,reliability};
}
// Average reliable evidence instead of rewarding match count indefinitely.
// Six units of reliable evidence reach full strength; smaller samples taper down.
const matchComponent=rows=>{let total=0,mass=0;for(const row of rows){finite(row.residual,'residual',-2.5,2.5);finite(row.reliability,'match reliability',0,1);total+=row.residual*row.reliability;mass+=row.reliability}return 40*(mass?total/mass:0)*Math.min(1,mass/6)};
/**
 * Pure calculation: returns an audit ledger without modifying input or team state.
 * The caller verifies event completion; completed=true is an assertion, not a check
 * against upstream data. Qualification/elimination inputs and title probability
 * are in [0,1]; null contribution/auto residuals mean unavailable evidence.
 */
export function settleEvent(input){
  const{rating,tier,matches,qualificationActual,qualificationExpected,eliminationActual,eliminationExpected,champion=false,titleProbability,completed,reliability=1,contributionResidual=null,autoResidual=null}=input;
  finite(rating,'rating');finite(reliability,'reliability',0,1);if(!Object.hasOwn(EVENT_WEIGHTS,tier))throw new RangeError('Unknown tier');if(completed!==true)throw new Error('Only a verified completed event may settle');
  for(const[k,v]of Object.entries({qualificationActual,qualificationExpected,eliminationActual,eliminationExpected,titleProbability}))finite(v,k,0,1);if(champion&&eliminationActual!==1)throw new Error('Champion must have eliminationActual=1');
  const statistic=(v,scale,name)=>v===null?0:scale*Math.tanh(finite(v,name,-10,10)/2);
  const components={match:matchComponent(matches),qualification:21*(qualificationActual-qualificationExpected),elimination:39*(eliminationActual-eliminationExpected),contribution:statistic(contributionResidual,8,'contribution residual'),auto:statistic(autoResidual,4,'auto residual')};
  // Upside follows tier weight; downside uses its bounded reciprocal. Apply event
  // reliability once here, independently of reliability on individual match rows.
  const base=Object.values(components).reduce((a,b)=>a+b,0),eventWeight=EVENT_WEIGHTS[tier],negativeWeight=clamp(1/eventWeight,.8,1.25),weighted=base*(base>=0?eventWeight:negativeWeight)*reliability;
  // Favorites who win cannot lose points; winners with <=25% title probability
  // receive a positive floor. Record the correction before the final +/-100 cap.
  const championFloor=champion?(titleProbability<=.25?8*eventWeight*(1-titleProbability)*reliability:0):null,achievementCorrection=champion?Math.max(0,championFloor-weighted):0,uncappedDelta=weighted+achievementCorrection,delta=clamp(uncappedDelta,-100,100);
  return{version:VCR_VERSION,ratingBefore:rating,ratingAfter:rating+delta,delta,components,base,eventWeight,negativeWeight,reliability,weighted,championFloor,achievementCorrection,capAdjustment:delta-uncappedDelta};
}
function activeTeams(alliance,includeSitting=false){return(alliance?.teams??[]).filter(x=>includeSitting||!x.sitting).map(x=>x.team).filter(Boolean)}
function resultFor(score,other){return score===other?.5:score>other?1:0}
function stage(match){const name=String(match?.name??'');if(/^final\b/i.test(name))return 1;if(/^sf\b|semifinal/i.test(name))return .65;if(/^qf\b|quarterfinal/i.test(name))return .45;if(/^r16\b|round of 16/i.test(name))return .25;return 0}
// Blend frozen strength with evidence from earlier matches in this event.
// Bound the partner split so a stronger partner never takes all two-team credit.
function dynamicShares(teams,ratings,local){
  if(teams.length===1)return[1];if(teams.length!==2)return teams.map(()=>1/teams.length);
  const strength=teams.map(t=>(ratings.get(t.id)??1500)+80*(local.get(t.id)??0));const raw=1/(1+Math.exp(-(strength[0]-strength[1])/220));const gap=Math.abs(strength[0]-strength[1]);const max=gap<100?.55:gap<200?.65:gap<300?.725:.8;const a=clamp(raw,1-max,max);return[a,1-a];
}
/**
 * Mutates states (Map keyed by numeric official team ID) and optional historyByTeam.
 * Call once per completed event, in event-end order: this is not idempotent.
 * Callers must exclude placeholders, deduplicate matches and verify completion;
 * this function only checks alliance/score shape. Match objects are not mutated.
 * Sitting teammates enter the field, but only active teammates get match evidence.
 */
export function processCompletedEvent({event,matches,states,historyByTeam}){
  const valid=matches.filter(m=>m?.alliances?.length===2&&m.alliances.every(a=>Number.isFinite(a.score)&&activeTeams(a).length));if(!valid.length)return;
  const participantIds=new Set(valid.flatMap(m=>m.alliances.flatMap(a=>activeTeams(a,true).map(t=>t.id))));for(const m of valid)for(const a of m.alliances)for(const t of activeTeams(a,true))if(!states.has(t.id))states.set(t.id,{id:t.id,number:t.name,rating:1500,matches:0,wins:0,losses:0,ties:0,pointsFor:0,pointsAgainst:0,events:new Set(),middleGradeEvents:new Set(),highGradeEvents:new Set()});
  // Freeze expectations for the entire event. Updating these inside the match loop
  // would make later opponents depend on already-settled outcomes in this event.
  const frozen=new Map([...participantIds].map(id=>[id,states.get(id)?.rating??1500])),field=[...frozen.values()].sort((a,b)=>a-b),mean=field.reduce((a,b)=>a+b,0)/field.length;
  // Softmax field-strength proxy for title probability, not a bracket simulation.
  const expWeights=new Map([...frozen].map(([id,r])=>[id,Math.exp((r-mean)/200)])),expTotal=[...expWeights.values()].reduce((a,b)=>a+b,0);
  // qA/qE hold actual/expected qualification results; elim is furthest named stage.
  // local accumulates residuals only for partner shares, never for expectations.
  const rows=new Map([...participantIds].map(id=>[id,{matches:[],qA:[],qE:[],elim:0,finalW:0,finalL:0}])),local=new Map();
  // Use event score spread (minimum 12) to limit margin sensitivity across games.
  const scores=valid.flatMap(m=>m.alliances.map(a=>a.score)),scoreMean=scores.reduce((a,b)=>a+b,0)/scores.length,scoreScale=Math.max(12,Math.sqrt(scores.reduce((s,x)=>s+(x-scoreMean)**2,0)/scores.length));
  for(const match of valid.sort((a,b)=>String(a.scheduled??a.started??'').localeCompare(String(b.scheduled??b.started??'')))){
    const[a,b]=match.alliances,ta=activeTeams(a),tb=activeTeams(b);const ra=ta.reduce((s,t)=>s+(frozen.get(t.id)??1500),0)/ta.length,rb=tb.reduce((s,t)=>s+(frozen.get(t.id)??1500),0)/tb.length,ea=expectedResult(ra,rb),aa=resultFor(a.score,b.score),qual=/qual/i.test(String(match.name??'')),final=/^final\b/i.test(String(match.name??''));
    for(const[alliance,opponent,teams,expected,actual]of[[a,b,ta,ea,aa],[b,a,tb,1-ea,1-aa]]){const shares=dynamicShares(teams,frozen,local);teams.forEach((team,i)=>{const row=rows.get(team.id),e=matchEvidence({actual,expected,margin:alliance.score-opponent.score,scoreScale,share:shares[i]});row.matches.push(e);local.set(team.id,(local.get(team.id)??0)+e.residual);if(qual){row.qA.push(actual);row.qE.push(expected)}row.elim=Math.max(row.elim,stage(match));if(final){actual===1?row.finalW++:actual===0&&row.finalL++}})}
  }
  // Finals wins/losses infer champions from match names, not awards. Multi-division
  // events aggregate those records per team; this is not an overall-bracket resolver.
  // Missing qualification evidence contributes zero (both means default to 0.5).
  const tier=eventTier(event);
  for(const id of participantIds){const team=states.get(id),row=rows.get(id),champion=row.finalW>row.finalL&&row.finalW>0;if(champion)row.elim=1;else if(row.finalL>row.finalW&&row.finalL>0)row.elim=.85;const own=frozen.get(id),below=field.filter(x=>x<own).length,equal=field.filter(x=>x===own).length,percentile=field.length>1?(below+.5*(equal-1))/(field.length-1):.5,expectedElim=.1+.55*percentile,titleProbability=(expWeights.get(id)??1)/expTotal,qA=row.qA.length?row.qA.reduce((a,b)=>a+b,0)/row.qA.length:.5,qE=row.qE.length?row.qE.reduce((a,b)=>a+b,0)/row.qE.length:.5,reliability=Math.min(1,valid.length/6);
    // Contribution/autonomous estimates are unavailable in this adapter. Keep them
    // null rather than inventing evidence. Save rawChange before display rounding.
    const ledger=settleEvent({rating:team.rating,tier,matches:row.matches,qualificationActual:qA,qualificationExpected:qE,eliminationActual:row.elim,eliminationExpected:expectedElim,champion,titleProbability,completed:true,reliability,contributionResidual:null,autoResidual:null});team.rating=ledger.ratingAfter;team.events.add(event.id);if(historyByTeam){if(!historyByTeam.has(id))historyByTeam.set(id,[]);historyByTeam.get(id).push({seasonId:event.season?.id,eventId:event.id,event:event.name,eventDate:event.start,change:Math.round(ledger.delta),rawChange:ledger.delta,rating:Math.round(team.rating),matches:row.matches.length,version:VCR_VERSION,tier,champion,components:ledger.components,achievementCorrection:ledger.achievementCorrection})}
  }
  for(const match of valid)for(const[own,other]of[[match.alliances[0],match.alliances[1]],[match.alliances[1],match.alliances[0]]])for(const t of activeTeams(own)){const team=states.get(t.id);team.matches++;team.pointsFor+=own.score;team.pointsAgainst+=other.score;own.score>other.score?team.wins++:own.score<other.score?team.losses++:team.ties++}
}

