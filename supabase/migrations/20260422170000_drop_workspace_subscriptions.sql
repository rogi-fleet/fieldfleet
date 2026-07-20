-- Drop workspace_subscriptions; billing state lives on the workspaces row.
--
-- The table duplicated subscription_tier / subscription_status / stripe_* columns
-- that already exist on workspaces. The Stripe webhook wrote both rows, giving
-- the two copies a chance to drift, while the Flutter client reads exclusively
-- from workspaces. Removing the table eliminates the drift risk and the dead
-- SupabaseSubscriptionService.getSubscriptionStatus() read path (deleted in
-- lib/services/supabase/subscription_service.dart in the same change).

DROP TABLE IF EXISTS public.workspace_subscriptions CASCADE;
