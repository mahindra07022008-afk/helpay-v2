# Bolt upgrade prompt — Helpay 2.0

Import this existing GitHub repository rather than replacing it with an empty template.

Helpay is a safe, fully functional public-offer discovery MVP with Supabase authentication and tightly permissioned PostgreSQL RLS. Improve it incrementally, preserving the existing behaviour, database structure, and test coverage.

## Requirements
1. Keep a beautiful responsive web UI: homepage, explore, search, category filter, sort, offer details and issuer links.
2. Preserve calculator and its pure tests, including percent/flat discounts, caps, minimum spend.
3. Keep email registration, login, favourites, private submissions, reports and admin moderation working with Supabase.
4. Never expose unreviewed offers to anonymous visitors. Users cannot modify status, choose admin role, or read other users' private data.
5. Do NOT add live payments, escrow, coupon-code storage, transfer/sale of payment-app rewards or automatic redemption. Real coupon resale must only follow issuer and provider approval.
6. **Production-only**: no demo mode, no sample offers, no local fake submissions. Never weaken production-build validation for missing Supabase configuration.
7. Preserve the current RLS SQL and review any proposed migrations for escalation risks.
8. Improve accessibility, mobile navigation, rate limiting recommendations, error states, testing and developer documentation.
9. Prefer a safe, minimal implementation. Do not rewrite working components solely to chase new dependencies. If you migrate to React/Vite, keep working behaviour and tests and update GitHub CI and Cloudflare output instructions.
10. Test every change. Report passing tests, remaining issues and any setup actions needed from the project owner.

Deployment: Cloudflare Pages, currently `npm run build` => `dist/`; Supabase auth + PostgreSQL remain hosted in the user's Supabase project.

Before claiming completion, run automated tests and a production build. Do not claim remote Supabase functionality is tested without actual test accounts and permission checks.
