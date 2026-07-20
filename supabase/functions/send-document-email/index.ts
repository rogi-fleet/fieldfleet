import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.43.4";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

interface SendDocumentEmailRequest {
  documentId: string;
  recipientEmail: string;
  subject?: string;
  message?: string;
  documentTitle?: string;
  requireSignature?: boolean;
}

interface FileAttachmentRow {
  id: string;
  file_name: string;
  file_url: string | null;
  file_size: number | null;
  mime_type: string | null;
  bucket: string | null;
  storage_path: string | null;
}

interface ResendAttachment {
  filename: string;
  content: string;
}

const defaultAttachmentMaxBytes = 25 * 1024 * 1024;

function generateToken(): string {
  return `${crypto.randomUUID().replaceAll("-", "")}${Date.now().toString(36)}`;
}

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

function normalizeAttachmentIds(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return value
    .map((item) => item?.toString())
    .filter((item): item is string => Boolean(item));
}

function sanitizeAttachmentFilename(fileName: string): string {
  return fileName.replaceAll(/[\\/\r\n]/g, "_").trim() || "attachment";
}

function normalizeEmail(email: string): string {
  return email.trim().toLowerCase();
}

async function downloadAttachmentBytes(
  adminClient: ReturnType<typeof createClient>,
  file: FileAttachmentRow,
): Promise<Uint8Array | null> {
  if (file.bucket && file.storage_path) {
    const { data, error } = await adminClient.storage
      .from(file.bucket)
      .download(file.storage_path);
    if (!error && data) {
      return new Uint8Array(await data.arrayBuffer());
    }
    console.warn("Failed to download document attachment from storage", {
      fileId: file.id,
      error: error?.message,
    });
  }

  if (!file.file_url) return null;

  try {
    const response = await fetch(file.file_url);
    if (!response.ok) return null;
    return new Uint8Array(await response.arrayBuffer());
  } catch (error) {
    console.warn("Failed to download document attachment from URL", {
      fileId: file.id,
      error: error instanceof Error ? error.message : String(error),
    });
    return null;
  }
}

async function loadDocumentEmailAttachments(
  adminClient: ReturnType<typeof createClient>,
  documentRow: Record<string, unknown>,
): Promise<{
  files: FileAttachmentRow[];
  emailAttachments: ResendAttachment[];
  skippedFileNames: string[];
}> {
  const attachmentIds = normalizeAttachmentIds(documentRow["attached_photo_ids"]);
  if (attachmentIds.length === 0) {
    return { files: [], emailAttachments: [], skippedFileNames: [] };
  }

  const { data: rows, error } = await adminClient
    .from("file_attachments")
    .select("id, file_name, file_url, file_size, mime_type, bucket, storage_path")
    .eq("workspace_id", documentRow["workspace_id"])
    .in("id", attachmentIds);

  if (error) {
    throw new Error(`Failed to load document attachments: ${error.message}`);
  }

  const orderedRows = ((rows ?? []) as FileAttachmentRow[]).sort(
    (a, b) => attachmentIds.indexOf(a.id) - attachmentIds.indexOf(b.id),
  );
  const emailAttachments: ResendAttachment[] = [];
  const skippedFileNames: string[] = [];
  const maxAttachmentBytes = Number(
    Deno.env.get("DOCUMENT_EMAIL_ATTACHMENT_MAX_BYTES") ||
      defaultAttachmentMaxBytes,
  );
  let totalAttachmentBytes = 0;

  for (const file of orderedRows) {
    const fileSize = Number(file.file_size ?? 0);
    if (fileSize > 0 && totalAttachmentBytes + fileSize > maxAttachmentBytes) {
      skippedFileNames.push(file.file_name);
      continue;
    }

    const bytes = await downloadAttachmentBytes(adminClient, file);
    if (!bytes || bytes.length === 0) {
      skippedFileNames.push(file.file_name);
      continue;
    }

    if (totalAttachmentBytes + bytes.length > maxAttachmentBytes) {
      skippedFileNames.push(file.file_name);
      continue;
    }

    totalAttachmentBytes += bytes.length;
    emailAttachments.push({
      filename: sanitizeAttachmentFilename(file.file_name),
      content: bytesToBase64(bytes),
    });
  }

  return { files: orderedRows, emailAttachments, skippedFileNames };
}

