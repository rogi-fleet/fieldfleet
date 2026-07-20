import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.43.4";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

interface SendSpecSheetEmailRequest {
  specSheetId: string;
  recipientEmail: string;
  subject?: string;
  message?: string;
}

const defaultAttachmentMaxBytes = 25 * 1024 * 1024;

function escapeHtml(value: string): string {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}

function bytesToBase64(bytes: Uint8Array): string {
  let binary = "";
  const chunkSize = 0x8000;
  for (let i = 0; i < bytes.length; i += chunkSize) {
    const chunk = bytes.subarray(i, i + chunkSize);
    binary += String.fromCharCode(...chunk);
  }
  return btoa(binary);
}

function sanitizeAttachmentFilename(fileName: string): string {
  return fileName.replaceAll(/[\\/\r\n]/g, "_").trim() || "specifications.pdf";
}

function normalizeEmail(email: string): string {
  return email.trim().toLowerCase();
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

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY");
    const supabaseServiceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const resendApiKey = Deno.env.get("RESEND_API_KEY");
    const fromEmail =
      Deno.env.get("FROM_EMAIL") || "FieldFleet <noreply@example.com>";

    if (!supabaseUrl || !supabaseAnonKey || !supabaseServiceRoleKey) {
      return new Response(JSON.stringify({ error: "Supabase configuration missing" }), {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }
    if (!resendApiKey) {
      return new Response(JSON.stringify({ error: "Email service not configured" }), {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const adminClient = createClient(supabaseUrl, supabaseServiceRoleKey);
    const supabase = createClient(supabaseUrl, supabaseAnonKey, {
      global: { headers: { Authorization: authHeader } },
    });

    const { data: { user }, error: authError } = await supabase.auth.getUser();
    if (authError || !user) {
      return new Response(JSON.stringify({ error: "Invalid or expired authentication token" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const { specSheetId, recipientEmail, subject, message }:
      SendSpecSheetEmailRequest = await req.json();

    if (!specSheetId || !recipientEmail) {
      return new Response(
        JSON.stringify({ error: "Missing required fields: specSheetId, recipientEmail" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    // RLS scoped fetch — uses caller's JWT.
    const { data: sheetRow, error: sheetError } = await supabase
      .from("spec_sheets")
      .select("id, workspace_id, project_id, title, file_attachment_id")
      .eq("id", specSheetId)
      .maybeSingle();

    if (sheetError || !sheetRow) {
      return new Response(JSON.stringify({ error: "Spec sheet not found or access denied" }), {
        status: 404,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Authorization guard: the attachment must live in the same workspace and
    // project as the sheet. Without this, a malicious workspace member could
    // craft a spec_sheets row pointing at another workspace's attachment and
    // exfiltrate it via service-role download below. A DB trigger enforces the
    // same invariant on writes; this is defence-in-depth on reads.
    const { data: fileRow, error: fileError } = await adminClient
      .from("file_attachments")
      .select(
        "file_name, file_url, file_size, bucket, storage_path, workspace_id, project_id",
      )
      .eq("id", sheetRow.file_attachment_id)
      .eq("workspace_id", sheetRow.workspace_id)
      .eq("project_id", sheetRow.project_id)
      .maybeSingle();

    if (fileError || !fileRow) {
      return new Response(JSON.stringify({ error: "Spec sheet file missing" }), {
        status: 404,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Download bytes
    let bytes: Uint8Array | null = null;
    if (fileRow.bucket && fileRow.storage_path) {
      const { data, error } = await adminClient.storage
        .from(fileRow.bucket as string)
        .download(fileRow.storage_path as string);
      if (!error && data) {
        bytes = new Uint8Array(await data.arrayBuffer());
      }
    }
    if ((!bytes || bytes.length === 0) && fileRow.file_url) {
      try {
        const r = await fetch(fileRow.file_url as string);
        if (r.ok) bytes = new Uint8Array(await r.arrayBuffer());
      } catch (_) { /* ignore */ }
    }

    const maxBytes = Number(
      Deno.env.get("DOCUMENT_EMAIL_ATTACHMENT_MAX_BYTES") || defaultAttachmentMaxBytes,
    );
    const includeAsAttachment = bytes && bytes.length > 0 && bytes.length <= maxBytes;
    const fileName = sanitizeAttachmentFilename(
      (fileRow.file_name as string) || `${sheetRow.title}.pdf`,
    );

    const resolvedTitle = escapeHtml(sheetRow.title as string);
    const defaultSubject = `Specifications: ${sheetRow.title}`;
    const defaultMessage = "Please find the attached specifications sheet for your records.";
    const resolvedSubject = subject?.trim() || defaultSubject;
    const resolvedMessage = escapeHtml(message?.trim() || defaultMessage)
      .replaceAll("\n", "<br/>");
    const normalizedRecipient = normalizeEmail(recipientEmail);

    const linkBlock = fileRow.file_url
      ? `<p style="margin: 8px 0;"><a href="${escapeHtml(fileRow.file_url as string)}" style="color: #1f3a8a;">Open PDF</a></p>`
      : "";

    const html = `
      <!DOCTYPE html>
      <html><head><meta charset="utf-8"></head>
        <body style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Arial, sans-serif; line-height: 1.6; color: #333; max-width: 620px; margin: 0 auto; padding: 20px;">
          <div style="background: #1f3a8a; color: white; padding: 20px; border-radius: 8px 8px 0 0;">
            <h1 style="margin: 0; font-size: 20px;">Specifications Sheet</h1>
          </div>
          <div style="background: #fff; border: 1px solid #e5e7eb; border-top: none; padding: 24px;">
            <p><strong>${resolvedTitle}</strong></p>
            <p>${resolvedMessage}</p>
            ${linkBlock}
          </div>
        </body>
      </html>
    `;

    const resendPayload: Record<string, unknown> = {
      from: fromEmail,
      to: normalizedRecipient,
      subject: resolvedSubject,
      html,
    };
    if (includeAsAttachment && bytes) {
      resendPayload.attachments = [{
        filename: fileName,
        content: bytesToBase64(bytes),
      }];
    }

    const resendResponse = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${resendApiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(resendPayload),
    });

    if (!resendResponse.ok) {
      const errorText = await resendResponse.text();
      return new Response(
        JSON.stringify({ error: "Failed to send email", details: errorText }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const resendResult = await resendResponse.json();
    return new Response(
      JSON.stringify({ success: true, id: resendResult.id, attached: includeAsAttachment }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  } catch (error) {
    const m = error instanceof Error ? error.message : String(error);
    return new Response(JSON.stringify({ error: m }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
