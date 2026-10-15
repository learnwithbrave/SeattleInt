# Seattle International Church — Architecture Decision

**Status:** Proposed for review; implementation has not started  
**Date:** 2026-10-15  
**Repository:** learnwithbrave/SeattleInt  
**Decision owner:** Project owner / church-designated administrator

## 1. Purpose

Replace the browser-local CMS with a secure, shared content-management system while preserving the existing public website's routes, content, responsive behavior, and visual design. This document is a review gate: application implementation and backend provisioning must not begin until the architecture and migration plan are approved.

## 2. Current-state findings

The repository currently contains a React 19 + TypeScript + Vite frontend, React Router routes, Tailwind CSS, and Framer Motion. The public site and the /admin CMS use one frontend application.

The content layer is centered on:
- src/content/siteContent.ts — default site content and search-index helpers.
- src/content/SiteContentProvider.tsx — content state provider and persistence lifecycle.
- src/content/siteContentStore.ts — content model-facing context, localStorage persistence, reset, and JSON import/export.
- src/pages/AdminPage.tsx — current admin editing interface.
- src/components/ExternalForm.tsx and src/pages/PrayerRequestPage.tsx — public form flows.
- src/App.tsx — current route registration.

Current constraints and risks:
- CMS content is saved in each browser's localStorage; it is not shared across devices or administrators.
- The /admin route is registered in the client router. Client-side route visibility alone is not authorization.
- The content import check is a shallow structure check, not a complete schema validator.
- Hosted-form endpoints and social/giving destinations include placeholders that need owner verification.
- The prayer-request flow requires a verified submission and delivery path before it can be treated as operational.
- BrowserRouter requires the production host to rewrite application routes to the SPA entry point.

Before implementation, capture a known-good baseline build, export and archive current content, record screenshots of major pages at representative viewport sizes, and confirm all currently used routes and form destinations.

## 3. Architecture decision

### Recommended stack

Keep the existing React/Vite client. Use Supabase for managed PostgreSQL, authentication, row-level security, private object storage, and narrowly scoped Edge Functions for sensitive workflows. Use a typed content-service interface in the frontend so the UI is not coupled to Supabase calls.

This avoids introducing a separate Node.js API and its maintenance/deployment burden for the initial migration. Revisit a dedicated API only if the application develops complex orchestration or domain rules that no longer fit comfortably in database policies and small server functions.

### System boundaries

    Public browser
      ├── Existing public routes and components
      ├── CMS login, editing, preview, and review UI
      └── Typed content/form service
                 │
                 ▼
      Supabase client (publishable/anon key only)
                 │
       ┌─────────┼──────────────────┐
       ▼         ▼                  ▼
    Auth + RLS  PostgreSQL       Storage
                 │
                 ├── Versioned content revisions
                 ├── Publication pointer
                 ├── Role assignments
                 ├── Audit events
                 └── Private form submissions
                 ▲
                 │
      Edge Functions for invitation,
      publishing-sensitive operations,
      and validated public-form submissions
                 │
                 ▼
       Email/provider integrations

The diagram is logical rather than a network topology. Every operation exposed to a browser must be safe under untrusted input and enforced by database policy or a trusted server function, not only by React UI checks.

## 4. Content migration approach

### Keep the existing frontend content contract initially

The current application edits one structured SiteContent object. For the first backend-backed release, store each complete, validated SiteContent revision as a versioned JSONB snapshot. This is an intentional low-risk migration seam: it preserves the current shape and minimizes changes to page components while shared editing, review, authorization, and publishing are introduced.

Use relational tables immediately for identities/roles, revision metadata, the current publication pointer, audit records, media metadata, and private form submissions. Do not duplicate the same church content into both a JSON snapshot and separate leader/ministry/event tables during the first release. Normalize those collections later only when query patterns or constraints justify a separately reviewed migration.

A Zod schema (or equivalent runtime validator) must validate the entire incoming content payload on import, save, and server-side publication. TypeScript types alone do not validate untrusted runtime data.

### Published content must be distinct from drafts

A draft is never the public source of truth. A publisher-approved revision becomes the active published revision through one atomic operation. Public routes request only that current published revision. Publishing retains the previous content revision for audit/rollback; it must not delete the prior working version. The UI should never show a success message until the backend confirms the write.

