// Fans out staff notifications when a customer posts to a portal-visible
// thread. Called from portal_send_message via pg_net, always with the
// service-role bearer.
//
// For each workspace_member participant (excluding the sender):
//   1. Create a `message_received` notification (dedupe-keyed on
//      conversation+sender so a flurry of messages collapses).
//   2. Enqueue an email via enqueue_digest_email; immediate-mode users get
//      sent synchronously via Resend.
//   3. POST to push-dispatch with the notification id.
//
// Customer-side push isn't dispatched here (no customer device registration
// yet). Customers see staff replies on next portal open and via the unread
// badge driven by conversations.unread_counts.

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.43.4";
import {
  buildTaskFleetEmail,
  escapeHtml,
} from "../_shared/email_template.ts";
import { getResendConfig, sendResendEmail } from "../_shared/resend.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

interface RequestBody {
  message_id?: string;
}

interface MessageRow {
  id: string;
  conversation_id: string;
  workspace_id: string;
  sender_id: string | null;
  sender_name: string | null;
  content: string | null;
}

interface ConversationRow {
  id: string;
  workspace_id: string;
  scope: string;
  scope_reference_id: string | null;
  participant_ids: string[] | null;
  portal_visible: boolean;
}

interface ProjectRow {
  id: string;
  name: string | null;
  workspace_id: string;
}

