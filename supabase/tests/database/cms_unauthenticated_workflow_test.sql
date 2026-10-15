begin;

select plan(9);

select ok(
  not public.has_cms_role(array['editor', 'publisher', 'administrator']::public.cms_role[]),
  'A request without an authenticated CMS identity has no CMS role'
);

select throws_ok(
  'select public.create_site_content_draft()',
  '42501',
  'Editor or administrator role required',
  'Unauthenticated draft creation is rejected'
);

select throws_ok(
  'select public.save_site_content_draft(gen_random_uuid(), ''{}''::jsonb, 1, null)',
  '42501',
  'Editor or administrator role required',
  'Unauthenticated draft save is rejected before content mutation'
);

select throws_ok(
  'select public.submit_site_content_for_review(gen_random_uuid(), 1)',
  '42501',
  'Editor or administrator role required',
  'Unauthenticated review submission is rejected'
);

select throws_ok(
  'select public.request_site_content_changes(gen_random_uuid(), ''Please revise'')',
  '42501',
  'Publisher or administrator role required',
  'Unauthenticated review decision is rejected'
);

select throws_ok(
  'select public.publish_site_content_revision(gen_random_uuid(), null, null)',
  '42501',
  'Publisher or administrator role required',
  'Unauthenticated publishing is rejected'
);

select throws_ok(
  'select public.admin_set_cms_role(gen_random_uuid(), ''editor''::public.cms_role, true)',
  '42501',
  'Administrator role required',
  'Unauthenticated role assignment is rejected'
);

select throws_ok(
  'select public.admin_set_cms_user_active(gen_random_uuid(), false)',
  '42501',
  'Administrator role required',
  'Unauthenticated account deactivation is rejected'
);

select throws_ok(
  'select public.read_site_publication_state()',
  '42501',
  'Publisher or administrator role required',
  'Anonymous publication metadata access is rejected'
);

select * from finish();
rollback;
