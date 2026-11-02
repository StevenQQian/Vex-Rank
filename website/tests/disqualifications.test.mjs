import test from 'node:test';
import assert from 'node:assert/strict';
import { officialRulings, rulingFor } from '../lib/disqualifications.mjs';

const side = (color, score, ...teams) => ({ color, score, teams: teams.map(name => ({ team: { name } })) });
const qual = (id, red, blue) => ({ id, round: 2, name: `Qualifier #${id}`, alliances: [red, blue] });
const rank = (name, wins, losses, ties = 0) => ({ team: { name }, wins, losses, ties });

test('VEX IQ: a station at 0 beside a scoring partner is a DQ', () => {
  const division = { matches: [qual(1, side('red', 144, '19970A'), side('blue', 0, '5216A')), qual(2, side('red', 0, '1A'), side('blue', 0, '2A'))], rankings: [] };
  const rulings = officialRulings(division, { iq: true });
  assert.equal(rulingFor(rulings, { id: 1 }, '5216A'), 'dq');
  assert.equal(rulingFor(rulings, { id: 1 }, '19970A'), null);
  assert.equal(rulings.byMatch.has(2), false, 'an unplayed 0-0 is not a DQ');
  // Any mismatch marks the lower station, as OpenScout does.
  const partial = officialRulings({ matches: [qual(3, side('red', 90, '7A'), side('blue', 85, '8A'))], rankings: [] }, { iq: true });
  assert.equal(rulingFor(partial, { id: 3 }, '8A'), 'dq');
});

test('V5: when every win on score was overturned, those matches are ruled losses', () => {
  // 3388G won #5 on score but is 0-2 officially.
  const division = {
    matches: [qual(5, side('red', 27, '45519S', '45519B'), side('blue', 30, '3388G', '2088Y')), qual(7, side('red', 0, '45519J', '3388G'), side('blue', 22, '14353S', '45519Z'))],
    rankings: [rank('3388G', 0, 2)],
  };
  const rulings = officialRulings(division);
  assert.equal(rulingFor(rulings, { id: 5 }, '3388G'), 'ruled-loss');
  assert.equal(rulingFor(rulings, { id: 7 }, '3388G'), null);
});

test('V5: when every non-win became a win, those matches are ruled wins', () => {
  const division = { matches: [qual(89, side('red', 83, '2145V', '32K'), side('blue', 93, '2567U', '2567M'))], rankings: [rank('32K', 1, 0)] };
  assert.equal(rulingFor(officialRulings(division), { id: 89 }, '32K'), 'ruled-win');
});

test('V5: a gap that could sit in more than one match marks nothing and is reported', () => {
  // Two wins on score, one official: which one was overturned is unknown.
  const division = {
    matches: [qual(1, side('red', 50, 'A1', 'B1'), side('blue', 10, 'C1', 'D1')), qual(2, side('red', 60, 'A1', 'E1'), side('blue', 20, 'F1', 'G1'))],
    rankings: [rank('A1', 1, 1)],
  };
  const rulings = officialRulings(division);
  assert.equal(rulings.byMatch.size, 0);
  assert.deepEqual(rulings.unresolved, ['A1']);
});
