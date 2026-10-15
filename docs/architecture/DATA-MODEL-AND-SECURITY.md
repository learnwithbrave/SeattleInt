# Data Model, Authorization, and Security Specification

**Status:** Proposed for review  
**Applies to:** SeattleInt CMS migration  
**Companion document:** [Architecture decision](README.md)

## 1. Design constraints

The existing application treats the whole website as a typed SiteContent object. The first backend migration should preserve that contract while adding shared storage, draft review, publishing, and auditability. Versioned JSONB snapshots are the initial content representation; this is not a commitment to keep every future feature in JSONB indefinitely.

Use PostgreSQL constraints and row-level security as defense in depth. A frontend role guard improves the user experience but is never an authorization boundary. Supabase's browser publishable/anon key is not a secret; its safety depends on narrow grants and correctly tested RLS. The service-role key bypasses RLS and must remain server-side.

## 2. Initial tables

Names below are proposed names. The migration author should apply consistent snake_case and create them in reviewed, versioned SQL migrations.

### 2.1 cms_profiles

| Column | Type / rule | Purpose |
|---|---|---|
| user_id | uuid, primary key, references auth.users(id) on delete cascade | Auth identity |
| display_name | text, nullable, bounded length | CMS display name |
| active | boolean, not null, default true | Disable CMS access without deleting history |
| created_at | timestamptz, not null, default now() | Creation time |
| updated_at | timestamptz, not null, default now() | Update time |

Do not store role as a user-editable profile column. Profile fields are not trusted claims.

### 2.2 cms_user_roles

| Column | Type / rule | Purpose |
|---|---|---|
| user_id | uuid, references auth.users(id) on delete cascade | Subject |
| role | text or enum constrained to editor, publisher, administrator | CMS role |
| assigned_by | uuid, nullable, references auth.users(id) | Trusted assignment actor |
| assigned_at | timestamptz, not null, default now() | Assignment time |

Primary key: (user_id, role). No browser insert/update/delete grants. Role changes occur through a narrow administrator-only server function or a documented trusted operator procedure. Prevent the last active administrator from accidentally removing their own access.

### 2.3 site_content_revisions

| Column | Type / rule | Purpose |
|---|---|---|
| id | uuid, primary key, generated | Revision identity |
| revision_number | bigint identity, unique, not null | Monotonic audit/order number |
| payload | jsonb, not null, object | Full SiteContent snapshot |
| status | constrained text: draft, in_review, changes_requested, published, archived | Workflow state |
| created_by | uuid, references auth.users(id), not null | Draft owner |
| created_at | timestamptz, not null, default now() | Creation time |
| updated_at | timestamptz, not null, default now() | Last save time |
| base_published_revision_id | uuid, nullable, references site_content_revisions(id) | Published version from which editing began |
| submitted_at | timestamptz, nullable | Review submission time |
| reviewed_by | uuid, nullable, references auth.users(id) | Reviewer/publisher |
| reviewed_at | timestamptz, nullable | Review decision time |
| published_at | timestamptz, nullable | Publication time |
| change_note | text, nullable, bounded length | Human-readable reason for change |
| version | integer, not null, default 1 | Optimistic concurrency token |

Add a check that payload is a JSON object. Enforce allowed status transitions through trusted database functions rather than permitting arbitrary client status changes. Application Zod schema validation must check the complete SiteContent shape and field constraints before save/import; publish functions should reject invalid or structurally incomplete payloads as a second line of defense.

Each draft has an owner. Editors can edit their own draft; publishers/administrators can review drafts. An editor may create a new draft from the current published revision, but must not change a submitted draft until it is returned to changes_requested. An edit uses the expected version number; a mismatch returns a conflict instead of silently overwriting newer data.

### 2.4 site_publication

A singleton row points to the currently published revision.

| Column | Type / rule | Purpose |
|---|---|---|
| singleton_id | integer primary key, check singleton_id = 1 | Exactly one publication pointer |
| revision_id | uuid, not null, references site_content_revisions(id) | Current published content |
| published_by | uuid, references auth.users(id), not null | Publishing actor |
| published_at | timestamptz, not null, default now() | Publication time |

