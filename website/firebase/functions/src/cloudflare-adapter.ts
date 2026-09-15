import { database } from './database';

// Port the existing rank-lock contract without changing how ratings are calculated.
export const env={DB:{prepare(sql:string){
  let values:any[]=[];
  const statement={
    bind(...args:any[]){values=args;return statement},
    async run(){
      if(/^CREATE TABLE/i.test(sql.trim()))return;
      if(!sql.startsWith('INSERT OR IGNORE INTO event_rank_locks'))throw new Error('Unsupported rank-lock statement');
      const [event_id,tier,rank_score,team_count,locked_at]=values;
      const ref=database().collection('event_rank_locks').doc(String(event_id));
      await database().runTransaction(async tx=>{if(!(await tx.get(ref)).exists)tx.create(ref,{event_id,tier,rank_score,team_count,locked_at})});
    },
    async first(){
      if(!sql.startsWith('SELECT tier,rank_score,team_count,locked_at FROM event_rank_locks'))throw new Error('Unsupported rank-lock query');
      return (await database().collection('event_rank_locks').doc(String(values[0])).get()).data()??null;
    },
  };return statement;
}}};
