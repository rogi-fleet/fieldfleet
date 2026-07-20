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

const NOTIFY_EMAILS = ["notifications.com", "notifications.com"];

interface FeedbackNotificationRequest {
  category: string;
  message: string;
  workspaceId: string;
}

const CATEGORY_LABELS: Record<string, string> = {
  bug: "Bug Report",
  feature_request: "Feature Request",
  improvement: "Improvement",
  general: "General Feedback",
};

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const authHeader = req.headers.get("authorization");
    if (!authHeader) {
      return new Response(
        JSON.stringify({ error: "Missing authorization header" }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const supabaseServiceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY");

    if (!supabaseUrl || !supabaseServiceRoleKey || !supabaseAnonKey) {
      console.error("Supabase configuration missing");
      return new Response(
        JSON.stringify({ error: "Server configuration error" }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    // Verify caller is authenticated
    const authClient = createClient(supabaseUrl, supabaseAnonKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: { user }, error: authError } = await authClient.auth.getUser();
    if (authError || !user) {
      return new Response(
        JSON.stringify({ error: "Invalid or expired authentication token" }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const resendConfig = getResendConfig();
    if (!resendConfig) {
      console.error("RESEND_API_KEY not configured");
      return new Response(
        JSON.stringify({ error: "Email service not configured" }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const { category, message, workspaceId }: FeedbackNotificationRequest =
      await req.json();

    if (!category || !message) {
      return new Response(
        JSON.stringify({ error: "category and message are required" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    // Look up sender and workspace names for context
    const adminClient = createClient(supabaseUrl, supabaseServiceRoleKey);

    const [{ data: senderRow }, { data: workspaceRow }] = await Promise.all([
      adminClient
        .from("users")
        .select("display_name, email")
        .eq("id", user.id)
        .single(),
      adminClient
        .from("workspaces")
        .select("name")
        .eq("id", workspaceId)
        .single(),
    ]);

    const senderName = senderRow?.display_name || senderRow?.email || user.email || "Unknown user";
    const workspaceName = workspaceRow?.name || workspaceId;
    const categoryLabel = CATEGORY_LABELS[category] || category;
    const safeMessage = escapeHtml(message);
    const safeSender = escapeHtml(senderName);
    const safeWorkspace = escapeHtml(workspaceName);

    const html = buildTaskFleetEmail({
      preheader: `New ${categoryLabel} from ${senderName}`,
      title: `New Feedback: ${categoryLabel}`,
      intro: `${safeSender} from ${safeWorkspace} submitted feedback.`,
      bodyHtml: `
        <table style="width: 100%; border-collapse: collapse; margin: 12px 0;">
          <tr>
            <td style="padding: 8px 12px; font-weight: 600; color: #516173; width: 110px; vertical-align: top;">Category</td>
            <td style="padding: 8px 12px;">${escapeHtml(categoryLabel)}</td>
          </tr>
          <tr>
            <td style="padding: 8px 12px; font-weight: 600; color: #516173; vertical-align: top;">From</td>
            <td style="padding: 8px 12px;">${safeSender} (${escapeHtml(user.email || "")})</td>
          </tr>
          <tr>
            <td style="padding: 8px 12px; font-weight: 600; color: #516173; vertical-align: top;">Workspace</td>
            <td style="padding: 8px 12px;">${safeWorkspace}</td>
          </tr>
        </table>
        <div style="background: #f5f8fc; border-left: 4px solid #0d4f8b; padding: 14px 16px; border-radius: 0 8px 8px 0; margin: 12px 0;">
          <p style="margin: 0; white-space: pre-wrap;">${safeMessage}</p>
        </div>
      `,
      footerHtml: '<p style="margin: 0;">This is an automated notification from FieldFleet feedback.</p>',
    });

    let sentCount = 0;
    const errors: string[] = [];

    for (const recipient of NOTIFY_EMAILS) {
      try {
        await sendResendEmail(resendConfig, {
          to: recipient,
          subject: `FieldFleet Feedback: ${categoryLabel} from ${senderName}`,
          html,
        });
        sentCount++;
        console.log(`Feedback notification sent to ${recipient}`);
      } catch (emailError) {
        const msg = emailError instanceof Error ? emailError.message : String(emailError);
        console.error(`Error sending to ${recipient}:`, emailError);
        errors.push(`${recipient}: ${msg}`);
      }
    }

    return new Response(
      JSON.stringify({ success: true, sent: sentCount, errors }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error("Error in send-feedback-notification:", error);
    return new Response(
      JSON.stringify({ error: message }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }
});
