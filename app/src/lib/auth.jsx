import { createContext, useContext, useEffect, useState, useCallback } from 'react';
import { supabase, configured } from './supabase';

const AuthContext = createContext(null);

/**
 * Session + profile + org memberships for the signed-in user.
 *
 * The permission helpers here decide what UI to SHOW. They are not the
 * security boundary — Row Level Security is, and it is enforced in Postgres on
 * every request. Anything this file gets wrong results in a button that fails
 * with a policy error, not in unauthorised data changes.
 */
export function AuthProvider({ children }) {
  const [session, setSession] = useState(null);
  const [profile, setProfile] = useState(null);
  const [memberships, setMemberships] = useState([]);
  const [loading, setLoading] = useState(true);

  const loadProfile = useCallback(async (userId) => {
    if (!userId) {
      setProfile(null);
      setMemberships([]);
      return;
    }

    const [{ data: p }, { data: m }] = await Promise.all([
      supabase.from('profiles').select('*').eq('id', userId).maybeSingle(),
      supabase
        .from('org_memberships')
        .select('id, role, officer_title, org_id, organizations ( id, name, slug, approved )')
        .eq('user_id', userId),
    ]);

    setProfile(p ?? null);
    setMemberships(m ?? []);
  }, []);

  useEffect(() => {
    if (!configured) {
      setLoading(false);
      return;
    }

    supabase.auth.getSession().then(async ({ data }) => {
      setSession(data.session);
      await loadProfile(data.session?.user?.id);
      setLoading(false);
    });

    // Fires on sign-in, sign-out, and token refresh — including in other tabs.
    const { data: sub } = supabase.auth.onAuthStateChange(async (_event, s) => {
      setSession(s);
      await loadProfile(s?.user?.id);
    });

    return () => sub.subscription.unsubscribe();
  }, [loadProfile]);

  const value = {
    session,
    user: session?.user ?? null,
    profile,
    memberships,
    loading,
    refresh: () => loadProfile(session?.user?.id),

    signIn: (email, password) =>
      supabase.auth.signInWithPassword({ email, password }),

    signUp: (email, password, displayName) =>
      supabase.auth.signUp({
        email,
        password,
        // Read by the handle_new_user trigger to populate profiles.display_name.
        options: { data: { display_name: displayName } },
      }),

    signOut: () => supabase.auth.signOut(),

    isSuperAdmin: profile?.role === 'super_admin',
    isAdmin: profile?.role === 'super_admin' || profile?.role === 'sub_admin',
  };

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth() {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error('useAuth must be used inside <AuthProvider>');
  return ctx;
}

/**
 * Whether to show edit controls for a county.
 *
 * Mirrors can_edit_county() in supabase/migrations/0002_rls.sql: admins
 * anywhere, otherwise president or officer of an approved org participating in
 * that county. Kept deliberately in sync — if these ever diverge, the database
 * wins and the user sees a policy error.
 */
export function useCanEditCounty(county) {
  const { isAdmin, memberships } = useAuth();

  if (isAdmin) return true;
  if (!county) return false;

  const participatingOrgIds = new Set(
    (county.county_org_participation ?? [])
      .filter((p) => p.active && p.organizations)
      .map((p) => p.organizations.id)
  );

  return memberships.some(
    (m) =>
      (m.role === 'president' || m.role === 'officer') &&
      m.organizations?.approved &&
      participatingOrgIds.has(m.org_id)
  );
}
