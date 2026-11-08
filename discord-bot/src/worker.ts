// Discord interactions endpoint for the #verify channel. Discord POSTs every
// button press and form submission here; nothing runs between them.
import {
  cleanName, cleanTeamNumber, modalValues, nickname, success, verifyModal, warning,
  MODAL_ID, RETRY_PREFIX, START_BUTTON,
} from './verify.ts';

export interface Env {
  DISCORD_PUBLIC_KEY: string;
  DISCORD_TOKEN: string;
  ROBOT_EVENTS_API_TOKEN: string;
  /** Given on verification. Optional: without it the bot only renames. */
  VERIFIED_ROLE_ID?: string;
}

type Ctx = { waitUntil(promise: Promise<unknown>): void };

const DISCORD = 'https://discord.com/api/v10';
const VEX = 'https://events.vex.com/api/v2';
/** V5RC. The lookup is limited to it so a VIQRC team with the same number can't match. */
const V5RC = 1;

const hex = (value: string) => new Uint8Array(value.match(/../g)?.map(byte => parseInt(byte, 16)) ?? []);

export async function verifySignature(publicKey: string, signature: string, timestamp: string, body: string) {
  try {
    const key = await crypto.subtle.importKey('raw', hex(publicKey), { name: 'Ed25519' }, false, ['verify']);
    return await crypto.subtle.verify('Ed25519', key, hex(signature), new TextEncoder().encode(timestamp + body));
  } catch {
    return false;
  }
}

type Lookup = { found: true; number: string; name: string } | { found: false; reason: 'missing' | 'unavailable' };

export async function lookupTeam(env: Env, number: string): Promise<Lookup> {
  try {
    const response = await fetch(`${VEX}/teams?number%5B%5D=${encodeURIComponent(number)}&program%5B%5D=${V5RC}`, {
      headers: { Authorization: `Bearer ${env.ROBOT_EVENTS_API_TOKEN}`, Accept: 'application/json' },
      // A missing or expired token is answered with a redirect to the login
      // page. Following it would read that page as "no such team".
      redirect: 'manual',
    });
    if (!response.ok) {
      console.error('VEX lookup failed', response.status);
      return { found: false, reason: 'unavailable' };
    }
    const { data } = await response.json() as { data: { number: string; team_name?: string }[] };
    const team = data.find(entry => entry.number.toUpperCase() === number);
    return team ? { found: true, number: team.number, name: team.team_name ?? '' } : { found: false, reason: 'missing' };
  } catch (error) {
    console.error('VEX lookup failed', error);
    return { found: false, reason: 'unavailable' };
  }
}

async function discord(env: Env, method: string, path: string, body: unknown, reason?: string) {
  return fetch(`${DISCORD}${path}`, {
    method,
    headers: {
      Authorization: `Bot ${env.DISCORD_TOKEN}`,
      'Content-Type': 'application/json',
      ...(reason ? { 'X-Audit-Log-Reason': encodeURIComponent(reason) } : {}),
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
}

/** Runs after the "thinking…" reply, so a slow VEX lookup can't time out the interaction. */
async function finishVerify(env: Env, interaction: any, name: string, number: string) {
  const reply = (message: unknown) =>
    discord(env, 'PATCH', `/webhooks/${interaction.application_id}/${interaction.token}/messages/@original`, message);

  const team = await lookupTeam(env, number);
  if (!team.found) {
    return reply(team.reason === 'missing'
      ? warning(`⚠️ I couldn't find V5RC team **${number}**. Check the number and try again.`, name)
      : warning('⚠️ The VEX team lookup isn\'t responding right now. Please try again in a minute.', name));
  }

  const nick = nickname(name, team.number);
  const member = `/guilds/${interaction.guild_id}/members/${interaction.member.user.id}`;
  const reason = `Verified as team ${team.number}`;
  // Independent of each other: the owner can't be renamed but can still get
  // the role, so one failing must not skip the other.
  const [renamed, roled] = await Promise.all([
    discord(env, 'PATCH', member, { nick }, reason),
    env.VERIFIED_ROLE_ID ? discord(env, 'PUT', `${member}/roles/${env.VERIFIED_ROLE_ID}`, undefined, reason) : null,
  ]);
  if (!renamed.ok) console.error('rename failed', renamed.status, await renamed.text());
  if (roled && !roled.ok) console.error('role failed', roled.status, await roled.text());

  const label = team.name ? `**${team.number}** (${team.name})` : `**${team.number}**`;
  const role = env.VERIFIED_ROLE_ID ? `<@&${env.VERIFIED_ROLE_ID}>` : '';
  const gotRole = roled?.ok ? ` You now have the ${role} role.` : '';
  const noRole = roled && !roled.ok ? ` I also couldn't give you the ${role} role, so please ask an admin.` : '';

  if (renamed.ok && !noRole) {
    return reply(success(`✅ Verified with team ${label}. Your server name is now **${nick}**.${gotRole}`));
  }
  if (renamed.ok) return reply(warning(`Verified with team ${label}. Your server name is now **${nick}**.${noRole}`, name));
  // 403 is the usual rename failure: the server owner, or someone whose top
  // role sits above the bot's. Discord allows neither, so say what to do instead.
  return reply(warning(
    `Found team ${label}, but Discord won't let me change your name. `
      + `Server owners can't be renamed by bots, and neither can members whose role is above mine. `
      + `Set your server name to **${nick}** yourself.${gotRole}${noRole}`,
    name,
  ));
}

async function handle(interaction: any, env: Env, ctx: Ctx): Promise<unknown> {
  // PING: Discord checking the endpoint when it is saved.
  if (interaction.type === 1) return { type: 1 };

  if (!interaction.guild_id) {
    return { type: 4, data: success('Verification only works inside the server.') };
  }

  if (interaction.type === 3) {
    const id: string = interaction.data.custom_id;
    if (id === START_BUTTON) return verifyModal();
    if (id.startsWith(RETRY_PREFIX)) return verifyModal(id.slice(RETRY_PREFIX.length));
  }

  if (interaction.type === 5 && interaction.data.custom_id === MODAL_ID) {
    const fields = modalValues(interaction.data.components);
    const name = cleanName(fields.name ?? '');
    const number = cleanTeamNumber(fields.team ?? '');
    if (!name) return { type: 4, data: warning('⚠️ Please enter your name.', null) };
    if (!number) {
      return { type: 4, data: warning(`⚠️ **${fields.team}** isn't a team number. It should look like **55288A**.`, name) };
    }
    ctx.waitUntil(finishVerify(env, interaction, name, number));
    return { type: 5, data: { flags: 64 } };
  }

  return { type: 4, data: success('That button is out of date. Use the Verify button in #verify.') };
}

export default {
  async fetch(request: Request, env: Env, ctx: Ctx): Promise<Response> {
    if (request.method !== 'POST') return new Response('Scouting Cat verify bot', { status: 200 });
    const body = await request.text();
    const valid = await verifySignature(
      env.DISCORD_PUBLIC_KEY,
      request.headers.get('X-Signature-Ed25519') ?? '',
      request.headers.get('X-Signature-Timestamp') ?? '',
      body,
    );
    if (!valid) return new Response('Bad signature', { status: 401 });
    return Response.json(await handle(JSON.parse(body), env, ctx));
  },
};