During transition, the existing seeded site content becomes the initial approved/published revision. Exported browser-local content must be reviewed and imported deliberately; do not automatically trust arbitrary localStorage content as the production seed.

## 5. Identity and publishing roles

All CMS access is invitation-only; no public self-registration.

| Role | Allowed actions |
|---|---|
| Public visitor | Read current published content; submit only supported public forms |
| Editor | View published content; create and edit an assigned draft; submit it for review; preview the draft |
| Publisher | Review drafts; approve, request changes, or publish; no role administration by default |
| Administrator | All CMS content/publishing actions; invite or deactivate CMS users and assign roles |
| Deployment operator | Manage deployment configuration and secrets; this operational role is not implicitly a content role |

An editor must not approve their own submission by default. If a small church team later explicitly requires self-publishing, treat that as a separate policy decision and document the risk.

Role assignments come from trusted database state and are not editable from a user's profile. Removing a role must take effect in database policies, even if the user's browser still has an open CMS screen.

## 6. Security baseline

- Enable row-level security on every table accessible through the Supabase API, and define least-privilege policies and SQL grants.
- Public clients may read only the current published payload. Drafts, revision metadata that reveals private workflow information, audit rows, user roles, and form submissions are not public.
- Never put a Supabase service-role key, SMTP credential, form secret, or provider secret in a Vite-prefixed variable or browser bundle.
- Treat publish, role assignment/invitation, and private form processing as trusted operations with server-side validation and authorization.
- Validate payload shape, text lengths, allowed URL schemes, media MIME type/size, and form type at the trust boundary.
- Do not log prayer-request or contact message bodies. Minimize sensitive data collection and agree on access, retention, and deletion procedures before enabling prayer requests.
- Keep audit events append-only to ordinary CMS roles. Record actor, action, target revision, and timestamp without copying sensitive form content into the audit trail.
- Test negative authorization cases, not just happy paths.

Detailed schema and policy expectations are in [DATA-MODEL-AND-SECURITY.md](DATA-MODEL-AND-SECURITY.md).

## 7. Forms and external integrations

All public form submissions should pass through a single validated server-side submission boundary with explicit supported form types, anti-spam/rate controls, safe error handling, and a verified delivery destination. Do not assume a successful browser POST means staff received the message. Prayer requests should use restricted storage and recipient access.

The giving experience should continue to redirect to the church's verified hosted giving provider; this architecture does not introduce card-data processing. Social, YouTube, map, email, and giving destinations must be verified with an authorized church representative before production cutover. Secrets for email and other providers belong in the backend secret store.

## 8. Deployment and operations

- Separate staging and production Supabase projects/configuration.
- Keep migrations and seed data under version control; production changes run through reviewed migrations, not undocumented dashboard edits.
- Run dependency install, lint, TypeScript/build, unit/schema tests, RLS/integration tests, and end-to-end smoke tests in CI.
- Configure SPA fallback rewrites for direct route entry and refresh.
- Keep the public website deployable independently from content data migrations where practical.
- Define backup ownership, recovery point/retention expectations, and perform a restore rehearsal before production release.
- Record the rollback procedure and the previous published content revision before cutover.
- Monitor function errors and delivery failures without recording private prayer or contact content.

Hosting provider selection for the static frontend remains open until current deployment ownership and constraints are confirmed. Supabase is the recommended backend service; no service has been provisioned by this documentation change.

## 9. Non-goals for the first release

- No redesign or rebranding of public pages.
- No public account registration.
- No real-time collaborative typing or multi-cursor editor.
- No custom Node.js API unless implementation evidence requires it.
- No replacement of the giving provider or direct handling of payment-card details.
- No simultaneous full normalization of every nested content collection.
- No unreviewed automated production cutover.

## 10. Approval gate

Before Phase 1 implementation, the project owner should approve:
1. Supabase as the managed backend and the initial no-custom-API approach.
2. The snapshot-based first migration for the existing SiteContent aggregate.
3. The role matrix and the default prohibition on self-approval.
4. Private handling and retention expectations for prayer/contact submissions.
5. The named staging/production owners, static frontend host, and verified form/giving destinations.
6. The acceptance criteria and rollback steps in MIGRATION-IMPLEMENTATION-PLAN.md.

This change set is documentation-only. No application code, dependencies, schema, secrets, hosted resources, or production content have been changed.