function previewOf(content: string | null | undefined): string {
  if (!content) return "";
  const trimmed = content.trim();
  return trimmed.length > 200 ? `${trimmed.slice(0, 200)}…` : trimmed;
}

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const authHeader = req.headers.get("authorization") ?? "";
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY");

    if (!supabaseUrl || !serviceRoleKey || !anonKey) {
      return new Response(
        JSON.stringify({ error: "Server configuration error" }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    // Service-role only — this function is intended to be called from
    // pg_net (portal_send_message) with the service-role JWT.
    const token = authHeader.replace(/^Bearer\s+/i, "").trim();
    if (!token || token !== serviceRoleKey) {
      return new Response(
        JSON.stringify({ error: "Service role required" }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const body = (await req.json()) as RequestBody;
    const messageId = body.message_id?.trim();
    if (!messageId) {
      return new Response(
        JSON.stringify({ error: "message_id is required" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const admin = createClient(supabaseUrl, serviceRoleKey);

    // 1. Load the message. NB: the column is `timestamp` (a reserved word
    //    used as a column name), not `created_at`. We only need fields the
    //    notification + email/push routing rely on, so we omit timestamps
    //    entirely here.
    const { data: message, error: messageError } = await admin
      .from("messages")
      .select("id,conversation_id,workspace_id,sender_id,sender_name,content")
      .eq("id", messageId)
      .maybeSingle();

    if (messageError || !message) {
      return new Response(
        JSON.stringify({
          error: "Message not found",
          details: messageError?.message,
        }),
        { status: 404, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }
    const messageRow = message as MessageRow;

    // 2. Load the conversation; bail if it's not portal-visible or
    //    project-scoped (defensive — caller should already enforce this).
    const { data: conversation, error: convError } = await admin
      .from("conversations")
      .select("id,workspace_id,scope,scope_reference_id,participant_ids,portal_visible")
      .eq("id", messageRow.conversation_id)
      .maybeSingle();

    if (convError || !conversation) {
      return new Response(
        JSON.stringify({
          error: "Conversation not found",
          details: convError?.message,
        }),
        { status: 404, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }
    const conv = conversation as ConversationRow;

    if (!conv.portal_visible || conv.scope !== "project" || !conv.scope_reference_id) {
      return new Response(
        JSON.stringify({
          success: true,
          skipped: "not_portal_visible",
        }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    // 3. Load the project (for title in notification + email).
    const { data: project, error: projectError } = await admin
      .from("projects")
      .select("id,name,workspace_id")
      .eq("id", conv.scope_reference_id)
      .maybeSingle();

    if (projectError || !project) {
      return new Response(
        JSON.stringify({
          error: "Project not found",
          details: projectError?.message,
        }),
        { status: 404, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }
    const projectRow = project as ProjectRow;

    // 4. Recipient list = participant_ids ∩ workspace_members − sender.
    //    Customer contacts authenticate via auth.users but typically have
    //    no public.users / workspace_members row, so this intersection
    //    naturally drops them and leaves only staff.
    const participantIds = (conv.participant_ids ?? []).filter(
      (id) => id && id !== messageRow.sender_id,
    );

    if (participantIds.length === 0) {
      return new Response(
        JSON.stringify({ success: true, recipients: 0 }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const { data: members, error: membersError } = await admin
      .from("workspace_members")
      .select("user_id")
      .eq("workspace_id", conv.workspace_id)
      .in("user_id", participantIds);

    if (membersError) {
      return new Response(
        JSON.stringify({
          error: "Failed to load workspace members",
          details: membersError.message,
        }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const staffIds = (members ?? [])
      .map((row) => (row as { user_id: string }).user_id)
      .filter((id) => !!id);

    if (staffIds.length === 0) {
      return new Response(
        JSON.stringify({ success: true, recipients: 0 }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    // 5. Resolve emails + display names for the email path.
    const { data: users, error: usersError } = await admin
      .from("users")
      .select("id,email,display_name")
      .in("id", staffIds);

    if (usersError) {
      console.error("portal-message-notify: failed to load users", usersError);
    }
    const usersById = new Map<string, { email: string | null; display_name: string | null }>();
    for (const row of (users ?? []) as Array<
      { id: string; email: string | null; display_name: string | null }
    >) {
      usersById.set(row.id, { email: row.email, display_name: row.display_name });
    }

    const senderName = messageRow.sender_name ?? "A customer";
    const projectName = projectRow.name ?? "your project";
    const preview = previewOf(messageRow.content);
    const subject = `FieldFleet: ${senderName} messaged you on ${projectName}`;
    const previewText = `${senderName}: ${preview}`;

    const SITE_URL =
      Deno.env.get("SITE_URL") || "https://app.example.com";
    const threadUrl = `${SITE_URL}/#/projects/${projectRow.id}?tab=messages`;

    const safeSender = escapeHtml(senderName);
    const safeProject = escapeHtml(projectName);
    const safePreview = escapeHtml(preview);

    const html = buildTaskFleetEmail({
      preheader: previewText,
      title: "New message from your customer",
      bodyHtml: `
        <p style="margin: 0 0 12px 0;"><strong>${safeSender}</strong> posted a new message on <strong>${safeProject}</strong>.</p>
        <div style="background: #f5f8fc; border-left: 4px solid #0d4f8b; padding: 14px 16px; border-radius: 0 8px 8px 0; margin: 0 0 12px 0;">
          <p style="margin: 0; color: #1f2937;">${safePreview}</p>
        </div>
      `,
      ctaLabel: "Open thread",
      ctaUrl: threadUrl,
      footerHtml:
        '<p style="margin: 0;">You received this because you are a team member on this project.</p>',
    });

    const resendConfig = getResendConfig();
    const dedupeKey = `portal_msg:${conv.id}:${messageRow.sender_id ?? "unknown"}`;

    let notifiedCount = 0;
    let queuedCount = 0;
    let sentCount = 0;
    let pushDispatched = 0;
    let pushFailed = 0;
    const errors: string[] = [];

    for (const recipientId of staffIds) {
      // 5a. Create the in-app notification (dedupe-keyed).
      let notificationId: string | null = null;
      try {
        const { data, error } = await admin.rpc("create_notification", {
          p_user_id: recipientId,
          p_workspace_id: conv.workspace_id,
          p_type: "message_received",
          p_title: `${senderName} messaged you`,
          p_body: preview,
          p_metadata: {
            conversation_id: conv.id,
            project_id: projectRow.id,
            message_id: messageRow.id,
            sender_id: messageRow.sender_id,
            sender_name: senderName,
            deeplink_path: `/projects/${projectRow.id}?tab=messages`,
          },
          p_dedupe_key: dedupeKey,
          p_dedupe_window_seconds: 300,
        });
        if (error) {
          errors.push(`create_notification(${recipientId}): ${error.message}`);
          continue;
        }
        notificationId = (data as string | null) ?? null;
        if (notificationId) notifiedCount += 1;
      } catch (e) {
        errors.push(
          `create_notification(${recipientId}) threw: ${
            e instanceof Error ? e.message : String(e)
          }`,
        );
        continue;
      }

      // 5b. Email path — enqueue_digest_email; fall back to immediate Resend
      //     for users in immediate mode (RPC returns NULL in that case).
      const recipient = usersById.get(recipientId);
      const recipientEmail = recipient?.email ?? null;
      if (recipientEmail) {
        let queuedId: string | null = null;
        try {
          const { data, error } = await admin.rpc("enqueue_digest_email", {
            p_user_id: recipientId,
            p_workspace_id: conv.workspace_id,
            p_notification_id: notificationId,
            p_type: "message_received",
            p_subject: subject,
            p_body_html: html,
            p_cta_label: "Open thread",
            p_cta_url: threadUrl,
            p_preview_text: previewText,
          });
          if (!error) {
            queuedId = (data as string | null) ?? null;
          }
        } catch (e) {
          console.error("enqueue_digest_email threw", e);
        }
        if (queuedId) {
          queuedCount += 1;
        } else if (resendConfig) {
          try {
            await sendResendEmail(resendConfig, {
              to: recipientEmail,
              subject,
              html,
            });
            sentCount += 1;
          } catch (e) {
            const message = e instanceof Error ? e.message : String(e);
            errors.push(`resend(${recipientEmail}): ${message}`);
          }
        }
      }

      // 5c. Push dispatch.
      if (notificationId) {
        try {
          const resp = await fetch(
            `${supabaseUrl}/functions/v1/push-dispatch`,
            {
              method: "POST",
              headers: {
                "Content-Type": "application/json",
                Authorization: `Bearer ${serviceRoleKey}`,
                apikey: anonKey,
              },
              body: JSON.stringify({ notification_id: notificationId }),
            },
          );
          if (resp.ok) {
            pushDispatched += 1;
          } else {
            pushFailed += 1;
            console.error("push-dispatch failed", {
              notificationId,
              status: resp.status,
              body: await resp.text(),
            });
          }
        } catch (e) {
          pushFailed += 1;
          console.error("push-dispatch threw", {
            notificationId,
            error: e instanceof Error ? e.message : String(e),
          });
        }
      }
    }

    return new Response(
      JSON.stringify({
        success: true,
        recipients: staffIds.length,
        notified: notifiedCount,
        emails_queued: queuedCount,
        emails_sent: sentCount,
        push_dispatched: pushDispatched,
        push_failed: pushFailed,
        errors,
      }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error("portal-message-notify error", error);
    return new Response(
      JSON.stringify({ error: message }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }
});
