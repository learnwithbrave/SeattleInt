# Phase 0 Baseline Inventory

**Date:** 2026-10-15  
**Repository branch inspected:** main  
**Implementation branch:** feat/cms-phase-0-1-foundation  
**Status:** Source inventory completed; runtime baseline checks remain pending

## Repository facts inspected

| Area | Current finding | Evidence |
|---|---|---|
| Frontend | React 19, TypeScript, Vite 8, React Router DOM 7, Tailwind CSS 4, Framer Motion | package.json, vite.config.ts |
| Scripts | dev, build (TypeScript build then Vite), lint (ESLint) and preview; no test script declared | package.json |
| Content seed | Structured SiteContent data and search-index helpers | src/content/siteContent.ts |
| Types | SiteContent includes site identity, page summaries, about, visit highlights, leaders, ministries, sermons, events, giving and four form integrations | src/types.ts |
| Provider | Reducer/context initializes in browser and persists changes through an effect | src/content/SiteContentProvider.tsx |
| Persistence | localStorage keys seattle-international-site-content and seattle-international-site-content-saved-at; validates only top-level shape | src/content/siteContentStore.ts |
| CMS route | /admin is currently directly registered in client-side route table | src/App.tsx |
| Forms | ExternalForm accepts form integration settings; public form behavior needs integration-specific verification | src/components/ExternalForm.tsx |
| Prayer requests | Dedicated public route exists; privacy, delivery and retention require separate validation | src/pages/PrayerRequestPage.tsx |
| Routes | Home, about, visit, sermons, events and detail, ministries and detail, giving, contact, prayer request, admin, not-found and /home redirect | src/App.tsx |
| Host configuration | BrowserRouter means direct route requests need SPA fallback; no CI workflow was found at the inspected candidate paths | README.md; .github/workflows/ci.yml and deploy.yml returned 404 |
| External data | README reports formsubmit.co endpoints and placeholder giving/social destinations | README.md |

## Preserved source revision references

The following blob SHAs were observed on main during source inspection. They are evidence for what was inspected, not a substitute for the full Git commit SHA.

- README.md: 9fa9a6101f64ee147ac1b3ea43c0491157793014
- package.json: 66bc0b84b2f29926b28aa2dc22506bcb1b1d7c54
- src/App.tsx: 22c34083e6fb5afbf12a15d375041a15cb002f68
- src/types.ts: 1c19569235871419042eb05fe8a19032ee6c27ca
- src/content/siteContent.ts: 136010ac8d4c80ebd1ac17153995ad0c05e0096a
- src/content/SiteContentProvider.tsx: 6358f983090114359c5dfdae99e2658f043142f4
- src/content/siteContentStore.ts: 09041c05aaa176b3cc63f695b3f518e1df09bf95

## Baseline checks not yet completed

The execution environment used for this run cannot resolve github.com, so a local checkout was not available and the commands below have **not** been run. Do not infer they passed.

- [ ] Record the exact main commit SHA and save a source archive locally.
- [ ] Run npm ci.
- [ ] Run npm run lint.
- [ ] Run npm run build.
- [ ] Capture desktop/mobile screenshots for existing public routes and the admin page.
- [ ] Export any meaningful browser-local CMS copies from known editor devices and reconcile them with the repository seed.
- [ ] Confirm staging/production hosting and the authorized content owner's real contact, giving, social, and form destinations.
- [ ] Decide which named staff may receive/read prayer requests and confirm retention/deletion policy.
- [ ] Confirm media upload is in scope for the first release or defer it.

## Phase 0 outcome

Source-level assessment is complete enough to design a backend foundation without altering current routes, page components, public content, or styling. Runtime checks, localStorage data reconciliation and church-owner operational decisions remain required before production cutover. Phase 1 backend schema and policy work can proceed in an isolated branch; it does not switch the current frontend to the backend.
