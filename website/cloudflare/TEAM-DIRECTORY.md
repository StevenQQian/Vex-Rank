# Team directory

The Teams page searches a complete official V5RC team-directory snapshot, not the current ranking or a single exact-number profile. The snapshot includes unregistered teams and contains only public team IDs, numbers, names, organization, school level, registration status, and city/region/country. Street addresses and coordinates are excluded.

## Refresh

From `website`, set `ROBOT_EVENTS_API_TOKEN` privately in the process environment and run:

```
node scripts/build-team-directory.mjs
node --test tests/team-directory.test.mjs
node node_modules/wrangler/bin/wrangler.js deploy --config cloudflare/wrangler.json
```

The generator downloads every page without a season or registration filter. It verifies the unique team count against official pagination metadata before replacing `archive-assets/team-directory.json`. Failed/partial downloads never replace the published snapshot. Checkpoint pages in ignored `work/team-directory-pages` are reused for up to 24 hours. The source timestamp, count and checksum are recorded in `cloudflare/team-directory-manifest.json`. No credentials are written into either artifact.

Keep the other existing files in `archive-assets` when deploying: they contain the ranking archives. The frontend obtains the snapshot through `/api/team-directory`, displays its date, and searches locally without expensive per-team history requests. Locations include inactive-only countries and regions; school levels refer to the latest official profile, not an inferred historical-season grade. New registrations appear after rebuilding/publishing this snapshot.

Use the manual GitHub Pages test deployment workflow after changing the frontend. A source update alone does not publish the website.

