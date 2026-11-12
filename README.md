# Helpay 2.0 — Production-only Offer Discovery MVP (Tablet Setup)

**This edition has NO demo fallback and NO sample coupons.** The static build intentionally FAILS until a genuine Supabase Project URL and publishable API key are provided. Real, approved public offer discovery is supported. It does **not** implement private coupon resale, checkout, payment collections, seller payouts, AI fraud scoring, OAuth or production email delivery. No live money exchange should be enabled.

## Architecture
- Frontend: dependency-free ES modules, CSS, HTML
- Backend: Supabase Auth + PostgREST + PostgreSQL with Row Level Security
- Hosting: Cloudflare Pages Git integration (not Direct Upload)
- Code: GitHub, optionally Bolt to edit/import

## Do these steps IN ORDER on Samsung Galaxy Tab A9+ 5G (Chrome Desktop site)

1. **Supabase:** Create a new project at https://supabase.com/dashboard. Under SQL Editor → New query paste the entire contents of `supabase/migrations/202611120001_initial.sql` and Run. Then run `supabase/tests/001_schema_checks.sql` and confirm all rows read true. Inspect Security Advisors; fix issues before launching. These SQL checks are structural, not proof of RLS behavior.
2. **Get public values:** In the Supabase project's Connect dialog obtain Project URL (`https://...supabase.co`) and Publishable Key (`sb_publishable_...`). Never place database passwords or `sb_secret_...` in browser code.
3. **GitHub:** Extract this ZIP with Samsung My Files. Create a PRIVATE `helpay-2-0` GitHub repository and upload the CONTENTS of the inner `helpay-2.0` directory, preserving hidden files and nested folder structure. Editing/uploading from mobile browser can be difficult; use GitHub Desktop site mode or Bolt's GitHub sync if available.
4. **Connect backend:** Edit `src/config.js` in GitHub (or Bolt). Enter your exact Project URL and Publishable Key. Save/commit. `npm run build` will refuse to publish without both valid-looking values.
5. **Bolt (optional):** Import the GitHub repo into https://bolt.new. Paste `BOLT_UPGRADE_PROMPT.md` to improve the code without adding demo or fake records. Keep `supabase/migrations` and RLS rules. Do not commit generated SQL without review. Do not enable payments.
6. **Test before launch:** Create/verify a test user, sign in, submit a genuine PUBLIC promotion using an issuer-approved HTTPS source, verify it is hidden before moderation; assign admin using the SQL Editor below; approve from the moderation queue; verify public listing is shown; test that other accounts cannot read private/pending offers. Try sign-out, favourites, reports, invalid URLs, expired offers and phone-sized layouts. Test emails and password reset behavior separately (password reset is not implemented in this MVP).
7. **Cloudflare Pages ONLY AFTER CHECKS PASS:** Workers & Pages → Create application → Pages → Connect to Git → select GitHub repo `helpay-2-0`. Build command `npm run build`; output `dist`; root `/`; branch `main`. Production build will fail if `src/config.js` has no public Supabase settings. Cloudflare gives you an HTTPS `pages.dev` address.
8. **Auth URLs:** Supabase → Authentication → URL Configuration; set `Site URL` to the exact deployed `https://...pages.dev` address and add that URL to allowed redirects. For initial real user email verification before final domain is known, use the domain you plan to keep or configure the new URL promptly.
9. **Custom domain OPTIONAL:** In Cloudflare Pages → Custom domains, add the purchased domain; complete DNS instructions; update Supabase Auth URL settings.

## Assign first admin (trusted database owner only)
After registering and confirming your own test user, copy its UUID from Supabase → Authentication → Users. In SQL Editor run:

```sql
insert into public.user_roles(user_id, role)
values ('REPLACE-WITH-EXACT-AUTH-USER-UUID', 'admin')
on conflict (user_id) do update set role = excluded.role;
```

Sign out/in and open Moderation. Admin can publish or reject submissions. Ordinary users cannot self-promote.

## Build and test
- `npm run check` — parse checks
- `npm test` — five unit tests
- `npm run build` — production-only build; FAILS if Supabase values are missing
- `supabase/tests/001_schema_checks.sql` — SQL schema checks; execute via Supabase SQL Editor

## Release blockers and disclosures
- Before serving the public, manually check actual RLS behavior using two normal accounts plus an anonymous visitor; the included SQL test is only structural.
- Live authentication and Supabase REST calls have NOT yet been tested against your personal Supabase project.
- Check Supabase Auth email settings (send limits and confirmation) for real users; no custom SMTP provider configured.
- No real offers are bundled; the live catalogue starts empty until an approved real promotion exists.
- User profiles and account deletion are not fully self-service; privacy policies and a contact route must be added before collecting public user accounts commercially.
- Session tokens use browser localStorage. Conduct security review before storing sensitive user data.
- Coupon redemption codes, payment, seller checkout/payouts, official brand validation, AI risk classification, and other proposed features are NOT shipped.

## Structure
`index.html`, `src/`, `assets/`, `supabase/migrations/`, `supabase/tests/`, `scripts/`, `tests/`, `.github/workflows/`, `BOLT_UPGRADE_PROMPT.md`.
