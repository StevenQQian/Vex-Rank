/** Keep replays in their original bracket position instead of creating a new opponent. */
export function bracketRound(matches:any[], round:number, slots:number) {
  return Array.from({length:slots},(_,index)=>{
    const games=matches.filter(match=>Number(match.round)===round&&Number(match.instance)===index+1)
      .sort((a,b)=>Number(a.matchnum)-Number(b.matchnum));
    return games.length?{...games[games.length-1],games}:null;
  });
}
