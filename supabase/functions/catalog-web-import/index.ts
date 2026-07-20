// catalog-web-import — "web clipper" for the cost catalog.
//
// Takes a supplier product-page URL, fetches it server-side (browsers can't:
// CORS), and extracts {name, description, price, unit, sku, image} for a
// pre-filled catalog item draft. Extraction is layered:
//   1. schema.org JSON-LD Product blocks (most supplier sites ship these) —
//      free and exact, no model call;
//   2. OpenGraph/meta tags for whatever JSON-LD didn't cover;
//   3. the self-hosted llama.cpp server (AI_GATEWAY_URL, defaults to
//      ai.example.com) over the stripped page text when name or price is
//      still missing.
//
// Auth: caller JWT + workspace membership, same pattern as ai-text-ops.

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.43.4";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

const MAX_HTML_BYTES = 3_000_000;
const LLM_INPUT_CHARS = 6000;
const FETCH_TIMEOUT_MS = 15_000;

interface ExtractedItem {
  name: string | null;
  description: string | null;
  price: number | null;
  unit: string | null;
  sku: string | null;
  image_url: string | null;
}

function emptyItem(): ExtractedItem {
  return {
    name: null,
    description: null,
    price: null,
    unit: null,
    sku: null,
    image_url: null,
  };
}

function parsePrice(value: unknown): number | null {
  if (typeof value === "number" && isFinite(value) && value > 0) return value;
  if (typeof value === "string") {
    const cleaned = value.replace(/[^0-9.]/g, "");
    const parsed = parseFloat(cleaned);
    if (isFinite(parsed) && parsed > 0) return parsed;
  }
  return null;
}

/** Walk JSON-LD (handles @graph and arrays) looking for a Product node. */
function findProductNode(node: unknown): Record<string, unknown> | null {
  if (Array.isArray(node)) {
    for (const child of node) {
      const found = findProductNode(child);
      if (found) return found;
    }
    return null;
  }
  if (node && typeof node === "object") {
    const obj = node as Record<string, unknown>;
    const type = obj["@type"];
    const types = Array.isArray(type) ? type : [type];
    if (types.some((t) => typeof t === "string" && /product/i.test(t))) {
      return obj;
    }
    if (obj["@graph"]) return findProductNode(obj["@graph"]);
  }
  return null;
}

