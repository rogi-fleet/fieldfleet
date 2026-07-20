# Private Beta Signup Gate

This note documents how FieldFleet signup is currently restricted while the site remains in beta.

## Goal

Prevent public self-signup from the normal signup form while still allowing:

- invited users to create accounts through workspace invite links
- creators/internal testers to create accounts through a private link

## Current Behavior

Public users can no longer browse to `/signup` and create an account normally.

The signup form is only enabled when one of these is true:

- the request came from an invite flow with `from=/invite/...`
- the URL includes a valid creator access token in the `creator_access` query parameter

If neither condition is met, the signup page shows a private beta message and routes users back to login.

The login page also no longer shows a public "Sign up" CTA.

## Secret Creator Link

The creator-only signup link uses a build-time token:

```bash
--dart-define=CREATOR_SIGNUP_TOKEN=your-secret-value
```

Example private creator signup URL:

```text
/signup?creator_access=your-secret-value
```

## Implementation Files

- [lib/config/beta_signup_config.dart](../lib/config/beta_signup_config.dart)
- [lib/router.dart](../lib/router.dart)
- [lib/screens/auth/login_screen.dart](../lib/screens/auth/login_screen.dart)
- [lib/screens/auth/signup_screen.dart](../lib/screens/auth/signup_screen.dart)

## Important Limitation

This is currently an app-route/UI gate.

It blocks the normal signup route in the app, but it does **not** fully enforce beta signup restrictions at the backend/auth-provider level by itself.

That means this protects the intended web flow, but it should not be treated as a strong security boundary if stricter enforcement is needed later.

If stronger control is required, add server-side or auth-side enforcement so unauthorized first-time account creation is rejected even outside the gated route.

## Related Commit

Initial implementation commit:

```text
d4dc6b8b  Gate signup behind beta creator access
```

