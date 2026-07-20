import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.43.4";
import { SignJWT, importPKCS8 } from "npm:jose@5.9.6";
import { pushPrefKeyFor } from "../_shared/notification_types.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

type DispatchRequest = {
  notification_id?: string;
};

type PushDeviceRow = {
  id: string;
  user_id: string;
  platform: "android" | "ios";
  transport: "fcm" | "apns";
  push_token: string;
};

type NotificationRow = {
  id: string;
  user_id: string;
  workspace_id: string;
  type: string;
  title: string;
  body: string | null;
  metadata: Record<string, unknown> | null;
};

let cachedApnsJwt: { token: string; expiresAt: number } | null = null;

function getEnv(name: string): string {
  const value = Deno.env.get(name);
  if (!value) {
    throw new Error(`Missing environment variable: ${name}`);
  }
  return value;
}

function getOptionalString(input: unknown): string | undefined {
  return typeof input === "string" && input.trim().length > 0
    ? input.trim()
    : undefined;
}

function routeFromMetadata(metadata: Record<string, unknown>): string {
  const explicit =
    getOptionalString(metadata["deeplink_path"]) ??
    getOptionalString(metadata["deep_link"]) ??
    getOptionalString(metadata["route"]) ??
    getOptionalString(metadata["target_path"]);

  if (explicit) {
    return explicit.startsWith("/") ? explicit : `/${explicit}`;
  }

  const projectId =
    getOptionalString(metadata["project_id"]) ??
    getOptionalString(metadata["projectId"]);
  const taskId =
    getOptionalString(metadata["task_id"]) ?? getOptionalString(metadata["taskId"]);
  const conversationId =
    getOptionalString(metadata["conversation_id"]) ??
    getOptionalString(metadata["conversationId"]);
  const documentId =
    getOptionalString(metadata["document_id"]) ??
    getOptionalString(metadata["documentId"]);

  if (projectId && taskId) {
    return `/projects/${projectId}?tab=tasks&taskId=${taskId}`;
  }
  if (conversationId) {
    return `/messages/${conversationId}`;
  }
  if (documentId) {
    return `/documents/${documentId}`;
  }
  if (projectId) {
    return `/projects/${projectId}`;
  }
  return "/notifications";
}

function stringifyDataValue(value: unknown): string {
  if (value == null) return "";
  if (typeof value === "string") return value;
  if (typeof value === "number" || typeof value === "boolean") {
    return String(value);
  }
  try {
    return JSON.stringify(value);
  } catch {
    return String(value);
  }
}

function normalizeApnsPrivateKey(raw: string): string {
  return raw.includes("\\n") ? raw.replaceAll("\\n", "\n") : raw;
}

async function getApnsJwt(): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cachedApnsJwt && cachedApnsJwt.expiresAt > now + 30) {
    return cachedApnsJwt.token;
  }

  const teamId = getEnv("APNS_TEAM_ID");
  const keyId = getEnv("APNS_KEY_ID");
  const privateKeyPem = normalizeApnsPrivateKey(getEnv("APNS_PRIVATE_KEY"));

  const key = await importPKCS8(privateKeyPem, "ES256");
  const token = await new SignJWT({})
    .setProtectedHeader({ alg: "ES256", kid: keyId })
    .setIssuer(teamId)
    .setIssuedAt(now)
    .sign(key);

  cachedApnsJwt = {
    token,
    expiresAt: now + 50 * 60,
  };

  return token;
}

