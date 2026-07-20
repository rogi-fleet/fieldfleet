import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.43.4";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

type ScanRequest = {
  workspace_id?: string;
  date?: string; // YYYY-MM-DD (UTC)
  max_alerts_per_user?: number;
};

function getEnv(name: string): string {
  const value = Deno.env.get(name);
  if (!value) {
    throw new Error(`Missing environment variable: ${name}`);
  }
  return value;
}

function ymd(date: Date): string {
  return date.toISOString().slice(0, 10);
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
    }

    const body = (await req.json().catch(() => ({}))) as ScanRequest;
    const workspaceId = body.workspace_id?.trim();
    if (!workspaceId) {
      return new Response(JSON.stringify({ error: "workspace_id is required" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const alertDate = body.date?.trim() || ymd(new Date());
    const alertStart = `${alertDate}T00:00:00.000Z`;
    const maxAlertsPerUser = Math.max(1, Math.min(25, body.max_alerts_per_user ?? 8));

    const admin = createClient(supabaseUrl, serviceRoleKey);

    const { data: overdueTasks, error: tasksError } = await admin
      .from("tasks")
      .select("id,title,project_id,due_date,assigned_to_ids,workspace_id")
      .eq("workspace_id", workspaceId)
      .eq("priority", "high")
      .eq("is_complete", false)
      .lt("due_date", alertStart)
      .order("due_date", { ascending: true })
      .limit(500);

    if (tasksError) {
      return new Response(
        JSON.stringify({ error: "Failed to load overdue tasks", details: tasksError.message }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const notificationsCreated: string[] = [];
    const userAlertCounts = new Map<string, number>();

    for (const task of overdueTasks ?? []) {
      const assigned = Array.isArray(task.assigned_to_ids)
        ? (task.assigned_to_ids as string[]).filter((id) => typeof id === "string" && id.length > 0)
        : [];

      if (assigned.length === 0) continue;

      for (const userId of assigned) {
        const count = userAlertCounts.get(userId) ?? 0;
        if (count >= maxAlertsPerUser) continue;

        const { data: existing } = await admin
          .from("notifications")
          .select("id")
          .eq("workspace_id", workspaceId)
          .eq("user_id", userId)
          .eq("type", "priority_alert")
          .contains("metadata", {
            task_id: task.id,
            alert_date: alertDate,
          })
          .limit(1);

        if (existing && existing.length > 0) continue;

        const dueDateRaw = typeof task.due_date === "string" ? task.due_date : "";
        const dueDateLabel = dueDateRaw ? dueDateRaw.slice(0, 10) : "unknown";

        const { data: inserted, error: insertError } = await admin
          .from("notifications")
          .insert({
            user_id: userId,
            workspace_id: workspaceId,
            type: "priority_alert",
            title: `High-priority task overdue: ${task.title}`,
            body: `Due ${dueDateLabel}. Tap to open task details.`,
            metadata: {
              target_type: "task",
              task_id: task.id,
              project_id: task.project_id,
              alert_date: alertDate,
              tab: "tasks",
              deeplink_path: `/projects/${task.project_id}?tab=tasks&taskId=${task.id}`,
            },
          })
          .select("id")
          .single();

        if (insertError || !inserted?.id) {
          console.error("Failed to create priority alert notification", {
            userId,
            taskId: task.id,
            error: insertError?.message,
          });
          continue;
        }

        notificationsCreated.push(inserted.id as string);
        userAlertCounts.set(userId, count + 1);
      }
    }

    let dispatchOk = 0;
    let dispatchFailed = 0;

    for (const notificationId of notificationsCreated) {
      try {
        const dispatchResponse = await fetch(`${supabaseUrl}/functions/v1/push-dispatch`, {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            Authorization: `Bearer ${serviceRoleKey}`,
            apikey: anonKey,
          },
          body: JSON.stringify({ notification_id: notificationId }),
        });

        if (dispatchResponse.ok) {
          dispatchOk += 1;
        } else {
          dispatchFailed += 1;
          console.error("Priority alert dispatch failed", {
            notificationId,
            status: dispatchResponse.status,
            response: await dispatchResponse.text(),
          });
        }
      } catch (error) {
        dispatchFailed += 1;
        console.error("Priority alert dispatch exception", {
          notificationId,
          error: error instanceof Error ? error.message : String(error),
        });
      }
    }

    return new Response(
      JSON.stringify({
        success: true,
        workspace_id: workspaceId,
        alert_date: alertDate,
        notifications_created: notificationsCreated.length,
        dispatch_ok: dispatchOk,
        dispatch_failed: dispatchFailed,
      }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error("Error in priority-alert-scan:", error);
    return new Response(JSON.stringify({ error: message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
