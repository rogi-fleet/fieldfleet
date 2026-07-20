# Security Policy

## Reporting a Vulnerability

Please do **not** report security vulnerabilities through public GitHub
issues, discussions, or pull requests.

Instead, use GitHub's private vulnerability reporting on this repository
(**Security** tab → **Report a vulnerability**). You should receive a
response within a few business days.

Please include:

- A description of the issue and its impact
- Steps to reproduce (a proof of concept if possible)
- Affected components (Flutter app, Supabase migrations/RLS policies, edge
  functions, deployment stack)

## Scope

Reports about the schema, row-level-security policies, edge functions, the
Flutter app, and the example `deployment/` stack are all in scope and
appreciated — people self-host FieldFleet, so hardening the public
distribution protects real deployments.

## Supported Versions

Only the latest commit on `main` is supported.
