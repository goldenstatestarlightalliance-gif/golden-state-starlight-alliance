import { useCallback, useEffect, useRef, useState } from 'react';
import { supabase, configured } from './supabase';

/**
 * Chat data layer — channels, messages, and the Realtime subscription.
 *
 * Row Level Security is the access boundary, not this file. An org channel is
 * private because 0009's policies say so; the sidebar simply never receives
 * rows it may not read. If these two ever disagree, the database wins and the
 * user sees an empty list rather than someone else's messages.
 */

const MESSAGE_SELECT = `
  id, body, created_at, flagged, flag_reason, deleted_at, user_id,
  profiles ( id, display_name )
`;

/** How much history to load on open. Older messages are not paged in yet. */
const PAGE_SIZE = 100;

/**
 * Every channel this user can see, grouped for the sidebar.
 *
 * Org channels arrive here only for members — RLS filters them server-side, so
 * there is no client-side check to forget.
 */
export function useChannels() {
  const [channels, setChannels] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);

  useEffect(() => {
    if (!configured) {
      setLoading(false);
      return;
    }

    let cancelled = false;

    supabase
      .from('channels')
      .select('id, kind, name, slug, county_id, org_id')
      .order('kind')
      .order('name')
      .then(({ data, error: err }) => {
        if (cancelled) return;
        // supabase-js reports network failures on the result object, not by
        // rejecting, so this branch has to handle both.
        if (err) setError(err.message);
        else setChannels(data ?? []);
        setLoading(false);
      });

    return () => {
      cancelled = true;
    };
  }, []);

  return {
    channels,
    loading,
    error,
    statewide: channels.find((c) => c.kind === 'statewide') ?? null,
    counties: channels.filter((c) => c.kind === 'county'),
    orgs: channels.filter((c) => c.kind === 'org'),
  };
}

/**
 * Live messages for one channel.
 *
 * On a Realtime INSERT we re-fetch that single row rather than trusting the
 * payload, for two reasons: the payload carries no joined author name, and a
 * bot-flagged message is invisible to ordinary members under RLS — re-fetching
 * lets the server decide, so a flagged post silently never appears instead of
 * flashing on screen and then vanishing.
 */
export function useMessages(channelId) {
  const [messages, setMessages] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);

  // Read inside the subscription callback without making it a dependency,
  // which would tear down and rebuild the channel on every message.
  const channelIdRef = useRef(channelId);
  channelIdRef.current = channelId;

  useEffect(() => {
    if (!configured || !channelId) {
      setMessages([]);
      setLoading(false);
      return;
    }

    let cancelled = false;
    setLoading(true);
    setError(null);

    supabase
      .from('messages')
      .select(MESSAGE_SELECT)
      .eq('channel_id', channelId)
      .order('created_at', { ascending: false })
      .limit(PAGE_SIZE)
      .then(({ data, error: err }) => {
        if (cancelled) return;
        if (err) setError(err.message);
        // Fetched newest-first so the LIMIT takes the most recent 100, then
        // reversed for display.
        else setMessages((data ?? []).slice().reverse());
        setLoading(false);
      });

    const sub = supabase
      .channel(`messages:${channelId}`)
      .on(
        'postgres_changes',
        {
          event: 'INSERT',
          schema: 'public',
          table: 'messages',
          filter: `channel_id=eq.${channelId}`,
        },
        async (payload) => {
          const { data } = await supabase
            .from('messages')
            .select(MESSAGE_SELECT)
            .eq('id', payload.new.id)
            .maybeSingle();

          // Null means RLS withheld it — flagged by the bot, or soft-deleted
          // before we got here. Either way it is not ours to show.
          if (!data) return;
          if (channelIdRef.current !== channelId) return;

          setMessages((prev) =>
            prev.some((m) => m.id === data.id) ? prev : [...prev, data]
          );
        }
      )
      .on(
        'postgres_changes',
        {
          event: 'UPDATE',
          schema: 'public',
          table: 'messages',
          filter: `channel_id=eq.${channelId}`,
        },
        (payload) => {
          // Covers retraction and moderator action. Patch in place so the
          // author name from the original join survives.
          setMessages((prev) =>
            prev.map((m) => (m.id === payload.new.id ? { ...m, ...payload.new } : m))
          );
        }
      )
      .subscribe();

    return () => {
      cancelled = true;
      supabase.removeChannel(sub);
    };
  }, [channelId]);

  return { messages, loading, error };
}

/** Post to a channel. The bot may flag it on the way in; that is the server's call. */
export async function sendMessage(channelId, userId, body) {
  const trimmed = body.trim();
  if (!trimmed) return { error: null, skipped: true };
  // Mirrors the length check on messages.body so an over-long paste fails
  // here with a readable message rather than as a constraint violation.
  if (trimmed.length > 4000) {
    return { error: { message: 'Messages are limited to 4,000 characters.' } };
  }

  const { error } = await supabase
    .from('messages')
    .insert({ channel_id: channelId, user_id: userId, body: trimmed });

  return { error };
}

/**
 * Soft delete. Authors may retract their own; moderators may act on any.
 * Hard deletion is reserved for the retention job, so moderation stays
 * auditable.
 */
export async function retractMessage(messageId, actorId) {
  const { error } = await supabase
    .from('messages')
    .update({ deleted_at: new Date().toISOString(), deleted_by: actorId })
    .eq('id', messageId);

  return { error };
}

/** Clear a bot flag after a moderator decides the message is fine. */
export async function approveMessage(messageId) {
  const { error } = await supabase
    .from('messages')
    .update({ flagged: false, flag_reason: null })
    .eq('id', messageId);

  return { error };
}

/** Used by the composer to decide whether to show a hint about bot filtering. */
export function useIsStatewide(channel) {
  return channel?.kind === 'statewide';
}
