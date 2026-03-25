# PM2 Deploy To Tailscale

## Service Discovery Rules

The deploy script discovers deployable components by scanning for `build.sh` files.

- A `build.sh` in a subdirectory (example: `apps/api/build.sh`) maps to PM2 service name `apps-api`.
- A `build.sh` in the repository root (`./build.sh`) is supported.

## Root Service Name Resolution

When `./build.sh` exists, the action resolves the PM2 service name with the following logic:

1. `ecosystem.config.js` must contain exactly one PM2 app.
2. The single app `name` is used as the root service name.
3. If zero or multiple apps exist, deployment fails with an explicit error.

## Input

No additional input is required for root-level deployments.
