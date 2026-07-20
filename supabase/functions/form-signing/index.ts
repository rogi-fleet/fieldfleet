import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.43.4";

// ─────────────────────────────────────────────────────────
// CORS
// ─────────────────────────────────────────────────────────

function getCorsHeaders(): Record<string, string> {
  const siteUrl = Deno.env.get("SITE_URL") || "*";
  return {
    "Access-Control-Allow-Origin": siteUrl,
    "Access-Control-Allow-Headers":
      "authorization, x-client-info, apikey, content-type",
  };
}

// ─────────────────────────────────────────────────────────
// Constants
// ─────────────────────────────────────────────────────────

const MAX_SIGNATURE_BASE64_LENGTH = 5 * 1024 * 1024; // ~3.75 MB decoded
const MAX_NAME_LENGTH = 200;
const PRIVATE_STORAGE_SCHEME = "tfstorage://";
const SIGNATURE_BUCKET = "project-files";

// ─────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────

function isValidEmail(email: string): boolean {
  return /^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$/.test(email);
}

function normalizeEmail(email: string): string {
  return email.trim().toLowerCase();
}

function buildPrivateStorageRef(bucket: string, path: string): string {
  return `${PRIVATE_STORAGE_SCHEME}${bucket}/${path}`;
}

function parsePrivateStorageRef(
  value: string | null | undefined,
): { bucket: string; path: string } | null {
  if (!value || !value.startsWith(PRIVATE_STORAGE_SCHEME)) return null;
  const withoutScheme = value.slice(PRIVATE_STORAGE_SCHEME.length);
  const separatorIndex = withoutScheme.indexOf("/");
  if (separatorIndex <= 0 || separatorIndex === withoutScheme.length - 1) {
    return null;
  }
  return {
    bucket: withoutScheme.slice(0, separatorIndex),
    path: withoutScheme.slice(separatorIndex + 1),
  };
}

async function resolveStorageUrl(
  admin: ReturnType<typeof createClient>,
  value: string | null | undefined,
): Promise<string | null> {
  if (!value) return null;
  const parsedRef = parsePrivateStorageRef(value);
  if (!parsedRef) return value;
  const { data, error } = await admin.storage
    .from(parsedRef.bucket)
    .createSignedUrl(parsedRef.path, 60 * 60);
  if (error) {
    console.error("Failed to generate signed URL", {
      bucket: parsedRef.bucket,
      path: parsedRef.path,
      error: error.message,
    });
    return null;
  }
  return data.signedUrl;
}

function decodeBase64(base64Data: string): Uint8Array {
  const cleaned = base64Data.replace(/^data:image\/png;base64,/, "");
  const binary = atob(cleaned);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes;
}

function getClientIp(req: Request): string | null {
  const forwarded = req.headers.get("x-forwarded-for");
  if (!forwarded || forwarded.length === 0) return null;
  return forwarded.split(",")[0].trim();
}

function jsonResponse(
  body: unknown,
  status = 200,
  extraHeaders: Record<string, string> = {},
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...getCorsHeaders(),
      "Content-Type": "application/json",
      ...extraHeaders,
    },
  });
}

// ─────────────────────────────────────────────────────────
// Request types
// ─────────────────────────────────────────────────────────

type ResolveRequest = {
  action: "resolve";
  token: string;
};

type SignRequest = {
  action: "sign";
  token: string;
  signedByName: string;
  signedByEmail: string;
  signaturePngBase64: string;
};

