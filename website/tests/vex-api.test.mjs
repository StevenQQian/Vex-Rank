import test from 'node:test';
import assert from 'node:assert/strict';
import { vexJson } from '../lib/vex-api.ts';

// Each test uses a distinct URL: vexJson keeps a process-local cache of
// successful pages, and sharing a URL would let one test answer another.
// Takes factories, not responses: a Response body can only be read once, and a
// retry test needs a fresh one each time round.
function stub(make) {
  const calls = [];
  globalThis.fetch = async (url, init) => {
    calls.push({ url, redirect: init?.redirect });
    return make(calls.length - 1);
  };
  return calls;
}

const json = (body) => new Response(JSON.stringify(body), { status: 200, headers: { 'Content-Type': 'application/json' } });
const status = (code, headers) => new Response('', { status: code, headers });

test('a redirect to sign-in is reported as credentials, not as an outage', async () => {
  // Official data answers an expired token with a 302 to its login page. Left
  // to follow it, fetch lands on HTML, fails to parse, and the failure is
  // retried three times - so the one problem a person could actually fix reads
  // as "temporarily unavailable, please retry".
  const calls = stub(() => status(302, { Location: '/auth/login' }));
  await assert.rejects(
    () => vexJson('https://events.vex.com/api/v2/events?redirect-case', {}),
    /credentials/i
  );
  assert.equal(calls.length, 1, 'a rejected token must not be retried');
  assert.equal(calls[0].redirect, 'manual', 'the redirect has to be visible to be recognised');
});

test('401 and 403 are terminal too', async () => {
  for (const code of [401, 403]) {
    const calls = stub(() => status(code));
    await assert.rejects(
      () => vexJson(`https://events.vex.com/api/v2/events?auth-${code}`, {}),
      /credentials/i
    );
    assert.equal(calls.length, 1, `${code} must not be retried`);
  }
});

test('a genuine server error is still retried', async () => {
  const calls = stub(() => status(500));
  await assert.rejects(() => vexJson('https://events.vex.com/api/v2/events?five-hundred', {}), /unavailable/i);
  assert.equal(calls.length, 3, 'transient failures are worth another go');
});

test('a success is returned and served from cache the second time', async () => {
  const calls = stub(() => json({ data: [{ id: 1 }] }));
  const url = 'https://events.vex.com/api/v2/events?cache-case';
  assert.deepEqual(await vexJson(url, {}), { data: [{ id: 1 }] });
  assert.deepEqual(await vexJson(url, {}), { data: [{ id: 1 }] });
  assert.equal(calls.length, 1, 'the second read should not reach the network');
});
