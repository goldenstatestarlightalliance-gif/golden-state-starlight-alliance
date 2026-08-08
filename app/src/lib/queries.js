import { useEffect, useState } from 'react';
import { supabase, configured } from './supabase';

// Shown in place of a database error when there are simply no credentials yet.
export const NOT_CONFIGURED =
  'Database not connected yet — showing geography only. ' +
  'Set VITE_SUPABASE_URL and VITE_SUPABASE_PUBLISHABLE_KEY in .env.';

// A failed fetch surfaces as the browser's bare "TypeError: Failed to fetch",
// which tells nobody anything. It means the request never reached the server at
// all — offline, DNS failure, or the Supabase project no longer exists — as
// opposed to a query error, which comes back as structured JSON.
function describeError(e) {
  const raw = e?.message ?? String(e);
  if (/failed to fetch|networkerror|load failed/i.test(raw)) {
    return (
      'Could not reach the database. The Supabase project may be paused, ' +
      'deleted, or unreachable from this network — check that ' +
      `${import.meta.env.VITE_SUPABASE_URL} still resolves.`
    );
  }
  return raw;
}

// Small shared shape so every page renders loading/error the same way.
function useQuery(runner, deps = []) {
  const [state, setState] = useState({ data: null, error: null, loading: true });
  // Bumping this re-runs the effect, so a component can refetch after writing.
  const [nonce, setNonce] = useState(0);

  useEffect(() => {
    let cancelled = false;

    // Without credentials there is nothing to await; report it once and stop.
    if (!configured) {
      setState({ data: null, error: NOT_CONFIGURED, loading: false });
      return;
    }

    setState((s) => ({ ...s, loading: true }));

    runner()
      .then(({ data, error }) => {
        if (cancelled) return;
        // supabase-js reports even network failures through `error` rather than
        // throwing, so this branch — not the catch below — is what usually sees
        // "TypeError: Failed to fetch".
        setState({ data, error: error ? describeError(error) : null, loading: false });
      })
      .catch((e) => {
        if (!cancelled) setState({ data: null, error: describeError(e), loading: false });
      });

    // Guards against a slow response for county A landing after the user has
    // already navigated to county B.
    return () => { cancelled = true; };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [...deps, nonce]);

  // Awaitable, so a save button can wait for fresh data before clearing itself.
  const reload = () =>
    new Promise((resolve) => { setNonce((n) => n + 1); setTimeout(resolve, 0); });

  return { ...state, reload };
}

// Every county plus the orgs credited on it. One round trip — PostgREST
// resolves the nested select through the county_org_participation join table.
export const useCounties = () =>
  useQuery(() =>
    supabase
      .from('counties')
      // City statuses come along because the map colours counties by what
      // fraction of their cities have an ordinance, not by county status.
      .select(`
        id, fips, name, slug, status, region, priority, hook,
        cities ( id, status ),
        county_org_participation (
          active,
          organizations ( id, name, slug, website, email, kind )
        )
      `)
      .order('name')
  );

export const useCounty = (slug) =>
  useQuery(
    () =>
      supabase
        .from('counties')
        .select(`
          id, fips, name, slug, status, region, priority, priority_reason,
          rationale, hook, confidence, slides_url,
          cities ( id, name, slug, status, is_priority, place_fips ),
          county_org_participation (
            active,
            organizations ( id, name, slug, website, email, kind, logo_url )
          ),
          ordinances ( id, title, summary, date_passed, date_effective, legal_text_url, city_id ),
          county_documents ( id, kind, label, url, sort_order )
        `)
        .eq('slug', slug)
        .single(),
    [slug]
  );

// The public county timeline (spec §4). Only rows flagged public come back for
// anonymous visitors; RLS drops the rest.
export const useCountyTimeline = (countyId) =>
  useQuery(
    () =>
      countyId
        ? supabase
            .from('events')
            .select('id, action, description, created_at, entity_type')
            .eq('county_id', countyId)
            .order('created_at', { ascending: false })
            .limit(50)
        : Promise.resolve({ data: [], error: null }),
    [countyId]
  );

// Flattens the nested participation rows into a plain list of active orgs.
export const activeOrgs = (county) =>
  (county?.county_org_participation ?? [])
    .filter((p) => p.active && p.organizations)
    .map((p) => p.organizations)
    .sort((a, b) => a.name.localeCompare(b.name));