// ─────────────────────────────────────────────────────────
// Main handler
// ─────────────────────────────────────────────────────────

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: getCorsHeaders() });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!supabaseUrl || !serviceRoleKey) {
      return jsonResponse({ error: "Server configuration missing" }, 500);
    }

    const admin = createClient(supabaseUrl, serviceRoleKey);
    const body = await req.json() as ResolveRequest | SignRequest;
    const token = body.token?.trim();
    if (!token) {
      return jsonResponse({ error: "Missing token" }, 400);
    }

    // ── Resolve sign link ──────────────────────────────────
    const { data: link, error: linkError } = await admin
      .from("field_form_sign_links")
      .select(
        "id, workspace_id, submission_id, recipient_email, expires_at, revoked_at, used_at",
      )
      .eq("token", token)
      .maybeSingle();

    if (linkError || !link) {
      return jsonResponse({ error: "Signing link not found" }, 404);
    }
    if (link.revoked_at) {
      return jsonResponse({ error: "Signing link has been revoked" }, 410);
    }
    if (new Date(link.expires_at).getTime() < Date.now()) {
      return jsonResponse({ error: "Signing link has expired" }, 410);
    }

    // ── Fetch submission ───────────────────────────────────
    const { data: submission, error: subError } = await admin
      .from("field_form_submissions")
      .select(
        "id, workspace_id, template_id, template_name, project_id, task_id, title, status, data, filled_by_name, submitted_at, customer_signature_url, customer_signed_by_name, customer_signed_by_email, customer_signed_at",
      )
      .eq("id", link.submission_id)
      .maybeSingle();

    if (subError || !submission) {
      return jsonResponse({ error: "Form submission not found" }, 404);
    }

    // ── Fetch template fields (for display) ────────────────
    const { data: template } = await admin
      .from("field_form_templates")
      .select("id, name, category, fields, description")
      .eq("id", submission.template_id)
      .maybeSingle();

    // ── Touch last_accessed_at ─────────────────────────────
    await admin
      .from("field_form_sign_links")
      .update({ last_accessed_at: new Date().toISOString() })
      .eq("id", link.id);

    // ── RESOLVE ────────────────────────────────────────────
    if (body.action === "resolve") {
      const resolvedSignatureUrl = await resolveStorageUrl(
        admin,
        submission.customer_signature_url,
      );

      return jsonResponse({
        success: true,
        submission: {
          id: submission.id,
          templateName: submission.template_name,
          status: submission.status,
          data: submission.data,
          filledByName: submission.filled_by_name,
          submittedAt: submission.submitted_at,
          customerSignatureUrl: resolvedSignatureUrl,
          customerSignedByName: submission.customer_signed_by_name,
          customerSignedAt: submission.customer_signed_at,
        },
        template: template
          ? {
              name: template.name,
              category: template.category,
              description: template.description,
              fields: template.fields,
            }
          : null,
        link: {
          expiresAt: link.expires_at,
          recipientEmail: link.recipient_email,
        },
      });
    }

    // ── SIGN ───────────────────────────────────────────────
    if (body.action !== "sign") {
      return jsonResponse({ error: "Unsupported action" }, 400);
    }

    // Guard: already signed
    if (submission.customer_signed_at) {
      return jsonResponse(
        {
          error: "This form has already been signed",
          signedAt: submission.customer_signed_at,
        },
        409,
      );
    }
    if (link.used_at) {
      return jsonResponse(
        { error: "Signing link has already been used" },
        410,
      );
    }

    // Validate inputs
    const signedByName = (body as SignRequest).signedByName?.trim();
    const signedByEmail = (body as SignRequest).signedByEmail?.trim();
    const signaturePngBase64 = (body as SignRequest).signaturePngBase64?.trim();

    if (!signedByName || !signedByEmail || !signaturePngBase64) {
      return jsonResponse(
        {
          error:
            "Missing required fields: signedByName, signedByEmail, signaturePngBase64",
        },
        400,
      );
    }
    if (signedByName.length > MAX_NAME_LENGTH) {
      return jsonResponse({ error: "Name is too long" }, 400);
    }
    if (!isValidEmail(signedByEmail)) {
      return jsonResponse({ error: "Invalid email address" }, 400);
    }
    const normalizedEmail = normalizeEmail(signedByEmail);
    const linkedRecipientEmail = typeof link.recipient_email === "string"
      ? normalizeEmail(link.recipient_email)
      : "";
    if (linkedRecipientEmail && normalizedEmail !== linkedRecipientEmail) {
      return jsonResponse(
        {
          error:
            "Use the email address this signing link was sent to",
        },
        403,
      );
    }
    if (signaturePngBase64.length > MAX_SIGNATURE_BASE64_LENGTH) {
      return jsonResponse({ error: "Signature image is too large" }, 400);
    }

    // Upload signature
    const signatureBytes = decodeBase64(signaturePngBase64);
    const signaturePath =
      `${submission.workspace_id}/signatures/${submission.id}_customer_${Date.now()}.png`;

    const { error: uploadError } = await admin.storage
      .from(SIGNATURE_BUCKET)
      .upload(signaturePath, signatureBytes, {
        contentType: "image/png",
        upsert: false,
      });

    if (uploadError) {
      return jsonResponse(
        {
          error: "Failed to upload signature",
          details: uploadError.message,
        },
        500,
      );
    }

    const signatureStorageRef = buildPrivateStorageRef(
      SIGNATURE_BUCKET,
      signaturePath,
    );
    const nowIso = new Date().toISOString();

    // Update submission with customer signature
    const { error: updateError } = await admin
      .from("field_form_submissions")
      .update({
        customer_signature_url: signatureStorageRef,
        customer_signed_by_name: signedByName,
        customer_signed_by_email: normalizedEmail,
        customer_signed_at: nowIso,
        customer_signature_ip: getClientIp(req),
      })
      .eq("id", submission.id);

    if (updateError) {
      return jsonResponse(
        {
          error: "Failed to record signature",
          details: updateError.message,
        },
        500,
      );
    }

    // Mark link as used
    await admin
      .from("field_form_sign_links")
      .update({ used_at: nowIso })
      .eq("id", link.id);

    return jsonResponse({
      success: true,
      signedAt: nowIso,
      signatureUrl: await resolveStorageUrl(admin, signatureStorageRef),
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    return jsonResponse({ error: message }, 500);
  }
});
