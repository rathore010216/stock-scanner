STOCK-SCANNER: Firebase Realtime Database rules addition
=========================================================

Add the "stock" block below to your EXISTING family-locator database rules
(alongside users, contacts, groups, etc.). Do NOT remove the locator rules —
just insert this one node inside "rules": { ... }.

  "stock": {
    ".read": "auth != null",
    ".write": false
  }

- ".read": "auth != null"  -> the stock app reads it after signing in
  anonymously (free, no user accounts). Change to "true" if you want it
  readable without any auth at all.
- ".write": false          -> normal clients can NEVER write. The daily
  publisher (GitHub Action) writes using the database SECRET, which bypasses
  rules entirely, so it can still update /stock/*.

If you'd rather not use a legacy database secret for CI writes, an alternative
is a Firebase service-account token, but the database secret is the simplest
$0 path for a scheduled job.

Enable Anonymous auth: Firebase Console -> Authentication -> Sign-in method ->
Anonymous -> Enable. (The app uses it just to satisfy ".read": "auth != null".)
