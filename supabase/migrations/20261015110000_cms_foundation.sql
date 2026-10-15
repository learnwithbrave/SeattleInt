-- CMS foundation for Seattle International Church.
-- Apply with Supabase CLI migrations; never edit an already-applied migration.
-- Public website content is read through read_published_site_content(), not direct table reads.

create type public.cms_role as enum ('editor', 'publisher', 'administrator');
create type public.content_revision_status as enum (
  'draft',
  'in_review',
  'changes_requested',
  'published',
  'archived'
);
create type public.public_form_type as enum (
  'visitor',
  'contact',
  'prayer_request',
  'ministry_interest'
);
create type public.public_submission_status as enum (
  'received',
  'processing',
  'delivered',
  'failed',
  'closed'
);

create table public.cms_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  display_name text check (display_name is null or char_length(display_name) <= 120),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.cms_user_roles (
  user_id uuid not null references auth.users(id) on delete cascade,
  role public.cms_role not null,
  assigned_by uuid references auth.users(id) on delete set null,
  assigned_at timestamptz not null default now(),
  primary key (user_id, role)
);

create table public.site_content_revisions (
  id uuid primary key default gen_random_uuid(),
  revision_number bigint generated always as identity unique,
  payload jsonb not null
    check (jsonb_typeof(payload) = 'object' and octet_length(payload::text) <= 2097152),
  status public.content_revision_status not null default 'draft',
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  base_published_revision_id uuid references public.site_content_revisions(id) on delete restrict,
  submitted_by uuid references auth.users(id),
  submitted_at timestamptz,
  reviewed_by uuid references auth.users(id),
  reviewed_at timestamptz,
  published_at timestamptz,
  change_note text check (change_note is null or char_length(change_note) <= 2000),
  version integer not null default 1 check (version > 0)
);

create index site_content_revisions_created_by_idx
  on public.site_content_revisions (created_by, created_at desc);
create index site_content_revisions_status_created_idx
  on public.site_content_revisions (status, created_at desc);

create table public.site_publication (
  singleton_id integer primary key check (singleton_id = 1),
  revision_id uuid not null references public.site_content_revisions(id) on delete restrict,
  published_by uuid not null references auth.users(id),
  published_at timestamptz not null default now()
);

create table public.cms_audit_logs (
  id bigint generated always as identity primary key,
  actor_user_id uuid references auth.users(id) on delete set null,
  action text not null check (char_length(action) between 1 and 100),
  target_revision_id uuid references public.site_content_revisions(id) on delete set null,
  metadata jsonb not null default '{}'::jsonb
    check (jsonb_typeof(metadata) = 'object' and octet_length(metadata::text) <= 16384),
  created_at timestamptz not null default now()
);
create index cms_audit_logs_created_at_idx
  on public.cms_audit_logs (created_at desc);
create index cms_audit_logs_actor_created_idx
  on public.cms_audit_logs (actor_user_id, created_at desc);

-- Form submissions have no anonymous/authenticated table grants. A later server-side
-- submission function must validate and write these records, with restricted staff access.
create table public.public_form_submissions (
  id uuid primary key default gen_random_uuid(),
  form_type public.public_form_type not null,
  submitted_at timestamptz not null default now(),
  status public.public_submission_status not null default 'received',
  payload jsonb not null check (jsonb_typeof(payload) = 'object'),
  delivery_attempts integer not null default 0 check (delivery_attempts >= 0),
  last_delivery_error_code text check (
    last_delivery_error_code is null or char_length(last_delivery_error_code) <= 100
  ),
  retention_expires_at timestamptz
);
create index public_form_submissions_status_submitted_idx
  on public.public_form_submissions (status, submitted_at);

-- This only tracks metadata. The Storage bucket and public/private asset policy are
-- deliberately deferred until the owner confirms whether CMS uploads are in scope.
create table public.media_assets (
  id uuid primary key default gen_random_uuid(),
  storage_path text not null unique check (char_length(storage_path) between 1 and 1024),
  original_file_name text not null check (char_length(original_file_name) between 1 and 255),
  mime_type text not null check (char_length(mime_type) between 1 and 120),
  byte_size bigint not null check (byte_size > 0 and byte_size <= 20971520),
  is_public boolean not null default false,
  alt_text text check (alt_text is null or char_length(alt_text) <= 500),
  uploaded_by uuid not null references auth.users(id),
  created_at timestamptz not null default now()
);

