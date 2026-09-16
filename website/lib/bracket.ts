/** Keep replays in their original bracket position instead of creating a new opponent. */
// round + one-based instance identifies a slot; matchnum orders its games/replays.
// Return the latest game for the card and every game for details. Keep null slots:
// removing them would shift opponents and draw incorrect bracket connections.
export function bracketRound(matches:any[], round:number, slots:number) {
  return Array.from({length:slots},(_,index)=>{
    const games=matches.filter(match=>Number(match.round)===round&&Number(match.instance)===index+1)
      .sort((a,b)=>Number(a.matchnum)-Number(b.matchnum));
    return games.length?{...games[games.length-1],games}:null;
  });
}
