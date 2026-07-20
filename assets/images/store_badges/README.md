# Store badges

This folder holds the official Apple and Google store badge artwork
that the `AppDownloadSection` widget swaps in when
`MobileAppLinks.useOfficialBadges` is `true`.

Drop in two files (transparent-background PNG, ~4:1 aspect ratio):

- `app_store.png` — Apple's official "Download on the App Store"
  badge. Download from
  https://developer.apple.com/app-store/marketing/guidelines/.
  Pick the black-on-white variant for light backgrounds.
- `play_store.png` — Google's official "Get it on Google Play" badge.
  Download from https://play.google.com/intl/en_us/badges/.
  Pick the colour version, English locale.

Both stores require their official trademarked artwork; inlining a
re-drawn approximation is a TOS violation. Until the PNGs are
present here, the widget falls back to a Material-styled
text-and-icon button that's free of trademarked elements.

After adding the files, flip
`MobileAppLinks.useOfficialBadges = true` in
`lib/config/mobile_app_links.dart`. No other code changes required.
