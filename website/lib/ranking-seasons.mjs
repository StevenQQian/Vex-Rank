// Labels are UI keys; numeric IDs are official upstream season identifiers.
// archive=null selects live data. Historical paths require versioned VCR 3 data.
export const RANKING_SEASONS = Object.freeze({
  '2026–27 Override': {id:204,archive:null},
  '2025–26 Push Back': {id:197,archive:'/rankings-2025-26-vcr3.json'},
  '2024–25 High Stakes': {id:190,archive:'/rankings-2024-25-vcr3.json'},
  '2023–24 Over Under': {id:181,archive:'/rankings-2023-24-vcr3.json'},
  '2022–23 Spin Up': {id:173,archive:'/rankings-2022-23-vcr3.json'},
});
// Fail closed on mismatched season/model or incomplete download coverage.
// This checks envelope metadata, not every team row or exact candidate version:
// publication also relies on the builder's validation and archive regression tests.
export function validateArchive(data,season) {
  if(data?.seasonId!==RANKING_SEASONS[season]?.id||!String(data?.modelVersion??'').startsWith('VCR-3.0')||!Array.isArray(data?.rankings)||!data.rankings.length||data.coverage?.failures?.length!==0||data.coverage?.loadedEvents!==data.coverage?.expectedEvents)throw new Error('The requested VCR 3.0 archive is not complete.');
  return data;
}

