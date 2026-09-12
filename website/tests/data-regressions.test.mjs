import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import ts from 'typescript';

async function loadModule(path) {
  const source = await readFile(new URL(path, import.meta.url), 'utf8');
  const { outputText } = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.ESNext, target: ts.ScriptTarget.ES2022 } });
  return import(`data:text/javascript;base64,${Buffer.from(outputText).toString('base64')}`);
}
const { vexCollection } = await loadModule('../lib/vex-api.ts');
const { parseAgenda } = await loadModule('../lib/agenda.ts');
const { bracketRound } = await loadModule('../lib/bracket.ts');

test('semifinal replays retain their bracket slot and missing byes leave a gap', () => {
  const games=[{id:1,round:4,instance:1,matchnum:1},{id:2,round:4,instance:2,matchnum:1},{id:3,round:4,instance:1,matchnum:2}];
  const slots=bracketRound(games,4,2);
  assert.equal(slots[0].id,3);
  assert.equal(slots[0].games.length,2);
  assert.equal(slots[1].id,2);
  assert.equal(bracketRound([{round:6,instance:6,matchnum:1}],6,8)[0],null);
});
const { classifyEvent } = await loadModule('../lib/event-classification.ts');

test('a Worlds qualifier is not the World Championship', () => {
  assert.equal(classifyEvent('Ontario Provincial Championship', 'World').levelClass, 'Event Region Championship');
  assert.equal(classifyEvent('2025 VEX Robotics World Championship - High School', 'World').levelClass, 'World Championship');
  assert.notEqual(classifyEvent('VEX Robotics World Championship Practice', 'World').levelClass, 'World Championship');
});

test('mentioning a signature event does not make a scrimmage a signature', () => {
  assert.equal(classifyEvent('Pre Mall Scrimmage: a week before the Signature event', null).levelClass, 'None');
  assert.equal(classifyEvent('Speedway', 'Signature').levelClass, 'Signature Event');
});

test('high-school names do not imply school-based tournament format', () => {
  assert.equal(classifyEvent('High School Tournament', null).eventType, 'Open Tournament');
  assert.equal(classifyEvent('School-Based Tournament', null).eventType, 'School-Based Tournament');
});

test('all pages are retained and elimination round filters survive pagination', async () => {
  const original = globalThis.fetch;
  const seen = [];
  globalThis.fetch = async value => {
    const url = new URL(value); seen.push(url);
    return Response.json({ data: [{ id: Number(url.searchParams.get('page')) }], meta: { last_page: 4 } });
  };
  try {
    assert.deepEqual(await vexCollection('https://events.vex.com/api/v2/events/1/matches?round[]=3&round[]=5', {}), [{id:1},{id:2},{id:3},{id:4}]);
    assert.ok(seen.every(url => url.searchParams.getAll('round[]').join(',') === '3,5'));
  } finally { globalThis.fetch = original; }
});

test('failed later pages reject rather than publish a partial collection', async () => {
  const original = globalThis.fetch;
  globalThis.fetch = async value => new URL(value).searchParams.get('page') === '1'
    ? Response.json({data:[{id:1}],meta:{last_page:2}})
    : new Response('', {status:403});
  try { await assert.rejects(vexCollection('https://events.vex.com/api/v2/events', {})); }
  finally { globalThis.fetch = original; }
});

test('table agenda keeps activity, start/end and location together', () => {
  const result = parseAgenda('Friday September 12 |\nStart Time | End Time | Activity | Location |\n08:30:00 AM | 06:00:00 PM | Pits Open | CCA Pits |', []);
  assert.equal(result.days[0].entries.length, 1);
  assert.equal(result.days[0].entries[0].activity, 'Pits Open');
  assert.equal(result.days[0].entries[0].location, 'CCA Pits');
  assert.equal(result.days[0].entries[0].time, '08:30 AM–06:00 PM');
});

test('single-day agendas without day headings still retain timed entries', () => {
  const result = parseAgenda('8:00 AM Doors open\n9:00 AM Qualification matches\nBring safety glasses', [new Date('2026-09-12T12:00:00')]);
  assert.equal(result.days[0].entries.length, 3);
  assert.equal(result.days[0].entries[0].activity, 'Doors open');
  assert.equal(result.days[0].entries[2].activity, 'Bring safety glasses');
});
