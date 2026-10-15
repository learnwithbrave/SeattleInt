import { supabase } from '../lib/supabase/client'
import { isSiteContent } from './siteContentStore'
import type { SiteContent } from '../types'

/**
 * Fetches the active published SiteContent snapshot from Supabase.
 *
 * This service is intentionally not wired into the public content provider yet.
 * The CMS migration must be applied and an approved initial publication seeded
 * in a validated staging environment before the existing pages switch to it.
 */
export async function fetchPublishedSiteContent(): Promise<SiteContent | null> {
  const { data, error } = await supabase.rpc('read_published_site_content')

  if (error) {
    throw new Error('Unable to load published site content: ' + error.message)
  }

  // The database returns NULL until the initial approved publication is installed.
  if (data === null) {
    return null
  }

  // Runtime-validate the shape rather than trusting an untyped API response.
  if (!isSiteContent(data)) {
    throw new Error('Supabase returned published content with an invalid structure.')
  }

  return data
}
