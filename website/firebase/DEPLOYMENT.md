# VEXRank test deployment

This Firebase API approach was superseded by the free Cloudflare Workers + D1 deployment. See `../cloudflare/DEPLOYMENT.md`. Firebase remains on Spark; its database rules are deployed, but the Firebase API was never deployed.

- Firebase project: `vexrank-test`
- Project number: `302355000355`
- Frontend: GitHub Pages, repository `easonli29/Vex-Rank`
- Backend: Firebase second-generation HTTPS function `api`, `us-central1`
- Database: Firestore Standard, `(default)`
- Status: Google authorization verified; Firestore deployment reported successful (database, security rules and indexes). API deployment is blocked by the project's Spark plan: Secret Manager requires Blaze. The API key has not been uploaded. GitHub Pages has not been published.

The API reuses the existing event/team/ranking implementation. Firestore stores compressed response records in `api_cache` and immutable event ratings in `event_rank_locks`. It is an on-demand cache, not a new complete historical archive. Existing archived rankings are served as static assets.

Cost controls: zero minimum instances, one maximum instance, two concurrent cache fills, 15-minute database cache and a short process cache. These controls are not a hard billing cap. No paid TTL or scheduled full-season ingestion is configured. Cloud Functions deployment requires Blaze.

## Authorized project setup

1. Authenticate locally with `pnpm dlx firebase-tools login`.
2. Confirm `vexrank-test` appears in `pnpm dlx firebase-tools projects:list` and billing is enabled.
3. Inspect existing Firestore databases before creating `(default)` in Standard/native mode, preferably regional `us-central1` to colocate with the API. Preserve an existing database's location.
4. From `functions`, install backend dependencies with `pnpm --ignore-workspace install --frozen-lockfile`.
5. Set `ROBOT_EVENTS_API_TOKEN` using `firebase functions:secrets:set` with a local input file. Never commit or paste the token into frontend configuration.
6. Deploy rules and the function with `pnpm dlx firebase-tools deploy --project vexrank-test --only firestore:rules,firestore:indexes,functions:api`.
7. Verify the returned function URL, `/health`, event and team responses, database cache writes and rank-lock persistence.
8. Build the Pages frontend from `website` with `pnpm exec vite build --config vite.pages.config.ts`. Set `VEX_API_BASE` to the deployed function URL if it differs from the configured default.
9. Enable Pages with GitHub Actions, then run the test Pages workflow. Record its actual URL and deployment result in GitHub issue #3.

Firestore browser reads/writes are denied. Only the API's Google service identity accesses the database. CORS permits the GitHub Pages origin; CORS is not authentication, and competition-data API endpoints are publicly readable. No account secrets are shipped to Pages. This test frontend is labelled and requests search engines not to index it.

The original Sites build remains available through its existing configuration. The Pages build has a separate output directory and publishes only that static output.

## Test record

- Backend bundle: passed.
- GitHub Pages production build: passed (non-blocking bundle-size warning).
- Existing data regression suite: 8/8 passed.
- Live API and frontend integration: not tested; backend billing prerequisite is unresolved.
- No billing upgrade was performed and the existing Sites deployment was not changed.
- In the GitHub repository, place the Pages workflow at root `.github/workflows/github-pages-test.yml` (the rest of this project is under `website/`).
