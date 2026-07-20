import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.43.4";
import Stripe from "https://esm.sh/stripe@14.21.0?target=deno";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};
const payableGeneratedDocumentTypes = new Set(["invoice", "progress_invoice"]);
const payableGeneratedDocumentStatuses = new Set([
  "sent",
  "viewed",
  "approved",
  "signed",
]);

type GeneratedDocumentLineItem = {
  type?: string;
  isVisible?: boolean;
  quantity?: number;
  unitPrice?: number;
};

function calculateGeneratedDocumentTotal(
  lineItems: GeneratedDocumentLineItem[] | null | undefined,
  collectTax: unknown,
  taxRate: unknown,
  storedTotalAmount: unknown,
): number {
  if (!Array.isArray(lineItems) || lineItems.length === 0) {
    return typeof storedTotalAmount === "number" ? storedTotalAmount : 0;
  }

  const subtotal = lineItems.reduce((sum, item) => {
    if (item?.type !== "item") return sum;
    if (item?.isVisible === false) return sum;

    const quantity = typeof item?.quantity === "number" ? item.quantity : 1;
    const unitPrice =
      typeof item?.unitPrice === "number" ? item.unitPrice : 0;
    return sum + (quantity * unitPrice);
  }, 0);

  if (collectTax !== true) {
    return subtotal;
  }

  const numericTaxRate = typeof taxRate === "number" ? taxRate : 0;
  if (numericTaxRate <= 0) {
    return subtotal;
  }

  return subtotal + (subtotal * (numericTaxRate / 100));
}

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const stripeSecretKey = Deno.env.get("STRIPE_SECRET_KEY");

    if (!supabaseUrl || !anonKey || !serviceRoleKey || !stripeSecretKey) {
      return new Response(
        JSON.stringify({ error: "Server configuration missing" }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Verify caller JWT
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(
        JSON.stringify({ error: "Missing authorization header" }),
        {
          status: 401,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const anonClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    });

    const { data: { user }, error: authError } = await anonClient.auth.getUser();
    if (authError || !user) {
      return new Response(
        JSON.stringify({ error: "Unauthorized" }),
        {
          status: 401,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const body = await req.json() as { invoiceId?: string };
    const invoiceId = body.invoiceId?.trim();
    if (!invoiceId) {
      return new Response(
        JSON.stringify({ error: "Missing invoiceId" }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Use service role client for DB writes
    const admin = createClient(supabaseUrl, serviceRoleKey);

    // Fetch from generated_documents (primary) with fallback to legacy invoices
    let invoice: Record<string, unknown> | null = null;
    let isGeneratedDocument = false;

    const { data: genDoc, error: genDocError } = await admin
      .from("generated_documents")
      .select(
        "id, document_number, document_type, status, paid_date, total_amount, amount_paid, line_items, collect_tax, tax_rate, metadata, workspace_id, project_id",
      )
      .eq("id", invoiceId)
      .maybeSingle();

    if (genDocError) {
      console.error("Error querying generated_documents:", genDocError);
    }

    if (genDoc) {
      if (!payableGeneratedDocumentTypes.has(genDoc.document_type as string)) {
        return new Response(
          JSON.stringify({ error: "Payment links are only available for invoices" }),
          {
            status: 400,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          },
        );
      }

      if (!payableGeneratedDocumentStatuses.has(genDoc.status as string)) {
        return new Response(
          JSON.stringify({ error: "Invoice is not in a payable status" }),
          {
            status: 400,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          },
        );
      }

      if (genDoc.paid_date) {
        return new Response(
          JSON.stringify({ error: "Invoice is already marked as paid" }),
          {
            status: 400,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          },
        );
      }

      const meta = (genDoc.metadata ?? {}) as Record<string, unknown>;
      invoice = {
        id: genDoc.id,
        invoice_number: genDoc.document_number,
        total: calculateGeneratedDocumentTotal(
          genDoc.line_items as GeneratedDocumentLineItem[] | null | undefined,
          genDoc.collect_tax,
          genDoc.tax_rate,
          genDoc.total_amount,
        ),
        retainage_amount: 0, // retainage handled in line items total
        // Partial payments [F011]: the link must charge the outstanding
        // balance, not the full total.
        amount_paid: (genDoc.amount_paid as number) ?? 0,
        workspace_id: genDoc.workspace_id,
        project_id: genDoc.project_id,
        stripe_payment_link_url: meta.stripePaymentLinkUrl ?? null,
        stripe_payment_link_amount_cents:
          (meta.stripePaymentLinkAmountCents as number) ?? null,
      };
      isGeneratedDocument = true;
    } else if (!genDocError) {
      // Only fall back to legacy if generated_documents returned no result (not an error)
      const { data: legacyInvoice, error: invoiceError } = await admin
        .from("invoices")
        .select("id, invoice_number, total, retainage_amount, workspace_id, project_id, stripe_payment_link_url")
        .eq("id", invoiceId)
        .maybeSingle();
      if (!invoiceError && legacyInvoice) {
        invoice = legacyInvoice as Record<string, unknown>;
      }
    }

    if (!invoice) {
      return new Response(
        JSON.stringify({ error: "Invoice not found" }),
        {
          status: 404,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Authorization:
    // 1) Workspace members can always access.
    // 2) Portal users can access only if their email is an active contact for
    //    the invoice's project customer.
    let isAuthorized = false;

    const { data: membership } = await anonClient
      .from("workspace_members")
      .select("workspace_id")
      .eq("workspace_id", invoice.workspace_id)
      .maybeSingle();

    if (membership) {
      isAuthorized = true;
    } else {
      const userEmail = user.email?.toLowerCase().trim();
      if (!userEmail) {
        return new Response(
          JSON.stringify({ error: "Forbidden" }),
          {
            status: 403,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          },
        );
      }

      const { data: project, error: projectError } = await admin
        .from("projects")
        .select("client_id")
        .eq("id", invoice.project_id)
        .maybeSingle();

      if (!projectError && project?.client_id) {
        const { data: customer } = await admin
          .from("customers")
          .select("id, is_active")
          .eq("id", project.client_id)
          .maybeSingle();

        if (customer?.is_active !== true) {
          isAuthorized = false;
        } else {
          const { data: contact } = await admin
            .from("customer_contacts")
            .select("id")
            .eq("customer_id", project.client_id)
            .eq("is_active", true)
            .ilike("email", userEmail)
            .limit(1)
            .maybeSingle();

          isAuthorized = !!contact;
        }
      }
    }

    if (!isAuthorized) {
      return new Response(
        JSON.stringify({ error: "Forbidden" }),
        {
          status: 403,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Charge amountDue = total - retainage - amount already paid [F011]
    const amountDue = ((invoice.total as number) ?? 0) -
      ((invoice.retainage_amount as number) ?? 0) -
      ((invoice.amount_paid as number) ?? 0);
    const amountCents = Math.round(amountDue * 100);

    if (amountCents <= 0) {
      return new Response(
        JSON.stringify({ error: "Invoice amount due must be greater than zero" }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Idempotent: reuse the existing link only while it still charges the
    // current balance. After a partial payment the cached link is stale
    // (wrong amount) — fall through and create a fresh one. Legacy invoices
    // have no stored amount; keep their original reuse behaviour.
    const cachedAmountCents = invoice.stripe_payment_link_amount_cents as
      | number
      | null
      | undefined;
    if (
      invoice.stripe_payment_link_url &&
      (!isGeneratedDocument || cachedAmountCents === amountCents)
    ) {
      return new Response(
        JSON.stringify({ success: true, url: invoice.stripe_payment_link_url as string }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const stripe = new Stripe(stripeSecretKey, {
      apiVersion: "2024-06-20",
      httpClient: Stripe.createFetchHttpClient(),
    });

    // Create a one-time Stripe price
    const price = await stripe.prices.create({
      currency: "usd",
      unit_amount: amountCents,
      product_data: {
        name: `Invoice ${invoice.invoice_number}`,
      },
    });

    // Create a Stripe Payment Link
    const paymentLink = await stripe.paymentLinks.create({
      line_items: [{ price: price.id, quantity: 1 }],
      metadata: {
        invoiceId: invoice.id as string,
        workspaceId: (invoice.workspace_id as string) ?? "",
      },
    });

    // Persist the URL back to the appropriate table
    if (isGeneratedDocument) {
      // Merge stripePaymentLinkUrl into metadata JSONB
      const { data: freshDoc } = await admin
        .from("generated_documents")
        .select("metadata")
        .eq("id", invoiceId)
        .maybeSingle();
      const meta = (freshDoc?.metadata ?? {}) as Record<string, unknown>;
      meta.stripePaymentLinkUrl = paymentLink.url;
      // Remembered so a later call can detect the link is stale once the
      // outstanding balance changes (partial payments).
      meta.stripePaymentLinkAmountCents = amountCents;
      const { error: updateError } = await admin
        .from("generated_documents")
        .update({ metadata: meta })
        .eq("id", invoiceId);
      if (updateError) {
        console.error("Failed to persist payment link URL:", updateError);
      }

      // Log activity
      const { error: activityErr } = await admin.from("document_activity_log").insert({
        workspace_id: invoice.workspace_id,
        document_id: invoiceId,
        action: "payment_initiated",
        actor_type: "system",
        details: { amount_cents: amountCents },
      });
      if (activityErr) {
        console.error("Failed to log payment_initiated activity:", activityErr);
      }
    } else {
      const { error: updateError } = await admin
        .from("invoices")
        .update({ stripe_payment_link_url: paymentLink.url })
        .eq("id", invoiceId);
      if (updateError) {
        console.error("Failed to persist payment link URL:", updateError);
      }
    }

    return new Response(
      JSON.stringify({ success: true, url: paymentLink.url }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error("generate-invoice-payment-link error:", message);
    return new Response(
      JSON.stringify({ error: message }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});
