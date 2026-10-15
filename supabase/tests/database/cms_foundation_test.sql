begin;

select plan(35);

select has_table('public', 'cms_profiles', 'CMS profiles table exists');
select has_table('public', 'cms_user_roles', 'CMS role assignments table exists');
select has_table('public', 'site_content_revisions', 'Versioned content revisions table exists');
select has_table('public', 'site_publication', 'Published revision pointer table exists');
select has_table('public', 'cms_audit_logs', 'CMS audit table exists');
select has_table('public', 'public_form_submissions', 'Private form submissions table exists');
select has_table('public', 'media_assets', 'Media metadata table exists');

select ok((select relrowsecurity from pg_class where oid = 'public.cms_profiles'::regclass), 'RLS enabled on cms_profiles');
select ok((select relrowsecurity from pg_class where oid = 'public.cms_user_roles'::regclass), 'RLS enabled on cms_user_roles');
select ok((select relrowsecurity from pg_class where oid = 'public.site_content_revisions'::regclass), 'RLS enabled on site_content_revisions');
select ok((select relrowsecurity from pg_class where oid = 'public.site_publication'::regclass), 'RLS enabled on site_publication');
select ok((select relrowsecurity from pg_class where oid = 'public.cms_audit_logs'::regclass), 'RLS enabled on cms_audit_logs');
select ok((select relrowsecurity from pg_class where oid = 'public.public_form_submissions'::regclass), 'RLS enabled on public_form_submissions');
select ok((select relrowsecurity from pg_class where oid = 'public.media_assets'::regclass), 'RLS enabled on media_assets');

select ok(not has_table_privilege('anon', 'public.site_content_revisions', 'SELECT'), 'Anonymous users cannot query revisions directly');
select ok(has_table_privilege('authenticated', 'public.site_content_revisions', 'SELECT'), 'Authenticated SQL reads are still constrained by RLS');
select ok(not has_table_privilege('anon', 'public.site_publication', 'SELECT'), 'Anonymous users cannot query publication metadata directly');
select ok(not has_table_privilege('authenticated', 'public.site_publication', 'SELECT'), 'CMS clients cannot bypass publication metadata function');
select ok(not has_table_privilege('anon', 'public.public_form_submissions', 'SELECT'), 'Anonymous users cannot read private submissions');
select ok(not has_table_privilege('authenticated', 'public.public_form_submissions', 'SELECT'), 'CMS clients cannot read private submissions without a later explicit policy');
select ok(not has_table_privilege('anon', 'public.site_content_revisions', 'INSERT'), 'Anonymous users cannot insert revisions');
select ok(not has_table_privilege('authenticated', 'public.site_content_revisions', 'INSERT'), 'CMS clients cannot bypass draft creation function');
select ok(not has_table_privilege('authenticated', 'public.site_content_revisions', 'UPDATE'), 'CMS clients cannot bypass versioned draft save function');
select ok(not has_table_privilege('authenticated', 'public.cms_user_roles', 'INSERT'), 'CMS clients cannot assign roles directly');
select ok(not has_table_privilege('authenticated', 'public.cms_user_roles', 'UPDATE'), 'CMS clients cannot modify roles directly');
select ok(not has_table_privilege('authenticated', 'public.cms_audit_logs', 'INSERT'), 'CMS clients cannot write audit records directly');
select ok(not has_table_privilege('authenticated', 'public.cms_audit_logs', 'UPDATE'), 'CMS clients cannot rewrite audit records');

select ok(has_function_privilege('anon', 'public.read_published_site_content()', 'EXECUTE'), 'Public visitor can call published-content read function');
select ok(has_function_privilege('authenticated', 'public.read_published_site_content()', 'EXECUTE'), 'Signed-in visitor can call published-content read function');
select ok(not has_function_privilege('anon', 'public.create_site_content_draft()', 'EXECUTE'), 'Anonymous users cannot create drafts');
select ok(has_function_privilege('authenticated', 'public.create_site_content_draft()', 'EXECUTE'), 'Authenticated client may call guarded draft creation function');
select ok(not has_function_privilege('anon', 'public.publish_site_content_revision(uuid,uuid,text)', 'EXECUTE'), 'Anonymous users cannot publish');
select ok(has_function_privilege('authenticated', 'public.publish_site_content_revision(uuid,uuid,text)', 'EXECUTE'), 'Publishing RPC is callable only through its internal role check');
select ok(not has_function_privilege('anon', 'public.admin_set_cms_role(uuid,public.cms_role,boolean)', 'EXECUTE'), 'Anonymous users cannot assign CMS roles');
select ok(has_function_privilege('authenticated', 'public.admin_set_cms_role(uuid,public.cms_role,boolean)', 'EXECUTE'), 'Role-management RPC is protected by its internal administrator check');
select ok(not has_function_privilege('authenticated', 'public.is_valid_site_content_payload(jsonb)', 'EXECUTE'), 'Runtime payload validator is not exposed as an API');

select ok(
  public.is_valid_site_content_payload(
    '{"site":{"name":"Test Church"},"pageSummaries":[],"about":{},"visitHighlights":[],"leaders":[],"ministries":[],"sermons":[],"events":[],"giving":{"options":[],"faqs":[]},"forms":{"visitor":{},"contact":{},"prayer":{},"ministryJoin":{}}}'::jsonb
  ),
  'Minimal structurally valid SiteContent payload passes the database guard'
);
select ok(
  not public.is_valid_site_content_payload(
    '{"site":{"name":"  "},"pageSummaries":[],"about":{},"visitHighlights":[],"leaders":[],"ministries":[],"sermons":[],"events":[],"giving":{"options":[],"faqs":[]},"forms":{"visitor":{},"contact":{},"prayer":{},"ministryJoin":{}}}'::jsonb
  ),
  'Blank church name is rejected'
);
select ok(
  not public.is_valid_site_content_payload(
    '{"site":{"name":"Test Church"},"pageSummaries":[],"about":{},"visitHighlights":[],"leaders":[],"ministries":[],"sermons":[],"events":[],"giving":{"options":[]},"forms":{"visitor":{},"contact":{},"prayer":{},"ministryJoin":{}}}'::jsonb
  ),
  'Payload missing the giving FAQ array is rejected'
);

select * from finish();
rollback;
