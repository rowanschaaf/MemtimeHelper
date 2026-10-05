-- Capture store schema, version 1.
-- MemtimeHelper owns this schema. TimesheetHelper reads it.
-- CaptureSchema.v1 must match this file exactly.

CREATE TABLE schema_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);

CREATE TABLE segments (
  id        INTEGER PRIMARY KEY,
  start     INTEGER NOT NULL,
  end       INTEGER NOT NULL,
  type      TEXT NOT NULL CHECK (type IN ('app', 'browser', 'offline')),
  program   TEXT,
  title     TEXT,
  path      TEXT,
  raw_title TEXT,
  enricher  TEXT
);
CREATE INDEX segments_start ON segments (start);

CREATE TABLE open_segment (
  id        INTEGER PRIMARY KEY CHECK (id = 1),
  start     INTEGER NOT NULL,
  end       INTEGER NOT NULL,
  type      TEXT NOT NULL,
  program   TEXT,
  title     TEXT,
  path      TEXT,
  raw_title TEXT,
  enricher  TEXT
);

CREATE TABLE enrichers (
  program TEXT PRIMARY KEY,
  name    TEXT NOT NULL
);
