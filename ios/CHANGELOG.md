# Scouting Cat (iOS) changelog

Releases of the iOS app. Tags are `ios-vVERSION+BUILD`; the scheme and release
steps are in [VERSIONING.md](https://github.com/vex-rank-team/Vex-Rank/blob/main/VERSIONING.md).
Every App Store upload raises the build number, even when the version stays.

## [Unreleased]

## [1.1.0+5] - 2026-11-03 (prepared for App Store submission)

### Added
- Tournament mode: one team followed through an event's qualifiers on the Lock
  Screen and in the Dynamic Island (a Live Activity, in a widget extension).
- Livestreams: an event's stream in the app, with a jump to any match placed by
  when it actually started; every day's stream at multi-day events.
- VEX IQ: VIQCR ratings, world rankings, event results and teamwork finals.
- Disqualifications and the alliance selection on match lists; a Stats tab
  (momentum, strengths) for a team at an event.

### Changed
- Standings and match results update as soon as they are posted.
- The world ranking covers every rated team; search shows the world rank.
- Team profiles load straight from events.vex.

## [1.0.0+4] - 2026-10-01 (in App Store review)

First App Store submission, resubmitted after a guideline 4.1(a) rejection.

### Added
- World ranking, events, stat leaders and a teams directory with favourites.
- Team profiles, event pages with standings, brackets, awards and skills, a
  team's matches at a tournament, and match detail.
- Colour themes and team-number fonts; the 55288A Makapaka logo in the top bar.
- About screen (settings menu → About Scouting Cat) with the disclaimer:
  Scouting Cat is not affiliated with VEX Robotics and is not a VEX product,
  and its data comes from the events.vex.com API.

### Changed
- Signs with the developer team JJRCKVACCR, which owns `com.vexrank.app`.

Builds 1 to 3 were earlier uploads of 1.0.0; build 3 was the one rejected.

[Unreleased]: https://github.com/StevenQQian/Vex-Rank/compare/ios-v1.1.0+5...main
[1.1.0+5]: https://github.com/StevenQQian/Vex-Rank/compare/ios-v1.0.0+4...ios-v1.1.0+5
[1.0.0+4]: https://github.com/StevenQQian/Vex-Rank/releases/tag/ios-v1.0.0+4
