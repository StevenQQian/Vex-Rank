import test from 'node:test';
import assert from 'node:assert/strict';
import worker from '../src/worker.ts';
import { cleanName, cleanTeamNumber, modalValues, nickname, RETRY_PREFIX } from '../src/verify.ts';

test('team numbers are normalised and junk is refused', () => {
  assert.equal(cleanTeamNumber(' #55288a '), '55288A');
  assert.equal(cleanTeamNumber('1698 Z'), '1698Z');
  assert.equal(cleanTeamNumber('Makapaka'), null);
  assert.equal(cleanTeamNumber('55288A; DROP'), null);
  assert.equal(cleanTeamNumber(''), null);
});

test('names lose pipes and extra spaces', () => {
  assert.equal(cleanName('  Steven   Q  '), 'Steven Q');
  assert.equal(cleanName('A|B'), 'A B');
  assert.equal(cleanName(' | '), null);
});

test('nickname keeps the team and fits in 32 characters', () => {
  assert.equal(nickname('Steven', '55288A'), 'Steven | 55288A');
  const long = nickname('Bartholomew Montgomery-Smithson', '10102A');
  assert.equal(long.length <= 32, true);
  assert.equal(long.endsWith(' | 10102A'), true);
});

test('modal values are read from classic and label layouts', () => {
  assert.deepEqual(modalValues([
    { type: 1, components: [{ type: 4, custom_id: 'name', value: 'Steven' }] },
    { type: 18, component: { type: 4, custom_id: 'team', value: '55288A' } },
  ]), { name: 'Steven', team: '55288A' });
});

// --- The worker, end to end, against a fake Discord and a fake VEX lookup.

const keys = await crypto.subtle.generateKey('Ed25519', true, ['sign', 'verify']);
const publicKey = Buffer.from(await crypto.subtle.exportKey('raw', keys.publicKey)).toString('hex');

function harness({ teams = { '55288A': 'Makapaka' }, rename = 204, vex = 200, role = 204, roleId = 'r1' } = {}) {
  const calls = [];
  const pending = [];
  const realFetch = globalThis.fetch;
  globalThis.fetch = async (url, init = {}) => {
    const href = String(url);
    if (href.startsWith('https://events.vex.com/')) {
      calls.push({ url: href, auth: init.headers.Authorization, redirect: init.redirect });
      if (vex !== 200) return new Response('', { status: vex });
      const number = new URL(href).searchParams.get('number[]');
      // The API matches loosely, so return a near miss the worker must skip.
      const data = [{ number: `${number}X`, team_name: 'Other' },
        ...(teams[number] ? [{ number, team_name: teams[number] }] : [])];
      return Response.json({ data });
    }
    calls.push({ url: href, method: init.method, body: init.body === undefined ? undefined : JSON.parse(init.body) });
    const status = href.includes('/roles/') ? role : href.includes('/members/') ? rename : 200;
    return new Response(status === 204 ? null : '{}', { status });
  };
  const env = { DISCORD_PUBLIC_KEY: publicKey, DISCORD_TOKEN: 'test-token', ROBOT_EVENTS_API_TOKEN: 'vex-token', ...(roleId ? { VERIFIED_ROLE_ID: roleId } : {}) };
  const ctx = { waitUntil: p => pending.push(p) };
  const send = async (interaction, { sign = true } = {}) => {
    const body = JSON.stringify(interaction);
    const timestamp = '1727400000';
    const signature = sign
      ? Buffer.from(await crypto.subtle.sign('Ed25519', keys.privateKey, new TextEncoder().encode(timestamp + body))).toString('hex')
      : '00'.repeat(64);
    const response = await worker.fetch(new Request('https://bot/', {
      method: 'POST', body,
      headers: { 'X-Signature-Ed25519': signature, 'X-Signature-Timestamp': timestamp },
    }), env, ctx);
    await Promise.all(pending.splice(0));
    return response;
  };
  return { send, calls, restore: () => { globalThis.fetch = realFetch; } };
}

const base = { application_id: 'app1', token: 'itok', guild_id: 'g1', member: { user: { id: 'u1' } } };
const submit = (name, team) => ({
  ...base, type: 5,
  data: { custom_id: 'verify:submit', components: [
    { type: 1, components: [{ type: 4, custom_id: 'name', value: name }] },
    { type: 1, components: [{ type: 4, custom_id: 'team', value: team }] },
  ] },
});

test('unsigned requests are rejected', async () => {
  const h = harness();
  const response = await h.send({ type: 1 }, { sign: false });
  h.restore();
  assert.equal(response.status, 401);
});

test('Discord endpoint check gets a pong', async () => {
  const h = harness();
  const response = await h.send({ type: 1 });
  h.restore();
  assert.deepEqual(await response.json(), { type: 1 });
});

test('the Verify button opens the form', async () => {
  const h = harness();
  const reply = await (await h.send({ ...base, type: 3, data: { custom_id: 'verify:start' } })).json();
  h.restore();
  assert.equal(reply.type, 9);
  assert.deepEqual(reply.data.components.map(r => r.components[0].custom_id), ['name', 'team']);
});