function buildAttachmentBlock(
  files: FileAttachmentRow[],
  skippedFileNames: string[],
): string {
  if (files.length === 0) return "";

  const items = files.map((file) => {
    const safeName = escapeHtml(file.file_name);
    const safeUrl = file.file_url ? escapeHtml(file.file_url) : null;
    return safeUrl
      ? `<li><a href="${safeUrl}" style="color: #1f3a8a;">${safeName}</a></li>`
      : `<li>${safeName}</li>`;
  }).join("");
  const skipped = skippedFileNames.length === 0
    ? ""
    : `<p style="font-size: 12px; color: #92400e; margin: 8px 0 0 0;">${escapeHtml(skippedFileNames.join(", "))} could not be attached because of size or download limits. Use the links above to view them.</p>`;

  return `
            <div style="background: #f8fafc; border: 1px solid #e5e7eb; border-radius: 8px; padding: 14px 16px; margin: 18px 0;">
              <p style="margin: 0 0 8px 0;"><strong>Attached files</strong></p>
              <ul style="margin: 0; padding-left: 18px;">${items}</ul>
              ${skipped}
            </div>`;
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
    const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY");
    const supabaseServiceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const resendApiKey = Deno.env.get("RESEND_API_KEY");
    const fromEmail =
      Deno.env.get("FROM_EMAIL") || "FieldFleet <noreply@example.com>";
    const siteUrl = Deno.env.get("SITE_URL") || "https://app.example.com";

    if (!supabaseUrl || !supabaseAnonKey || !supabaseServiceRoleKey) {
      return new Response(
        JSON.stringify({ error: "Supabase configuration missing" }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    if (!resendApiKey) {
      return new Response(
        JSON.stringify({ error: "Email service not configured" }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const adminClient = createClient(supabaseUrl, supabaseServiceRoleKey);

    const supabase = createClient(supabaseUrl, supabaseAnonKey, {
      global: {
        headers: { Authorization: authHeader },
      },
    });

    const {
      data: { user },
      error: authError,
    } = await supabase.auth.getUser();

    if (authError || !user) {
      return new Response(
        JSON.stringify({ error: "Invalid or expired authentication token" }),
        {
          status: 401,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const {
      documentId,
      recipientEmail,
      subject,
      message,
      documentTitle,
      requireSignature = true,
    }: SendDocumentEmailRequest = await req.json();

    if (!documentId || !recipientEmail) {
      return new Response(
        JSON.stringify({
          error: "Missing required fields: documentId, recipientEmail",
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const { data: documentRow, error: documentError } = await supabase
      .from("generated_documents")
      .select("id, workspace_id, template_name, attached_photo_ids")
      .eq("id", documentId)
      .maybeSingle();

    if (documentError || !documentRow) {
      return new Response(
        JSON.stringify({ error: "Document not found or access denied" }),
        {
          status: 404,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const resolvedTitle = escapeHtml(
      documentTitle ||
        (documentRow["template_name"] as string | null) ||
        "Document",
    );
    const defaultSubject = requireSignature
      ? `Document for your signature: ${resolvedTitle}`
      : `Document: ${resolvedTitle}`;
    const defaultMessage = requireSignature
      ? "Please review and sign the attached document at your earliest convenience."
      : "Please find the attached document for your records.";
    const resolvedSubject = escapeHtml(subject?.trim() || defaultSubject);
    const resolvedMessage = escapeHtml(
      message?.trim() || defaultMessage,
    ).replaceAll("\n", "<br/>");

    const normalizedRecipient = normalizeEmail(recipientEmail);
    const { files, emailAttachments, skippedFileNames } =
      await loadDocumentEmailAttachments(
        adminClient,
        documentRow as Record<string, unknown>,
      );
    const attachmentBlock = buildAttachmentBlock(files, skippedFileNames);

    let signUrl: string | null = null;
    let signBlock = `
            <p style="font-size: 13px; color: #6b7280;">
              This document has been sent for your records. No signature is required.
            </p>`;

    if (requireSignature) {
      const expiresInDays = Number(Deno.env.get("SIGN_LINK_EXPIRY_DAYS") || "14");
      const expiresAt = new Date(
        Date.now() + Math.max(expiresInDays, 1) * 24 * 60 * 60 * 1000,
      ).toISOString();
      const revocationTimestamp = new Date().toISOString();

      const { data: existingLink } = await adminClient
        .from("document_sign_links")
        .select("token")
        .eq("document_id", documentId)
        .eq("recipient_email", normalizedRecipient)
        .is("revoked_at", null)
        .is("used_at", null)
        .gt("expires_at", new Date().toISOString())
        .order("created_at", { ascending: false })
        .limit(1)
        .maybeSingle();

      const signToken = existingLink?.token ?? generateToken();

      if (!existingLink) {
        const { error: linkError } = await adminClient.from("document_sign_links")
          .insert({
            workspace_id: documentRow["workspace_id"],
            document_id: documentId,
            token: signToken,
            recipient_email: normalizedRecipient,
            created_by: user.id,
            expires_at: expiresAt,
          });
        if (linkError) {
          return new Response(
            JSON.stringify({ error: "Failed to create signing link", details: linkError.message }),
            {
              status: 500,
              headers: { ...corsHeaders, "Content-Type": "application/json" },
            },
          );
        }
      }

      const { error: revokeOtherLinksError } = await adminClient
        .from("document_sign_links")
        .update({ revoked_at: revocationTimestamp })
        .eq("document_id", documentId)
        .is("revoked_at", null)
        .is("used_at", null)
        .neq("token", signToken);
      if (revokeOtherLinksError) {
        return new Response(
          JSON.stringify({
            error: "Failed to invalidate previous signing links",
            details: revokeOtherLinksError.message,
          }),
          {
            status: 500,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          },
        );
      }

      signUrl = `${siteUrl}/#/sign/${signToken}`;
      signBlock = `
            <div style="text-align: center; margin: 24px 0;">
              <a href="${signUrl}" style="display: inline-block; background: #1f3a8a; color: white; text-decoration: none; padding: 12px 24px; border-radius: 6px; font-weight: 600;">Review and Sign</a>
            </div>
            <p style="font-size: 13px; color: #6b7280;">
              If the button does not work, copy and paste this link into your browser:<br/>
              <a href="${signUrl}" style="word-break: break-all; color: #1f3a8a;">${signUrl}</a>
            </p>
            <p style="font-size: 12px; color: #6b7280;">
              This link expires on ${new Date(expiresAt).toLocaleDateString("en-US")}.
            </p>`;
    } else {
      await adminClient
        .from("document_sign_links")
        .update({ revoked_at: new Date().toISOString() })
        .eq("document_id", documentId)
        .is("revoked_at", null)
        .is("used_at", null);
    }

    const html = `
      <!DOCTYPE html>
      <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1.0">
          <title>${resolvedSubject}</title>
        </head>
        <body style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif; line-height: 1.6; color: #333; max-width: 620px; margin: 0 auto; padding: 20px;">
          <div style="background: #1f3a8a; color: white; padding: 24px; border-radius: 8px 8px 0 0;">
            <h1 style="margin: 0; font-size: 22px;">FieldFleet Document</h1>
          </div>
          <div style="background: #ffffff; border: 1px solid #e5e7eb; border-top: none; padding: 24px;">
            <p><strong>${resolvedTitle}</strong></p>
            <p>${resolvedMessage}</p>
            ${attachmentBlock}
            ${signBlock}
          </div>
        </body>
      </html>
    `;

    const resendPayload: Record<string, unknown> = {
      from: fromEmail,
      to: normalizedRecipient,
      subject: subject?.trim() || defaultSubject,
      html,
    };
    if (emailAttachments.length > 0) {
      resendPayload.attachments = emailAttachments;
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
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const resendResult = await resendResponse.json();

    return new Response(
      JSON.stringify({
        success: true,
        id: resendResult.id,
      }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    return new Response(
      JSON.stringify({ error: message }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});
