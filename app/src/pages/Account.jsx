import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { useAuth } from '../lib/auth';
import { supabase } from '../lib/supabase';

const ROLE_LABEL = {
  super_admin: 'Super Admin',
  sub_admin: 'Sub-Admin',
  member: 'Member',
};

const ORG_ROLE_LABEL = {
  president: 'President',
  officer: 'Officer',
  member: 'Member',
};

export default function Account() {
  const { user, profile, memberships, signOut, refresh, isAdmin } = useAuth();
  const navigate = useNavigate();

  const [name, setName] = useState(profile?.display_name ?? '');
  const [saving, setSaving] = useState(false);
  const [saved, setSaved] = useState(false);
  const [error, setError] = useState(null);

  const save = async (e) => {
    e.preventDefault();
    setSaving(true);
    setError(null);
    setSaved(false);

    // Only display_name is sent. The RLS policy rejects any update that
    // changes role or is_moderator, so there is nothing to gain by trying.
    const { error } = await supabase
      .from('profiles')
      .update({ display_name: name })
      .eq('id', user.id);

    if (error) setError(error.message);
    else {
      setSaved(true);
      await refresh();
    }
    setSaving(false);
  };

  const leave = async () => {
    await signOut();
    navigate('/');
  };

  return (
    <div className="page page-narrow">
      <header className="page-head">
        <h1>Your account</h1>
      </header>

      <section className="account-card">
        <dl className="account-facts">
          <div>
            <dt>Email</dt>
            <dd>{user?.email}</dd>
          </div>
          <div>
            <dt>Role</dt>
            <dd>
              <span className={`role-pill role-${profile?.role ?? 'member'}`}>
                {ROLE_LABEL[profile?.role] ?? 'Member'}
              </span>
              {profile?.sub_admin_title && (
                <span className="muted"> — {profile.sub_admin_title}</span>
              )}
              {profile?.is_moderator && <span className="muted"> · Moderator</span>}
            </dd>
          </div>
        </dl>
      </section>

      <section>
        <h2>Profile</h2>
        {error && <p className="error">{error}</p>}
        <form className="form" onSubmit={save}>
          <label>
            <span>Display name</span>
            <input value={name} onChange={(e) => setName(e.target.value)} required />
            <small className="muted">
              Shown next to your messages and in organization rosters.
            </small>
          </label>
          <div className="form-actions">
            <button className="btn btn-primary" type="submit" disabled={saving}>
              {saving ? 'Saving…' : 'Save'}
            </button>
            {saved && <span className="saved-flag">Saved</span>}
          </div>
        </form>
      </section>

      <section>
        <h2>Organizations</h2>
        {memberships.length ? (
          <ul className="membership-list">
            {memberships.map((m) => (
              <li key={m.id}>
                <span className="membership-org">
                  {m.organizations?.name ?? 'Unknown organization'}
                </span>
                <span className="membership-role">
                  {ORG_ROLE_LABEL[m.role]}
                  {m.officer_title ? ` — ${m.officer_title}` : ''}
                </span>
                {m.organizations && !m.organizations.approved && (
                  <span className="pending-flag">Pending approval</span>
                )}
              </li>
            ))}
          </ul>
        ) : (
          <p className="muted">
            You are not a member of any organization yet. Organization
            membership is what grants editing rights over a county.
          </p>
        )}
      </section>

      {isAdmin && (
        <section className="admin-note">
          <h2>Editing rights</h2>
          <p>
            As {ROLE_LABEL[profile.role]} you can edit every county. Open any
            county page from the{' '}
            <a href="/map">progress map</a> and use the edit panel to change its
            stage, update cities, and attach a presentation.
          </p>
        </section>
      )}

      <section>
        <button className="btn btn-ghost" onClick={leave}>Sign out</button>
      </section>
    </div>
  );
}