test('a real team renames the member to Name | Team', async () => {
  const h = harness();
  const reply = await (await h.send(submit('Steven', '55288a'))).json();
  h.restore();
  assert.equal(reply.type, 5);
  const rename = h.calls.find(c => c.url.endsWith('/guilds/g1/members/u1'));
  assert.deepEqual(rename.body, { nick: 'Steven | 55288A' });
  const followUp = h.calls.find(c => c.url.endsWith('/webhooks/app1/itok/messages/@original'));
  assert.match(followUp.body.content, /Verified with team \*\*55288A\*\* \(Makapaka\)/);
  assert.deepEqual(followUp.body.components, []);
});

test('verification gives the configured role without pinging it', async () => {
  const h = harness();
  await h.send(submit('Steven', '55288A'));
  h.restore();
  const grant = h.calls.find(c => c.url.endsWith('/guilds/g1/members/u1/roles/r1'));
  assert.equal(grant.method, 'PUT');
  const followUp = h.calls.find(c => c.url.includes('/messages/@original'));
  assert.match(followUp.body.content, /You now have the <@&r1> role/);
  assert.deepEqual(followUp.body.allowed_mentions, { parse: [] });
});

test('the role is still given when Discord refuses the rename', async () => {
  const h = harness({ rename: 403 });
  await h.send(submit('Steven', '55288A'));
  h.restore();
  assert.ok(h.calls.some(c => c.url.endsWith('/roles/r1')));
  const followUp = h.calls.find(c => c.url.includes('/messages/@original'));
  assert.match(followUp.body.content, /yourself\. You now have the <@&r1> role/);
});

test('a refused role is reported, and the rename still happens', async () => {
  const h = harness({ role: 403 });
  await h.send(submit('Steven', '55288A'));
  h.restore();
  assert.ok(h.calls.some(c => c.url.endsWith('/members/u1') && c.method === 'PATCH'));
  const followUp = h.calls.find(c => c.url.includes('/messages/@original'));
  assert.match(followUp.body.content, /couldn't give you the <@&r1> role/);
});

test('with no role configured, only the name changes', async () => {
  const h = harness({ roleId: null });
  await h.send(submit('Steven', '55288A'));
  h.restore();
  assert.equal(h.calls.some(c => c.url.includes('/roles/')), false);
  const followUp = h.calls.find(c => c.url.includes('/messages/@original'));
  assert.doesNotMatch(followUp.body.content, /role/);
});

test('an unknown team warns and offers a prefilled retry', async () => {
  const h = harness();
  await h.send(submit('Steven', '99999Z'));
  h.restore();
  assert.equal(h.calls.some(c => c.url.includes('/members/')), false, 'must not rename or give the role');
  const followUp = h.calls.find(c => c.url.includes('/messages/@original'));
  assert.match(followUp.body.content, /couldn't find V5RC team \*\*99999Z\*\*/);
  const button = followUp.body.components[0].components[0];
  assert.equal(button.custom_id, `${RETRY_PREFIX}Steven`);
});

test('retry reopens the form with the name filled in', async () => {
  const h = harness();
  const reply = await (await h.send({ ...base, type: 3, data: { custom_id: `${RETRY_PREFIX}Steven` } })).json();
  h.restore();
  assert.equal(reply.data.components[0].components[0].value, 'Steven');
  assert.equal('value' in reply.data.components[1].components[0], false);
});

test('a malformed team number is refused without a lookup', async () => {
  const h = harness();
  const reply = await (await h.send(submit('Steven', 'Makapaka'))).json();
  h.restore();
  assert.equal(reply.type, 4);
  assert.match(reply.data.content, /isn't a team number/);
  assert.equal(h.calls.length, 0);
});

test('a rename Discord refuses explains what to do', async () => {
  const h = harness({ rename: 403 });
  await h.send(submit('Steven', '55288A'));
  h.restore();
  const followUp = h.calls.find(c => c.url.includes('/messages/@original'));
  assert.match(followUp.body.content, /Set your server name to \*\*Steven \| 55288A\*\* yourself/);
});

test('the lookup asks events.vex.com for V5RC teams with the token', async () => {
  const h = harness();
  await h.send(submit('Steven', '55288A'));
  h.restore();
  const lookup = h.calls.find(c => c.url.startsWith('https://events.vex.com/'));
  const url = new URL(lookup.url);
  assert.equal(url.pathname, '/api/v2/teams');
  assert.equal(url.searchParams.get('number[]'), '55288A');
  assert.equal(url.searchParams.get('program[]'), '1');
  assert.equal(lookup.auth, 'Bearer vex-token');
  assert.equal(lookup.redirect, 'manual');
});

test('a rejected VEX token is not reported as a missing team', async () => {
  const h = harness({ vex: 302 });
  await h.send(submit('Steven', '55288A'));
  h.restore();
  assert.equal(h.calls.some(c => c.url.includes('/members/')), false);
  const followUp = h.calls.find(c => c.url.includes('/messages/@original'));
  assert.match(followUp.body.content, /isn't responding/);
});

test('a VEX outage is not reported as a missing team', async () => {
  const h = harness({ vex: 503 });
  await h.send(submit('Steven', '55288A'));
  h.restore();
  const followUp = h.calls.find(c => c.url.includes('/messages/@original'));
  assert.match(followUp.body.content, /isn't responding/);
});
