import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.43.4";
import Stripe from "https://esm.sh/stripe@14.21.0?target=deno";

// This endpoint is unauthenticated — Stripe calls it directly.
// Security is provided by the Stripe signature verification.

serve(async (req: Request) => {
  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const stripeSecretKey = Deno.env.get("STRIPE_SECRET_KEY");
    const webhookSecret = Deno.env.get("STRIPE_INVOICE_WEBHOOK_SECRET");

    if (!supabaseUrl || !serviceRoleKey || !stripeSecretKey || !webhookSecret) {
      return new Response(
        JSON.stringify({ error: "Server configuration missing" }),
        { status: 500, headers: { "Content-Type": "application/json" } },
      );
    }

    const stripe = new Stripe(stripeSecretKey, {
      apiVersion: "2024-06-20",
      httpClient: Stripe.createFetchHttpClient(),
    });

    const sig = req.headers.get("stripe-signature");
    if (!sig) {
      return new Response(
        JSON.stringify({ error: "Missing Stripe signature" }),
        { status: 400, headers: { "Content-Type": "application/json" } },
      );
    }

    const body = await req.text();

    let event: Stripe.Event;
    try {
      event = await stripe.webhooks.constructEventAsync(body, sig, webhookSecret);
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      console.error("Stripe signature verification failed:", message);
      return new Response(
        JSON.stringify({ error: `Webhook signature invalid: ${message}` }),
        { status: 400, headers: { "Content-Type": "application/json" } },
      );
    }

    // Handle relevant payment events
    if (
      event.type === "checkout.session.completed" ||
      event.type === "payment_link.completed"
    ) {
      const session = event.data.object as Stripe.Checkout.Session;
      const invoiceId = session.metadata?.invoiceId;

      if (!invoiceId) {
        console.warn("No invoiceId in session metadata, skipping");
        return new Response(
          JSON.stringify({ received: true }),
          { headers: { "Content-Type": "application/json" } },
        );
      }

      const admin = createClient(supabaseUrl, serviceRoleKey);

      // Fetch current status (safety guard — only update if sent or overdue)
      const { data: invoice, error: fetchError } = await admin
        .from("invoices")
        .select("id, status")
        .eq("id", invoiceId)
        .maybeSingle();

      if (fetchError || !invoice) {
        console.error("Invoice not found for id:", invoiceId, fetchError);
        return new Response(
          JSON.stringify({ received: true }),
          { headers: { "Content-Type": "application/json" } },
        );
      }

      if (invoice.status === "sent" || invoice.status === "overdue") {
        const now = new Date().toISOString();
        const { error: updateError } = await admin
          .from("invoices")
          .update({
            status: "paid",
            paid_date: now,
            updated_at: now,
          })
          .eq("id", invoiceId);

        if (updateError) {
          console.error("Failed to mark legacy invoice as paid:", updateError);
        } else {
          console.log(`Legacy invoice ${invoiceId} marked as paid via Stripe webhook`);
        }
      } else {
        console.log(
          `Legacy invoice ${invoiceId} already in status '${invoice.status}', skipping update`,
        );
      }

      // Also try to update generated_documents (new system).
      //
      // record_document_payment posts the payment journal entry (DR Bank /
      // CR A/R), advances amount_paid, and stamps paid_date only when the
      // balance hits zero — so partial payments stay correct [F012]. It is
      // idempotent per Stripe session id (webhook retries are no-ops).
      const { data: genDoc, error: genDocFetchError } = await admin
        .from("generated_documents")
        .select("id, workspace_id, status, paid_date")
        .eq("id", invoiceId)
        .maybeSingle();

      if (!genDocFetchError && genDoc && !genDoc.paid_date) {
        // Stripe reports the charged amount in cents; null for some legacy
        // payment_link events — the RPC then records the outstanding balance.
        const amountPaid = typeof session.amount_total === "number"
          ? session.amount_total / 100
          : null;
        const paymentIntent = typeof session.payment_intent === "string"
          ? session.payment_intent
          : null;

        const { data: rpcResult, error: rpcError } = await admin.rpc(
          "record_document_payment",
          {
            p_document_id: invoiceId,
            p_amount: amountPaid,
            p_method: "stripe",
            p_reference: paymentIntent,
            p_external_ref: session.id ?? null,
          },
        );

        let recorded = false;
        if (rpcError) {
          // Most likely missing system GL accounts in this workspace. Fall
          // back to the legacy paid-date stamp so the customer-facing state
          // is still correct; the GL entry must then be added by staff.
          console.error(
            "record_document_payment failed, falling back to paid_date stamp:",
            rpcError,
          );
          const now = new Date().toISOString();
          const { error: genUpdateError } = await admin
            .from("generated_documents")
            .update({
              paid_date: now,
              payment_method: "stripe",
              updated_at: now,
            })
            .eq("id", invoiceId);
          if (genUpdateError) {
            console.error("Fallback paid_date update also failed:", genUpdateError);
          } else {
            recorded = true;
          }
        } else {
          recorded = !(rpcResult as Record<string, unknown> | null)?.skipped;
          console.log(
            `Stripe payment recorded for document ${invoiceId}:`,
            JSON.stringify(rpcResult),
          );
        }

        if (recorded) {
          // Log activity
          const { error: activityErr } = await admin.from("document_activity_log").insert({
            workspace_id: genDoc.workspace_id,
            document_id: invoiceId,
            action: "payment_completed",
            actor_type: "system",
            details: {
              payment_method: "stripe",
              amount: amountPaid,
              stripe_session_id: session.id ?? null,
              gl_posted: !rpcError,
            },
          });
          if (activityErr) {
            console.error("Failed to log payment_completed activity:", activityErr);
          }

          // Send notifications
          const { error: notifErr } = await admin.rpc("create_document_action_notifications", {
            p_document_id: invoiceId,
            p_action: "payment_completed",
          });
          if (notifErr) {
            console.error("Failed to create payment notifications:", notifErr);
          }
        }
      }
    }

    return new Response(
      JSON.stringify({ received: true }),
      { headers: { "Content-Type": "application/json" } },
    );
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error("stripe-invoice-webhook error:", message);
    return new Response(
      JSON.stringify({ error: message }),
      { status: 500, headers: { "Content-Type": "application/json" } },
    );
  }
});
