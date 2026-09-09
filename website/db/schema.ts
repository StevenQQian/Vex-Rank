export const eventRankLocksSchema = `CREATE TABLE IF NOT EXISTS event_rank_locks (
  event_id INTEGER PRIMARY KEY,
  tier TEXT NOT NULL,
  rank_score INTEGER NOT NULL,
  team_count INTEGER NOT NULL,
  locked_at TEXT NOT NULL
)`;
