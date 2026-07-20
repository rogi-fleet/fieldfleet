import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.43.4";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

type RegisterRequest = {
  workspace_id?: string;
  device_id?: string;
  platform?: "android" | "ios";
  transport?: "fcm" | "apns";
  push_token?: string;
  app_version?: string;
  timezone?: string;
  locale?: string;
  metadata?: Record<string, unknown>;
};

function getEnv(name: string): string {
  const value = Deno.env.get(name);
  if (!value) {
    throw new Error(`Missing environment variable: ${name}`);
  }
  return value;
}

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const authHeader = req.headers.get("authorization");
    if (!authHeader) {
      return new Response(JSON.stringify({ error: "Missing authorization header" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const supabaseUrl = getEnv("SUPABASE_URL");
    const serviceRoleKey = getEnv("SUPABASE_SERVICE_ROLE_KEY");
    const anonKey = getEnv("SUPABASE_ANON_KEY");

    const authClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    });

    const {
      data: { user },
      error: authError,
    } = await authClient.auth.getUser();

    if (authError || !user) {
      return new Response(
        JSON.stringify({ error: "Invalid or expired authentication token" }),
        {
          status: 401,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const body = (await req.json()) as RegisterRequest;
    const deviceId = body.device_id?.trim();
    const platform = body.platform;
    const transport = body.transport ?? "fcm";
    const pushToken = body.push_token?.trim();

    if (!deviceId || !platform || !pushToken) {
      return new Response(
        JSON.stringify({
          error: "device_id, platform, and push_token are required",
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    if (!["android", "ios"].includes(platform)) {
      return new Response(JSON.stringify({ error: "Invalid platform" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    if (!["fcm", "apns"].includes(transport)) {
      return new Response(JSON.stringify({ error: "Invalid transport" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const admin = createClient(supabaseUrl, serviceRoleKey);

    let workspaceId = body.workspace_id?.trim();
    if (!workspaceId) {
      const { data: userRow } = await admin
        .from("users")
        .select("active_workspace_id")
        .eq("id", user.id)
        .maybeSingle();
      workspaceId = (userRow?.active_workspace_id as string | null) ?? undefined;
    }

    // Remove stale registration where the same token exists under another user.
    await admin
      .from("push_devices")
      .delete()
      .eq("platform", platform)
      .eq("transport", transport)
      .eq("push_token", pushToken)
      .neq("user_id", user.id);

    const payload = {
      user_id: user.id,
      workspace_id: workspaceId ?? null,
      device_id: deviceId,
      platform,
      transport,
      push_token: pushToken,
      app_version: body.app_version?.trim() || null,
      timezone: body.timezone?.trim() || null,
      locale: body.locale?.trim() || null,
      metadata: body.metadata ?? {},
      is_active: true,
      last_seen_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
    };

    const { data, error } = await admin
      .from("push_devices")
      .upsert(payload, {
        onConflict: "user_id,device_id,platform,transport",
      })
      .select("id,user_id,workspace_id,platform,transport,is_active,last_seen_at")
      .single();

    if (error) {
      return new Response(
        JSON.stringify({ error: "Failed to register push device", details: error.message }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    return new Response(
      JSON.stringify({ success: true, device: data }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error("Error in push-device-register:", error);
    return new Response(JSON.stringify({ error: message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
