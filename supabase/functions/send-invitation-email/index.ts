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

interface InvitationEmailRequest {
  email: string;
  workspaceName: string;
  inviterName: string;
  token: string;
  role?: string;
}

serve(async (req: Request) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // Verify the JWT token using Supabase client
    const authHeader = req.headers.get("authorization");
    if (!authHeader) {
      return new Response(
        JSON.stringify({ error: "Missing authorization header" }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Get Supabase URL and anon key from environment
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY");

    if (!supabaseUrl || !supabaseAnonKey) {
      console.error("Supabase configuration missing");
      return new Response(
        JSON.stringify({ error: "Server configuration error" }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Create Supabase client with the user's JWT
    const supabase = createClient(supabaseUrl, supabaseAnonKey, {
      global: {
        headers: { Authorization: authHeader },
      },
    });

    // Verify the user is authenticated by getting their info
    const { data: { user }, error: authError } = await supabase.auth.getUser();

    if (authError || !user) {
      console.error("Auth verification failed:", authError?.message);
      return new Response(
        JSON.stringify({ error: "Invalid or expired authentication token" }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    console.log(`Request authenticated for user: ${user.id}`);

    const resendConfig = getResendConfig();
    const SITE_URL = Deno.env.get("SITE_URL") || "https://app.example.com";

    if (!resendConfig) {
      console.error("RESEND_API_KEY not configured");
      return new Response(
        JSON.stringify({ error: "Email service not configured" }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const { email, workspaceName, inviterName, token, role }: InvitationEmailRequest = await req.json();

    if (!email || !workspaceName || !token) {
      return new Response(
        JSON.stringify({ error: "Missing required fields: email, workspaceName, token" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const inviteUrl = `${SITE_URL}/#/invite/${token}`;
    const displayRole = role ? role.charAt(0).toUpperCase() + role.slice(1).replace('_', ' ') : 'Team Member';
    const safeWorkspaceName = escapeHtml(workspaceName);
    const safeInviterName = escapeHtml(inviterName);
    const safeEmail = escapeHtml(email);
    const safeDisplayRole = escapeHtml(displayRole);

    const html = buildTaskFleetEmail({
      preheader: `${inviterName} invited you to ${workspaceName}`,
      title: "You’re Invited to FieldFleet",
      bodyHtml: `
        <p style="margin: 0 0 12px 0;"><strong>${safeInviterName}</strong> has invited you to join <strong>${safeWorkspaceName}</strong>.</p>
        <p style="margin: 0 0 12px 0;">
          Assigned role:
          <span style="display: inline-block; background: #e7eef7; color: #0d4f8b; border-radius: 999px; padding: 4px 12px; font-size: 13px; font-weight: 600;">
            ${safeDisplayRole}
          </span>
        </p>
        <p style="margin: 0 0 12px 0;">This invitation expires in 7 days.</p>
        <p style="margin: 0; font-size: 13px; color: #516173;">If the button does not work, open this link:<br/><a href="${inviteUrl}" style="color: #0d4f8b; word-break: break-all;">${inviteUrl}</a></p>
      `,
      ctaLabel: "Accept Invitation",
      ctaUrl: inviteUrl,
      footerHtml: `<p style="margin: 0;">This invitation was sent to <strong>${safeEmail}</strong>.</p><p style="margin: 8px 0 0 0;">If this wasn’t expected, you can ignore this email.</p>`,
    });

    const result = await sendResendEmail(resendConfig, {
      to: email,
      subject: `FieldFleet: Invitation to ${workspaceName}`,
      html,
    });
    console.log(`Invitation email sent to ${email}. Resend ID: ${result.id}`);

    return new Response(
      JSON.stringify({ success: true, id: result.id }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error("Error sending invitation email:", error);
    return new Response(
      JSON.stringify({ error: message }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
