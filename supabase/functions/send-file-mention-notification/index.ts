// send-file-mention-notification — transactional email for @mentions left
// in file comments. Mirrors send-mention-notification (which handles task
// comments) with a file-scoped payload and deep link back to the exact
// comment via `/files?fileId=<>&commentId=<>`. In-app notifications are
// fanned out separately by SupabaseFileCommentService; this function is
// responsible only for the email side.

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

interface FileMentionNotificationRequest {
  mentionedUserIds: string[];
  senderName: string;
  fileTitle: string;
  commentContent: string;
  fileAttachmentId: string;
  commentId: string;
  workspaceId: string;
}

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
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

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const supabaseServiceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY");

    if (!supabaseUrl || !supabaseServiceRoleKey || !supabaseAnonKey) {
      console.error("Supabase configuration missing");
      return new Response(
        JSON.stringify({ error: "Server configuration error" }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Verify caller is authenticated.
    const authClient = createClient(supabaseUrl, supabaseAnonKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: { user }, error: authError } = await authClient.auth
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

    const resendConfig = getResendConfig();
    const SITE_URL = Deno.env.get("SITE_URL") ||
      "https://app.example.com";

    if (!resendConfig) {
      console.error("RESEND_API_KEY not configured");
      return new Response(
        JSON.stringify({ error: "Email service not configured" }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const {
      mentionedUserIds,
      senderName,
      fileTitle,
      commentContent,
      fileAttachmentId,
      commentId,
    }: FileMentionNotificationRequest = await req.json();

    if (!mentionedUserIds || mentionedUserIds.length === 0) {
      return new Response(
        JSON.stringify({ error: "No mentioned users provided" }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Service-role client for email lookup — bypasses RLS deliberately so
    // we can reach mentioned users' emails regardless of whether the
    // caller can see them. We still only email ids the caller supplied.
    const adminClient = createClient(supabaseUrl, supabaseServiceRoleKey);

    const { data: users, error: usersError } = await adminClient
      .from("users")
      .select("id, email, display_name")
      .in_("id", mentionedUserIds);

    if (usersError) {
      console.error("Error fetching mentioned users:", usersError);
      return new Response(
        JSON.stringify({ error: "Failed to look up mentioned users" }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    if (!users || users.length === 0) {
      return new Response(
        JSON.stringify({ success: true, sent: 0, message: "No users found" }),
        {
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Deep link points at /files?fileId=...&commentId=... — the web
    // router parses both and the file detail panel highlights the
    // referenced comment on arrival.
    const fileUrl =
      `${SITE_URL}/#/files?fileId=${fileAttachmentId}&commentId=${commentId}`;

    const contentPreview = commentContent.length > 200
      ? commentContent.substring(0, 200) + "..."
      : commentContent;
    const safeSender = escapeHtml(senderName);
    const safeFileTitle = escapeHtml(fileTitle);
    const safePreview = escapeHtml(contentPreview);

    // Resolution centralized in effective_notification_pref (workspace
    // mute > workspace per-type > user per-type > default ON).
    const wantsMentionEmail = async (
      recipientId: string,
    ): Promise<boolean> => {
      try {
        const { data, error } = await adminClient.rpc(
          "effective_notification_pref",
          {
            p_user_id: recipientId,
            p_workspace_id: workspaceId,
            p_pref_key: "mentionsEmail",
          },
        );
        if (error) {
          console.error("effective_notification_pref RPC error", error);
          return true;
        }
        return data !== false;
      } catch (e) {
        console.error("effective_notification_pref threw", e);
        return true;
      }
    };

    let sentCount = 0;
    let skippedCount = 0;
    let queuedCount = 0;
    const errors: string[] = [];

    const subject = `FieldFleet: ${senderName} mentioned you`;
    const previewText = `${senderName} mentioned you on ${fileTitle}`;

    for (const mentionedUser of users) {
      // Never email the sender about their own mention.
      if (mentionedUser.id === user.id) continue;
      if (!(await wantsMentionEmail(mentionedUser.id))) {
        skippedCount++;
        console.log(
          `Skipping file mention email for ${mentionedUser.email}: prefs disabled or workspace muted`,
        );
        continue;
      }

      const html = buildTaskFleetEmail({
        preheader: previewText,
        title: "You Were Mentioned",
        bodyHtml: `
          <p style="margin: 0 0 12px 0;"><strong>${safeSender}</strong> mentioned you on <strong>${safeFileTitle}</strong>.</p>
          <div style="background: #f5f8fc; border-left: 4px solid #0d4f8b; padding: 14px 16px; border-radius: 0 8px 8px 0; margin: 0 0 12px 0;">
            <p style="margin: 0; color: #1f2937;">${safePreview}</p>
          </div>
        `,
        ctaLabel: "View File",
        ctaUrl: fileUrl,
        footerHtml:
          "<p style=\"margin: 0;\">You received this because you were mentioned in FieldFleet.</p>",
      });

      // Try the digest queue first; enqueue_digest_email returns NULL for
      // 'immediate' mode users, in which case we send synchronously.
      try {
        const { data: queuedId, error: queueError } = await adminClient.rpc(
          "enqueue_digest_email",
          {
            p_user_id: mentionedUser.id,
            p_workspace_id: workspaceId,
            p_notification_id: null,
            p_type: "mention",
            p_subject: subject,
            p_body_html: html,
            p_cta_label: "View File",
            p_cta_url: fileUrl,
            p_preview_text: previewText,
          },
        );
        if (!queueError && queuedId) {
          queuedCount++;
          continue;
        }
      } catch (e) {
        console.error("enqueue_digest_email threw", e);
        // Fall through to immediate send.
      }

      try {
        await sendResendEmail(resendConfig, {
          to: mentionedUser.email,
          subject,
          html,
        });
        sentCount++;
        console.log(
          `File mention notification sent to ${mentionedUser.email}`,
        );
      } catch (emailError) {
        const emailMessage = emailError instanceof Error
          ? emailError.message
          : String(emailError);
        console.error(
          `Error sending to ${mentionedUser.email}:`,
          emailError,
        );
        errors.push(`${mentionedUser.email}: ${emailMessage}`);
      }
    }

    return new Response(
      JSON.stringify({
        success: true,
        sent: sentCount,
        queued: queuedCount,
        skipped: skippedCount,
        errors,
      }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error("Error in send-file-mention-notification:", error);
    return new Response(
      JSON.stringify({ error: message }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});
