# SeattleInt CMS — File-by-File Implementation and Migration Plan

**Status:** Proposed for approval; Phase 1 is not authorized until the plan is approved  
**Date:** 2026-10-15  
**Target branch for this plan:** docs/architecture-and-migration-plan  
**Production application code changed:** No

Companion documents:
- [Architecture decision](README.md)
- [Data model and security](DATA-MODEL-AND-SECURITY.md)

## 1. Implementation rules

1. **Preserve the public experience.** Existing routes, page layout, copy, imagery, navigation, responsiveness, animations, metadata, and page behavior are the baseline. No visual redesign is part of this migration.
2. **Keep diffs small.** Replace persistence and integration boundaries incrementally. Do not rewrite unrelated components or rename/move large sets of files just to match the proposed folder structure.
3. **No browser-local source of truth.** localStorage may hold transient preferences or provide an explicit legacy export/import path; it must not be authoritative for shared site content or permissions.
4. **No draft leakage.** Public routes can retrieve only the active published revision.
5. **No UI-only security.** Database policies and trusted functions enforce roles; client route guards are supplementary.
6. **Migrations before consumers.** Versioned schema, policies and tests must exist before the frontend is switched to them.
7. **No silent data loss.** Save operations are acknowledged only after persistence succeeds. Concurrent/stale writes return a conflict and preserve the newer version.
8. **No real secrets in Git.** Only safe placeholders are committed.
9. **Review in stages.** Each phase must pass its exit criteria before the next begins; production cutover requires explicit owner sign-off.

## 2. Dependency order

    Review and approve this plan
                 │
                 ▼
    Phase 0 — baseline and migration inventory
                 │
                 ▼
    Phase 1 — backend project, schema, RLS,
              trusted operations, security tests
                 │
                 ▼
    Phase 2 — typed schema + content service
              + imported initial published snapshot
                 │
                 ▼
    Phase 3 — CMS authentication, permissions,
              draft/review/publish experience
                 │
                 ▼
    Phase 4 — forms, media, email and giving links
                 │
                 ▼
    Phase 5 — validation, staff UAT, cutover,
              backup/restore and rollback rehearsal

Phase 1 refers to the first implementation phase, not permission to begin today. This document must be approved first.

## 3. Phase 0 — Baseline and migration inventory

**Goal:** establish what must remain unchanged, and determine who owns production decisions.

### Files and artifacts

| Path / artifact | Action | Notes |
|---|---|---|
| docs/architecture/README.md | Review / accept decision | Record approved decisions and any exceptions |
| docs/architecture/DATA-MODEL-AND-SECURITY.md | Review security model | Confirm roles, privacy, RLS expectations |
| docs/architecture/MIGRATION-IMPLEMENTATION-PLAN.md | Review release gates | Track checklist decisions and sign-off |
| src/content/siteContent.ts | Inspect; do not redesign | Capture exact seed content and nested content shape |
| src/types.ts | Inventory | Map the current SiteContent domain contract |
| src/App.tsx and existing public page components | Baseline only | Record route list, screenshots and navigation |
| src/pages/AdminPage.tsx | Inventory | Record editing sections and current import/export/reset behavior |
| src/content/SiteContentProvider.tsx | Inventory | Record initialization, loading and persistence behavior |
| src/content/siteContentStore.ts | Inventory | Document legacy localStorage keys and import behavior |
| src/components/ExternalForm.tsx, src/pages/PrayerRequestPage.tsx | Inventory | Confirm field names, recipient destinations and delivery behavior |
| README.md / deployment configuration | Update later | Confirm current host, rewrites, environment variable names and release process |

### Required actions

