# Seattle International Church Website

This project now includes the Phase 1 public church website plus a Phase 2 admin CMS built on the same React and Vite frontend.

## What is included

- Multi-page routes for home, about, visit, sermons, events, ministries, giving, contact, and prayer requests
- An `/admin` CMS route for editing site settings, about copy, leaders, ministries, sermons, events, giving, and form integrations
- Structured church content stored in a reactive content layer instead of being hardcoded inside page components
- Search across pages, sermons, and events
- Event detail pages and ministry detail pages
- Live hosted form submission wiring for visitor, contact, prayer, and ministry-interest flows
- Route-based page titles and description metadata
- Browser-saved content persistence plus JSON export and import for CMS snapshots

## Admin CMS

Open `/admin` while the app is running to manage the public site.

The admin dashboard currently:

- saves content automatically in browser local storage
- updates the public site immediately in the same browser session
- supports export and import of the full site content as JSON
- can restore the default seeded church content at any time

Important:

- this CMS is currently browser-local, not multi-user or server-backed
- for production shared editing, connect the same content store to real authentication and a backend data source

## Content layer

Seeded default content lives in [src/content/siteContent.ts](D:/Dev/SeattleInt/src/content/siteContent.ts).

The CMS provider and reactive store live in:

- [src/content/SiteContentProvider.tsx](D:/Dev/SeattleInt/src/content/SiteContentProvider.tsx)
- [src/content/siteContentStore.ts](D:/Dev/SeattleInt/src/content/siteContentStore.ts)

The content model contains:

- church identity, service times, address, contacts, and social links
- leadership, ministries, sermons, and events
- giving links and FAQ content
- hosted form endpoints and success messages

## Integration notes

- Forms currently post to `formsubmit.co` endpoints defined in the content layer. Replace these email-based endpoints with the church's real verified destination before production use.
- The giving portal uses a placeholder `Tithe.ly` link and should be replaced with the church's live giving account.
- The YouTube and social URLs are placeholder church handles and should be updated to the real ministry accounts.
- BrowserRouter is used for clean URLs, so production hosting should include SPA fallback rewrites for deep links like `/events/city-prayer-night`.
- The admin CMS persists per browser/device until a shared backend is added.

## Commands

```bash
npm install
npm run dev
npm run build
npm run lint
```

## Suggested handoff checklist

- Replace the placeholder church name, address, phone numbers, and emails with real approved values.
- Replace giving, social, and sermon links with live ministry-owned destinations.
- Confirm every ministry leader name, schedule, and contact path with the church council.
- Verify hosted form endpoints submit successfully after email verification.
- Test `/admin` editing, export, import, and default reset flows in the target browser.
- Re-test mobile navigation, maps, and all external CTAs before launch.


## Supabase client setup

The project includes a shared browser client at \`src/lib/supabase/client.ts\` and a CMS content query helper at \`src/content/supabaseContentService.ts\`. Install dependencies with:

~~~sh
npm install
~~~

For local Vite development, copy \`.env.example\` to \`.env.local\` and put the project's Supabase URL and publishable key into that ignored file. The publishable key is intended for browser use; never use a Supabase secret/service-role key in a \`VITE_*\` variable. Restart the Vite dev server after editing environment variables.

The CMS helper calls the \`read_published_site_content\` RPC created by the versioned Supabase migration. It is not yet wired into the current public content provider: the site continues to use its existing content flow until the migration is applied to a reviewed staging project and an approved initial publication is loaded. Do not replace this church site's route-based \`App.tsx\` with the generic \`todos\` demo; no \`todos\` table is defined by this project.
