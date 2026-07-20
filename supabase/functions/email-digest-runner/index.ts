// email-digest-runner — drains email_notification_queue and sends one
// rolled-up digest email per user.
//
// Invocation:
//   POST /functions/v1/email-digest-runner
//   { "mode": "hourly" | "daily" }
//
// Auth: service-role only. The cron job posts using the service role key
// (see migration 20260503160300). End users can't trigger this.
//
// Per user: select their pending rows for this mode, build a single
// digest email (each row contributes one section), send via Resend, then
// mark the rows delivered. On send failure: bump attempts and keep them
// on the queue for the next run.

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.43.4";
import { buildTaskFleetEmail } from "../_shared/email_template.ts";
import { getResendConfig, sendResendEmail } from "../_shared/resend.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

type QueueRow = {
  id: string;
  workspace_id: string;
  notification_id: string | null;
  type: string;
  subject: string;
  body_html: string;
  cta_label: string | null;
  cta_url: string | null;
  preview_text: string | null;
  enqueued_at: string;
};

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const SITE_URL = Deno.env.get("SITE_URL") || "https://app.example.com";
const MAX_USERS_PER_RUN = Number(Deno.env.get("DIGEST_MAX_USERS_PER_RUN") || "200");
const MAX_ROWS_PER_USER = Number(Deno.env.get("DIGEST_MAX_ROWS_PER_USER") || "100");

function buildDigestHtml(rows: QueueRow[]): string {
  const sections = rows
    .map((row) => {
      const cta = row.cta_url && row.cta_label
        ? `<a href="${row.cta_url}" style="color: #0d4f8b; font-weight: 600; text-decoration: none;">${row.cta_label} →</a>`
        : "";
      return `
        <div style="border-left: 4px solid #0d4f8b; padding: 12px 16px; margin: 0 0 14px 0; background: #f5f8fc; border-radius: 0 8px 8px 0;">
          <p style="margin: 0 0 4px 0; font-weight: 600; color: #1f2937;">${row.subject}</p>
          ${row.preview_text ? `<p style="margin: 0 0 6px 0; color: #4b5563; font-size: 14px;">${row.preview_text}</p>` : ""}
          ${cta}
        </div>
      `;
    })
    .join("\n");

  return `
    <p style="margin: 0 0 16px 0;">Here's a summary of recent activity in your workspace.</p>
    ${sections}
  `;
}

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const authHeader = req.headers.get("authorization") || "";
    const token = authHeader.replace("Bearer ", "").trim();
    if (token !== SERVICE_ROLE_KEY) {
      return new Response(
        JSON.stringify({ error: "Service role required" }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const body = (await req.json().catch(() => ({}))) as { mode?: string };
    const mode = body.mode === "daily" ? "daily" : "hourly";

    const resendConfig = getResendConfig();
    if (!resendConfig) {
      return new Response(
        JSON.stringify({ error: "RESEND_API_KEY not configured" }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

    const { data: pendingUsers, error: pendingError } = await admin.rpc(
      "email_digest_users_pending",
      { p_mode: mode },
    );

    if (pendingError) {
      console.error("email_digest_users_pending failed", pendingError);
      return new Response(
        JSON.stringify({ error: "Failed to load pending users", details: pendingError.message }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const userRows = (pendingUsers ?? []) as Array<{ user_id: string; pending_count: number }>;
    const userBatch = userRows.slice(0, MAX_USERS_PER_RUN);

    let usersProcessed = 0;
    let totalSent = 0;
    let totalFailed = 0;
    const errors: Array<{ user_id: string; error: string }> = [];

    for (const { user_id } of userBatch) {
      const { data: rowsData, error: rowsError } = await admin
        .from("email_notification_queue")
        .select(
          "id, workspace_id, notification_id, type, subject, body_html, cta_label, cta_url, preview_text, enqueued_at",
        )
        .eq("user_id", user_id)
        .eq("digest_mode", mode)
        .is("delivered_at", null)
        .order("enqueued_at", { ascending: true })
        .limit(MAX_ROWS_PER_USER);

      if (rowsError) {
        console.error("Failed to load queue rows for user", user_id, rowsError);
        errors.push({ user_id, error: rowsError.message });
        continue;
      }

      const rows = (rowsData ?? []) as QueueRow[];
      if (rows.length === 0) continue;

      const { data: userData, error: userError } = await admin
        .from("users")
        .select("email, display_name")
        .eq("id", user_id)
        .maybeSingle();

      if (userError || !userData?.email) {
        const message = userError?.message ?? "Recipient email missing";
        await admin.rpc("mark_digest_emails_failed", {
          p_ids: rows.map((r) => r.id),
          p_error: message,
        });
        totalFailed += rows.length;
        errors.push({ user_id, error: message });
        continue;
      }

      const subject = mode === "daily"
        ? `FieldFleet daily digest (${rows.length} update${rows.length === 1 ? "" : "s"})`
        : `FieldFleet update digest (${rows.length} update${rows.length === 1 ? "" : "s"})`;

      const html = buildTaskFleetEmail({
        preheader: `${rows.length} new update${rows.length === 1 ? "" : "s"} from your workspace`,
        title: mode === "daily" ? "Your daily digest" : "Your latest updates",
        bodyHtml: buildDigestHtml(rows),
        ctaLabel: "Open FieldFleet",
        ctaUrl: `${SITE_URL}/#/notifications`,
      });

      try {
        await sendResendEmail(resendConfig, {
          to: userData.email,
          subject,
          html,
        });
        await admin.rpc("mark_digest_emails_delivered", {
          p_ids: rows.map((r) => r.id),
        });
        usersProcessed += 1;
        totalSent += rows.length;
      } catch (sendError) {
        const message = sendError instanceof Error ? sendError.message : String(sendError);
        await admin.rpc("mark_digest_emails_failed", {
          p_ids: rows.map((r) => r.id),
          p_error: message,
        });
        totalFailed += rows.length;
        errors.push({ user_id, error: message });
      }
    }

    return new Response(
      JSON.stringify({
        success: true,
        mode,
        users_pending: userRows.length,
        users_processed: usersProcessed,
        rows_sent: totalSent,
        rows_failed: totalFailed,
        errors,
      }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error("Error in email-digest-runner:", error);
    return new Response(
      JSON.stringify({ error: message }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }
});
