-- DORA dashboard schema.
--
-- Three raw tables mirror the CSV output of the vendored ADO exporters
-- (ado-deploy-metrics, ado-prs-export, ado-bugs-export). One provenance table
-- records each load run. Grafana queries these tables directly with SQL.
--
-- Every row carries (organization, project) so the store can hold more than one
-- ADO project later without a schema change. The natural keys make re-loading
-- the same run idempotent: a second load of overlapping data updates rows in
-- place instead of duplicating them.

CREATE TABLE IF NOT EXISTS runs (
    id            BIGSERIAL PRIMARY KEY,
    organization  TEXT        NOT NULL,
    project       TEXT        NOT NULL,
    since         DATE        NOT NULL,
    ran_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    deployments   INTEGER     NOT NULL DEFAULT 0,
    pull_requests INTEGER     NOT NULL DEFAULT 0,
    bugs          INTEGER     NOT NULL DEFAULT 0
);

-- Deployment stages (source: ado-deploy-metrics ado_deployments.csv).
CREATE TABLE IF NOT EXISTS deployments (
    organization   TEXT        NOT NULL,
    project        TEXT        NOT NULL,
    build_id       TEXT        NOT NULL,
    stage          TEXT        NOT NULL,
    finished_at    TIMESTAMPTZ,
    started_at     TIMESTAMPTZ,
    week           TEXT,
    pipeline_id    TEXT,
    pipeline       TEXT,
    repository     TEXT,
    build_number   TEXT,
    environment    TEXT,
    result         TEXT,          -- succeeded / failed
    success        BOOLEAN,
    branch         TEXT,
    source_version TEXT,
    url            TEXT,
    PRIMARY KEY (organization, project, build_id, stage)
);
-- Backfill the column on stores whose volume predates it (schema.sql runs only
-- on first init, so an idempotent ALTER keeps existing databases in sync).
ALTER TABLE deployments ADD COLUMN IF NOT EXISTS repository TEXT;
CREATE INDEX IF NOT EXISTS deployments_finished_idx ON deployments (finished_at);
CREATE INDEX IF NOT EXISTS deployments_env_idx      ON deployments (environment);
CREATE INDEX IF NOT EXISTS deployments_repo_idx     ON deployments (repository);

-- Pull requests (source: ado-prs-export ado_prs.csv). Lead-time proxy.
CREATE TABLE IF NOT EXISTS pull_requests (
    organization    TEXT        NOT NULL,
    project         TEXT        NOT NULL,
    repository      TEXT        NOT NULL,
    pull_request_id TEXT        NOT NULL,
    created_at      TIMESTAMPTZ,
    closed_at       TIMESTAMPTZ,
    title           TEXT,
    status          TEXT,          -- completed / active / abandoned
    created_by      TEXT,
    created_by_email TEXT,
    source_branch   TEXT,
    target_branch   TEXT,
    url             TEXT,
    PRIMARY KEY (organization, project, repository, pull_request_id)
);
CREATE INDEX IF NOT EXISTS pull_requests_closed_idx ON pull_requests (closed_at);
CREATE INDEX IF NOT EXISTS pull_requests_target_idx ON pull_requests (target_branch);

-- Bugs (source: ado-bugs-export ado_bugs.csv). Reliability proxy (later slice).
CREATE TABLE IF NOT EXISTS bugs (
    organization TEXT        NOT NULL,
    project      TEXT        NOT NULL,
    id           TEXT        NOT NULL,
    created_at   TIMESTAMPTZ,
    resolved_at  TIMESTAMPTZ,
    week         TEXT,
    state        TEXT,
    severity     TEXT,
    area_path    TEXT,
    title        TEXT,
    tags         TEXT,
    assigned_to  TEXT,
    url          TEXT,
    PRIMARY KEY (organization, project, id)
);
CREATE INDEX IF NOT EXISTS bugs_created_idx ON bugs (created_at);
