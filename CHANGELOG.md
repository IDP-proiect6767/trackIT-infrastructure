# Changelog

All notable changes to the TrackIT Infrastructure will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

<!--
Section types you can use under each release (omit empty ones):

  ### Added       — for new features.
  ### Changed     — for changes in existing functionality.
  ### Deprecated  — for soon-to-be removed features.
  ### Removed     — for now removed features.
  ### Fixed       — for any bug fixes.
  ### Security    — in case of vulnerabilities.

Workflow:
  1. Add entries under [Unreleased] as you work.
  2. When releasing, replace [Unreleased] heading with [X.Y.Z] - YYYY-MM-DD
     and start a fresh empty [Unreleased] section above it.
-->

## [0.1.0] - 2026-04-25

### Added

- **Phase 0 — Repo bootstrap**
  - `.gitignore` covering `.env`, logs, pids, IDE dirs, and Swarm state file.
  - Root `.env.example` with all secret placeholders (`change-me` values).
  - `README.md` with project description, architecture overview, three quick-start paths, repo layout, configuration reference, and known limitations.
  - `CHANGELOG.md` (this file) using Keep-a-Changelog format.
  - `INFRASTRUCTURE_IMPLEMENTATION_PLAN.md` (the full phased plan).
  - Directory skeleton with `.gitkeep` files: `docs/images/`, `grafana/dashboards/`, `prometheus/alerts/`.

- **Phase 1 — Multipass cluster**
  - `multipass/cloud-init.yaml`: installs Docker CE from the official apt repo, adds ubuntu user to docker group.
  - `multipass/launch-cluster.sh`: provisions 3 VMs (manager + 2 workers, 2 CPU / 2 GB / 10 GB each on Ubuntu 22.04 LTS), prints a summary table.
  - `multipass/destroy-cluster.sh`: purges all three VMs.
  - `multipass/ssh-into.sh`: helper to shell into manager/worker-1/worker-2.

- **Phase 2 — Docker Swarm**
  - `swarm/swarm-init.sh`: initialises Swarm on manager, saves join token and IP to `swarm/.swarm-state` (gitignored).
  - `swarm/join-workers.sh`: joins both workers using the saved state.
  - `swarm/label-nodes.sh`: applies `role=auth` on worker-1, `role=app` on worker-2.
  - `swarm/create-networks.sh`: creates all four overlay networks idempotently.
  - `swarm/teardown.sh`: workers leave Swarm, manager force-leaves, cleans up state file.

- **Phase 3 — Networks + architecture doc**
  - `docs/architecture.md`: ASCII topology, network membership table, cluster placement table, request flow examples for login and workout fetch, security boundary summary.

- **Phase 4 — Single-host dev compose**
  - `compose/docker-compose.dev.yml`: full stack (auth-db, data-db, auth-service, business-logic-service, data-service, kong, pgadmin, prometheus, grafana) on bridge networks, with healthchecks and depends-on.
  - `compose/.env.example`: all required variables for the dev stack.
  - `compose/README.md`: usage, log viewing, and wipe instructions.

- **Phase 5 — Kong API Gateway**
  - `kong/kong.yml`: DB-less declarative config — routes for auth (3 paths) and business-logic (8 paths), global rate limiting (100 req/min), auth-route rate limiting (20 req/min), CORS, file-log, and Prometheus plugin.
  - `kong/README.md`: local validation command, routes/plugins reference, reload instructions.

- **Phase 6 — TrackIT Swarm stack**
  - `stacks/stack-trackit.yml`: production stack for auth-db, data-db, auth-service, business-logic-service, data-service, kong — with placement constraints, healthchecks, rolling update config, and Docker configs for Kong.
  - `stacks/.env.example`.
  - `stacks/deploy-trackit.sh`: sources `.env`, deploys the stack, polls until all replicas are 1/1.

- **Phase 7 — Monitoring stack**
  - `prometheus/prometheus.yml`: scrape configs for all three Spring Boot services (`/actuator/prometheus`) and Kong (`/metrics` on admin port).
  - `grafana/provisioning/datasources/prometheus.yml`: Prometheus datasource pre-configured.
  - `grafana/provisioning/dashboards/dashboards.yml`: dashboard provisioning pointing to `/var/lib/grafana/dashboards`; Mihai drops `.json` files there.
  - `grafana/dashboards/.gitkeep`: empty directory tracked in git.
  - `stacks/stack-monitoring.yml`: Prometheus + Grafana on `monitoring-net`, pinned to manager.
  - `stacks/deploy-monitoring.sh`.

- **Phase 8 — Portainer + pgAdmin**
  - `pgadmin/servers.json`: pre-registered Auth DB and Data DB connections.
  - `stacks/stack-portainer.yml`: Portainer CE on manager, ports 9000 (HTTP) and 9443 (HTTPS).
  - `stacks/stack-pgadmin.yml`: pgAdmin 4 on manager, port 5050, single-user mode.
  - `stacks/deploy-portainer.sh`.
  - `stacks/deploy-pgadmin.sh`.

- **Phase 9 — Documentation**
  - `docs/runbook.md`: full from-scratch deploy sequence, service update procedure, log inspection, scaling warning (in-memory goals), common failures, teardown, secrets upgrade path, Grafana dashboard instructions, alerting future-work note.

- **Phase 10 — CI/CD**
  - `.github/workflows/lint-compose.yml`: validates dev compose and all four stack files on push/PR.
  - `.github/workflows/kong-validate.yml`: parses `kong/kong.yml` with Kong 3 on push/PR to `kong/**`.
  - `.github/workflows/shellcheck.yml`: runs ShellCheck (warning severity) on all `.sh` files.

- **Phase 11 — Smoke test**
  - `scripts/smoke-test.sh`: 9-step end-to-end test (register → login → validate → exercises → create workout → list workouts → create meal → nutrition stats → dashboard). Prints ✅ or ❌ with the failing step number.
