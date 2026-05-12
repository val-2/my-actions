# PM2 Deploy To Tailscale

## Service Discovery Rules

The deploy script discovers deployable components by scanning for `build.sh` files.

- A `build.sh` in a subdirectory (example: `apps/api/build.sh`) maps to PM2 service name `apps-api`.
- A `build.sh` in the repository root (`./build.sh`) is supported.
- PM2 apps with `deploy_managed: false` in `ecosystem.config.js` are excluded from deploy discovery.

## Root Service Name Resolution

When `./build.sh` exists, the action resolves the PM2 service name with the following logic:

1. `ecosystem.config.js` must contain exactly one PM2 app.
2. The single app `name` is used as the root service name.
3. If zero or multiple apps exist, deployment fails with an explicit error.

## Input

No additional input is required for root-level deployments.

## Build Contract

- For each discovered component, the action executes `<component>/build.sh`.
- The deploy context is exported to build scripts:
  - `DEPLOY_SHA`
  - `DEPLOY_REF`
  - `DEPLOY_EVENT_NAME`
  - `DEPLOY_TIMESTAMP`
- `build.sh` must stay build-only (no runtime traffic switch side effects).
- Optional deploy hooks can be added per component directory:
  - `deploy-before-restart.sh`
  - `deploy-after-restart.sh`
- Hook runtime context:
  - `PM2_SERVICE_NAME`
  - `PM2_SERVICE_ACTION`
  - `DEPLOY_SHA`
  - `DEPLOY_REF`
  - `DEPLOY_EVENT_NAME`
  - `DEPLOY_TIMESTAMP`
- Hooks run only when the service action is not `skip` and the hook file exists and is executable.
- Default orchestration remains action-level: `sync_repository -> discover_apps -> plan_deploy -> build_targets -> apply_deploy -> pm2 save`.

## Deploy Action Override

- Each PM2 app can set `deploy_action` in `ecosystem.config.js`.
- Supported override currently enforced by planner:
  - `deploy_action: "restart"` forces `restart` instead of `reload` when service is online and changes are detected.

## Manual Workflow Runs

- When the GitHub workflow is triggered with `workflow_dispatch` (`Run workflow` in GitHub), the action treats the deploy as an explicit operator restart.
- Every discovered PM2 app that is not marked `deploy_managed: false` is built and restarted, even if no files changed between the previous deployed commit and the target SHA.
- Missing managed services are started instead of restarted.
- Commit-triggered deploys keep the normal change-based skip/reload/restart planner.

## Concurrency

- Deployments are protected by a host-level lock (`flock`) per repository to prevent concurrent runs on the same server.