-- Every table is RLS-protected. No write policies are defined for direct browser writes:
-- controlled functions below own state transitions and record audit events.
alter table public.cms_profiles enable row level security;
alter table public.cms_user_roles enable row level security;
alter table public.site_content_revisions enable row level security;
alter table public.site_publication enable row level security;
alter table public.cms_audit_logs enable row level security;
alter table public.public_form_submissions enable row level security;
alter table public.media_assets enable row level security;

create or replace function public.has_cms_role(required_roles public.cms_role[])
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.cms_user_roles as role_row
    join public.cms_profiles as profile_row on profile_row.user_id = role_row.user_id
    where role_row.user_id = auth.uid()
      and profile_row.active
      and role_row.role = any (required_roles)
  );
$$;

-- Database-side structural guard. Full field validation (including URL allowlists and
-- nested values) must also run in the application runtime schema and before publication.
create or replace function public.is_valid_site_content_payload(candidate jsonb)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select coalesce(
    jsonb_typeof(candidate) = 'object'
    and jsonb_typeof(candidate -> 'site') = 'object'
    and jsonb_typeof(candidate #> '{site,name}') = 'string'
    and char_length(btrim(candidate #>> '{site,name}')) between 1 and 200
    and jsonb_typeof(candidate -> 'pageSummaries') = 'array'
    and jsonb_typeof(candidate -> 'about') = 'object'
    and jsonb_typeof(candidate -> 'visitHighlights') = 'array'
    and jsonb_typeof(candidate -> 'leaders') = 'array'
    and jsonb_typeof(candidate -> 'ministries') = 'array'
    and jsonb_typeof(candidate -> 'sermons') = 'array'
    and jsonb_typeof(candidate -> 'events') = 'array'
    and jsonb_typeof(candidate -> 'giving') = 'object'
    and jsonb_typeof(candidate #> '{giving,options}') = 'array'
    and jsonb_typeof(candidate #> '{giving,faqs}') = 'array'
    and jsonb_typeof(candidate -> 'forms') = 'object'
    and (candidate -> 'forms') ?& array['visitor', 'contact', 'prayer', 'ministryJoin']
    and jsonb_typeof(candidate #> '{forms,visitor}') = 'object'
    and jsonb_typeof(candidate #> '{forms,contact}') = 'object'
    and jsonb_typeof(candidate #> '{forms,prayer}') = 'object'
    and jsonb_typeof(candidate #> '{forms,ministryJoin}') = 'object'
    and octet_length(candidate::text) <= 2097152,
    false
  );
$$;

create or replace function public.handle_new_cms_profile()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.cms_profiles (user_id, display_name)
  values (
    new.id,
    left(coalesce(new.raw_user_meta_data ->> 'full_name', new.raw_user_meta_data ->> 'name', ''), 120)
  )
  on conflict (user_id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created_cms_profile on auth.users;
create trigger on_auth_user_created_cms_profile
  after insert on auth.users
  for each row execute function public.handle_new_cms_profile();

-- Profile / role reads are limited to the active user's own rows and administrators.
create policy cms_profiles_read_self_or_admin
  on public.cms_profiles for select to authenticated
  using (user_id = (select auth.uid()) or public.has_cms_role(array['administrator']::public.cms_role[]));

create policy cms_user_roles_read_self_or_admin
  on public.cms_user_roles for select to authenticated
  using (user_id = (select auth.uid()) or public.has_cms_role(array['administrator']::public.cms_role[]));

create policy revisions_read_owned_or_reviewer
  on public.site_content_revisions for select to authenticated
  using (
    created_by = (select auth.uid())
    or public.has_cms_role(array['publisher', 'administrator']::public.cms_role[])
  );

create policy audit_read_publisher_or_admin
  on public.cms_audit_logs for select to authenticated
  using (public.has_cms_role(array['publisher', 'administrator']::public.cms_role[]));

-- No policies are intentionally defined for publication, form submissions, or media assets.
-- Their underlying tables have no direct browser grants; use narrowly scoped functions.

-- Remove ambient access and re-grant exactly what the client needs.
revoke all on public.cms_profiles from public, anon, authenticated;
revoke all on public.cms_user_roles from public, anon, authenticated;
revoke all on public.site_content_revisions from public, anon, authenticated;
revoke all on public.site_publication from public, anon, authenticated;
revoke all on public.cms_audit_logs from public, anon, authenticated;
revoke all on public.public_form_submissions from public, anon, authenticated;
revoke all on public.media_assets from public, anon, authenticated;

grant usage on schema public to anon, authenticated;
grant select on public.cms_profiles, public.cms_user_roles, public.site_content_revisions,
  public.cms_audit_logs to authenticated;

revoke all on function public.has_cms_role(public.cms_role[]) from public, anon;
grant execute on function public.has_cms_role(public.cms_role[]) to authenticated;
revoke all on function public.is_valid_site_content_payload(jsonb) from public, anon, authenticated;
revoke all on function public.handle_new_cms_profile() from public, anon, authenticated;

create or replace function public.read_published_site_content()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select revision.payload
  from public.site_publication as publication
  join public.site_content_revisions as revision
    on revision.id = publication.revision_id
   and revision.status = 'published'
  where publication.singleton_id = 1;
$$;
revoke all on function public.read_published_site_content() from public;
grant execute on function public.read_published_site_content() to anon, authenticated;

create or replace function public.create_site_content_draft()
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  current_revision_id uuid;
  current_payload jsonb;
  new_revision_id uuid;
begin
  if caller_id is null
     or not public.has_cms_role(array['editor', 'administrator']::public.cms_role[]) then
    raise exception using errcode = '42501', message = 'Editor or administrator role required';
  end if;

  select publication.revision_id, revision.payload
    into current_revision_id, current_payload
  from public.site_publication as publication
  join public.site_content_revisions as revision on revision.id = publication.revision_id
  where publication.singleton_id = 1 and revision.status = 'published';

  if current_payload is null then
    raise exception using errcode = '55000', message = 'No published site content is available to draft';
  end if;

  insert into public.site_content_revisions (
    payload, status, created_by, base_published_revision_id
  ) values (
    current_payload, 'draft', caller_id, current_revision_id
  )
  returning id into new_revision_id;

  insert into public.cms_audit_logs (actor_user_id, action, target_revision_id, metadata)
  values (caller_id, 'draft_created', new_revision_id, jsonb_build_object(
    'base_published_revision_id', current_revision_id
  ));

  return new_revision_id;
end;
$$;

create or replace function public.save_site_content_draft(
  revision_id uuid,
  new_payload jsonb,
  expected_version integer,
  note text default null
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  revision_row public.site_content_revisions%rowtype;
  next_version integer;
begin
  if caller_id is null
     or not public.has_cms_role(array['editor', 'administrator']::public.cms_role[]) then
    raise exception using errcode = '42501', message = 'Editor or administrator role required';
  end if;

  if not public.is_valid_site_content_payload(new_payload) then
    raise exception using errcode = '22023', message = 'Site content payload is invalid';
  end if;

  select * into revision_row
  from public.site_content_revisions
  where id = revision_id
  for update;

  if not found
     or (revision_row.created_by <> caller_id
         and not public.has_cms_role(array['administrator']::public.cms_role[])) then
    raise exception using errcode = '42501', message = 'Draft not accessible';
  end if;

  if revision_row.status not in ('draft', 'changes_requested') then
    raise exception using errcode = '55000', message = 'Only editable drafts can be saved';
  end if;

  if revision_row.version is distinct from expected_version then
    raise exception using errcode = '40001', message = 'Draft version conflict; reload before saving';
  end if;

  update public.site_content_revisions
  set payload = new_payload,
      change_note = case when note is null then change_note else left(btrim(note), 2000) end,
      updated_at = now(),
      version = version + 1
  where id = revision_id
  returning version into next_version;

  insert into public.cms_audit_logs (actor_user_id, action, target_revision_id, metadata)
  values (caller_id, 'draft_saved', revision_id, jsonb_build_object('version', next_version));

  return next_version;
end;
$$;

create or replace function public.submit_site_content_for_review(revision_id uuid, expected_version integer)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  revision_row public.site_content_revisions%rowtype;
  next_version integer;
begin
  if caller_id is null
     or not public.has_cms_role(array['editor', 'administrator']::public.cms_role[]) then
    raise exception using errcode = '42501', message = 'Editor or administrator role required';
  end if;

  select * into revision_row
  from public.site_content_revisions
  where id = revision_id
  for update;

  if not found or revision_row.created_by <> caller_id then
    raise exception using errcode = '42501', message = 'Only the draft owner can submit this draft';
  end if;
  if revision_row.status not in ('draft', 'changes_requested') then
    raise exception using errcode = '55000', message = 'Draft is not ready for submission';
  end if;
  if revision_row.version is distinct from expected_version then
    raise exception using errcode = '40001', message = 'Draft version conflict; reload before submitting';
  end if;
  if not public.is_valid_site_content_payload(revision_row.payload) then
    raise exception using errcode = '22023', message = 'Site content payload is invalid';
  end if;

  update public.site_content_revisions
  set status = 'in_review',
      submitted_by = caller_id,
      submitted_at = now(),
      reviewed_by = null,
      reviewed_at = null,
      updated_at = now(),
      version = version + 1
  where id = revision_id
  returning version into next_version;

  insert into public.cms_audit_logs (actor_user_id, action, target_revision_id, metadata)
  values (caller_id, 'draft_submitted', revision_id, jsonb_build_object('version', next_version));

  return next_version;
end;
$$;

create or replace function public.request_site_content_changes(revision_id uuid, note text)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  revision_row public.site_content_revisions%rowtype;
  next_version integer;
  reviewer_note text := left(btrim(coalesce(note, '')), 2000);
begin
  if caller_id is null
     or not public.has_cms_role(array['publisher', 'administrator']::public.cms_role[]) then
    raise exception using errcode = '42501', message = 'Publisher or administrator role required';
  end if;
  if reviewer_note = '' then
    raise exception using errcode = '22023', message = 'A review note is required';
  end if;

  select * into revision_row
  from public.site_content_revisions
  where id = revision_id
  for update;

  if not found or revision_row.status <> 'in_review' then
    raise exception using errcode = '55000', message = 'Revision is not awaiting review';
  end if;
  if revision_row.submitted_by = caller_id then
    raise exception using errcode = '42501', message = 'A submitter cannot review their own revision';
  end if;

  update public.site_content_revisions
  set status = 'changes_requested',
      change_note = reviewer_note,
      reviewed_by = caller_id,
      reviewed_at = now(),
      updated_at = now(),
      version = version + 1
  where id = revision_id
  returning version into next_version;

  insert into public.cms_audit_logs (actor_user_id, action, target_revision_id, metadata)
  values (caller_id, 'changes_requested', revision_id, jsonb_build_object('note', reviewer_note));

  return next_version;
end;
$$;

create or replace function public.publish_site_content_revision(
  revision_id uuid,
  expected_current_revision_id uuid,
  note text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  revision_row public.site_content_revisions%rowtype;
  current_revision_id uuid;
  previous_revision_id uuid;
  publication_time timestamptz := now();
begin
  if caller_id is null
     or not public.has_cms_role(array['publisher', 'administrator']::public.cms_role[]) then
    raise exception using errcode = '42501', message = 'Publisher or administrator role required';
  end if;

  select publication.revision_id into current_revision_id
  from public.site_publication as publication
  where publication.singleton_id = 1
  for update;

  if current_revision_id is distinct from expected_current_revision_id then
    raise exception using errcode = '40001', message = 'Published revision changed; reload before publishing';
  end if;

  select * into revision_row
  from public.site_content_revisions
  where id = revision_id
  for update;

  if not found or revision_row.status <> 'in_review' then
    raise exception using errcode = '55000', message = 'Revision is not awaiting review';
  end if;
  if revision_row.submitted_by is null or revision_row.submitted_by = caller_id then
    raise exception using errcode = '42501', message = 'A submitter cannot publish their own revision';
  end if;
  if revision_row.base_published_revision_id is distinct from current_revision_id then
    raise exception using errcode = '40001', message = 'Draft is based on an older publication; rebase and resubmit';
  end if;
  if not public.is_valid_site_content_payload(revision_row.payload) then
    raise exception using errcode = '22023', message = 'Site content payload is invalid';
  end if;

  previous_revision_id := current_revision_id;

  if previous_revision_id is not null then
    update public.site_content_revisions
    set status = 'archived', updated_at = publication_time, version = version + 1
    where id = previous_revision_id;
  end if;

  update public.site_content_revisions
  set status = 'published',
      reviewed_by = caller_id,
      reviewed_at = publication_time,
      published_at = publication_time,
      updated_at = publication_time,
      change_note = case when note is null then change_note else left(btrim(note), 2000) end,
      version = version + 1
  where id = revision_id;

  insert into public.site_publication (singleton_id, revision_id, published_by, published_at)
  values (1, revision_id, caller_id, publication_time)
  on conflict (singleton_id) do update
    set revision_id = excluded.revision_id,
        published_by = excluded.published_by,
        published_at = excluded.published_at;

  insert into public.cms_audit_logs (actor_user_id, action, target_revision_id, metadata)
  values (caller_id, 'content_published', revision_id, jsonb_build_object(
    'previous_revision_id', previous_revision_id,
    'published_revision_id', revision_id,
    'note', case when note is null then '' else left(btrim(note), 2000) end
  ));

  return revision_id;
end;
$$;

create or replace function public.admin_set_cms_role(
  target_user_id uuid,
  target_role public.cms_role,
  should_grant boolean
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  target_active boolean;
  affected_count integer;
  active_admin_count integer;
begin
  -- Serialize administrator membership changes so concurrent requests cannot remove the last admin.
  perform pg_catalog.pg_advisory_xact_lock(1420493334);
  if caller_id is null
     or not public.has_cms_role(array['administrator']::public.cms_role[]) then
    raise exception using errcode = '42501', message = 'Administrator role required';
  end if;
  if target_role is null then
    raise exception using errcode = '22023', message = 'Role is required';
  end if;

  select active into target_active
  from public.cms_profiles
  where user_id = target_user_id
  for update;

  if not found then
    raise exception using errcode = '22023', message = 'Target CMS profile not found';
  end if;

  if should_grant and not target_active then
    raise exception using errcode = '55000', message = 'Cannot grant CMS role to an inactive user';
  end if;

  if not should_grant and target_role = 'administrator' then
    select count(*) into active_admin_count
    from public.cms_user_roles as role_row
    join public.cms_profiles as profile_row on profile_row.user_id = role_row.user_id
    where role_row.role = 'administrator' and profile_row.active;

    if active_admin_count <= 1 and exists (
      select 1 from public.cms_user_roles
      where user_id = target_user_id and role = 'administrator'
    ) then
      raise exception using errcode = '55000', message = 'Cannot remove the last active administrator';
    end if;
  end if;

  if should_grant then
    insert into public.cms_user_roles (user_id, role, assigned_by)
    values (target_user_id, target_role, caller_id)
    on conflict (user_id, role) do nothing;
    get diagnostics affected_count = row_count;
  else
    delete from public.cms_user_roles
    where user_id = target_user_id and role = target_role;
    get diagnostics affected_count = row_count;
  end if;

  if affected_count > 0 then
    insert into public.cms_audit_logs (actor_user_id, action, metadata)
    values (caller_id, case when should_grant then 'cms_role_granted' else 'cms_role_removed' end,
      jsonb_build_object('target_user_id', target_user_id, 'role', target_role));
  end if;
end;
$$;

create or replace function public.admin_set_cms_user_active(target_user_id uuid, should_be_active boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  currently_active boolean;
  target_is_admin boolean;
  active_admin_count integer;
begin
  -- Use the same lock as role membership changes to serialize last-admin safety checks.
  perform pg_catalog.pg_advisory_xact_lock(1420493334);
  if caller_id is null
     or not public.has_cms_role(array['administrator']::public.cms_role[]) then
    raise exception using errcode = '42501', message = 'Administrator role required';
  end if;
  if caller_id = target_user_id and not should_be_active then
    raise exception using errcode = '55000', message = 'Administrators cannot deactivate their own account';
  end if;

  select active into currently_active
  from public.cms_profiles
  where user_id = target_user_id
  for update;

  if not found then
    raise exception using errcode = '22023', message = 'Target CMS profile not found';
  end if;

  if currently_active = should_be_active then
    return;
  end if;

  select exists (
    select 1 from public.cms_user_roles
    where user_id = target_user_id and role = 'administrator'
  ) into target_is_admin;

  if target_is_admin and not should_be_active then
    select count(*) into active_admin_count
    from public.cms_user_roles as role_row
    join public.cms_profiles as profile_row on profile_row.user_id = role_row.user_id
    where role_row.role = 'administrator' and profile_row.active;

    if active_admin_count <= 1 then
      raise exception using errcode = '55000', message = 'Cannot deactivate the last active administrator';
    end if;
  end if;

  update public.cms_profiles
  set active = should_be_active, updated_at = now()
  where user_id = target_user_id;

  insert into public.cms_audit_logs (actor_user_id, action, metadata)
  values (caller_id, case when should_be_active then 'cms_user_activated' else 'cms_user_deactivated' end,
    jsonb_build_object('target_user_id', target_user_id));
end;
$$;

-- These security-definer operations are not callable by anonymous clients.


create or replace function public.read_site_publication_state()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  publication_row public.site_publication%rowtype;
begin
  if caller_id is null
     or not public.has_cms_role(array['publisher', 'administrator']::public.cms_role[]) then
    raise exception using errcode = '42501', message = 'Publisher or administrator role required';
  end if;

  select * into publication_row
  from public.site_publication
  where singleton_id = 1;

  if not found then
    return null;
  end if;

  return jsonb_build_object(
    'revision_id', publication_row.revision_id,
    'published_by', publication_row.published_by,
    'published_at', publication_row.published_at
  );
end;
$$;
revoke all on function public.read_site_publication_state() from public, anon;
grant execute on function public.read_site_publication_state() to authenticated;

revoke all on function public.create_site_content_draft() from public, anon;
revoke all on function public.save_site_content_draft(uuid, jsonb, integer, text) from public, anon;
revoke all on function public.submit_site_content_for_review(uuid, integer) from public, anon;
revoke all on function public.request_site_content_changes(uuid, text) from public, anon;
revoke all on function public.publish_site_content_revision(uuid, uuid, text) from public, anon;
revoke all on function public.admin_set_cms_role(uuid, public.cms_role, boolean) from public, anon;
revoke all on function public.admin_set_cms_user_active(uuid, boolean) from public, anon;

grant execute on function public.create_site_content_draft() to authenticated;
grant execute on function public.save_site_content_draft(uuid, jsonb, integer, text) to authenticated;
grant execute on function public.submit_site_content_for_review(uuid, integer) to authenticated;
grant execute on function public.request_site_content_changes(uuid, text) to authenticated;
grant execute on function public.publish_site_content_revision(uuid, uuid, text) to authenticated;
grant execute on function public.admin_set_cms_role(uuid, public.cms_role, boolean) to authenticated;
grant execute on function public.admin_set_cms_user_active(uuid, boolean) to authenticated;

comment on table public.site_content_revisions is
  'Versioned full SiteContent snapshots. Browser clients may read authorized rows but must write through controlled workflow functions.';
comment on table public.site_publication is
  'Singleton pointer to the only revision exposed to public visitors.';
comment on table public.public_form_submissions is
  'Private, server-written submissions. Never expose message content through public APIs or logs.';
comment on table public.cms_audit_logs is
  'Append-only CMS audit events; ordinary browser roles have no insert, update, or delete grants.';
