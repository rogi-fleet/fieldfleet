import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.43.4";

function getCorsHeaders(): Record<string, string> {
  const siteUrl = Deno.env.get("SITE_URL") || "*";
  return {
    "Access-Control-Allow-Origin": siteUrl,
    "Access-Control-Allow-Headers":
      "authorization, x-client-info, apikey, content-type",
  };
}

const MAX_SIGNATURE_BASE64_LENGTH = 5 * 1024 * 1024; // ~3.75 MB decoded
const MAX_NAME_LENGTH = 200;
const PRIVATE_STORAGE_SCHEME = "tfstorage://";
const SIGNATURE_BUCKET = "project-files";

function isValidEmail(email: string): boolean {
  return /^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$/.test(email);
}

function normalizeEmail(email: string): string {
  return email.trim().toLowerCase();
}

function buildPrivateStorageRef(bucket: string, path: string): string {
  return `${PRIVATE_STORAGE_SCHEME}${bucket}/${path}`;
}

function parsePrivateStorageRef(value: string | null | undefined): {
  bucket: string;
  path: string;
} | null {
  if (!value || !value.startsWith(PRIVATE_STORAGE_SCHEME)) {
    return null;
  }

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

type ChangeOrderLineItem = {
  id?: string;
  type?: string;
  isVisible?: boolean;
  name?: string;
  description?: string | null;
  quantity?: number;
  unit?: string | null;
  unitPrice?: number;
};

function getVisibleChangeOrderLeafItems(
  lineItems: unknown,
): ChangeOrderLineItem[] {
  if (!Array.isArray(lineItems)) return [];
  return lineItems.filter((item): item is ChangeOrderLineItem => {
    if (!item || typeof item !== "object") return false;
    const typedItem = item as ChangeOrderLineItem;
    return typedItem.type === "item" &&
      typedItem.isVisible !== false &&
      typeof typedItem.id === "string" &&
      typedItem.id.length > 0;
  });
}

async function recalculateParentTotals(
  admin: ReturnType<typeof createClient>,
  parentId: string,
  workspaceId: string,
): Promise<void> {
  const { data: parent } = await admin
    .from("budget_items")
    .select("id, parent_id")
    .eq("id", parentId)
    .maybeSingle();

  if (!parent) return;

  const { data: children } = await admin
    .from("budget_items")
    .select("approved_price, projected_cost, committed_cost")
    .eq("workspace_id", workspaceId)
    .eq("parent_id", parentId);

  let approvedPrice = 0;
  let projectedCost = 0;
  let committedCost = 0;
  for (const child of children ?? []) {
    approvedPrice += Number(child.approved_price ?? 0);
    projectedCost += Number(child.projected_cost ?? 0);
    committedCost += Number(child.committed_cost ?? 0);
  }

  await admin
    .from("budget_items")
    .update({
      approved_price: approvedPrice,
      projected_cost: projectedCost,
      committed_cost: committedCost,
      updated_at: new Date().toISOString(),
    })
    .eq("id", parentId);

  if (typeof parent.parent_id === "string" && parent.parent_id.length > 0) {
    await recalculateParentTotals(admin, parent.parent_id, workspaceId);
  }
}

async function syncChangeOrderBudgetItems(
  admin: ReturnType<typeof createClient>,
  document: {
    id: string;
    workspace_id: string;
    project_id: string | null;
    document_type: string | null;
    document_number: string | null;
    template_name: string | null;
    line_items: unknown;
  },
): Promise<void> {
  if (document.document_type !== "change_order" || !document.project_id) {
    return;
  }

  const leafItems = getVisibleChangeOrderLeafItems(document.line_items);
  const { data: existingRows } = await admin
    .from("budget_items")
    .select("id, parent_id, sort_order, source_line_item_id")
    .eq("change_order_id", document.id)
    .order("sort_order");

  if (leafItems.length === 0) {
    const staleIds = (existingRows ?? [])
      .map((row) => row.id as string | null)
      .filter((id): id is string => !!id);
    if (staleIds.length > 0) {
      await admin.from("budget_items").delete().in("id", staleIds);
    }
    return;
  }

  const nowIso = new Date().toISOString();
  const parentRow = (existingRows ?? []).find((row) => row.parent_id == null);
  const label = document.document_number
    ? `${document.document_number}: ${document.template_name ?? "Change Order"}`
    : (document.template_name ?? "Change Order");

  let parentId = parentRow?.id as string | undefined;
  if (parentId) {
    await admin
      .from("budget_items")
      .update({ name: label, updated_at: nowIso })
      .eq("id", parentId);
  } else {
    const { data: topLevelRows } = await admin
      .from("budget_items")
      .select("sort_order")
      .eq("project_id", document.project_id)
      .is("parent_id", null)
      .order("sort_order", { ascending: false })
      .limit(1);
    const parentSortOrder = topLevelRows && topLevelRows.length > 0
      ? Number(topLevelRows[0].sort_order ?? 0) + 1
      : 0;
    const { data: insertedParent, error: insertParentError } = await admin
      .from("budget_items")
      .insert({
        workspace_id: document.workspace_id,
        project_id: document.project_id,
        parent_id: null,
        hierarchy_level: 0,
        sort_order: parentSortOrder,
        name: label,
        item_type: "group",
        approved_price: 0,
        projected_cost: 0,
        committed_cost: 0,
        final_cost: 0,
        is_complete: false,
        source_type: "change_order",
        change_order_id: document.id,
        created_at: nowIso,
        updated_at: nowIso,
      })
      .select("id")
      .single();
    if (insertParentError || !insertedParent?.id) {
      throw new Error(insertParentError?.message ?? "Failed to create change order budget group");
    }
    parentId = insertedParent.id as string;
  }

  const existingChildren = (existingRows ?? []).filter((row) =>
    row.parent_id === parentId
  );
  const childrenBySourceLineItemId = new Map<string, Record<string, unknown>>();
  const unmatchedLegacyChildren: Record<string, unknown>[] = [];
  for (const row of existingChildren) {
    const sourceLineItemId = typeof row.source_line_item_id === "string"
      ? row.source_line_item_id
      : null;
    if (sourceLineItemId) {
      childrenBySourceLineItemId.set(sourceLineItemId, row);
    } else {
      unmatchedLegacyChildren.push(row);
    }
  }

  for (const [index, lineItem] of leafItems.entries()) {
    const approvedPrice = Number(lineItem.quantity ?? 1) *
      Number(lineItem.unitPrice ?? 0);
    const updatePayload = {
      workspace_id: document.workspace_id,
      project_id: document.project_id,
      parent_id: parentId,
      hierarchy_level: 1,
      sort_order: index,
      name: lineItem.name ?? "Change Order Item",
      description: lineItem.description ?? null,
      item_type: "item",
      quantity: Number(lineItem.quantity ?? 1),
      unit: lineItem.unit ?? null,
      unit_price: Number(lineItem.unitPrice ?? 0),
      approved_price: approvedPrice,
      projected_cost: approvedPrice,
      source_type: "change_order",
      change_order_id: document.id,
      source_line_item_id: lineItem.id,
      updated_at: nowIso,
    };

    const existingChild = childrenBySourceLineItemId.get(lineItem.id!) ??
      unmatchedLegacyChildren.shift();
    if (existingChild && typeof existingChild.id === "string") {
      childrenBySourceLineItemId.delete(lineItem.id!);
      await admin
        .from("budget_items")
        .update(updatePayload)
        .eq("id", existingChild.id);
    } else {
      await admin
        .from("budget_items")
        .insert({
          ...updatePayload,
          unit_cost: 0,
          committed_cost: 0,
          final_cost: 0,
          is_complete: false,
          created_at: nowIso,
        });
    }
  }

  const staleChildIds = [
    ...Array.from(childrenBySourceLineItemId.values()),
    ...unmatchedLegacyChildren,
  ]
    .map((row) => row.id as string | null)
    .filter((id): id is string => !!id);
  if (staleChildIds.length > 0) {
    await admin.from("budget_items").delete().in("id", staleChildIds);
  }

  await recalculateParentTotals(admin, parentId, document.workspace_id);
}

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: getCorsHeaders() });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!supabaseUrl || !serviceRoleKey) {
      return new Response(
        JSON.stringify({ error: "Server configuration missing" }),
        {
          status: 500,
          headers: { ...getCorsHeaders(), "Content-Type": "application/json" },
        },
      );
    }

    const admin = createClient(supabaseUrl, serviceRoleKey);
    const body = await req.json() as ResolveRequest | SignRequest;
    const token = body.token?.trim();
    if (!token) {
      return new Response(
        JSON.stringify({ error: "Missing token" }),
        {
          status: 400,
          headers: { ...getCorsHeaders(), "Content-Type": "application/json" },
        },
      );
    }

    const { data: link, error: linkError } = await admin
      .from("document_sign_links")
      .select("id, workspace_id, document_id, recipient_email, expires_at, revoked_at, used_at")
      .eq("token", token)
      .maybeSingle();

    if (linkError || !link) {
      return new Response(
        JSON.stringify({ error: "Signing link not found" }),
        {
          status: 404,
          headers: { ...getCorsHeaders(), "Content-Type": "application/json" },
        },
      );
    }

    if (link.revoked_at) {
      return new Response(
        JSON.stringify({ error: "Signing link has been revoked" }),
        {
          status: 410,
          headers: { ...getCorsHeaders(), "Content-Type": "application/json" },
        },
      );
    }

    if (new Date(link.expires_at).getTime() < Date.now()) {
      return new Response(
        JSON.stringify({ error: "Signing link has expired" }),
        {
          status: 410,
          headers: { ...getCorsHeaders(), "Content-Type": "application/json" },
        },
      );
    }

    const { data: document, error: docError } = await admin
      .from("generated_documents")
      .select(
        "id, workspace_id, project_id, document_type, document_number, template_name, rendered_content, status, signed_by_name, signed_by_email, signed_at, signature_url, line_items, line_item_visibility, collect_tax, tax_rate, tax_name, total_amount, prepared_by, prepared_for, footer_content, sent_to",
      )
      .eq("id", link.document_id)
      .maybeSingle();

    if (docError || !document) {
      return new Response(
        JSON.stringify({ error: "Document not found" }),
        {
          status: 404,
          headers: { ...getCorsHeaders(), "Content-Type": "application/json" },
        },
      );
    }

    const currentRecipientEmail = typeof document.sent_to === "string"
      ? normalizeEmail(document.sent_to)
      : "";
    const linkedRecipientEmail = typeof link.recipient_email === "string"
      ? normalizeEmail(link.recipient_email)
      : "";
    if (
      currentRecipientEmail &&
      linkedRecipientEmail &&
      currentRecipientEmail !== linkedRecipientEmail
    ) {
      return new Response(
        JSON.stringify({
          error: "This signing link has been replaced by a newer recipient",
        }),
        {
          status: 410,
          headers: { ...getCorsHeaders(), "Content-Type": "application/json" },
        },
      );
    }

    await admin
      .from("document_sign_links")
      .update({ last_accessed_at: new Date().toISOString() })
      .eq("id", link.id);

    let resolvedStatus = document.status;
    if (body.action === "resolve") {
      if (document.status === "sent") {
        const { data: viewedDoc, error: viewedError } = await admin
          .from("generated_documents")
          .update({ status: "viewed" })
          .eq("id", document.id)
          .eq("status", "sent")
          .select("status")
          .maybeSingle();

        if (viewedError) {
          console.error("Failed to mark document as viewed", {
            documentId: document.id,
            error: viewedError.message,
          });
        } else if (viewedDoc) {
          resolvedStatus = viewedDoc.status;

          const { error: activityLogError } = await admin
            .from("document_activity_log")
            .insert({
              workspace_id: document.workspace_id,
              document_id: document.id,
              action: "viewed",
              actor_email: link.recipient_email,
              actor_type: "portal_user",
              ip_address: getClientIp(req),
            });
          if (activityLogError) {
            console.error("Failed to log document view activity", {
              documentId: document.id,
              error: activityLogError.message,
            });
          }
        }
      }

      const resolvedSignatureUrl = await resolveStorageUrl(
        admin,
        document.signature_url,
      );

      return new Response(
        JSON.stringify({
          success: true,
          document: {
            id: document.id,
            templateName: document.template_name,
            renderedContent: document.rendered_content,
            status: resolvedStatus,
            signedByName: document.signed_by_name,
            signedByEmail: document.signed_by_email,
            signedAt: document.signed_at,
            signatureUrl: resolvedSignatureUrl,
            lineItems: document.line_items,
            lineItemVisibility: document.line_item_visibility,
            collectTax: document.collect_tax,
            taxRate: document.tax_rate,
            taxName: document.tax_name,
            totalAmount: document.total_amount,
            preparedBy: document.prepared_by,
            preparedFor: document.prepared_for,
            footerContent: document.footer_content,
          },
          link: {
            expiresAt: link.expires_at,
            recipientEmail: link.recipient_email,
          },
        }),
        {
          headers: { ...getCorsHeaders(), "Content-Type": "application/json" },
        },
      );
    }

    if (body.action !== "sign") {
      return new Response(
        JSON.stringify({ error: "Unsupported action" }),
        {
          status: 400,
          headers: { ...getCorsHeaders(), "Content-Type": "application/json" },
        },
      );
    }

    if (document.status === "signed") {
      return new Response(
        JSON.stringify({
          error: "Document has already been signed",
          signedAt: document.signed_at,
        }),
        {
          status: 409,
          headers: { ...getCorsHeaders(), "Content-Type": "application/json" },
        },
      );
    }

    if (link.used_at) {
      return new Response(
        JSON.stringify({ error: "Signing link has already been used" }),
        {
          status: 410,
          headers: { ...getCorsHeaders(), "Content-Type": "application/json" },
        },
      );
    }

    const signedByName = body.signedByName?.trim();
    const signedByEmail = body.signedByEmail?.trim();
    const signaturePngBase64 = body.signaturePngBase64?.trim();
    if (!signedByName || !signedByEmail || !signaturePngBase64) {
      return new Response(
        JSON.stringify({
          error: "Missing required fields: signedByName, signedByEmail, signaturePngBase64",
        }),
        {
          status: 400,
          headers: { ...getCorsHeaders(), "Content-Type": "application/json" },
        },
      );
    }

    // Input size/format validation
    if (signedByName.length > MAX_NAME_LENGTH) {
      return new Response(
        JSON.stringify({ error: "Name is too long" }),
        { status: 400, headers: { ...getCorsHeaders(), "Content-Type": "application/json" } },
      );
    }
    if (!isValidEmail(signedByEmail)) {
      return new Response(
        JSON.stringify({ error: "Invalid email address" }),
        { status: 400, headers: { ...getCorsHeaders(), "Content-Type": "application/json" } },
      );
    }
    const normalizedSignedByEmail = normalizeEmail(signedByEmail);
    if (linkedRecipientEmail && normalizedSignedByEmail !== linkedRecipientEmail) {
      return new Response(
        JSON.stringify({ error: "Use the email address this signing link was sent to" }),
        { status: 403, headers: { ...getCorsHeaders(), "Content-Type": "application/json" } },
      );
    }
    if (signaturePngBase64.length > MAX_SIGNATURE_BASE64_LENGTH) {
      return new Response(
        JSON.stringify({ error: "Signature image is too large" }),
        { status: 400, headers: { ...getCorsHeaders(), "Content-Type": "application/json" } },
      );
    }

    const signatureBytes = decodeBase64(signaturePngBase64);
    const signaturePath =
      `${document.workspace_id}/signatures/${document.id}_${Date.now()}.png`;

    const { error: uploadError } = await admin.storage.from(SIGNATURE_BUCKET)
      .upload(signaturePath, signatureBytes, {
        contentType: "image/png",
        upsert: false,
      });

    if (uploadError) {
      return new Response(
        JSON.stringify({ error: "Failed to upload signature", details: uploadError.message }),
        {
          status: 500,
          headers: { ...getCorsHeaders(), "Content-Type": "application/json" },
        },
      );
    }

    const signatureStorageRef = buildPrivateStorageRef(
      SIGNATURE_BUCKET,
      signaturePath,
    );
    const nowIso = new Date().toISOString();

    // Atomic update — only sign if document is in a signable state
    // Rejects if already signed, denied, or changes_requested
    const { data: updateResult, error: updateDocError } = await admin
      .from("generated_documents")
      .update({
        status: "signed",
        signature_url: signatureStorageRef,
        signed_by_name: signedByName,
        signed_by_email: normalizedSignedByEmail,
        signed_at: nowIso,
        signature_ip: getClientIp(req),
      })
      .eq("id", document.id)
      .in("status", ["sent", "viewed"])
      .select("id");

    if (updateDocError) {
      return new Response(
        JSON.stringify({ error: "Failed to sign document", details: updateDocError.message }),
        {
          status: 500,
          headers: { ...getCorsHeaders(), "Content-Type": "application/json" },
        },
      );
    }

    if (!updateResult || updateResult.length === 0) {
      return new Response(
        JSON.stringify({ error: "Document can no longer be signed — it may have been signed, denied, or had changes requested" }),
        {
          status: 409,
          headers: { ...getCorsHeaders(), "Content-Type": "application/json" },
        },
      );
    }

    try {
      await syncChangeOrderBudgetItems(admin, {
        id: document.id as string,
        workspace_id: document.workspace_id as string,
        project_id: (document.project_id as string | null) ?? null,
        document_type: (document.document_type as string | null) ?? null,
        document_number: (document.document_number as string | null) ?? null,
        template_name: (document.template_name as string | null) ?? null,
        line_items: document.line_items,
      });
    } catch (syncError) {
      console.error("Signed change order but failed to sync budget", {
        documentId: document.id,
        error: syncError instanceof Error ? syncError.message : String(syncError),
      });
    }

    const { error: notifyError } = await admin.rpc("create_document_signed_notifications", {
      p_document_id: document.id,
      p_signed_by_name: signedByName,
      p_signed_by_email: normalizedSignedByEmail,
    });

    if (notifyError) {
      console.error("Failed to create document signed notifications", {
        documentId: document.id,
        error: notifyError.message,
      });
    }

    // Log signing activity
    const { error: activityLogError } = await admin.from("document_activity_log").insert({
      workspace_id: document.workspace_id,
      document_id: document.id,
      action: "signed",
      actor_email: normalizedSignedByEmail,
      actor_name: signedByName,
      actor_type: "portal_user",
      ip_address: getClientIp(req),
    });
    if (activityLogError) {
      console.error("Failed to log signing activity:", activityLogError);
    }

    await admin
      .from("document_sign_links")
      .update({ used_at: nowIso })
      .eq("id", link.id);

    return new Response(
      JSON.stringify({
        success: true,
        signedAt: nowIso,
        signatureUrl: await resolveStorageUrl(admin, signatureStorageRef),
      }),
      { headers: { ...getCorsHeaders(), "Content-Type": "application/json" } },
    );
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    return new Response(
      JSON.stringify({ error: message }),
      {
        status: 500,
        headers: { ...getCorsHeaders(), "Content-Type": "application/json" },
      },
    );
  }
});
