# VEX Ranking

VEX ranking website, ranking scripts, and algorithm documentation.

## Project contents

- `website/`: React website, API routes, UI components, ranking scripts, database schema and migration, public assets, and dependency lockfile.
- [Full algorithm documentation](../output/pdf/vex_competitive_rating_full_algorithm.pdf)
- [Rating specification](../output/pdf/vex_competitive_rating_specification.pdf)
- `build_full_algorithm_pdf.py` and `build_vcr_pdf.py`: editable sources used to generate the algorithm PDFs.

## Website development

Requires Node.js 22.13 or newer and pnpm.

```sh
cd website
pnpm install --frozen-lockfile
pnpm dev
```

The website uses vinext, Vite, and Cloudflare tooling. Its existing hosting configuration is in `website/.openai/hosting.json`. Live RobotEvents requests require `ROBOT_EVENTS_API_TOKEN` in the runtime environment. Keep credentials out of version control.

Other available commands, run from `website/`:

```sh
pnpm build
pnpm lint
```

## Regenerate the algorithm documents

Requires Python and ReportLab.

```sh
python -m pip install reportlab
python build_full_algorithm_pdf.py
python build_vcr_pdf.py
```

The generated documents are saved in `output/pdf/`.

## GitHub upload scope

Include the website source and configuration, both algorithm PDFs, their Python source scripts, and this README. Dependency folders, build output, local caches, temporary previews, credentials, and deployment archives are not source files and are excluded.

The website currently has its own Git repository and hosting remote. Preserve that repository when preparing the combined GitHub upload; adding it directly to a parent repository would record a nested repository instead of its files.

