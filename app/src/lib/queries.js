import { useEffect, useState } from 'react';
import { supabase, configured } from './supabase';

// Shown in place of a database error when there are simply no credentials yet.
export const NOT_CONFIGURED =
  'Database not connected yet — showing geography only. ' +
  'Set VITE_SUPABASE_URL and VITE_SUPABASE_PUBLISHABLE_KEY in .env.';

// Small shared shape so every page renders loading/error the same way.
function useQuery(runner, deps = []) {
  const [state, setState] = useState({ data: null, error: null, loading: true });

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
        setState({ data, error: error?.message ?? null, loading: false });
      })
      .catch((e) => {
        if (!cancelled) setState({ data: null, error: e.message, loading: false });
      });

    // Guards against a slow response for county A landing after the user has
    // already navigated to county B.
    return () => { cancelled = true; };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, deps);

  return state;
}

// Every county plus the orgs credited on it. One round trip — PostgREST
// resolves the nested select through the county_org_participation join table.
export const useCounties = () =>
  useQuery(() =>
    supabase
      .from('counties')
      .select(`
        id, fips, name, slug, status, region, priority, hook,
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
          rationale, hook, confidence,
          cities ( id, name, slug, status, is_priority, place_fips ),
          county_org_participation ( active, organizations ( id, name, slug, website, email, kind ) ),
          ordinances ( id, title, summary, date_passed, date_effective, legal_text_url, city_id )
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
