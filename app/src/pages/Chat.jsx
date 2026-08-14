import { useEffect, useMemo, useRef, useState } from 'react';
import { useAuth } from '../lib/auth';
import {
  useChannels,
  useMessages,
  sendMessage,
  retractMessage,
  approveMessage,
} from '../lib/chat';

/**
 * Coalition chat — one statewide channel, one per county, one per organization.
 *
 * Three channel kinds with different audiences, so the sidebar groups them
 * rather than presenting 100+ rooms as one flat list. Org channels are private;
 * they appear here only because RLS returned them, never because of a check
 * made in this file.
 */

function timeOf(iso) {
  const d = new Date(iso);
  const today = new Date().toDateString() === d.toDateString();
  return today
    ? d.toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' })
    : d.toLocaleString([], {
        month: 'short',
        day: 'numeric',
        hour: 'numeric',
        minute: '2-digit',
      });
}

function Message({ m, meId, isModerator, onRetract, onApprove }) {
  const mine = m.user_id === meId;
  const name = m.profiles?.display_name || 'Former member';

  if (m.deleted_at && !isModerator) return null;

  return (
    <li className={m.deleted_at ? 'msg msg-deleted' : 'msg'}>
      <div className="msg-head">
        <strong className={mine ? 'msg-author msg-author-me' : 'msg-author'}>
          {name}
        </strong>
        <span className="msg-time">{timeOf(m.created_at)}</span>

        {/* Both states are moderator-only in the UI because RLS never sends
            them to anyone else — an ordinary member simply does not receive
            flagged or deleted rows. */}
        {m.flagged && (
          <span className="msg-badge msg-badge-flag" title={m.flag_reason || ''}>
            flagged
          </span>
        )}
        {m.deleted_at && <span className="msg-badge">removed</span>}
      </div>

      <p className="msg-body">{m.body}</p>

      {m.flagged && isModerator && (
        <p className="msg-reason">
          Bot: {m.flag_reason}{' '}
          <button className="linkish" onClick={() => onApprove(m.id)}>
            not spam — publish
          </button>
        </p>
      )}

      {!m.deleted_at && (mine || isModerator) && (
        <button className="linkish msg-retract" onClick={() => onRetract(m.id)}>
          {mine ? 'Retract' : 'Remove'}
        </button>
      )}
    </li>
  );
}

