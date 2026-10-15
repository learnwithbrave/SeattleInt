# SeattleInt CMS Foundation — Operations Runbook

**Status:** Initial Phase 1 runbook; hosted deployment is not configured by this document.  
**Scope:** Local Supabase development, migration review, initial administrator bootstrap, and safe remote application.

## 1. Requirements and safety

Install a currently supported Node.js/npm version, Docker-compatible runtime, and Supabase CLI. This repository uses React/Vite; Phase 1 database work does not change its runtime application or connect the frontend to Supabase.

Do not provision or migrate production until the church/project owner confirms the Supabase organization/project, deployment owner, authorized administrator, and recovery requirements. Use a disposable local database and a dedicated staging project first.

**Never run supabase db reset --linked against production.** That command is destructive: it resets the linked database. Do not use a production connection string for local tests.

## 2. Local database workflow

From the repository root:

1. Start the local Supabase stack:

   ~~~sh
   supabase start
   ~~~

2. Confirm the CLI reports local API, database, Studio and other service addresses. Do not commit local credentials or .temp files.
3. Apply migrations and reset the local database only:

   ~~~sh
   supabase db reset --local --yes
   ~~~

   This is expected to destroy and recreate the local database from the committed migrations and seed. Check the active target before every destructive command.
4. The committed local seed enables pgTAP in the `extensions` schema. The `supabase db reset --local --yes` step above runs the migration and seed. Confirm pgTAP is available to the test runner; do not expose the extensions schema through the public Data API. If running the test suite outside this local reset workflow, enable pgTAP explicitly in that disposable test database.
5. Run database tests:

   ~~~sh
   supabase test db
   ~~~

6. Stop the local stack when finished:

   ~~~sh
   supabase stop
   ~~~

The current source-inspection runner did not have Docker, the Supabase CLI, or psql available and could not resolve github.com. These commands and SQL have therefore **not been executed in that environment**. Run them in a Supabase-capable development machine or CI before accepting the migration.

## 3. What the first migration creates

The migration creates the initial CMS profile and role tables, versioned content revision table, current-publication pointer, audit table, private public-form submissions table, media metadata table, RLS, explicit table grants, and server-side functions for:
- returning only the current published payload to visitors;
- reading publication metadata for publisher/administrator users;
- creating drafts from current published content;
- saving drafts with optimistic concurrency;
- submitting drafts for review;
- requesting changes;
- atomically publishing an approved-in-review revision;
- assigning/removing roles and activating/deactivating CMS users.

No content snapshot is published by Phase 1. Until Phase 2 imports approved content and creates the site_publication row, the public content RPC returns NULL; the existing frontend does not use this RPC yet.

The submission table has no direct browser read/write grants. A validated Edge Function/service and a restricted staff access workflow are required before any live form should write there. The media table is metadata only; no Storage bucket is created in this phase.

## 4. Initial administrator bootstrap (operator-controlled)

There is intentionally no anonymous or self-service role escalation. The profile trigger creates a profile row when Supabase Auth creates a user. To provision the first administrator:

1. In the selected **staging** Supabase Dashboard, invite the named administrator through Authentication / Users. Confirm the invited email belongs to an authorized operator.
2. After the user exists in auth.users, copy the account UUID from the dashboard. Do not put the UUID or email into a committed seed file.
3. In the Dashboard SQL Editor, run the following template after replacing REPLACE_WITH_AUTH_USER_UUID with that verified UUID. The statement aborts if the profile is absent or inactive.

   ~~~sql
   begin;

   do $bootstrap$
   declare
     first_admin uuid := 'REPLACE_WITH_AUTH_USER_UUID'::uuid;
   begin
     if not exists (
       select 1
       from public.cms_profiles
       where user_id = first_admin and active
     ) then
       raise exception 'Target must be an existing active CMS profile';
     end if;

     insert into public.cms_user_roles (user_id, role, assigned_by)
     values (first_admin, 'administrator', null)
     on conflict (user_id, role) do nothing;

     insert into public.cms_audit_logs (actor_user_id, action, metadata)
     values (
       null,
       'initial_admin_bootstrap',
       jsonb_build_object('target_user_id', first_admin, 'method', 'operator_sql')
     );
   end;
   $bootstrap$;

   commit;
   ~~~

