export const RANKING_SEASONS = Object.freeze({
  '2026–27 Override': {id:204,archive:null},
  '2025–26 Push Back': {id:197,archive:'/rankings-2025-26-vcr3.json'},
  '2024–25 High Stakes': {id:190,archive:'/rankings-2024-25-vcr3.json'},
  '2023–24 Over Under': {id:181,archive:'/rankings-2023-24-vcr3.json'},
  '2022–23 Spin Up': {id:173,archive:'/rankings-2022-23-vcr3.json'},
});
export function validateArchive(data,season) {
  if(data?.seasonId!==RANKING_SEASONS[season]?.id||!String(data?.modelVersion??'').startsWith('VCR-3.0')||!Array.isArray(data?.rankings)||!data.rankings.length||data.coverage?.failures?.length!==0||data.coverage?.loadedEvents!==data.coverage?.expectedEvents)throw new Error('The requested VCR 3.0 archive is not complete.');
  return data;
}