async function sendViaFcm(params: {
  token: string;
  title: string;
  body: string | null;
  data: Record<string, string>;
}) {
  const serverKey = Deno.env.get("FCM_SERVER_KEY");
  if (!serverKey) {
    return {
      provider: "fcm",
      status: "skipped" as const,
      errorCode: "missing_fcm_server_key",
      errorMessage: "FCM_SERVER_KEY is not configured",
      raw: null,
      invalidToken: false,
    };
  }

  const response = await fetch("https://fcm.googleapis.com/fcm/send", {
    method: "POST",
    headers: {
      Authorization: `key=${serverKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      to: params.token,
      priority: "high",
      notification: {
        title: params.title,
        body: params.body ?? "",
      },
      data: params.data,
    }),
  });

  const rawText = await response.text();
  let parsed: Record<string, unknown> | null = null;
  try {
    parsed = JSON.parse(rawText) as Record<string, unknown>;
  } catch {
    parsed = null;
  }

  if (!response.ok) {
    return {
      provider: "fcm",
      status: "failed" as const,
      errorCode: `http_${response.status}`,
      errorMessage: rawText,
      raw: parsed ?? rawText,
      invalidToken: response.status === 404,
    };
  }

  const firstResult = Array.isArray(parsed?.results)
    ? (parsed?.results as Array<Record<string, unknown>>)[0]
    : null;
  const fcmError = getOptionalString(firstResult?.error);
  const invalidToken = fcmError === "NotRegistered" || fcmError === "InvalidRegistration";

  if (fcmError) {
    return {
      provider: "fcm",
      status: invalidToken ? ("invalid_token" as const) : ("failed" as const),
      errorCode: fcmError,
      errorMessage: fcmError,
      raw: parsed,
      invalidToken,
    };
  }

  return {
    provider: "fcm",
    status: "sent" as const,
    errorCode: null,
    errorMessage: null,
    raw: parsed,
    invalidToken: false,
  };
}

async function sendViaApns(params: {
  token: string;
  title: string;
  body: string | null;
  data: Record<string, string>;
}) {
  const teamId = Deno.env.get("APNS_TEAM_ID");
  const keyId = Deno.env.get("APNS_KEY_ID");
  const bundleId = Deno.env.get("APNS_BUNDLE_ID");
  const privateKey = Deno.env.get("APNS_PRIVATE_KEY");

  if (!teamId || !keyId || !bundleId || !privateKey) {
    return {
      provider: "apns",
      status: "skipped" as const,
      errorCode: "missing_apns_config",
      errorMessage:
        "APNS_TEAM_ID/APNS_KEY_ID/APNS_BUNDLE_ID/APNS_PRIVATE_KEY not fully configured",
      raw: null,
      invalidToken: false,
    };
  }

  const jwt = await getApnsJwt();
  const useSandbox = (Deno.env.get("APNS_USE_SANDBOX") || "false").toLowerCase() === "true";
  const host = useSandbox ? "api.sandbox.push.apple.com" : "api.push.apple.com";

  const body = {
    aps: {
      alert: {
        title: params.title,
        body: params.body ?? "",
      },
      sound: "default",
    },
    ...params.data,
  };

  const response = await fetch(`https://${host}/3/device/${params.token}`, {
    method: "POST",
    headers: {
      authorization: `bearer ${jwt}`,
      "apns-topic": bundleId,
      "apns-push-type": "alert",
      "content-type": "application/json",
    },
    body: JSON.stringify(body),
  });

  const rawText = await response.text();
  let reason = "";
  if (rawText) {
    try {
      const parsed = JSON.parse(rawText) as Record<string, unknown>;
      reason = getOptionalString(parsed.reason) ?? "";
    } catch {
      reason = rawText;
    }
  }

  const invalidToken =
    response.status === 410 ||
    reason === "BadDeviceToken" ||
    reason === "Unregistered";

  if (!response.ok) {
    return {
      provider: "apns",
      status: invalidToken ? ("invalid_token" as const) : ("failed" as const),
      errorCode: `http_${response.status}`,
      errorMessage: reason || "APNs send failed",
      raw: rawText || null,
      invalidToken,
    };
  }

  return {
    provider: "apns",
    status: "sent" as const,
    errorCode: null,
    errorMessage: null,
    raw: rawText || null,
    invalidToken: false,
  };
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

    const token = authHeader.replace("Bearer ", "").trim();
    const isServiceRole = token === serviceRoleKey;

    let callerUserId: string | null = null;
    if (!isServiceRole) {
      const authClient = createClient(supabaseUrl, anonKey, {
        global: { headers: { Authorization: authHeader } },
      });
      const {
        data: { user },
        error,
      } = await authClient.auth.getUser();
      if (error || !user) {
        return new Response(
          JSON.stringify({ error: "Invalid or expired authentication token" }),
          {
            status: 401,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          },
        );
      }
      callerUserId = user.id;
    }

    const payload = (await req.json()) as DispatchRequest;
    const notificationId = payload.notification_id?.trim();
    if (!notificationId) {
      return new Response(JSON.stringify({ error: "notification_id is required" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const admin = createClient(supabaseUrl, serviceRoleKey);

    const { data: notification, error: notificationError } = await admin
      .from("notifications")
      .select("id,user_id,workspace_id,type,title,body,metadata")
      .eq("id", notificationId)
      .maybeSingle();

    if (notificationError || !notification) {
      return new Response(
        JSON.stringify({ error: "Notification not found", details: notificationError?.message }),
        {
          status: 404,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const notificationRow = notification as NotificationRow;

    if (!isServiceRole && callerUserId != null && callerUserId !== notificationRow.user_id) {
      const { data: membership } = await admin
        .from("workspace_members")
        .select("user_id")
        .eq("workspace_id", notificationRow.workspace_id)
        .eq("user_id", callerUserId)
        .limit(1);
      if (!membership || membership.length === 0) {
        return new Response(
          JSON.stringify({ error: "Not allowed to dispatch this notification" }),
          {
            status: 403,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          },
        );
      }
    }

    const metadata =
      notificationRow.metadata && typeof notificationRow.metadata === "object"
        ? (notificationRow.metadata as Record<string, unknown>)
        : {};
    const deeplinkPath = routeFromMetadata(metadata);

    // Resolution order is owned by effective_notification_pref:
    //   workspace mute → workspace per-type → user per-type → default ON.
    const pushPrefKey = pushPrefKeyFor(notificationRow.type);
    const { data: prefAllowed, error: prefError } = await admin.rpc(
      "effective_notification_pref",
      {
        p_user_id: notificationRow.user_id,
        p_workspace_id: notificationRow.workspace_id,
        p_pref_key: pushPrefKey,
      },
    );

    if (prefError) {
      console.error("Failed to resolve notification preference", prefError);
    }

    if (prefAllowed === false) {
      await admin.from("push_delivery_logs").insert({
        notification_id: notificationRow.id,
        user_id: notificationRow.user_id,
        provider: "none",
        status: "skipped",
        error_code: "preferences_disabled",
        error_message: `Push disabled for notification type ${notificationRow.type}`,
        payload: {
          deeplink_path: deeplinkPath,
          type: notificationRow.type,
          pref_key: pushPrefKey,
        },
      });

      return new Response(
        JSON.stringify({
          success: true,
          sent: 0,
          failed: 0,
          skipped: 1,
          reason: "preferences_disabled",
        }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const { data: devices, error: devicesError } = await admin
      .from("push_devices")
      .select("id,user_id,platform,transport,push_token")
      .eq("user_id", notificationRow.user_id)
      .eq("is_active", true);

    if (devicesError) {
      return new Response(
        JSON.stringify({ error: "Failed to load push devices", details: devicesError.message }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const activeDevices = (devices ?? []) as PushDeviceRow[];
    if (activeDevices.length === 0) {
      await admin.from("push_delivery_logs").insert({
        notification_id: notificationRow.id,
        user_id: notificationRow.user_id,
        provider: "none",
        status: "skipped",
        error_code: "no_active_devices",
        error_message: "No active push devices found for recipient",
        payload: {
          deeplink_path: deeplinkPath,
          type: notificationRow.type,
        },
      });

      return new Response(
        JSON.stringify({
          success: true,
          sent: 0,
          failed: 0,
          skipped: 1,
          reason: "no_active_devices",
        }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const pushData: Record<string, string> = {
      notification_id: notificationRow.id,
      notification_type: notificationRow.type,
      deeplink_path: deeplinkPath,
    };

    for (const [key, value] of Object.entries(metadata)) {
      if (pushData[key]) continue;
      pushData[key] = stringifyDataValue(value);
    }

    let sent = 0;
    let failed = 0;
    let skipped = 0;
    const invalidDeviceIds: string[] = [];

    for (const device of activeDevices) {
      let result:
        | Awaited<ReturnType<typeof sendViaFcm>>
        | Awaited<ReturnType<typeof sendViaApns>>;

      if (device.transport === "apns") {
        result = await sendViaApns({
          token: device.push_token,
          title: notificationRow.title,
          body: notificationRow.body,
          data: pushData,
        });
      } else {
        result = await sendViaFcm({
          token: device.push_token,
          title: notificationRow.title,
          body: notificationRow.body,
          data: pushData,
        });
      }

      if (result.status === "sent") sent += 1;
      else if (result.status === "skipped") skipped += 1;
      else failed += 1;

      if (result.invalidToken) {
        invalidDeviceIds.push(device.id);
      }

      await admin.from("push_delivery_logs").insert({
        notification_id: notificationRow.id,
        user_id: notificationRow.user_id,
        device_id: device.id,
        provider: result.provider,
        status: result.status,
        error_code: result.errorCode,
        error_message: result.errorMessage,
        payload: {
          title: notificationRow.title,
          body: notificationRow.body,
          data: pushData,
          provider_response: result.raw,
        },
      });
    }

    if (invalidDeviceIds.length > 0) {
      await admin
        .from("push_devices")
        .update({
          is_active: false,
          updated_at: new Date().toISOString(),
        })
        .in("id", invalidDeviceIds);
    }

    return new Response(
      JSON.stringify({
        success: true,
        notification_id: notificationRow.id,
        sent,
        failed,
        skipped,
        deactivated_devices: invalidDeviceIds.length,
      }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error("Error in push-dispatch:", error);
    return new Response(JSON.stringify({ error: message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
