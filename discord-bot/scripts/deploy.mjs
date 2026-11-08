// One command from nothing to a working #verify channel:
//   1. check the tokens             4. point Discord at the worker
//   2. deploy the worker            5. find the server and its #verify channel
//   3. upload its secrets           6. post (or refresh) the Verify panel
// Safe to rerun: every step replaces what the last run left.
import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { PANEL, START_BUTTON } from '../src/verify.ts';

const root = fileURLToPath(new URL('..', import.meta.url));
const API = 'https://discord.com/api/v10';
const MANAGE_ROLES = 268435456n;
const ADMINISTRATOR = 8n;
// View Channel, Send Messages, Embed Links, Read Message History, Manage Nicknames, Manage Roles.
const PERMISSIONS = 1024 + 2048 + 16384 + 65536 + 134217728 + Number(MANAGE_ROLES);

function fail(message) {
  console.error(`\n✗ ${message}`);
  process.exit(1);
}

function loadEnv() {
  let text = '';
  try { text = readFileSync(new URL('../.env', import.meta.url), 'utf8'); } catch {
    fail('No .env file. Copy .env.example to .env and fill it in (see README.md).');
  }
  const env = Object.fromEntries(text.split('\n')
    .map(line => line.match(/^\s*([A-Z_]+)\s*=\s*(.*?)\s*$/))
    .filter(Boolean)
    .map(([, key, value]) => [key, value.replace(/^['"]|['"]$/g, '')]));
  for (const key of ['DISCORD_TOKEN', 'ROBOT_EVENTS_API_TOKEN']) if (!env[key]) fail(`${key} is missing from .env.`);
  return env;
}

const env = loadEnv();

async function discord(method, path, body) {
  const response = await fetch(`${API}${path}`, {
    method,
    headers: { Authorization: `Bot ${env.DISCORD_TOKEN}`, 'Content-Type': 'application/json' },
    body: body && JSON.stringify(body),
  });
  const payload = response.status === 204 ? null : await response.json();
  if (!response.ok) fail(`Discord ${method} ${path} → ${response.status} ${JSON.stringify(payload)}`);
  return payload;
}

// A CLOUDFLARE_API_TOKEN in .env stands in for `wrangler login`.
const wranglerEnv = { ...process.env, ...(env.CLOUDFLARE_API_TOKEN ? { CLOUDFLARE_API_TOKEN: env.CLOUDFLARE_API_TOKEN } : {}) };

function wrangler(args, input) {
  try {
    return execFileSync('npx', ['--yes', 'wrangler@4', ...args],
      { cwd: root, input, env: wranglerEnv, encoding: 'utf8', stdio: ['pipe', 'pipe', 'pipe'] });
  } catch (error) {
    process.stderr.write(error.stdout ?? '');
    process.stderr.write(error.stderr ?? '');
    fail(`wrangler ${args[0]} failed (output above).`);
  }
}

console.log('==> Checking tokens');
const app = await discord('GET', '/applications/@me');
console.log(`  Discord bot: ${app.name} ✓`);

const vex = await fetch('https://events.vex.com/api/v2/teams?number%5B%5D=55288A&program%5B%5D=1', {
  headers: { Authorization: `Bearer ${env.ROBOT_EVENTS_API_TOKEN}`, Accept: 'application/json' },
  redirect: 'manual',
});
if (!vex.ok) fail(`events.vex.com refused ROBOT_EVENTS_API_TOKEN (HTTP ${vex.status}). Check the token in .env.`);
console.log('  events.vex.com ✓');

// whoami's exit code varies when signed out, so its output is what tells.
let whoami = '';
try {
  whoami = execFileSync('npx', ['--yes', 'wrangler@4', 'whoami'], { cwd: root, env: wranglerEnv, encoding: 'utf8', stdio: 'pipe' });
} catch (error) {
  whoami = `${error.stdout ?? ''}${error.stderr ?? ''}`;
}
if (/not authenticated/i.test(whoami) || !/you are logged in/i.test(whoami)) {
  fail('Not signed in to Cloudflare. Put a CLOUDFLARE_API_TOKEN in .env (see README.md),\n'
    + '  or run `npx wrangler login` and approve it in the browser.');
}
console.log('  Cloudflare ✓');

console.log('\n==> Deploying worker');
const output = wrangler(['deploy']);
const url = output.match(/https:\/\/[^\s]+\.workers\.dev/)?.[0];
if (!url) fail(`Could not find the worker URL in the wrangler output:\n${output}`);
console.log(`  ${url} ✓`);

console.log('\n==> Uploading secrets');
// The public key comes from Discord itself, so it can't be pasted wrong.
const secrets = {
  DISCORD_PUBLIC_KEY: app.verify_key,
  DISCORD_TOKEN: env.DISCORD_TOKEN,
  ROBOT_EVENTS_API_TOKEN: env.ROBOT_EVENTS_API_TOKEN,
};
for (const [key, value] of Object.entries(secrets)) {
  wrangler(['secret', 'put', key], value);
  console.log(`  ${key} ✓`);
}

console.log('\n==> Pointing Discord at the worker');
// Discord pings the URL before saving it, so this also proves the worker and
// its public key are right.
await discord('PATCH', '/applications/@me', { interactions_endpoint_url: url });
console.log('  ✓');

console.log('\n==> Finding #verify');
const guilds = await discord('GET', '/users/@me/guilds');
const invite = `https://discord.com/oauth2/authorize?client_id=${app.id}&scope=bot&permissions=${PERMISSIONS}`;
if (!guilds.length) fail(`The bot isn't in a server yet. Invite it with:\n  ${invite}\nthen run this again.`);
const guild = env.DISCORD_GUILD_ID ? guilds.find(g => g.id === env.DISCORD_GUILD_ID) : guilds.length === 1 ? guilds[0] : null;
if (!guild) {
  fail(`The bot is in several servers. Set DISCORD_GUILD_ID in .env to one of:\n${guilds.map(g => `  ${g.id}  ${g.name}`).join('\n')}`);
}
const channels = await discord('GET', `/guilds/${guild.id}/channels`);
const channel = channels.find(c => c.type === 0 && c.name === (env.VERIFY_CHANNEL || 'verify'));
if (!channel) fail(`No #${env.VERIFY_CHANNEL || 'verify'} text channel in ${guild.name}, or the bot can't see it.`);
console.log(`  ${guild.name} → #${channel.name} ✓`);

const roleName = env.VERIFIED_ROLE ?? 'User';
if (roleName) {
  console.log(`\n==> Checking the ${roleName} role`);
  const roles = await discord('GET', `/guilds/${guild.id}/roles`);
  const role = roles.find(r => r.name === roleName);
  if (!role) fail(`No role named "${roleName}" in ${guild.name}. Set VERIFIED_ROLE in .env, or leave it empty for no role.`);
  const me = await discord('GET', `/guilds/${guild.id}/members/${app.id}`);
  const mine = roles.filter(r => me.roles.includes(r.id));
  const perms = mine.reduce((all, r) => all | BigInt(r.permissions), 0n);
  if (!(perms & (MANAGE_ROLES | ADMINISTRATOR))) {
    fail(`The bot needs the Manage Roles permission to give out "${roleName}".\n`
      + `  In Discord: Server Settings → Roles → ${mine.find(r => r.managed)?.name ?? app.name} → Permissions → turn on Manage Roles.\n`
      + '  Then run this again.');
  }
  // Discord only lets a bot assign roles below its own highest one.
  if (Math.max(...mine.map(r => r.position)) <= role.position) {
    fail(`The bot's role must be above "${roleName}" in Server Settings → Roles. Drag it higher, then run this again.`);
  }
  wrangler(['secret', 'put', 'VERIFIED_ROLE_ID'], role.id);
  console.log(`  Members get "${roleName}" on verification ✓`);
} else {
  // An empty VERIFIED_ROLE turns the role off; the worker then only renames.
  // Missing already is fine, so this doesn't go through wrangler(), which exits on failure.
  try {
    execFileSync('npx', ['--yes', 'wrangler@4', 'secret', 'delete', 'VERIFIED_ROLE_ID', '--force'], { cwd: root, env: wranglerEnv, stdio: 'pipe' });
  } catch {}
}

console.log('\n==> Posting the Verify panel');
const recent = await discord('GET', `/channels/${channel.id}/messages?limit=50`);
const existing = recent.find(m => m.author.id === app.id
  && m.components?.some(row => row.components?.some(c => c.custom_id === START_BUTTON)));
if (existing) {
  await discord('PATCH', `/channels/${channel.id}/messages/${existing.id}`, PANEL);
  console.log('  Updated the existing panel ✓');
} else {
  await discord('POST', `/channels/${channel.id}/messages`, PANEL);
  console.log('  Posted ✓');
}

console.log(`\nDone. Members can now verify in #${channel.name}.`);
console.log('Reminder: the bot\'s role must sit above the roles of the members it renames.');
