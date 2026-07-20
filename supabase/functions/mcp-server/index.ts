// mcp-server — Model Context Protocol server over streamable HTTP.
//
// Lets external AI assistants (Claude, ChatGPT, or anything MCP-capable)
// act on a FieldFleet workspace: list jobs, read the WIP schedule and cash
// flow, search the catalog, list invoices/tasks, and create tasks.
//
// Auth: callers present a workspace API key ("tfk_…", created by a
// workspace admin under Settings → API Keys) as a Bearer token. Only the
// SHA-256 hash is stored (workspace_api_keys.key_hash); we hash the
// presented key and look it up with the service role, then scope every
// query to that key's workspace. Read tools require the 'read' scope,
// create_task requires 'write'.
//
// Transport: stateless streamable HTTP — each POST carries one JSON-RPC
// message and gets a single application/json response (no SSE session).
//
// DEPLOY with --no-verify-jwt: MCP clients send our API key, not a
// Supabase JWT.

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.43.4";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, content-type, mcp-protocol-version",
};

const PROTOCOL_VERSION = "2025-03-26";
const SERVER_INFO = { name: "taskfleet-mcp", version: "1.0.0" };

interface KeyContext {
  workspaceId: string;
  scopes: string[];
  keyId: string;
}

async function sha256Hex(input: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(input),
  );
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

// ---------------------------------------------------------------------------
// Tool definitions
// ---------------------------------------------------------------------------

const TOOLS = [
  {
    name: "list_projects",
    description:
      "List the workspace's jobs/projects with status and contract amount.",
    inputSchema: {
      type: "object",
      properties: {
        status: {
          type: "string",
          description: "Optional filter: bidding | active | complete",
        },
      },
    },
    scope: "read",
  },
  {
    name: "get_wip_report",
    description:
      "Work-in-progress schedule: per project contract, estimated cost, " +
      "cost to date, percent complete, earned revenue, billed to date, and " +
      "over/under billing.",
    inputSchema: { type: "object", properties: {} },
    scope: "read",
  },
  {
    name: "get_cash_flow",
    description:
      "Open invoice balances (expected inflows) and open bills (expected " +
      "outflows) with due dates.",
    inputSchema: { type: "object", properties: {} },
    scope: "read",
  },
  {
    name: "list_tasks",
    description: "List tasks, optionally for one project or one status.",
    inputSchema: {
      type: "object",
      properties: {
        project_id: { type: "string" },
        status: {
          type: "string",
          description: "not_started | working_on_it | stuck | done",
        },
        limit: { type: "number", description: "Max rows (default 50)" },
      },
    },
    scope: "read",
  },
  {
    name: "list_invoices",
    description:
      "List customer invoices with totals, amounts paid, and status.",
    inputSchema: {
      type: "object",
      properties: {
        project_id: { type: "string" },
        unpaid_only: { type: "boolean" },
      },
    },
    scope: "read",
  },
  {
    name: "search_catalog",
    description: "Search the cost catalog by name/SKU.",
    inputSchema: {
      type: "object",
      properties: {
        query: { type: "string" },
      },
      required: ["query"],
    },
    scope: "read",
  },
  {
    name: "create_task",
    description: "Create a task on a project.",
    inputSchema: {
      type: "object",
      properties: {
        project_id: { type: "string" },
        title: { type: "string" },
        description: { type: "string" },
        due_in_days: {
          type: "number",
          description: "Due date as days from today",
        },
      },
      required: ["project_id", "title"],
    },
    scope: "write",
  },
];

// ---------------------------------------------------------------------------
// Tool execution (every query MUST be scoped by ctx.workspaceId — the
// service-role client bypasses RLS)
// ---------------------------------------------------------------------------