Publishing must update this pointer and the revision statuses in one database transaction. Keep the prior snapshot as archived history so rollback can repoint to a reviewed earlier revision. Prevent deletion of a revision currently referenced by site_publication.

### 2.5 cms_audit_logs

| Column | Type / rule | Purpose |
|---|---|---|
| id | bigint identity primary key | Event identity |
| actor_user_id | uuid, nullable, references auth.users(id) | Actor; nullable for system events |
| action | text, bounded and allowlisted by application | Draft created, submitted, approved, published, etc. |
| target_revision_id | uuid, nullable, references site_content_revisions(id) | Affected revision |
| metadata | jsonb, not null, default '{}' | Non-sensitive context only |
| created_at | timestamptz, not null, default now() | Event time |

CMS roles must not update/delete audit rows. Do not copy prayer-request body text, contact-message contents, access tokens, or credentials into audit metadata. Audit important role changes and form delivery status without logging payload contents.

### 2.6 public_form_submissions

| Column | Type / rule | Purpose |
|---|---|---|
| id | uuid, primary key, generated | Submission identity |
| form_type | constrained text | visitor, contact, prayer_request, ministry_interest |
| submitted_at | timestamptz, not null, default now() | Receipt time |
| status | constrained text | received, processing, delivered, failed, closed |
| payload | jsonb, not null, schema-validated | Form-specific minimum data |
| delivery_attempts | integer, not null, default 0 | Operational retry count |
| last_delivery_error_code | text, nullable, non-sensitive | Diagnostic code only |
| retention_expires_at | timestamptz, nullable | Agreed deletion boundary |

Do not expose this table to anonymous direct reads or writes. The public form service should validate the exact allowlisted form shape, enforce anti-spam/rate controls, and store/dispatch through a controlled server-side workflow. Only explicitly authorized staff should be able to read the corresponding submission type. Prayer requests may require a distinct restricted recipient group instead of access for all CMS administrators. Set retention/deletion rules before production use.

### 2.7 media_assets (when CMS media upload is included)

Store metadata only: id, storage path, original file name with safe bounds, MIME type, byte size, upload actor, created_at, visibility, and optional alt text. Put the bytes in Supabase Storage. Separate public assets from private assets; enforce upload size and MIME allowlists; generate safe public URLs or short-lived signed links as appropriate. Do not trust the file extension or the browser-reported MIME type by itself.

## 3. Database functions and API boundary

Implement and review narrow functions for workflow transitions rather than allowing arbitrary status updates:

- create draft from the current published revision.
- save draft with an expected version / optimistic-lock token.
- submit owned draft for review.
- request changes with a bounded reviewer note.
- approve/publish a revision, requiring publisher or administrator privileges and a different reviewer from the submitting editor by default.
- retrieve the single current published SiteContent payload for public pages.
- invite/deactivate a CMS user and assign/remove roles through trusted administrator-authorized handling.

Every security-definer function must set a fixed safe search_path, fully qualify objects where needed, validate auth.uid() and current roles itself, and return the minimum data required. Revoke execution from public roles unless deliberately needed; grant each function to only the required database roles. A public content retrieval function returns only the current published payload, not historical revisions, draft identifiers, reviewer details, or audit data.

Use an authenticated caller context for ordinary CMS actions so RLS remains meaningful. Edge Functions should validate the caller and input, then call the least-privileged database operation. Use the service-role credential only for server-only tasks that truly require it, such as narrowly scoped invitation/administration logic; any such function must perform an explicit role check before using that credential.

## 4. Authorization matrix

| Resource / operation | Anonymous | Editor | Publisher | Administrator |
|---|---|---|---|---|
| Current published payload | Read through public retrieval function only | Read | Read | Read |
| Drafts | None | Own drafts and eligible review feedback | Review all drafts | Review all drafts |
| Create/edit draft | None | Own draft only | Only if explicitly permitted by policy | Allowed |
| Submit draft | None | Own draft only | Allowed if acting as editor is intentionally enabled | Allowed if policy permits |
| Approve/publish | None | No | Yes, not own submission by default | Yes, not own submission by default |
| Role assignment/invitation | None | None | None | Narrow admin-only function |
| Audit logs | None | No direct writes/updates/deletes | No direct writes/updates/deletes | Read; no editing/deletion through CMS |
| Public form submission | Allowed through validated server endpoint only | Same public endpoint; no bypass | Same | Same |
| Private form submissions | None | Explicit recipient permission only | Explicit recipient permission only | Only where assigned/authorized |
| Storage upload | None | Defined CMS bucket policies | Defined CMS bucket policies | Defined CMS bucket policies |