function extractFromJsonLd(html: string): ExtractedItem {
  const item = emptyItem();
  const scriptRe =
    /<script[^>]*type=["']application\/ld\+json["'][^>]*>([\s\S]*?)<\/script>/gi;
  let match: RegExpExecArray | null;
  while ((match = scriptRe.exec(html)) !== null) {
    try {
      const product = findProductNode(JSON.parse(match[1].trim()));
      if (!product) continue;

      if (typeof product.name === "string") item.name = product.name.trim();
      if (typeof product.description === "string") {
        item.description = product.description.trim().slice(0, 2000);
      }
      if (typeof product.sku === "string") item.sku = product.sku.trim();

      const image = product.image;
      if (typeof image === "string") item.image_url = image;
      else if (Array.isArray(image) && typeof image[0] === "string") {
        item.image_url = image[0];
      } else if (image && typeof image === "object") {
        const url = (image as Record<string, unknown>).url;
        if (typeof url === "string") item.image_url = url;
      }

      const offersRaw = product.offers;
      const offers = Array.isArray(offersRaw) ? offersRaw[0] : offersRaw;
      if (offers && typeof offers === "object") {
        const o = offers as Record<string, unknown>;
        item.price = parsePrice(o.price) ??
          parsePrice((o.priceSpecification as Record<string, unknown>)?.price);
      }
      if (item.name && item.price) break;
    } catch (_) {
      // Malformed JSON-LD block — keep scanning.
    }
  }
  return item;
}

function metaContent(html: string, attr: string, value: string): string | null {
  const re = new RegExp(
    `<meta[^>]*${attr}=["']${value}["'][^>]*content=["']([^"']*)["']`,
    "i",
  );
  const reFlipped = new RegExp(
    `<meta[^>]*content=["']([^"']*)["'][^>]*${attr}=["']${value}["']`,
    "i",
  );
  const m = re.exec(html) ?? reFlipped.exec(html);
  return m ? m[1].trim() : null;
}

function mergeMetaTags(html: string, item: ExtractedItem): void {
  item.name ??= metaContent(html, "property", "og:title") ??
    /<title[^>]*>([^<]*)<\/title>/i.exec(html)?.[1]?.trim() ?? null;
  item.description ??= metaContent(html, "property", "og:description") ??
    metaContent(html, "name", "description");
  item.image_url ??= metaContent(html, "property", "og:image");
  item.price ??= parsePrice(
    metaContent(html, "property", "product:price:amount") ??
      metaContent(html, "property", "og:price:amount") ??
      metaContent(html, "itemprop", "price"),
  );
  item.sku ??= metaContent(html, "itemprop", "sku");
}

function stripHtml(html: string): string {
  return html
    .replace(/<script[\s\S]*?<\/script>/gi, " ")
    .replace(/<style[\s\S]*?<\/style>/gi, " ")
    .replace(/<[^>]+>/g, " ")
    .replace(/&[a-z#0-9]+;/gi, " ")
    .replace(/\s+/g, " ")
    .trim();
}

async function llmExtract(
  pageText: string,
  partial: ExtractedItem,
): Promise<ExtractedItem> {
  const gatewayUrl = Deno.env.get("AI_GATEWAY_URL") ??
    "https://ai.example.com/completion";

  const prompt =
    `You extract product data from supplier web pages for a construction ` +
    `cost catalog.\n\nPage text:\n"""\n${pageText.slice(0, LLM_INPUT_CHARS)}` +
    `\n"""\n\nReturn ONLY a JSON object (no markdown, no commentary) with ` +
    `these keys: "name" (short product name), "description" (1-2 ` +
    `sentences), "price" (number, the current selling price, null if ` +
    `unclear), "unit" (selling unit like "each", "sq ft", "box", null if ` +
    `unclear), "sku" (model/SKU string or null).\nJSON:`;

  const response = await fetch(gatewayUrl, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      prompt,
      n_predict: 400,
      temperature: 0.1,
      stop: ["\n\n\n"],
    }),
  });
  if (!response.ok) {
    throw new Error(`AI gateway returned ${response.status}`);
  }
  const payload = await response.json();
  const content = (payload.content as string | undefined) ?? "";
  const start = content.indexOf("{");
  const end = content.lastIndexOf("}");
  if (start < 0 || end <= start) {
    throw new Error("AI gateway returned no JSON object");
  }
  const parsed = JSON.parse(content.slice(start, end + 1)) as Record<
    string,
    unknown
  >;

  return {
    name: partial.name ??
      (typeof parsed.name === "string" ? parsed.name.trim() : null),
    description: partial.description ??
      (typeof parsed.description === "string"
        ? parsed.description.trim()
        : null),
    price: partial.price ?? parsePrice(parsed.price),
    unit: partial.unit ??
      (typeof parsed.unit === "string" ? parsed.unit.trim() : null),
    sku: partial.sku ??
      (typeof parsed.sku === "string" ? parsed.sku.trim() : null),
    image_url: partial.image_url,
  };
}

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const json = (body: unknown, status = 200) =>
    new Response(JSON.stringify(body), {
      status,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!supabaseUrl || !anonKey || !serviceRoleKey) {
      return json({ error: "Server configuration missing" }, 500);
    }

    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return json({ error: "Missing authorization header" }, 401);
    }
    const supabaseUser = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: { user }, error: authError } = await supabaseUser.auth
      .getUser();
    if (authError || !user) {
      return json({ error: "Unauthorized" }, 401);
    }

    const body = await req.json() as { workspace_id?: string; url?: string };
    const workspaceId = body.workspace_id?.trim();
    const rawUrl = body.url?.trim();
    if (!workspaceId || !rawUrl) {
      return json({ error: "workspace_id and url are required" }, 400);
    }

    let url: URL;
    try {
      url = new URL(rawUrl);
    } catch (_) {
      return json({ error: "Invalid URL" }, 400);
    }
    if (url.protocol !== "https:" && url.protocol !== "http:") {
      return json({ error: "Only http(s) URLs are supported" }, 400);
    }

    const supabaseService = createClient(supabaseUrl, serviceRoleKey);
    const { data: membership, error: membershipError } = await supabaseService
      .from("workspace_members")
      .select("workspace_id")
      .eq("workspace_id", workspaceId)
      .eq("user_id", user.id)
      .maybeSingle();
    if (membershipError || !membership) {
      return json({ error: "Forbidden" }, 403);
    }

    // Fetch the supplier page
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), FETCH_TIMEOUT_MS);
    let html: string;
    try {
      const page = await fetch(url.toString(), {
        signal: controller.signal,
        redirect: "follow",
        headers: {
          "User-Agent":
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 " +
            "(KHTML, like Gecko) Chrome/124.0 Safari/537.36",
          "Accept": "text/html,application/xhtml+xml",
        },
      });
      if (!page.ok) {
        return json(
          { error: `Supplier page returned HTTP ${page.status}` },
          422,
        );
      }
      const buffer = await page.arrayBuffer();
      html = new TextDecoder("utf-8", { fatal: false }).decode(
        buffer.slice(0, MAX_HTML_BYTES),
      );
    } catch (_) {
      return json(
        { error: "Could not fetch that URL (timeout or network error)" },
        422,
      );
    } finally {
      clearTimeout(timer);
    }

    // Layered extraction
    const item = extractFromJsonLd(html);
    mergeMetaTags(html, item);
    let source = "structured";
    if (!item.name || item.price === null) {
      try {
        const completed = await llmExtract(stripHtml(html), item);
        Object.assign(item, completed);
        source = "ai";
      } catch (e) {
        console.error("LLM fallback failed:", e);
        // Whatever structured data we did get still goes back to the user.
        if (!item.name) {
          return json(
            { error: "Could not extract product data from that page" },
            422,
          );
        }
        source = "structured_partial";
      }
    }

    return json({
      success: true,
      source,
      item: { ...item, source_url: url.toString() },
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error("catalog-web-import error:", message);
    return json({ error: message }, 500);
  }
});
