PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS meta (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS models (
  provider TEXT NOT NULL,
  model TEXT NOT NULL,
  display_name TEXT,
  context_tokens INTEGER,
  price_input_per_m REAL,
  price_output_per_m REAL,
  free_tier INTEGER NOT NULL DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'unknown',
  status_source TEXT,
  status_updated_at TEXT,
  notes TEXT,
  PRIMARY KEY (provider, model)
);

CREATE TABLE IF NOT EXISTS routes (
  gateway TEXT NOT NULL,
  route TEXT NOT NULL,
  active_version TEXT,
  deployed_at TEXT,
  updated_at TEXT,
  notes TEXT,
  PRIMARY KEY (gateway, route)
);

CREATE TABLE IF NOT EXISTS route_models (
  gateway TEXT NOT NULL,
  route TEXT NOT NULL,
  position INTEGER NOT NULL,
  provider TEXT NOT NULL,
  model TEXT NOT NULL,
  notes TEXT,
  PRIMARY KEY (gateway, route, position),
  FOREIGN KEY (gateway, route) REFERENCES routes(gateway, route) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS observations (
  id INTEGER PRIMARY KEY,
  ts TEXT NOT NULL,
  kind TEXT NOT NULL,
  subject TEXT NOT NULL,
  metric TEXT NOT NULL,
  value_num REAL,
  value_text TEXT,
  source TEXT NOT NULL,
  details TEXT
);

CREATE INDEX IF NOT EXISTS idx_observations_subject_metric_ts
  ON observations(subject, metric, ts DESC);

INSERT INTO meta(key, value) VALUES
  ('schema_version', '1'),
  ('created_at', '2026-09-25T16:05:00Z'),
  ('owner', 'provider-catalog skill')
ON CONFLICT(key) DO NOTHING;
