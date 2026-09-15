# Website inspection — September 11, 2026

## Verified and corrected

- Full paginated event, team, match and ranking collections; upstream failure is not published as an empty or partially complete collection.
- Worlds elimination requests include every division and rounds 3–6. Event 64025 returned all 11 divisions, 865 teams and elimination records for every division, including the championship division.
- Browser verification of High Stakes Worlds: two actual Worlds events in the class filter; qualification/elimination controls; division results; championship series scores; team links.
- World-qualifying API level is no longer interpreted as World Championship event class. Signature class still requires its official API level.
- Bracket replays are grouped by round and instance; missing bracket positions retain their slot rather than shifting other matches. All replay scores remain in the hover details and classic view.
- Agenda table columns retain activity, start/end time and location. Single-day schedules without headings retain their entries.
- Team links carry the selected event/ranking season. Seasonal profile errors have a retry path.
- Reduced eager background traffic, bounded concurrency, successful-page cache, retry handling, loading/error states, cancelled-event exclusion, keyboard access and responsive schedule spacing.
- Production build and TypeScript checks passed. Eight regression tests pass with `node --test tests/data-regressions.test.mjs`.

## Remaining limitations (not represented as verified fixes)

- Event.VEX can still rate-limit cold requests. Successful pages are cached for five minutes and failures can be retried; this is not a durable full archive.
- Current-season ratings remain a sample, explicitly labelled in the UI. No unavailable historical archive has been fabricated.
- Exact registration availability, affiliation, grade and regional-subdivision parity with the official site's filters still needs its richer metadata; the v2 event collection does not provide all these fields. Existing name-derived classifications are not guaranteed to match every official filter.
- Team rating-history estimates are not a replay of the complete archived opponent-adjusted model.
- Organizer HTML varies by event. Regression coverage includes table and plain-text schedules, not every historical HTML format.
- Alliance seeds are left unknown when authoritative seed data is absent; qualification rank is not substituted as an alliance seed.

This is a bounded regression and integration inspection, not a claim that every historical event or device has been exhaustively checked.