export default function Chat() {
  const { user, profile, memberships, isAdmin } = useAuth();
  const isModerator = Boolean(isAdmin || profile?.is_moderator);

  const { statewide, counties, orgs, loading: loadingChannels, error } = useChannels();
  const [activeId, setActiveId] = useState(null);
  const [filter, setFilter] = useState('');
  const [draft, setDraft] = useState('');
  const [sendError, setSendError] = useState(null);
  const [sending, setSending] = useState(false);

  const all = useMemo(
    () => [statewide, ...orgs, ...counties].filter(Boolean),
    [statewide, orgs, counties]
  );
  const active = all.find((c) => c.id === activeId) ?? null;

  // Land in the statewide channel rather than an empty pane.
  useEffect(() => {
    if (!activeId && statewide) setActiveId(statewide.id);
  }, [activeId, statewide]);

  const { messages, loading: loadingMessages } = useMessages(active?.id);

  const listRef = useRef(null);
  useEffect(() => {
    const el = listRef.current;
    if (el) el.scrollTop = el.scrollHeight;
  }, [messages]);

  const q = filter.trim().toLowerCase();
  const matches = (c) => !q || c.name.toLowerCase().includes(q);

  async function onSend(e) {
    e.preventDefault();
    if (!active || sending) return;

    setSending(true);
    setSendError(null);
    const { error: err, skipped } = await sendMessage(active.id, user.id, draft);
    setSending(false);

    if (err) setSendError(err.message);
    else if (!skipped) setDraft('');
  }

  async function onRetract(id) {
    const { error: err } = await retractMessage(id, user.id);
    if (err) setSendError(err.message);
  }

  async function onApprove(id) {
    const { error: err } = await approveMessage(id);
    if (err) setSendError(err.message);
  }

  if (error) {
    return (
      <div className="page">
        <div className="callout callout-warn">
          <strong>Chat is unavailable.</strong> {error}
        </div>
      </div>
    );
  }

  return (
    <div className="chat-page">
      <aside className="chat-sidebar">
        <input
          className="chat-filter"
          placeholder="Filter channels"
          value={filter}
          onChange={(e) => setFilter(e.target.value)}
          aria-label="Filter channels"
        />

        {loadingChannels && <p className="muted">Loading channels…</p>}

        {statewide && matches(statewide) && (
          <>
            <h3 className="chat-group">Statewide</h3>
            <ul className="chat-list">
              <li>
                <button
                  className={active?.id === statewide.id ? 'chan chan-on' : 'chan'}
                  onClick={() => setActiveId(statewide.id)}
                >
                  {statewide.name}
                </button>
              </li>
            </ul>
          </>
        )}

        {orgs.filter(matches).length > 0 && (
          <>
            <h3 className="chat-group">
              My organizations <span className="chat-count">{orgs.length}</span>
            </h3>
            <ul className="chat-list">
              {orgs.filter(matches).map((c) => (
                <li key={c.id}>
                  <button
                    className={active?.id === c.id ? 'chan chan-on' : 'chan'}
                    onClick={() => setActiveId(c.id)}
                  >
                    {c.name}
                    <span className="chan-lock" aria-label="private">
                      🔒
                    </span>
                  </button>
                </li>
              ))}
            </ul>
          </>
        )}

        {/* Only surfaces for members of an org; everyone else never sees the
            heading at all rather than an empty section. */}
        {orgs.length === 0 && memberships.length > 0 && (
          <p className="muted chat-note">
            Your organization’s channel appears once its record is linked.
          </p>
        )}

        <h3 className="chat-group">
          Counties <span className="chat-count">{counties.length}</span>
        </h3>
        <ul className="chat-list">
          {counties.filter(matches).map((c) => (
            <li key={c.id}>
              <button
                className={active?.id === c.id ? 'chan chan-on' : 'chan'}
                onClick={() => setActiveId(c.id)}
              >
                {c.name}
              </button>
            </li>
          ))}
        </ul>
      </aside>

      <section className="chat-main">
        <header className="chat-head">
          <h2>{active?.name ?? 'Select a channel'}</h2>
          {active?.kind === 'org' && (
            <p className="muted">
              Private to members of this organization. Admins can read it for
              moderation.
            </p>
          )}
          {active?.kind === 'statewide' && (
            <p className="muted">
              Every coalition member is here. Automated spam filtering is on for
              this channel only.
            </p>
          )}
          {active?.kind === 'county' && (
            <p className="muted">
              Open to all members — the working space for organizations active in
              this county.
            </p>
          )}
        </header>

        <ul className="chat-messages" ref={listRef}>
          {loadingMessages && <li className="muted">Loading…</li>}

          {!loadingMessages && messages.length === 0 && (
            <li className="chat-empty">
              <p>
                <strong>No messages yet.</strong>
              </p>
              <p className="muted">
                {active?.kind === 'statewide'
                  ? 'This is the statewide channel — introductions are a good start.'
                  : 'Be the first to post here.'}
              </p>
            </li>
          )}

          {messages.map((m) => (
            <Message
              key={m.id}
              m={m}
              meId={user?.id}
              isModerator={isModerator}
              onRetract={onRetract}
              onApprove={onApprove}
            />
          ))}
        </ul>

        {sendError && (
          <p className="chat-error" role="alert">
            {sendError}
          </p>
        )}

        <form className="chat-composer" onSubmit={onSend}>
          <textarea
            value={draft}
            onChange={(e) => setDraft(e.target.value)}
            placeholder={active ? `Message ${active.name}` : 'Select a channel'}
            disabled={!active || sending}
            rows={2}
            // Enter sends, Shift+Enter breaks the line — the convention
            // everyone already has muscle memory for from other chat apps.
            onKeyDown={(e) => {
              if (e.key === 'Enter' && !e.shiftKey) {
                e.preventDefault();
                onSend(e);
              }
            }}
          />
          <button
            className="btn btn-primary"
            type="submit"
            disabled={!active || sending || !draft.trim()}
          >
            {sending ? 'Sending…' : 'Send'}
          </button>
        </form>
      </section>
    </div>
  );
}