- [ ] Run existing npm ci (or the repository's currently approved deterministic install) and record baseline npm run lint and npm run build results.
- [ ] Capture screenshots of home, about, visit, sermons, events/list and detail, ministries/list and detail, giving, contact, prayer request, and the current admin view at desktop and mobile widths.
- [ ] Record exact routes and test direct navigation/refresh on a nested route.
- [ ] Export current admin content from each known editor/browser that may contain meaningful local changes; retain separately labelled backups and compare them.
- [ ] Identify the authoritative content owner. Reconcile differences between the seeded siteContent.ts and all local exports; never choose one silently.
- [ ] Confirm production host, staging host, domain/DNS owner, deployment owner and rollback operator.
- [ ] Verify real church name, address, phones/emails, social/YouTube URLs, map URL, giving destination, and all form recipients with an authorized owner.
- [ ] Confirm who receives prayer requests and which people are permitted to read them. Decide retention/deletion interval before enabling submissions.
- [ ] Name an initial administrator and a backup. Decide which named users need editor vs publisher access.
- [ ] Decide whether media upload is in the first release or the first release will use approved existing media URLs only.

**Exit gate:** baseline build/lint results and content exports are archived; ownership, environment, role and privacy questions are recorded. No application code is changed in Phase 0.

## 4. Phase 1 — Backend foundation and security enforcement

**Goal:** establish the database/auth foundation independently of the live frontend.

### New files expected

| Path | Purpose |
|---|---|
| supabase/config.toml | Local Supabase project configuration, if local CLI development is adopted |
| supabase/migrations/<timestamp>_cms_foundation.sql | Profiles, roles, revisions, publication pointer, audit schema, constraints, grants, RLS and helper functions |
| supabase/migrations/<timestamp>_cms_workflows.sql | Draft/save/submit/review/publish operations and transaction/concurrency protections |
| supabase/seed.sql | Deterministic non-secret baseline seed for local/staging; avoid embedding personal submissions |
| supabase/tests/ (SQL or pgTAP as selected) | Database-policy and workflow regression tests |
| .env.example | Document only non-secret frontend values and safe placeholder server variable names |
| docs/architecture/OPERATIONS.md | Local setup, migration, environment separation, secret and rollback procedures |

Timestamped migration names above are templates; create real timestamped names when migrations are authored. Avoid editing an already-applied migration; add a follow-up migration instead.

### Existing files touched in this phase

None of the runtime application files should need modification merely to create the database foundation. package.json and the lockfile should change only if the team explicitly chooses and documents a local Supabase testing toolchain.

### Required actions

- [ ] Create separate staging and production backend projects; do not point a development client at production.
- [ ] Apply reviewed SQL migrations to local/staging first.
- [ ] Create constraints for unique role membership, singleton publication pointer, allowed statuses and payload object shape.
- [ ] Implement narrowly scoped transactional functions for draft writes with expected version, review transitions, publish pointer change, role administration and approved public content retrieval.
- [ ] Apply explicit table grants and RLS; confirm unauthenticated users cannot read/write internal tables directly.
- [ ] Ensure public access exposes only the active published payload.
- [ ] Add database tests for role escalation, owner boundaries, status transition bypass, self-approval, stale writes, private submissions and rollback.
- [ ] Decide and implement who can bootstrap the first administrator without enabling public role assignment. Use a trusted operator process or one-time server-side bootstrap, then disable/remove bootstrap access.
- [ ] Configure secrets only in the backend/deployment secret store. Add safe documentation but do not commit real credentials.
- [ ] Run migration from an empty staging database, and test rollback/recovery strategy on a disposable environment.

**Exit gate:** schema and security tests pass in staging; no frontend switch has happened; all privileged functions and role bootstrap have been reviewed.

## 5. Phase 2 — Content validation and backend service seam

**Goal:** connect content through a typed abstraction while keeping the public design and the existing SiteContent contract stable.

### Files expected to be added

| Path | Responsibility |
|---|---|
| src/lib/supabase/client.ts | Create browser Supabase client from approved public configuration only |
| src/content/schemas.ts | Runtime validation schema for the complete SiteContent structure and safe URL/text/array constraints |
| src/content/contentService.ts | Typed interface for load published, load draft, create/save draft, submit review, review/publish, reset-to-seed policy, import/export |
| src/content/supabaseContentService.ts | Supabase implementation of the content service |
| src/content/contentQueries.ts | Query helpers with explicit public/published vs authorized CMS paths |
| src/lib/errors/ (if needed) | Normalize auth, validation, conflict, permission and network errors |
| tests/unit/content-schema.test.ts | Runtime schema tests |
| tests/unit/content-mapping.test.ts | Seed/import/export compatibility tests |
| tests/integration/content-service.test.ts | Backend-backed behavior tests |

### Existing files expected to be touched

| File | Planned change | Preservation requirement |
|---|---|---|
| src/types.ts | Keep current public content types where possible; add revision/status/role/service result types | Do not casually redefine current page fields |
| src/content/siteContentStore.ts | Retain useful domain helpers, search behavior and context contract; route operations through service rather than directly using localStorage | Keep legacy import/export available during migration; do not treat local storage as production persistence |
| src/content/SiteContentProvider.tsx | Add loading/error state and async initialization; load published payload via service for public views and use authorized draft state only in CMS | Avoid exposing draft payload in the public context; handle no-network and auth expiration |
| src/content/siteContent.ts | Use as the reviewed initial migration seed and current search derivation if still applicable | Do not delete seeded content before parity is verified |
| package.json and lockfile | Add only approved libraries, expected to include @supabase/supabase-js and a runtime schema validator such as zod | Install deliberately and use the lockfile; no unrelated dependency upgrades |

### Required actions

- [ ] Implement full runtime validation for content saves and imports. Reject malformed input without partially changing the current revision.
- [ ] Keep the content-service interface independent of Supabase-specific response shapes so another implementation remains possible.
- [ ] Import the reconciled initial content into staging as revision 1 with a documented approver and publication timestamp.
- [ ] Test content parity across all existing routes, search, lists, detail pages, metadata, and empty states.
- [ ] Ensure public provider state contains only the published payload; create a separate authorized CMS query/context for drafts.
- [ ] Keep JSON export as an explicit administrator/editor capability according to policy, not an unauthenticated endpoint.
- [ ] Implement safe error states, retry behavior, optimistic concurrency conflicts, and loading states without layout-wide redesign.
- [ ] Verify no fallback silently publishes stale localStorage content when the backend is unavailable.

**Exit gate:** all public routes render the published staging snapshot with content parity; schema/service tests pass; no draft can be obtained from the public service; existing layout comparisons show no unexplained regressions.

## 6. Phase 3 — Authentication, roles and publishing experience

**Goal:** secure the CMS and introduce drafts/review/publishing in incremental UI changes.

### New files expected

| Path | Purpose |
|---|---|
| src/features/auth/AuthProvider.tsx (or existing src/auth/ convention if established) | Observe authenticated session and profile/role state |
| src/features/auth/ProtectedRoute.tsx | Client-side redirect and loading/error UI for protected pages; never the security boundary |
| src/features/auth/LoginPage.tsx | Invitation-only CMS sign-in flow |
| src/features/cms/components/DraftStatusBadge.tsx | Accessible status display |
| src/features/cms/components/RevisionHistory.tsx | Revision/history view |
| src/features/cms/components/ReviewActions.tsx | Submit, request changes, approve/publish controls gated by server result and role |
| src/features/cms/components/UnsavedChangesGuard.tsx | Warn before leaving a dirty draft, if supported cleanly |
| tests/e2e/cms-auth-publishing.spec.ts | End-to-end role and publishing cases |

Create components only when useful; do not split files for the sake of matching this exact tree if the existing conventions make a smaller patch safer.

### Existing files expected to be touched

| File | Planned change | Notes |
|---|---|---|
| src/App.tsx | Register login route and wrap only the CMS route with authentication/role checks | Preserve all existing public route paths and nesting |
| src/pages/AdminPage.tsx | Incrementally add draft status, save/submission state, review actions and revision context | Preserve existing editor fields and layout; split sections only to reduce risk |
| src/content/SiteContentProvider.tsx | Connect authorized CMS session/draft state to auth lifecycle | Public and private state boundaries stay separate |
| src/content/siteContentStore.ts | Dispatch service operations and expose explicit pending/success/conflict/error states | Remove production reliance on localStorage as content authority |
| src/types.ts | Add narrow domain types for roles, revisions, status and typed errors | Keep the existing SiteContent contract stable |
| README.md | Replace the current statement that /admin can be opened locally by the real invite/auth flow | Explain setup without secrets |

### Workflow rules to implement

1. Editor creates a draft from the currently published revision.
2. Editor makes changes, saves using an expected version, and can preview the draft privately.
3. Editor submits it for review, preventing further edits until it is returned or a new revision is created.
4. Publisher/admin reviews it and either requests changes or approves publication.
5. Publishing re-validates the full payload and atomically switches the public pointer.
6. Public pages see the new revision after successful publication; not before.
7. A failed publish leaves the old published revision live.
8. An outdated edit produces a conflict and preserves the latest saved revision.
9. Role deactivation or removal revokes access at the backend even if the client remains open.
10. UI messages must reflect backend responses; no optimistic success that can be mistaken for a saved/published state.

**Exit gate:** editor/publisher/admin end-to-end scenarios pass; direct backend tests enforce the same permissions; self-approval is denied by default; public content never changes from an unapproved edit.

## 7. Phase 4 — Forms, media and external links

**Goal:** make submissions operational and private without disrupting public form styling.

### New files expected

| Path | Purpose |
|---|---|
| supabase/functions/submit-public-form/index.ts | Validate allowlisted form type/fields, apply anti-spam/rate controls, persist and dispatch |
| supabase/functions/admin-invite-user/index.ts | If the built-in invitation flow requires trusted server credentials, validate administrator caller before use |
| supabase/functions/process-form-delivery/index.ts (or provider-appropriate worker) | Controlled retries and delivery status, if the selected provider needs it |
| src/integrations/forms/formSubmissionService.ts | Typed frontend submission contract |
| src/integrations/giving/ | Verified external giving destination handling |
| src/integrations/media/ | Media upload/read helpers if uploads are in the approved first release |
| tests/integration/forms.test.ts | Accepted, rejected, duplicate, throttled and delivery-failure cases |

### Existing files expected to be touched

| File | Planned change |
|---|---|
| src/components/ExternalForm.tsx | Keep presentation/styles; submit through the validated service and display reliable pending/success/failure states |
| src/pages/PrayerRequestPage.tsx | Ensure prayer requests use the restricted server-side submission path; avoid logging bodies |
| src/content/siteContent.ts / content validation schema | Keep integration configuration limited to public-safe values; secrets remain server-side |
| src/pages/ContactPage.tsx and any visitor/ministry-interest form owners | Wire to the common submission service while retaining form fields and layout |
| src/pages/GivePage.tsx (only if required) | Verify and replace placeholders with owner-approved hosted giving URL |
| Relevant footer/social/sermon components (only if required) | Verify destination URLs, not restyle them |

### Required actions

- [ ] Agree form-specific recipients and staff access before live submissions are enabled.
- [ ] Add server-side validation, rate control, anti-spam protection, duplicate handling, safe error responses and delivery-state observability.
- [ ] Test email/provider acceptance and actual staff receipt. A successful UI state must mean the backend has accepted the submission; the UI must not claim confirmed email delivery unless that is actually known.
- [ ] Establish retention/deletion and access-review procedures for prayer/contact submissions.
- [ ] Decide media support. If enabled, test file-size/MIME policies and public/private path boundaries.
- [ ] Verify and replace placeholder giving/social/YouTube/map URLs with owner-approved destinations.

**Exit gate:** all enabled forms have been tested end-to-end, recipient permissions and retention are documented, private submissions stay private, and the giving flow uses a verified hosted provider. Any unverified integration remains clearly disabled or marked non-production.

## 8. Phase 5 — Release readiness and cutover

### New files / configuration expected

| Path | Purpose |
|---|---|
| .github/workflows/ci.yml | Install, lint, type-check/build and automated test gates |
| playwright.config.ts and tests/e2e/ | Browser smoke/role/public-route tests if Playwright is selected |
| docs/architecture/OPERATIONS.md | Finalized release, backup, restore, incident and rollback runbook |
| Hosting configuration (provider-specific) | SPA fallback rewrite and environment configuration |

Avoid duplicating CI if the repository already has a workflow. Add to the existing workflow after inspecting it. Choose a test runner only after checking repo conventions and expected maintenance cost.

### Required release checks

- [ ] Clean clone can install and build using committed lockfile.
- [ ] Lint, TypeScript, unit, database/RLS integration and end-to-end checks pass.
- [ ] Browser-route direct loads and refresh work for all nested routes.
- [ ] Every current public route has content parity and responsive visual regression review.
- [ ] Keyboard navigation, accessible labels, loading/error feedback and mobile form use are checked.
- [ ] Two invited CMS users on separate devices see shared published content and authorized shared drafts according to role.
- [ ] A failed network/save/review/publish operation does not show false success or erase user changes.
- [ ] Anonymous access and negative role/security tests pass against staging.
- [ ] Backup and restoration are demonstrated on the selected service; RPO/RTO expectations are agreed rather than assumed.
- [ ] Form submissions, delivery failures/retries, privacy permissions and cleanup have been tested.
- [ ] Public giving link and external CTAs are verified by the owner.
- [ ] Production environment values and SPA rewrites are reviewed without publishing secrets.
- [ ] Content freeze/import reconciliation is complete; initial published revision is backed up and recorded.
- [ ] Rollback is rehearsed: previous frontend deployment restored if needed and prior content revision republished by authorized operator.
- [ ] Owner signs off on production cutover and a post-release verification checklist.

**Exit gate:** explicit production approval; no unresolved critical/high security findings; recovery and rollback path proven; design/content acceptance signed off.

## 9. Migration and data-preservation checklist

### Before switching any frontend consumer
- [ ] Archive baseline source commit SHA and build/lint outputs.
- [ ] Export current content JSON from every relevant browser, with date and editor label.
- [ ] Compare each export against the repository seed and resolve conflicting values with the content owner.
- [ ] Store a checksum and read-only copy of the approved import artifact in the team's secure project records (not public Git if it contains personal data).
- [ ] Seed staging and compare rendered pages against the baseline.
- [ ] Confirm no private form submissions or unnecessary personal data are included in content seed files.

### Before production cutover
- [ ] Pause CMS editing for the final reconciliation window.
- [ ] Export final browser-local state and compare against the staging import.
- [ ] Have the content owner approve the exact revision to publish.
- [ ] Record the current deployment revision and current backend publication revision.
- [ ] Confirm production migrations are the reviewed migrations tested in staging.
- [ ] Confirm only the current published revision is public.
- [ ] Run post-deploy route/form/auth smoke tests.
- [ ] Verify monitoring, alert destination, backup configuration and rollback operator access.

### Rollback
- [ ] Restore the previous static frontend release without reverting the database schema blindly.
- [ ] Republish a known-good content revision through the authorized workflow if content needs rollback.
- [ ] Preserve audit/history and investigate failed operations before retrying.
- [ ] If schema rollback is not safely reversible, use a forward fix or restore into a controlled recovery environment; never drop data simply to restore the UI.
- [ ] Reconcile any changes submitted during an incident before reopening editing.

## 10. Acceptance criteria

The migration is accepted only when all the following are demonstrated:

1. Two authorized administrators/editors using separate devices work against one shared source of truth.
2. Public visitors cannot write CMS content or access drafts, roles, audit details, or private submissions.
3. Editors cannot publish or grant roles; publishers can publish but cannot administer roles.
4. By default, an editor cannot approve their own revision.
5. Public content is unchanged until an authorized publisher confirms publishing.
6. Every content write has an authoritative success/error result; stale writes are rejected without lost updates.
7. Current routes, search, metadata, details, navigation, mobile layout and content are preserved.
8. Public forms are validated, delivered to verified recipients, and have meaningful failure behavior.
9. Prayer-request access and retention are explicit and tested.
10. No backend/provider secret is present in the client bundle or repository.
11. CI tests and direct route-refresh checks pass.
12. Backup restoration, rollback and production ownership are proven.

## 11. Review checklist and approval record

Mark an item complete only after the named owner has reviewed and recorded the decision.

- [ ] **Architecture:** approve Supabase managed Auth/Postgres/RLS/Storage/functions; no separate Node.js API in the first release.
- [ ] **Content model:** approve a full validated versioned SiteContent JSONB snapshot for the first migration, with revision metadata in relational tables.
- [ ] **Workflow:** approve editor → in review → publisher decision, with self-approval denied by default.
- [ ] **Privacy:** approve recipients, access model and retention/deletion procedure for prayer/contact submissions.
- [ ] **Hosting:** identify static frontend host, environment owners and SPA rewrite configuration.
- [ ] **Integrations:** identify verified form delivery provider, giving URL and social destinations.
- [ ] **Operations:** name primary/backup administrator, backup owner, rollback operator and incident contact.
- [ ] **Release gate:** approve the test, content-parity, security and restore criteria above.

**Architecture approval:** Pending  
**Phase 1 authorization:** Blocked until approval  
**Application changes made by this document change:** None

When the plan is reviewed, update this file with the decision date, reviewer/role (not private credentials), accepted exceptions and the commit/PR reference. Only then begin Phase 0/Phase 1 implementation work under the approved sequence.
