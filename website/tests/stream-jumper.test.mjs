import test from 'node:test';
import assert from 'node:assert/strict';
import { youtubeId, eventStreams, matchJump, matchesById, streamOrigin, videoTime } from '../lib/stream-jumper.mjs';

test('YouTube ids from every link shape, none from channels', () => {
  for (const url of ['https://www.youtube.com/watch?v=3XiT_3haGR4', 'https://youtu.be/3XiT_3haGR4?t=5', 'https://youtube.com/live/3XiT_3haGR4?feature=share', 'https://www.youtube.com/embed/3XiT_3haGR4', 'https://m.youtube.com/watch?v=3XiT_3haGR4&t=1'])
    assert.equal(youtubeId(url), '3XiT_3haGR4', url);
  for (const url of ['https://www.youtube.com/@CautionTape/streams', 'https://www.youtube.com/channel/UC-grQ9qvMoKXjtxOPDrC-yg', 'https://twitch.tv/x', 'not a link'])
    assert.equal(youtubeId(url), null, url);
});

test('streams come from the webcast notes, then viewers, once per video', () => {
  const notes = 'Livestream (Saturday, from 10:00 AM ET): https://www.youtube.com/watch?v=3XiT_3haGR4. Channel: https://www.youtube.com/@cautiontape';
  const { streams, others } = eventStreams(notes, [{ videoId: '3XiT_3haGR4' }, { videoId: 'abcdefghijk', sync: { matchId: 2, seconds: 60 } }]);
  assert.deepEqual(streams.map(s => [s.videoId, s.source]), [['3XiT_3haGR4', 'event'], ['abcdefghijk', 'viewer']]);
  assert.deepEqual(others, ['https://www.youtube.com/@cautiontape']);
});

// Caution Tape's first matches: scheduled 9:00, 9:04, 9:08 - started 9:33:13, 9:38:33, 9:45:29.
const divisions = [{ id: 1, name: 'Division 1', matches: [
  { id: 1, name: 'Qualifier #1', scheduled: '2026-10-31T09:00:00-04:00', started: '2026-10-31T09:33:13-04:00' },
  { id: 2, name: 'Qualifier #2', scheduled: '2026-10-31T09:04:00-04:00', started: '2026-10-31T09:38:33-04:00' },
  { id: 3, name: 'Qualifier #3', scheduled: '2026-10-31T09:08:00-04:00', started: '2026-10-31T09:45:29-04:00' },
  { id: 4, name: 'Qualifier #4', scheduled: '2026-10-31T09:12:00-04:00' },
] }];
const byId = matchesById(divisions);

test('a sync point places every match by when it actually started, not its scheduled time', () => {
  const streams = [{ videoId: 'v1', sync: { matchId: 2, seconds: 1800 } }];
  assert.deepEqual(matchJump(streams, byId.get(2), byId), { videoId: 'v1', seconds: 1800 });
  assert.deepEqual(matchJump(streams, byId.get(3), byId), { videoId: 'v1', seconds: 1800 + 416 }); // 6m56s later, not the scheduled 4m
  assert.deepEqual(matchJump(streams, byId.get(1), byId), { videoId: 'v1', seconds: 1800 - 320 });
  assert.equal(matchJump(streams, byId.get(4), byId), null, 'not played yet');
  assert.deepEqual(matchJump(streams, byId.get(3), byId, { v1: -10 }), { videoId: 'v1', seconds: 2206 }, 'the viewer nudge');
});

test('YouTube\'s start time works the same way; a match before the video has no jump', () => {
  const streams = [{ videoId: 'v1', startTime: '2026-10-31T09:35:00-04:00' }];
  assert.equal(matchJump(streams, byId.get(1), byId), null);
  assert.deepEqual(matchJump(streams, byId.get(2), byId), { videoId: 'v1', seconds: 213 });
  assert.equal(streamOrigin({ videoId: 'x' }, byId), null, 'an untimed stream');
  assert.equal(matchJump([{ videoId: 'x' }], byId.get(2), byId), null);
});

test('with a stream per day, a match is on the one that began most recently before it', () => {
  const streams = [{ videoId: 'day1', startTime: '2026-10-31T08:00:00-04:00' }, { videoId: 'day2', startTime: '2026-10-31T09:40:00-04:00' }];
  assert.equal(matchJump(streams, byId.get(2), byId).videoId, 'day1');
  assert.equal(matchJump(streams, byId.get(3), byId).videoId, 'day2');
  assert.equal(videoTime(3725), '1:02:05');
  assert.equal(videoTime(65), '1:05');
});