4. Verify the role is present and the administrator can sign in. Record the operator and date in the team's secured operations record. Do not record credentials or invite tokens.
5. Repeat for a backup administrator before production. The role/deactivation functions prevent ordinary operations from removing or deactivating the last active administrator.

This is a privileged database operation. Run it only as the trusted database operator. It is not a user-facing app feature, and must not be exposed through a browser.

## 5. First published content snapshot

Do not create a production snapshot by copying arbitrary browser localStorage or the first default sample that happens to be available.

Phase 0 must reconcile local exports with src/content/siteContent.ts and obtain approval from the content owner. Phase 2 will add the full runtime schema and controlled import path, then insert the selected content revision and publication pointer in staging. Record the seed revision/approval metadata and compare every current public route before production cutover.

No actual church contact, giving or form destination is verified by Phase 1. Do not enable live submissions until the correct recipients, privacy access and retention/deletion procedure are approved.

## 6. Remote staging migration

Only after local SQL validation and test review:

1. Create a new, dedicated staging project from the church owner's Supabase organization.
2. Protect project access with MFA and least-privilege collaborator access.
3. Record its project reference in the team's private operations record; do not commit access tokens.
4. Authenticate with the Supabase CLI interactively, then link to staging only:

   ~~~sh
   supabase login
   supabase link --project-ref YOUR_STAGING_PROJECT_REF
   supabase migration list --linked
   ~~~

5. Check the linked project reference and migration history. Confirm it is the intended staging project.
6. Apply versioned migrations with the non-reset migration workflow:

   ~~~sh
   supabase db push --linked
   ~~~

7. Run database/security checks against staging using the supported CLI test command and/or the CI test database URL. Run tests that mutate test data inside a transaction and use dedicated test identities.
8. Verify policies/functions in SQL and confirm no direct public table access. Do not seed production users or private submissions.

Do not run db push until the migration is reviewed and verified against local PostgreSQL. The current implementation branch has not applied this migration to a hosted project.

## 7. Secret handling

- Browser: the future VITE_SUPABASE_URL and VITE_SUPABASE_PUBLISHABLE_KEY values are public configuration. Publishable keys may appear in the bundle; RLS still must make unauthorized operations fail.
- Server / Edge Functions: any Supabase secret key, email-provider key, anti-spam secret, or other credential lives in Supabase secrets or the deployment provider's secret store.
- Never prefix server secrets with VITE_.
- Never place live credentials in supabase/seed.sql, GitHub Actions logs, screenshots, or issue comments.
- Use separate credentials/projects for local, staging, and production; rotate credentials if exposed.

The project’s current frontend is not wired to the placeholder values in .env.example. Do not add live keys until Phase 2 creates the client service and the owner chooses environments.

## 8. Rollback and incident response

Phase 1 does not switch the live frontend or publish a content snapshot. If a local migration fails, fix the migration on the feature branch and reset only the local database. Do not edit an applied migration in a shared environment; create a new forward migration.

For remote staging errors, stop application rollout, preserve logs that do not contain personal content, inspect migration history and use a reviewed forward fix. Do not drop production data to restore an application release. Backup/restore and content rollback must be rehearsed before cutover.

## 9. Phase 1 validation checklist

- [ ] Supabase CLI version and local database version recorded.
- [ ] Migration applies from an empty local database.
- [ ] supabase test db passes every pgTAP assertion.
- [ ] RLS and direct table grants verified against anon and authenticated.
- [ ] Workflow function tests cover draft ownership, role enforcement, stale version rejection, self-approval rejection, stale publication rejection, and administrator last-admin protection.
- [ ] Static security review confirms every SECURITY DEFINER function sets a safe search_path, checks the caller, has explicit execute grants, and returns minimum data.
- [ ] First administrator is bootstrapped only via trusted operator action in staging, with a backup administrator named.
- [ ] No live service has been provisioned by this documentation or feature branch.
- [ ] Existing frontend and main remain unchanged until a separate reviewed PR is accepted.

**Phase 1 implementation status:** SQL/config/test scaffolding is committed to an isolated branch. Execution and hosted application remain pending until local tests run and an owner-controlled staging environment is available.
