# DORA dashboard (Azure DevOps → Postgres → Grafana)

A self-contained Docker stack that turns Azure DevOps data into a live
[DORA metrics](https://dora.dev/) dashboard: **deployment frequency**, **lead
time for changes**, **change failure rate**, and **mean time to restore**, plus a
**reliability** (ADO-bug) proxy — all with Elite/High/Medium/Low band colouring
and filterable by environment, trunk branch, repository, pipeline, and bug area.

It reuses a set of Azure DevOps exporter scripts (vendored in `exporter/bin/`)
that already encode org-specific logic — a tuned deploy-stage heuristic, a
deployment-restore MTTR, and an ADO-Bug reliability proxy — things generic tools
such as Apache DevLake do not do for Azure DevOps Boards.

## ELI5: how to get it up and running

You need [Docker Desktop](https://www.docker.com/products/docker-desktop/)
installed and running. Then, in a terminal:

1. **Get the code.**
   ```bash
   git clone https://github.com/helgeu/dora-dashboard.git
   cd dora-dashboard
   ```

2. **Make your settings file.** Copy the example, then open `.env` in an editor.
   ```bash
   cp .env.example .env
   ```

3. **Fill in 3 things** in `.env`. For a project at
   `https://dev.azure.com/myorg/ourproj`, the org is `myorg` and the project is
   `ourproj`:
   - `DORA_ORG` — your Azure DevOps organisation name (just the name, e.g.
     `myorg`, not the full URL).
   - `DORA_PROJECT` — your project name (e.g. `ourproj`).
   - `ADO_PAT` — a Personal Access Token. Get one at
     `https://dev.azure.com/myorg/_usersSettings/tokens` → **New Token**,
     with **read** access to **Code**, **Build**, and **Work Items**. Paste it in.
   - (Optional) `DORA_RELIABILITY_AREA_PATH` — set this to your project name to
     pull *all* bugs (e.g. `ourproj`). Leave blank to skip reliability.

4. **Start everything.**
   ```bash
   docker compose up -d --build
   ```
   This starts three containers: the database, the exporter (which pulls your
   ADO data), and Grafana.

5. **Wait for the first data pull.** Watch it work:
   ```bash
   docker compose logs -f exporter
   ```
   When you see `load complete`, press `Ctrl+C` to stop watching (the containers
   keep running). On a big project the first pull can take a few minutes.

6. **Open the dashboards.** Go to **http://localhost:3000** in your browser.
   Log in with `admin` / `admin` (you can skip the "change password" prompt).
   In the **DORA** folder you get three dashboards — **Core**, **Delivery**, and
   **Reliability**. Start with **DORA — Core**. A dropdown at the top links
   between all three (carrying your filters and time range).

7. **Play with it.** Use the dropdowns at the top to switch environment, trunk
   branch, repository, pipeline, and bug area. Use the time picker (top right) to
   change the window.

**To stop it:** `docker compose down` (keeps your data).
**To wipe everything and start clean:** `docker compose down -v`.

That's it. The exporter re-pulls fresh data every hour automatically.

## Architecture

```
              cron loop (REFRESH_INTERVAL_SECONDS)
                         │
   [exporter] ── ado-dora (ADO REST API, PAT auth) ──▶ CSVs
                         │
                    dora-load ──▶ [Postgres] ◀── SQL ── [Grafana dashboard]
```

- **exporter** — `python:3.12-slim` image running the vendored `ado-*` scripts
  and the `dora-load` loader on a schedule. PAT auth, so no `az` CLI is needed.
- **db** — Postgres. Raw rows in `deployments`, `pull_requests`, `bugs`; load
  provenance in `runs`. Idempotent upserts, so history accumulates cleanly.
- **grafana** — provisioned datasource + three dashboards (Core / Delivery /
  Reliability), all version-controlled.

## Quick start

```bash
cp .env.example .env       # then edit .env: DORA_ORG, DORA_PROJECT, ADO_PAT ...
docker compose up -d --build
```

- Grafana: http://localhost:3000 (default `admin` / `admin`, change in `.env`).
- Open the **DORA** folder → **Core**, **Delivery**, or **Reliability**.
- The exporter runs once on boot, then every `REFRESH_INTERVAL_SECONDS`
  (default hourly). First load can take a while on large orgs.

> New to this? See the step-by-step **ELI5** section above.

### PAT scopes

The Personal Access Token (`ADO_PAT`) needs read access to:
**Code** (pull requests), **Build** (pipeline runs/timelines), and
**Work Items** (bugs, only if you enable reliability).

## Configuration

All configuration is in `.env` (see `.env.example` for the full list). Key vars:

| Variable | Meaning |
|---|---|
| `DORA_ORG` / `DORA_PROJECT` | Azure DevOps org name + project |
| `ADO_PAT` | Personal Access Token (never commit it) |
| `DORA_SINCE` | Window start `YYYY-MM-DD` (blank → Oct 1 last year) |
| `DORA_TARGET_BRANCH` | Trunk branch for lead time + deploys (`main`) |
| `DORA_PROD_ENV` | Environment to headline by default (`prod`) |
| `DORA_RELIABILITY_AREA_PATH` | Area path for the bug/reliability metric. Set to your project name to pull all bugs; blank = skip |
| `REFRESH_INTERVAL_SECONDS` | Seconds between refreshes (`3600`) |

In Grafana, the dashboard has dropdown template variables so you can retarget
panels without editing SQL:

| Variable | Filters |
|---|---|
| **Project** | everything |
| **Environment** | deployment-frequency / CFR / MTTR headline + the env deploy chart |
| **Trunk** | lead-time panels |
| **Repository** (multi) | lead-time panels |
| **Pipeline** (multi) | deployment panels + the deployments table |
| **Area** (multi) | reliability (bug) panels |

## Verify it works

```bash
docker compose logs -f exporter          # watch a refresh run
docker compose exec db psql -U dora -d dora -c "select count(*) from deployments;"
docker compose exec db psql -U dora -d dora -c "select * from runs order by ran_at desc limit 5;"
```

## Force a refresh now

```bash
docker compose restart exporter          # re-runs immediately on boot
```

## Multi-arch build

```bash
docker buildx build --platform linux/amd64,linux/arm64 -t <registry>/dora-exporter ./exporter
```

## Scope

Panels are organised into three provisioned dashboards (in the **DORA** folder,
cross-linked via a dropdown):

- **DORA — Core:** the four core DORA metrics (deployment frequency, lead time,
  change failure rate, MTTR) plus deployment and lead-time trends and a recent
  deployments table. Filters: environment, trunk, repository, pipeline.
- **DORA — Delivery:** PR throughput (merged/week by repository), PR abandonment
  rate, active PR contributors (context only), pipeline reliability (deploy fail
  rate), and deployment duration. Filters: repository, pipeline.
- **DORA — Reliability:** the ADO-bug proxy — defect inflow, open backlog, bug
  recovery time, per-area breakdown, inflow vs outflow, backlog over time, and
  resolution/severity trends. Populated only when `DORA_RELIABILITY_AREA_PATH`
  is set. Filter: area.

Honest caveats to socialise with stakeholders: lead time / cycle time here is
**PR-open-to-merge** (not commit-to-production), and change failure rate / MTTR
are **deploy-level proxies**, because the source data has no commit timestamps
or incident linkage. Panels are single-project today; multi-project selection is
an additive follow-up.

## Keeping the vendored scripts in sync

`exporter/bin/ado-*` are copies of the scripts in the `setup` repo
(`nix/bin/`). They change rarely; re-copy them deliberately if the upstream
versions are updated.
