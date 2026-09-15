# VCR 3.0 candidate

Status: implemented in website calculation paths; not deployed or historically calibrated.

Predecessor: VCR 2.0 on `main`. This version remains isolated on its own branch and pull request so the previous model and history remain traceable.

- [Specification and rationale](../docs/VCR-3.0-revision.md)
- [Reference event settlement](../algorithm/vcr-event.mjs)
- [Reference regression tests](../algorithm/vcr-event.test.mjs)
- [Website implementation](../website/lib/vcr3.mjs)
- [Website integration tests](../website/tests/vcr3.test.mjs)

Changes: stronger elimination evidence, bounded statistical penalties, Event Weight applied once, an explicit minimum gain for unexpected champions, a reconciled event audit ledger, and one processor shared by the live leaderboard, team history, and historical builder.

Validation: both Node test suites pass 12 tests total, and the production website build completes. Historical calibration, a full bracket simulator, and deployment remain outstanding.

