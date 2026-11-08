// Pure pieces of the verify flow: input cleanup, the nickname format, and the
// Discord messages. Kept free of I/O so the tests can run them directly.

/** Discord's nickname limit. */
export const MAX_NICKNAME = 32;
const SEPARATOR = ' | ';

export const START_BUTTON = 'verify:start';
export const RETRY_PREFIX = 'verify:retry:';
export const MODAL_ID = 'verify:submit';

/** Ephemeral: only the person verifying sees the reply. */
const EPHEMERAL = 64;

/** Collapses whitespace and drops `|`, which would break the `Name | Team` shape. */
export function cleanName(raw: string): string | null {
  const name = raw.replace(/\|/g, ' ').replace(/\s+/g, ' ').trim();
  return name ? name : null;
}

/**
 * `#55288a ` → `55288A`. V5RC numbers are digits and a letter; the team
 * lookup only accepts numbers that start with a digit, so anything else is
 * turned away here instead of costing a request.
 */
export function cleanTeamNumber(raw: string): string | null {
  const number = raw.replace(/\s+/g, '').replace(/^#/, '').toUpperCase();
  return /^\d{1,6}[A-Z]{0,2}$/.test(number) ? number : null;
}

/** `Name | Team`, shortening the name rather than the team when over the limit. */
export function nickname(name: string, team: string): string {
  const room = MAX_NICKNAME - SEPARATOR.length - team.length;
  return `${name.slice(0, room).trimEnd()}${SEPARATOR}${team}`;
}

/** Reads a submitted modal's fields, whichever component layout Discord sent. */
export function modalValues(components: unknown): Record<string, string> {
  const values: Record<string, string> = {};
  const walk = (node: any) => {
    if (Array.isArray(node)) return node.forEach(walk);
    if (!node || typeof node !== 'object') return;
    if (typeof node.custom_id === 'string' && typeof node.value === 'string') values[node.custom_id] = node.value;
    walk(node.components);
    walk(node.component);
  };
  walk(components);
  return values;
}

export function verifyModal(name = '') {
  const input = (custom_id: string, label: string, placeholder: string, max_length: number, value = '') => ({
    type: 1,
    components: [{
      type: 4, custom_id, label, placeholder, style: 1, min_length: 1, max_length, required: true,
      // Discord rejects an empty `value`, so it is only sent when prefilling.
      ...(value ? { value } : {}),
    }],
  });
  return {
    type: 9,
    data: {
      custom_id: MODAL_ID,
      title: 'Verify your team',
      components: [
        input('name', 'Your name', 'e.g. Steven', 24, name),
        input('team', 'Team number', 'e.g. 55288A', 8),
      ],
    },
  };
}

/** The button under a warning. Carries the name so the retry form is prefilled. */
function retryRow(name: string | null) {
  const custom_id = (RETRY_PREFIX + (name ?? '')).slice(0, 100);
  return [{ type: 1, components: [{ type: 2, style: 1, label: 'Try again', custom_id }] }];
}

// Replies name a role as <@&id> so it shows by name; this keeps that from pinging anyone.
const NO_PINGS = { parse: [] };

export function warning(content: string, name: string | null) {
  return { content, components: retryRow(name), flags: EPHEMERAL, allowed_mentions: NO_PINGS };
}

export function success(content: string) {
  return { content, components: [], flags: EPHEMERAL, allowed_mentions: NO_PINGS };
}

/**
 * The message the setup script leaves in #verify. Plain text rather than an
 * embed: verify channels often deny Embed Links, and an embed then fails to post.
 */
export const PANEL = {
  content: '## Verify your team\n'
    + 'Press **Verify** and enter your name and your V5RC team number.\n'
    + 'Once your team is found, your server name becomes **Name | Team #**.',
  embeds: [],
  components: [{ type: 1, components: [{ type: 2, style: 1, label: 'Verify', custom_id: START_BUTTON }] }],
};