The exact policy may be stricter than this matrix. Do not grant access merely because a user is authenticated.

## 5. Row-level security expectations

RLS must be enabled and tested on every exposed table. Policies should call a carefully reviewed role helper or narrow database functions. Avoid recursive policy patterns in which policies on cms_user_roles depend on querying themselves under the same RLS context.

Required outcomes:
- Anonymous clients cannot query revision, role, audit, profile, or private form tables directly.
- Anonymous clients can retrieve only the active published payload through the approved public boundary.
- An editor cannot read or mutate another editor's private draft except through explicitly authorized review behavior.
- An editor cannot set their own role, elevate another account, approve/publish, or bypass draft status transitions.
- A publisher cannot assign administrator access.
- Deactivated users and removed roles immediately lose database-authorized CMS access.
- Ordinary CMS roles cannot rewrite audit rows or delete revision history.
- Private submissions and private media are isolated from public reads.
- Every exposed function's execute grant is explicit and covered by negative tests.

Do not treat a UI guard, hidden button, route redirect, localStorage flag, or editable JWT metadata as security enforcement.

## 6. Secrets and configuration

Client-side allowed variables are limited to non-secret endpoint/project configuration and the publishable/anon key. Never prefix server secrets with VITE_. Store service-role, mail delivery, captcha/anti-spam, and other provider secrets in the backend's secret store. Do not commit .env files containing real values.

The .env.example should document names and safe placeholders only. Production and staging must use different projects and separate credentials. Rotate any secret found in Git history or browser output; deleting the current file alone does not remediate leaked credentials.

## 7. Validation and privacy controls

- Validate content structure, URL schemes, lengths, array counts, required text, and supported link protocols at every trust boundary.
- Limit JSON upload/import size and fail atomically; do not partially replace content on validation failure.
- Use expected-version checks for draft writes and a base-published-revision check at publication.
- Apply per-form rate limits and anti-spam measures; return generic user-safe errors and correlate operational failures using a submission ID.
- Avoid storing unnecessary personal details; restrict staff access by ministry/process need and define a retention interval with the church.
- Keep message bodies out of application, edge-function, analytics, and audit logs.
- Test email/provider delivery, retry behavior, duplicate submissions, failure messaging, and deletion workflows.
- Treat giving as an external hosted destination; do not collect or store card details in this system.

## 8. Required security tests before production

1. Unauthenticated direct reads/writes against every private table are denied.
2. Public retrieval returns only the currently published content revision.
3. Editors cannot publish, assign roles, modify other owners' drafts, or read private form submissions without explicit permission.
4. Editors cannot approve their own draft; rejected/changes-requested revisions do not change public content.
5. A stale expected version is rejected with a conflict response and does not lose the newer edit.
6. Publishing is atomic; if any part fails, the publication pointer remains unchanged.
7. Removed/deactivated users cannot perform CMS operations using an old browser session.
8. Invalid JSON, unsupported form types, oversized inputs, and disallowed URLs are rejected.
9. Audit rows are append-only for ordinary CMS users and contain no sensitive submission bodies.
10. Storage rejects disallowed MIME types and excessive file sizes; private assets are not publicly readable.
11. Service-role and provider secrets do not appear in built assets, browser requests, logs, or committed configuration.
12. Public form success is displayed only when the backend accepted the submission; delivery failures remain observable to authorized staff.

## 9. Open decisions to resolve during review

- Who is the designated account/role administrator and backup administrator?
- Which staff members should receive each form type, especially prayer requests?
- What is the approved retention/deletion period for each submission type?
- Which email delivery service and anti-spam provider will be used, and who owns their credentials?
- Is CMS media upload in the first release or will initial media remain managed assets with approved URLs?
- Who owns staging/production deployment, backup monitoring, and incident response?
