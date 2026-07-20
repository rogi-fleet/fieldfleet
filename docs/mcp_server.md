# TaskFleet MCP Server

Lets MCP-capable AI assistants (Claude, ChatGPT, or anything speaking the
Model Context Protocol) act on a FieldFleet workspace — the equivalent of
JobTread's "AI Connector".

## Connecting an assistant

1. A **workspace admin** opens *Settings → API Keys* and creates a key.
   - **Read-only** keys can list projects/tasks/invoices, search the
     catalog, and pull the WIP schedule and cash-flow projection.
   - **Read + Write** keys can additionally create tasks.
   - The plaintext key (`tfk_…`) is shown exactly once; only its SHA-256
     hash is stored.
2. In the assistant, add a custom MCP connector:
   - **URL**: `https://<project-ref>.supabase.co/functions/v1/mcp-server`
     (shown on the API Keys screen)
   - **Auth**: Bearer token = the API key.

## Tools exposed

| Tool | Scope | Description |
|------|-------|-------------|
| `list_projects` | read | Jobs with status + contract amount |
| `get_wip_report` | read | Full WIP schedule (earned vs billed, over/under) |
| `get_cash_flow` | read | Open invoice/bill balances by due date |
| `list_tasks` | read | Tasks, filterable by project/status |
| `list_invoices` | read | Customer invoices with paid amounts |
| `search_catalog` | read | Cost catalog search by name/SKU |
| `create_task` | write | Create a task on a project |

## Operational notes

- Transport is **stateless streamable HTTP**: one JSON-RPC message per
  POST, plain JSON responses, no SSE session. This is what Claude custom
  connectors expect for simple servers.
- Deploy with `supabase functions deploy mcp-server --no-verify-jwt` —
  callers authenticate with the workspace API key, not a Supabase JWT.
  Signature: every query inside the function is explicitly scoped to the
  key's `workspace_id` because the service role bypasses RLS.
- Revoking a key (Settings → API Keys) cuts access immediately;
  `last_used_at` shows whether a key is actually in use.
- Schema lives in `supabase/migrations/20260611024311_workspace_api_keys.sql`;
  the server is `supabase/functions/mcp-server/index.ts`.

## Extending

Add new tools in `TOOLS` + `executeTool()` in the function. Keep two rules:
scope-check via the tool's `scope` field, and **always** filter by
`ctx.workspaceId`.
