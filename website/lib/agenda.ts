/**
 * Parse organizer text (including pipe-separated HTML-table cells) for the agenda UI.
 * fallbackDays supplies headings when the organizer omits them; it does not invent
 * activities. Preserve unrecognized text as notes or untimed entries.
 */
export function parseAgenda(text:string, fallbackDays:Date[]) {
  const weekdayPattern=/^(Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday)\b/i;
  const dayPattern=/^day\s*\d+\b/i;
  const datePattern=/^(January|February|March|April|May|June|July|August|September|October|November|December)\s+\d{1,2}/i;
  const timePattern=/^((?:\d{1,2}(?::\d{2})?\s*(?:AM|PM)?\s*(?:–|-|to)\s*)?\d{1,2}(?::\d{2})?\s*(?:AM|PM)|\d{1,2}(?::\d{2})?\s*(?:–|-)\s*\d{1,2}(?::\d{2})?|Noon|Midnight|TBA|All Day)\s*(?:[|:–—-]\s*)?(.*)$/i;
  const segments:any[]=[];
  const notes:string[]=[];
  let current:any=null;
  const lines=String(text||'').split('\n').map(line=>line.replace(/^#+\s*/,'').replace(/\s*\|\s*$/,'').replace(/(\d{1,2}:\d{2}):00\s*(AM|PM)/gi,'$1 $2').replace(/^•\s*/, '').trim()).filter(line=>line&&!/^[|—–-]+$/.test(line));
  for(let index=0;index<lines.length;index++) {
    const line=lines[index];
    if(dayPattern.test(line)) { current={title:line.toLowerCase().replace(/\b\w/g,letter=>letter.toUpperCase()),raw:[]};segments.push(current);continue; }
    if(weekdayPattern.test(line)||datePattern.test(line)) { const label=line.toLowerCase().replace(/\b\w/g,letter=>letter.toUpperCase());if(current&&dayPattern.test(current.title)&&current.raw.length===0)current.title=label;else{current={title:label,raw:[]};segments.push(current)}continue; }
    if(!current&&timePattern.test(line)){current={title:fallbackDays[0]?.toLocaleDateString('en-US',{weekday:'long',month:'long',day:'numeric'})??'Schedule',raw:[]};segments.push(current)}
    if(!current) { notes.push(line);continue; }
    current.raw.push(line);
  }
  const cleanDays=(segments.length?segments:fallbackDays.map(day=>({title:day.toLocaleDateString('en-US',{weekday:'long',month:'long',day:'numeric'}),raw:[]}))).map(segment=>({title:segment.title,entries:agendaEntries(segment.raw,timePattern)}));
  return {days:cleanDays,notes:Array.from(new Set(notes.filter(note=>note.length>2)))};
}

// Recognize the four-column organizer table before free-form time parsing.
// The column path assumes Start time, End time, Activity, Location order; keep
// fixtures for both table and plain-text schedules when changing this parser.
function agendaEntries(raw:string[],timePattern:RegExp) {
  const cells=raw.flatMap(line=>line.split('|')).map(line=>line.trim()).filter(Boolean);const headers=['start time','end time','activity','location'];const hasColumns=headers.every(header=>cells.some(line=>line.toLowerCase()===header));
  if(hasColumns){const values=cells.filter(line=>!headers.includes(line.toLowerCase()));const entries=[];for(let index=0;index<values.length;index+=4){const [start,end,activity,location]=values.slice(index,index+4);if(!activity){entries.push({time:'',activity:values.slice(index).join(' · '),location:''});continue;}entries.push({time:[cleanAgendaTime(start),cleanAgendaTime(end)].filter(Boolean).join('–'),activity,location:location||''})}return entries}
  const entries:any[]=[];for(let index=0;index<raw.length;index++){const line=raw[index];const match=line.match(timePattern);if(match){let activity=match[2].replace(/^[|:–—-]+\s*/,'').replace(/\s*\|\s*/g,' ').trim();if(!activity&&raw[index+1]&&!timePattern.test(raw[index+1]))activity=raw[++index].replace(/^[|:–—-]+\s*/,'').trim();if(activity)entries.push({time:match[1].replace(/\s+/g,' '),activity})}else{const activity=line.replace(/^[|:–—-]+\s*/,'').trim();if(activity)entries.push({time:'',activity})}}return entries.filter((entry,index,list)=>entry.activity&&!(index>0&&entry.time===list[index-1].time&&entry.activity===list[index-1].activity));
}
function cleanAgendaTime(value:string) { return String(value??'').trim().replace(/^(\d{1,2}:\d{2}):\d{2}\s*(AM|PM)$/i,'$1 $2'); }
