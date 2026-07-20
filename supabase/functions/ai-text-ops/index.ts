// ai-text-ops — lightweight LLM-backed text transforms used by the file
// comment composer (rewrite / expand / tone).
//
// Separate from `ai-copilot` because that function is project-scoped and
// entirely rule-based; this one is generic, stateless, and reaches an
// external LLM. Gated by workspace feature flag `ai_text_ops_v1` and
// rate-limited per user per minute.

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.43.4";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

type Operation = "rewrite" | "expand" | "tone";

interface TextOpsRequest {
  operation: Operation;
  workspace_id: string;
  text: string;
  // Operation-specific:
  style?: "concise" | "clear" | "professional"; // rewrite
  tone?: "friendly" | "formal" | "direct";      // tone
}

const MAX_INPUT_CHARS = 4000;
const MAX_OUTPUT_TOKENS = 1000;
const RATE_LIMIT_PER_MINUTE = 20;

function getEnv(name: string): string {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`Missing environment variable: ${name}`);
  return value;
}

function buildPrompt(req: TextOpsRequest): string {
  const text = req.text.trim();
  switch (req.operation) {
    case "rewrite": {
      const style = req.style ?? "clear";
      return `Rewrite the following text to be more ${style}. ` +
        `Preserve meaning, tone, and any @mentions or URLs exactly. ` +
        `Return ONLY the rewritten text — no preamble, no quotes.\n\n${text}`;
    }
    case "expand":
      return `Expand the following short text into a slightly longer, ` +
        `more detailed version while keeping the same voice. Do not ` +
        `invent facts. Preserve @mentions and URLs exactly. Return ONLY ` +
        `the expanded text — no preamble, no quotes.\n\n${text}`;
    case "tone": {
      const tone = req.tone ?? "friendly";
      return `Rewrite the following text in a more ${tone} tone while ` +
        `preserving meaning and any @mentions or URLs. Return ONLY the ` +
        `rewritten text — no preamble, no quotes.\n\n${text}`;
    }
  }
}

async function ensureMembership(
  supabaseService: ReturnType<typeof createClient>,
  workspaceId: string,
  userId: string,
) {
  const { data, error } = await supabaseService
    .from("workspace_members")
    .select("workspace_id")
    .eq("workspace_id", workspaceId)
    .eq("user_id", userId)
    .maybeSingle();
  if (error) throw new Error(`Membership check failed: ${error.message}`);
  if (!data) throw new Error("User is not a member of this workspace");
}

async function isFlagEnabled(
  supabaseService: ReturnType<typeof createClient>,
  workspaceId: string,
): Promise<boolean> {
  const { data } = await supabaseService
    .from("workspace_feature_flags")
    .select("flags")
    .eq("workspace_id", workspaceId)
    .maybeSingle();
  const flags = (data?.flags || {}) as Record<string, boolean>;
  return flags["ai_text_ops_v1"] === true;
}

/**
 * Very simple per-user sliding-window rate limit using the ai_copilot_events
 * table (already present). Counts how many ai-text-ops events this user has
 * logged in the last 60 seconds. Cheap and good enough; swap for a proper
 * KV-backed limiter if traffic spikes.
 */
async function enforceRateLimit(
  supabaseService: ReturnType<typeof createClient>,
  userId: string,
) {
  const since = new Date(Date.now() - 60_000).toISOString();
  const { count, error } = await supabaseService
    .from("ai_copilot_events")
    .select("id", { count: "exact", head: true })
    .eq("user_id", userId)
    .eq("operation", "text_ops")
    .gte("created_at", since);
  if (error) {
    // Fail open — don't block on telemetry hiccups.
    console.warn("rate-limit check failed:", error.message);
    return;
  }
  if ((count ?? 0) >= RATE_LIMIT_PER_MINUTE) {
    throw new Error(
      `Rate limit reached (${RATE_LIMIT_PER_MINUTE}/min). Try again shortly.`,
    );
  }
}