async function executeTool(
  admin: ReturnType<typeof createClient>,
  ctx: KeyContext,
  name: string,
  args: Record<string, unknown>,
): Promise<unknown> {
  switch (name) {
    case "list_projects": {
      let query = admin
        .from("projects")
        .select("id, name, status, contract_amount, address, price_type")
        .eq("workspace_id", ctx.workspaceId)
        .order("created_at", { ascending: false })
        .limit(200);
      if (typeof args.status === "string") {
        query = query.eq("status", args.status);
      }
      const { data, error } = await query;
      if (error) throw new Error(error.message);
      return data;
    }
    case "get_wip_report": {
      const { data, error } = await admin.rpc("get_wip_report", {
        p_workspace_id: ctx.workspaceId,
      });
      if (error) throw new Error(error.message);
      return data;
    }
    case "get_cash_flow": {
      const { data, error } = await admin.rpc("get_cash_flow_entries", {
        p_workspace_id: ctx.workspaceId,
      });
      if (error) throw new Error(error.message);
      return data;
    }
    case "list_tasks": {
      let query = admin
        .from("tasks")
        .select("id, project_id, title, status, priority, start_date, due_date, progress")
        .eq("workspace_id", ctx.workspaceId)
        .order("due_date", { ascending: true, nullsFirst: false })
        .limit(Math.min(Number(args.limit) || 50, 200));
      if (typeof args.project_id === "string") {
        query = query.eq("project_id", args.project_id);
      }
      if (typeof args.status === "string") {
        query = query.eq("status", args.status);
      }
      const { data, error } = await query;
      if (error) throw new Error(error.message);
      return data;
    }
    case "list_invoices": {
      let query = admin
        .from("generated_documents")
        .select(
          "id, project_id, document_number, document_type, status, total_amount, amount_paid, due_date, paid_date",
        )
        .eq("workspace_id", ctx.workspaceId)
        .in("document_type", ["invoice", "progress_invoice", "aia_pay_app", "deposit"])
        .order("created_at", { ascending: false })
        .limit(200);
      if (typeof args.project_id === "string") {
        query = query.eq("project_id", args.project_id);
      }
      if (args.unpaid_only === true) {
        query = query.is("paid_date", null);
      }
      const { data, error } = await query;
      if (error) throw new Error(error.message);
      return data;
    }
    case "search_catalog": {
      const term = String(args.query ?? "").trim();
      if (!term) throw new Error("query is required");
      const escaped = term.replace(/[%_]/g, "\\$&");
      const { data, error } = await admin
        .from("catalog_items")
        .select("id, name, description, unit, unit_cost, unit_price, sku")
        .eq("workspace_id", ctx.workspaceId)
        .or(`name.ilike.%${escaped}%,sku.ilike.%${escaped}%`)
        .limit(50);
      if (error) throw new Error(error.message);
      return data;
    }
    case "create_task": {
      const projectId = String(args.project_id ?? "").trim();
      const title = String(args.title ?? "").trim();
      if (!projectId || !title) {
        throw new Error("project_id and title are required");
      }
      // The project must belong to this key's workspace.
      const { data: project } = await admin
        .from("projects")
        .select("id")
        .eq("id", projectId)
        .eq("workspace_id", ctx.workspaceId)
        .maybeSingle();
      if (!project) throw new Error("Project not found in this workspace");

      const now = new Date();
      const dueInDays = Number(args.due_in_days);
      const { data, error } = await admin
        .from("tasks")
        .insert({
          workspace_id: ctx.workspaceId,
          project_id: projectId,
          title,
          description: typeof args.description === "string"
            ? args.description
            : null,
          status: "not_started",
          priority: "medium",
          created_at: now.toISOString(),
          updated_at: now.toISOString(),
          ...(isFinite(dueInDays) && dueInDays > 0
            ? {
              due_date: new Date(
                now.getTime() + dueInDays * 86_400_000,
              ).toISOString(),
            }
            : {}),
        })
        .select("id, title, due_date")
        .single();
      if (error) throw new Error(error.message);
      return data;
    }
    default:
      throw new Error(`Unknown tool: ${name}`);
  }
}

// ---------------------------------------------------------------------------
// JSON-RPC plumbing
// ---------------------------------------------------------------------------

