# Scouting Cat verify bot

Posts a **Verify** button in `#verify`. A member presses it and enters their name
and V5RC team number. The bot looks the team up on events.vex.com, then:

- **Team found:** renames the member to `Name | Team #`, for example `Steven | 55288A`, and gives them
  the **User** role. Set `VERIFIED_ROLE` in `.env` to use a different role, or leave it empty for none.
- **Team not found:** warns them privately and offers **Try again**, with their name already filled in.

Runs as a Cloudflare Worker on Discord's HTTP interactions endpoint, so it stays
up without a server or a computer left on.

## One-time setup

1. **Create the bot.** Go to <https://discord.com/developers/applications> and select
   **New Application**, name it **Scouting Cat**, then open **Bot**.
   - Select **Reset Token** and copy the token.
   - Under **Installation**, set **Install Link** to *None*. Under **Bot**, turn off
     **Public Bot**, so only you can add it to servers.
2. **Fill in `.env`.** Run `cp .env.example .env`, then fill in:
   - `DISCORD_TOKEN`: the bot token from step 1.
   - `ROBOT_EVENTS_API_TOKEN`: your events.vex.com API token.
   - `CLOUDFLARE_API_TOKEN`: in the Cloudflare dashboard, go to **My Profile → API Tokens →
     Create Token** and use the **Edit Cloudflare Workers** template. Use the same account
     that owns the VEXRank API. You can leave this blank if `npx wrangler login` works for you.
3. The deploy script reads the bot's public key from Discord, so you don't need to copy it.
4. **Deploy with `npm run deploy`.** The first run stops and prints an invite link.
   Open it, choose your server and authorize, then run `npm run deploy` again.
5. **Check the bot's role.** Under **Server Settings → Roles**, turn on **Manage Roles** for the bot's role,
   and drag it above the verified role and above the roles of the members it should rename. Discord never lets a bot
   rename the server owner, so the owner has to set their own name.

## Updating

Change the code, run `npm test`, then run `npm run deploy`. The deploy refreshes the
existing panel in `#verify` rather than posting a second one.

## Files

- `src/worker.ts`: the interactions endpoint. It checks signatures, runs the lookup and renames the member.
- `src/verify.ts`: input cleanup, the nickname format and the Discord messages.
- `scripts/deploy.mjs`: checks the three tokens, deploys the worker, uploads its secrets, registers the endpoint and posts the panel.