async function callAnthropic(prompt: string): Promise<string> {
  const apiKey = getEnv("ANTHROPIC_API_KEY");
  const model = Deno.env.get("ANTHROPIC_MODEL") ?? "claude-haiku-4-5-20251001";

  const res = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "x-api-key": apiKey,
      "anthropic-version": "2023-06-01",
      "content-type": "application/json",
    },
    body: JSON.stringify({
      model,
      max_tokens: MAX_OUTPUT_TOKENS,
      messages: [{ role: "user", content: prompt }],
    }),
  });

  if (!res.ok) {
    const body = await res.text();
    throw new Error(`Anthropic API ${res.status}: ${body.slice(0, 500)}`);
  }

  const json = await res.json() as {
    content?: Array<{ type: string; text?: string }>;
  };
  const text = (json.content ?? [])
    .filter((block) => block.type === "text")
    .map((block) => block.text ?? "")
    .join("")
    .trim();
  if (!text) throw new Error("LLM returned empty response");
  return text;
}

async function logEvent(
  supabaseService: ReturnType<typeof createClient>,
  payload: Record<string, unknown>,
) {
  const { error } = await supabaseService
    .from("ai_copilot_events")
    .insert(payload);
  if (error) console.error("Failed to log ai_copilot_events:", error.message);
}

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const startedAt = Date.now();

  try {
    const supabaseUrl = getEnv("SUPABASE_URL");
    const supabaseAnonKey = getEnv("SUPABASE_ANON_KEY");
    const serviceRoleKey = getEnv("SUPABASE_SERVICE_ROLE_KEY");

    const authHeader = req.headers.get("authorization");
    if (!authHeader) {
      return new Response(
        JSON.stringify({ error: "Missing authorization header" }),
        {
          status: 401,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const supabaseUser = createClient(supabaseUrl, supabaseAnonKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const supabaseService = createClient(supabaseUrl, serviceRoleKey);

    const { data: { user }, error: authError } = await supabaseUser.auth
      .getUser();
    if (authError || !user) {
      return new Response(
        JSON.stringify({ error: "Invalid or expired authentication token" }),
        {
          status: 401,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const body = (await req.json()) as TextOpsRequest;
    if (!body?.workspace_id || !body?.operation || !body?.text) {
      return new Response(
        JSON.stringify({
          error: "Missing required fields: workspace_id, operation, text",
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    if (!["rewrite", "expand", "tone"].includes(body.operation)) {
      return new Response(
        JSON.stringify({ error: `Unknown operation: ${body.operation}` }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    if (body.text.length > MAX_INPUT_CHARS) {
      return new Response(
        JSON.stringify({
          error: `Input too long (max ${MAX_INPUT_CHARS} chars)`,
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    await ensureMembership(supabaseService, body.workspace_id, user.id);

    if (!await isFlagEnabled(supabaseService, body.workspace_id)) {
      return new Response(
        JSON.stringify({
          error: "Feature disabled",
          required_flag: "ai_text_ops_v1",
        }),
        {
          status: 403,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    await enforceRateLimit(supabaseService, user.id);

    const prompt = buildPrompt(body);
    const output = await callAnthropic(prompt);
    const latency = Date.now() - startedAt;

    await logEvent(supabaseService, {
      workspace_id: body.workspace_id,
      user_id: user.id,
      project_id: null,
      operation: "text_ops",
      status: "success",
      request_payload: {
        op: body.operation,
        style: body.style,
        tone: body.tone,
        input_length: body.text.length,
      },
      response_payload: { output_length: output.length },
      provider: "anthropic",
      model: Deno.env.get("ANTHROPIC_MODEL") ?? "claude-haiku-4-5-20251001",
      latency_ms: latency,
      error: null,
    });

    return new Response(
      JSON.stringify({
        operation: body.operation,
        text: output,
        meta: { latency_ms: latency },
      }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  } catch (error) {
    const msg = (error instanceof Error) ? error.message : String(error);
    console.error("ai-text-ops error:", msg);
    const status = msg.startsWith("Rate limit") ? 429 : 500;
    return new Response(
      JSON.stringify({ error: msg }),
      {
        status,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});