function rpcResult(id: unknown, result: unknown) {
  return { jsonrpc: "2.0", id, result };
}

function rpcError(id: unknown, code: number, message: string) {
  return { jsonrpc: "2.0", id, error: { code, message } };
}

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const json = (body: unknown, status = 200) =>
    new Response(JSON.stringify(body), {
      status,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });

  if (req.method !== "POST") {
    // Stateless transport: no SSE stream to offer on GET.
    return json({ error: "Method not allowed" }, 405);
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!supabaseUrl || !serviceRoleKey) {
      return json({ error: "Server configuration missing" }, 500);
    }

    // --- API key auth -----------------------------------------------------
    const authHeader = req.headers.get("Authorization") ?? "";
    const presented = authHeader.replace(/^Bearer\s+/i, "").trim();
    if (!presented.startsWith("tfk_")) {
      return json(
        {
          error:
            "Provide a FieldFleet workspace API key (Settings → API Keys) " +
            "as a Bearer token",
        },
        401,
      );
    }

    const admin = createClient(supabaseUrl, serviceRoleKey);
    const keyHash = await sha256Hex(presented);
    const { data: keyRow } = await admin
      .from("workspace_api_keys")
      .select("id, workspace_id, scopes, revoked_at")
      .eq("key_hash", keyHash)
      .maybeSingle();
    if (!keyRow || keyRow.revoked_at) {
      return json({ error: "Invalid or revoked API key" }, 401);
    }
    const ctx: KeyContext = {
      workspaceId: keyRow.workspace_id as string,
      scopes: (keyRow.scopes as string[] | null) ?? [],
      keyId: keyRow.id as string,
    };
    // Best-effort usage stamp; never blocks the request.
    admin
      .from("workspace_api_keys")
      .update({ last_used_at: new Date().toISOString() })
      .eq("id", ctx.keyId)
      .then(() => {}, () => {});

    // --- JSON-RPC dispatch --------------------------------------------------
    const message = await req.json();
    const { id, method, params } = message ?? {};

    if (method === "initialize") {
      return json(rpcResult(id, {
        protocolVersion: PROTOCOL_VERSION,
        capabilities: { tools: {} },
        serverInfo: SERVER_INFO,
        instructions:
          "FieldFleet construction-management workspace. Use list_projects " +
          "to discover jobs, get_wip_report / get_cash_flow for financial " +
          "position, and create_task to add work items.",
      }));
    }
    if (method === "notifications/initialized" || method === "ping") {
      return method === "ping"
        ? json(rpcResult(id, {}))
        : new Response(null, { status: 202, headers: corsHeaders });
    }
    if (method === "tools/list") {
      return json(rpcResult(id, {
        tools: TOOLS.map(({ scope: _scope, ...tool }) => tool),
      }));
    }
    if (method === "tools/call") {
      const toolName = params?.name as string | undefined;
      const tool = TOOLS.find((t) => t.name === toolName);
      if (!tool || !toolName) {
        return json(rpcError(id, -32602, `Unknown tool: ${toolName}`));
      }
      if (!ctx.scopes.includes(tool.scope)) {
        return json(rpcResult(id, {
          content: [{
            type: "text",
            text: `This API key lacks the '${tool.scope}' scope.`,
          }],
          isError: true,
        }));
      }
      try {
        const result = await executeTool(
          admin,
          ctx,
          toolName,
          (params?.arguments ?? {}) as Record<string, unknown>,
        );
        return json(rpcResult(id, {
          content: [{ type: "text", text: JSON.stringify(result, null, 2) }],
        }));
      } catch (e) {
        const text = e instanceof Error ? e.message : String(e);
        return json(rpcResult(id, {
          content: [{ type: "text", text: `Tool failed: ${text}` }],
          isError: true,
        }));
      }
    }

    return json(rpcError(id, -32601, `Method not found: ${method}`));
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error("mcp-server error:", message);
    return json(rpcError(null, -32603, message), 500);
  }
});
