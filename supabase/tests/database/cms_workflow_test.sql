begin;

select plan(30);

-- These identities exist only inside this rolled-back test transaction.
insert into auth.users (id, email) values
  ('11111111-1111-4111-8111-111111111111', 'editor1@seattleint.test'),
  ('22222222-2222-4222-8222-222222222222', 'publisher1@seattleint.test'),
  ('33333333-3333-4333-8333-333333333333', 'admin1@seattleint.test');

insert into public.cms_user_roles (user_id, role) values
  ('11111111-1111-4111-8111-111111111111', 'editor'),
  ('22222222-2222-4222-8222-222222222222', 'publisher'),
  ('33333333-3333-4333-8333-333333333333', 'administrator');

create temporary table test_revision_refs (
  label text primary key,
  revision_id uuid not null
) on commit drop;

with inserted_revision as (
  insert into public.site_content_revisions (
    payload, status, created_by, reviewed_by, reviewed_at, published_at
  ) values (
    '{
      "site":{"name":"Original Test Church"},
      "pageSummaries":[],
      "about":{},
      "visitHighlights":[],
      "leaders":[],
      "ministries":[],
      "sermons":[],
      "events":[],
      "giving":{"options":[],"faqs":[]},
      "forms":{"visitor":{},"contact":{},"prayer":{},"ministryJoin":{}}
    }'::jsonb,
    'published',
    '33333333-3333-4333-8333-333333333333',
    '33333333-3333-4333-8333-333333333333',
    now(),
    now()
  )
  returning id
)
insert into test_revision_refs (label, revision_id)
select 'published', id from inserted_revision;

insert into public.site_publication (singleton_id, revision_id, published_by, published_at)
select 1, revision_id, '33333333-3333-4333-8333-333333333333', now()
from test_revision_refs where label = 'published';

select set_config(
  'test.published_id',
  (select revision_id::text from test_revision_refs where label = 'published'),
  true
);

set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-4111-8111-111111111111';

select ok(
  public.has_cms_role(array['editor']::public.cms_role[]),
  'Editor role is resolved from trusted database role assignments'
);

select ok(
  set_config('test.editor_draft_id', public.create_site_content_draft()::text, true) <> '',
  'Editor can create a draft from current published content'
);

select is(
  (select count(*)::integer from public.site_content_revisions
   where id = current_setting('test.editor_draft_id', true)::uuid),
  1,
  'Editor can read their own draft'
);

select is(
  public.save_site_content_draft(
    current_setting('test.editor_draft_id', true)::uuid,
    '{
      "site":{"name":"Changed Test Church"},
      "pageSummaries":[],
      "about":{},
      "visitHighlights":[],
      "leaders":[],
      "ministries":[],
      "sermons":[],
      "events":[],
      "giving":{"options":[],"faqs":[]},
      "forms":{"visitor":{},"contact":{},"prayer":{},"ministryJoin":{}}
    }'::jsonb,
    1,
    'Updated test name'
  ),
  2,
  'Expected-version save advances the draft version'
);

select throws_ok(
  $test$select public.save_site_content_draft(
    current_setting('test.editor_draft_id', true)::uuid,
    '{"site":{"name":"Stale Write"},"pageSummaries":[],"about":{},"visitHighlights":[],"leaders":[],"ministries":[],"sermons":[],"events":[],"giving":{"options":[],"faqs":[]},"forms":{"visitor":{},"contact":{},"prayer":{},"ministryJoin":{}}}'::jsonb,
    1,
    'stale save'
  )$test$,
  '40001',
  'Draft version conflict; reload before saving',
  'Stale draft write is rejected without overwriting the newer version'
);

select throws_ok(
  $test$select public.submit_site_content_for_review(
    current_setting('test.editor_draft_id', true)::uuid,
    1
  )$test$,
  '40001',
  'Draft version conflict; reload before submitting',
  'Stale editor cannot submit a newer draft version by mistake'
);

select is(
  public.submit_site_content_for_review(
    current_setting('test.editor_draft_id', true)::uuid,
    2
  ),
  3,
  'Editor can submit the current version for review'
);

select is(
  (select status::text from public.site_content_revisions
   where id = current_setting('test.editor_draft_id', true)::uuid),
  'in_review',
  'Submitting moves the revision into review'
);

select throws_ok(
  $test$select public.publish_site_content_revision(
    current_setting('test.editor_draft_id', true)::uuid,
    current_setting('test.published_id', true)::uuid,
    null
  )$test$,
  '42501',
  'Publisher or administrator role required',
  'Editor cannot publish directly'
);

set local request.jwt.claim.sub = '33333333-3333-4333-8333-333333333333';


select throws_ok(
  $test$select public.admin_set_cms_role(
    '11111111-1111-4111-8111-111111111111'::uuid,
    'editor'::public.cms_role,
    null
  )$test$,
  '22023',
  'Role grant action is required',
  'Null role-management action is rejected'
);

select throws_ok(
  $test$select public.admin_set_cms_user_active(
    '11111111-1111-4111-8111-111111111111'::uuid,
    null
  )$test$,
  '22023',
  'Account active state is required',
  'Null account state is rejected'
);

