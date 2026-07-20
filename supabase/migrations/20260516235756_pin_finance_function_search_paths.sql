-- =============================================================================
-- Pin search_path on finance/document Postgres functions.
--
-- Supabase security advisor flagged these as `function_search_path_mutable`.
-- A SECURITY-DEFINER function (or any function whose owner schemas can be
-- shadowed) is at risk when search_path is the caller-controlled default:
-- an attacker who can CREATE in a schema earlier on the search_path can
-- shadow a referenced relation or operator and intercept the call. Pinning
-- search_path to `public, pg_temp` removes the vector at no cost to the
-- function bodies.
--
-- Applied to the live DB via the supabase MCP `apply_migration` tool.
-- =============================================================================

ALTER FUNCTION public.next_document_number(uuid, text)                  SET search_path = public, pg_temp;
ALTER FUNCTION public.set_document_counter(uuid, text, integer)         SET search_path = public, pg_temp;
ALTER FUNCTION public.enforce_budget_document_link_integrity()          SET search_path = public, pg_temp;
ALTER FUNCTION public.seed_core_document_templates(uuid, uuid)          SET search_path = public, pg_temp;
