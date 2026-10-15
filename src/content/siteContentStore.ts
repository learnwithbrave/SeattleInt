import { createContext, useContext } from 'react'
import type { Dispatch } from 'react'

import { buildSearchIndex, defaultSiteContent } from './siteContent'
import type { SearchEntry, SiteContent } from '../types'

const CONTENT_STORAGE_KEY = 'seattle-international-site-content'
const CONTENT_SAVED_AT_KEY = 'seattle-international-site-content-saved-at'

export interface CmsState {
  content: SiteContent
  lastSavedAt: string | null
}

export type CmsAction =
  | { type: 'replace'; nextContent: SiteContent }
  | { type: 'update'; updater: (current: SiteContent) => SiteContent }
  | { type: 'reset' }

interface ImportResult {
  ok: boolean
  message: string
}

export interface SiteContentContextValue {
  content: SiteContent
  searchIndex: SearchEntry[]
  lastSavedAt: string | null
  updateContent: (updater: (current: SiteContent) => SiteContent) => void
  replaceContent: (nextContent: SiteContent) => void
  restoreDefaults: () => void
  exportContent: () => string
  importContent: (raw: string) => ImportResult
}

export const SiteContentContext = createContext<SiteContentContextValue | null>(null)

function getSaveStamp() {
  return new Date().toISOString()
}

function cloneSiteContent(content: SiteContent) {
  return structuredClone(content)
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return Boolean(value) && typeof value === 'object' && !Array.isArray(value)
}

export function isSiteContent(value: unknown): value is SiteContent {
  if (!isRecord(value)) {
    return false
  }

  return (
    isRecord(value.site) &&
    Array.isArray(value.pageSummaries) &&
    isRecord(value.about) &&
    Array.isArray(value.visitHighlights) &&
    Array.isArray(value.leaders) &&
    Array.isArray(value.ministries) &&
    Array.isArray(value.sermons) &&
    Array.isArray(value.events) &&
    isRecord(value.giving) &&
    isRecord(value.forms)
  )
}

export function loadInitialCmsState(): CmsState {
  if (typeof window === 'undefined') {
    return { content: cloneSiteContent(defaultSiteContent), lastSavedAt: null }
  }

  const raw = window.localStorage.getItem(CONTENT_STORAGE_KEY)
  const savedAt = window.localStorage.getItem(CONTENT_SAVED_AT_KEY)

  if (!raw) {
    return { content: cloneSiteContent(defaultSiteContent), lastSavedAt: savedAt }
  }

  try {
    const parsed = JSON.parse(raw)

    if (!isSiteContent(parsed)) {
      return { content: cloneSiteContent(defaultSiteContent), lastSavedAt: savedAt }
    }

    return {
      content: parsed,
      lastSavedAt: savedAt,
    }
  } catch {
    return { content: cloneSiteContent(defaultSiteContent), lastSavedAt: savedAt }
  }
}

export function cmsReducer(state: CmsState, action: CmsAction): CmsState {
  switch (action.type) {
    case 'replace':
      return {
        content: cloneSiteContent(action.nextContent),
        lastSavedAt: getSaveStamp(),
      }
    case 'update':
      return {
        content: action.updater(state.content),
        lastSavedAt: getSaveStamp(),
      }
    case 'reset':
      return {
        content: cloneSiteContent(defaultSiteContent),
        lastSavedAt: getSaveStamp(),
      }
    default:
      return state
  }
}

export function persistCmsState(state: CmsState) {
  window.localStorage.setItem(CONTENT_STORAGE_KEY, JSON.stringify(state.content))

  if (state.lastSavedAt) {
    window.localStorage.setItem(CONTENT_SAVED_AT_KEY, state.lastSavedAt)
  }
}

export function createSiteContentContextValue(
  state: CmsState,
  dispatch: Dispatch<CmsAction>,
): SiteContentContextValue {
  return {
    content: state.content,
    searchIndex: buildSearchIndex(state.content),
    lastSavedAt: state.lastSavedAt,
    updateContent: (updater) => dispatch({ type: 'update', updater }),
    replaceContent: (nextContent) => dispatch({ type: 'replace', nextContent }),
    restoreDefaults: () => dispatch({ type: 'reset' }),
    exportContent: () => JSON.stringify(state.content, null, 2),
    importContent: (raw) => {
      try {
        const parsed = JSON.parse(raw)

        if (!isSiteContent(parsed)) {
          return {
            ok: false,
            message:
              'Import failed. The JSON is valid, but it does not match the required site content structure.',
          }
        }

        dispatch({ type: 'replace', nextContent: parsed })

        return {
          ok: true,
          message: 'Content imported successfully. The public site has been updated.',
        }
      } catch {
        return {
          ok: false,
          message: 'Import failed. Please paste valid JSON exported from this CMS.',
        }
      }
    },
  }
}

export function useSiteContent() {
  const context = useContext(SiteContentContext)

  if (!context) {
    throw new Error('useSiteContent must be used within SiteContentProvider.')
  }

  return context.content
}

export function useSearchIndex() {
  const context = useContext(SiteContentContext)

  if (!context) {
    throw new Error('useSearchIndex must be used within SiteContentProvider.')
  }

  return context.searchIndex
}

export function useCmsController() {
  const context = useContext(SiteContentContext)

  if (!context) {
    throw new Error('useCmsController must be used within SiteContentProvider.')
  }

  return context
}