select ok(
  public.has_cms_role(array['administrator']::public.cms_role[]),
  'Administrator role is resolved from trusted database role assignments'
);

select throws_ok(
  $test$select public.admin_set_cms_role(
    '33333333-3333-4333-8333-333333333333'::uuid,
    'administrator'::public.cms_role,
    false
  )$test$,
  '55000',
  'Cannot remove the last active administrator',
  'The last active administrator cannot remove their own admin role'
);

select throws_ok(
  $test$select public.admin_set_cms_user_active(
    '33333333-3333-4333-8333-333333333333'::uuid,
    false
  )$test$,
  '55000',
  'Administrators cannot deactivate their own account',
  'An administrator cannot deactivate their own account'
);

select ok(
  set_config('test.admin_draft_id', public.create_site_content_draft()::text, true) <> '',
  'Administrator can create a draft through the controlled operation'
);

select is(
  public.submit_site_content_for_review(current_setting('test.admin_draft_id', true)::uuid, 1),
  2,
  'Administrator draft can enter the same review workflow'
);

select throws_ok(
  $test$select public.publish_site_content_revision(
    current_setting('test.admin_draft_id', true)::uuid,
    current_setting('test.published_id', true)::uuid,
    null
  )$test$,
  '42501',
  'A submitter cannot publish their own revision',
  'Self-approval is denied even to an administrator'
);

set local request.jwt.claim.sub = '11111111-1111-4111-8111-111111111111';

select is(
  (select count(*)::integer from public.site_content_revisions
   where id = current_setting('test.admin_draft_id', true)::uuid),
  0,
  'Editor cannot read another users draft'
);

select throws_ok(
  $test$select public.save_site_content_draft(
    current_setting('test.admin_draft_id', true)::uuid,
    '{"site":{"name":"Unauthorized"},"pageSummaries":[],"about":{},"visitHighlights":[],"leaders":[],"ministries":[],"sermons":[],"events":[],"giving":{"options":[],"faqs":[]},"forms":{"visitor":{},"contact":{},"prayer":{},"ministryJoin":{}}}'::jsonb,
    2,
    null
  )$test$,
  '42501',
  'Draft not accessible',
  'Editor cannot modify another users draft'
);

set local request.jwt.claim.sub = '22222222-2222-4222-8222-222222222222';

select ok(
  public.has_cms_role(array['publisher']::public.cms_role[]),
  'Publisher role is resolved from trusted database role assignments'
);

select is(
  public.request_site_content_changes(
    current_setting('test.admin_draft_id', true)::uuid,
    'Please revise before publication.'
  ),
  3,
  'Publisher can request changes with a review note'
);

select is(
  (select status::text from public.site_content_revisions
   where id = current_setting('test.admin_draft_id', true)::uuid),
  'changes_requested',
  'Review decision returns the draft for changes'
);

select is(
  public.publish_site_content_revision(
    current_setting('test.editor_draft_id', true)::uuid,
    current_setting('test.published_id', true)::uuid,
    'Publish approved editor draft'
  ),
  current_setting('test.editor_draft_id', true)::uuid,
  'Publisher can publish another users reviewed revision'
);

select is(
  (public.read_site_publication_state() ->> 'revision_id'),
  current_setting('test.editor_draft_id', true),
  'Publication pointer changes to the new revision'
);

select is(
  (select status::text from public.site_content_revisions
   where id = current_setting('test.published_id', true)::uuid),
  'archived',
  'Previous published revision is preserved as archived history'
);

select throws_ok(
  $test$select public.publish_site_content_revision(
    current_setting('test.admin_draft_id', true)::uuid,
    current_setting('test.published_id', true)::uuid,
    null
  )$test$,
  '40001',
  'Published revision changed; reload before publishing',
  'A concurrent/stale publication cannot replace a newer publication'
);

select throws_ok(
  $test$select public.admin_set_cms_role(
    '11111111-1111-4111-8111-111111111111'::uuid,
    'publisher'::public.cms_role,
    true
  )$test$,
  '42501',
  'Administrator role required',
  'Publisher cannot grant roles'
);

set local request.jwt.claim.sub = '33333333-3333-4333-8333-333333333333';

select public.admin_set_cms_user_active(
  '11111111-1111-4111-8111-111111111111'::uuid,
  false
);

set local request.jwt.claim.sub = '11111111-1111-4111-8111-111111111111';

select is(
  (select count(*)::integer from public.site_content_revisions
   where id = current_setting('test.editor_draft_id', true)::uuid),
  0,
  'Deactivated editor loses direct access to their own revisions'
);

select throws_ok(
  'select public.create_site_content_draft()',
  '42501',
  'Editor or administrator role required',
  'Deactivated editor cannot start a new CMS operation'
);

set local role anon;
set local request.jwt.claim.sub = '';

select is(
  (public.read_published_site_content() #>> '{site,name}'),
  'Changed Test Church',
  'Anonymous visitor reads only the currently published payload'
);

select * from finish();
rollback;
