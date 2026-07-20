# Notification Matrix

This document defines which product events should create entries in the in-app notification view.

It is scoped to the bell/notifications surface, not the messaging inbox. New chat messages should remain in the messaging inbox unless we explicitly decide to build a unified activity feed.

## Principles

- Prefer high-signal events over activity spam.
- Exclude the actor unless the event is system-generated.
- Send to the smallest useful audience.
- Use direct deep links whenever possible.
- Reuse existing categories where the meaning fits; add new types only when the event needs distinct UI/prefs/reporting.

## Adding a new type

The set of allowed `notifications.type` values is the lookup table
`public.notification_types` (introduced in
`20260503160000_unify_notifications_foundation.sql`). Adding a new type
is now a single INSERT, not a CHECK-constraint rebuild. Keep the
following three places in sync:

1. The seed in the unify-foundation migration (or a follow-on migration
   that does `INSERT INTO public.notification_types ...`).
2. `lib/models/app_notification.dart` (`AppNotificationTypes`).
3. `supabase/functions/_shared/notification_types.ts`.

Both the DB FK and the shared TS module make drift caught at the next
deploy / next CI run.

## Current Implemented Triggers

| Event | Type | Recipient |
| --- | --- | --- |
| Task comment mention | `mention` | Mentioned user |
| File comment mention | `mention` | Mentioned user |
| Task assigned | `task_assignment` | Newly assigned user |
| Task completed | `task_completion` | Assigned users except actor |
| New message in conversation | `message_received` | Conversation members except sender |
| Workspace member joined | `workspace_member_joined` | All workspace members except the new member |
| Time entry submitted for approval | `time_entry_submitted` | Workspace admins and managers, excluding submitter |
| Time entry approved | `time_entry_approved` | Submitter |
| Time entry rejected | `time_entry_rejected` | Submitter |
| Document signed | `document_signed` | Document creator, project manager |
| Document denied | `document_denied` | Document creator, project manager |
| Document changes requested | `document_changes_requested` | Document creator, project manager |
| Document payment completed | `document_payment_completed` | Document creator, project manager |
| Vendor bid received on RFP | `document_bid_received` | RFP owner |
| Vendor bid applied to budget | `document_bid_applied` | Budget owner / actor |
| Agreement signed | `agreement_signed` | Agreement creator, project manager |
| Project manager / status / team / target-date changed | `project_update` | Project manager and team |
| Capacity risk / over-capacity | `capacity_alert` | Member and leads |
| Overdue high-priority task | `priority_alert` | Assigned users |
| AI plan ready / failed | `ai_plan_ready` / `ai_plan_failed` | Requesting user |
| Automation-created notification | `automation` | Rule-defined recipients |
| Field form submission received | `form_submission` | Configured recipients |

## Deferred / Not Yet Built

These types appeared in earlier proposals but are not yet implemented.
If we revisit them, prefer reusing existing types where the meaning
fits rather than inventing new ones:

| Event | Suggested approach |
| --- | --- |
| Document sent for signature | Reuse `project_update` until product calls for a distinct type. |
| Agreement sent (not signed) | Reuse `project_update`. |
| Invoice sent / paid / overdue | New `invoice_update` type if/when invoicing notifications matter; otherwise `project_update`. |
| Client portal invite sent / first login | New `client_portal_update` type if/when client-portal events become user-visible. |

## Default Title/Body Guidance

- Team join: title with member name, optional body with role.
- Time approval: body should include date and total hours.
- Signed documents/agreements: body should include signer name and timestamp.
- Project updates: body should include old value -> new value when practical.
- Invoice updates: body should include amount and status date.

## Dedupe Rules

The unified `create_notification` RPC accepts an optional
`p_dedupe_key` and `p_dedupe_window_seconds`. When set, calling the RPC
again with the same `(user_id, workspace_id, type, dedupe_key)` inside
the window returns the prior notification id instead of inserting a new
row. Recommended dedupe-key shape: `<scope>:<entity_id>[:<extra>]`
(e.g. `mention:<comment_id>`, `over_capacity:<member_id>:<date>:<scope>`).

Per-event guidance:

- Team join: one notification per membership creation event (no dedupe needed; trigger fires once).
- Time approval: one notification per status transition per entry (use `time_entry_id` as dedupe_key).
- Project updates: collapse repeated edits within a short window if multiple fields change in one save (use `project_id` and a 60s window).
- Invoice overdue (when implemented): at most one per invoice per day (window: 24h).
- Capacity alerts: already deduped by `<issue_type>:<member_id>:<date>:<scope>` over 24h.

## Per-User Preferences

User-global JSON in `users.notification_preferences`:

- Per-channel toggles per category: `mentionsEmail`, `mentionsPush`, `taskAssignmentsEmail/Push`, `taskCompletionsEmail/Push`, `projectUpdatesEmail/Push`, `messagesPush`.
- Email cadence: `digestMode` ∈ `{immediate, hourly, daily}`. The mention email functions enqueue into `email_notification_queue` whenever the user is in a non-`immediate` mode; the `email-digest-runner` edge function rolls those up on a pg_cron schedule.

Per-workspace overrides live in `workspace_notification_preferences`:

- `muted_until` mutes everything in that workspace until the timestamp passes.
- `preferences` JSONB can override individual keys for that workspace only.

Resolution is centralized in the `effective_notification_pref(user, workspace, key)` SQL function, in this order:
1. Workspace mute-until in the future ⇒ FALSE for everything.
2. Workspace per-key override.
3. User-global per-key value.
4. Default ON.

Both `push-dispatch` and the email-sending edge functions read through this helper.

## Explicit Non-Goals

These should not create notification-view entries by default:

- Every new chat message
- Every project edit field change
- Every file upload
- Every comment without a mention
- Every automation execution success


