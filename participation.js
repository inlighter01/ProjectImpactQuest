/**
 * Impact Quest v0.10.0 — Quest Participation Module
 * Join / leave quests, live slot counts, participant list, organizer
 * announcements, and quest cancellation. Uses the global
 * window.supabaseClient created in config.js. Loaded on any page that
 * needs participation data: quest-details.html, my-quests.html,
 * quest-lobby.html, community-feed.html.
 */
(function () {
  "use strict";

  const safe = (value) =>
    String(value ?? "").replace(/[&<>'"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", "'": "&#39;", '"': "&quot;" }[c]));

  /** Returns the signed-in user, or null (does NOT redirect — callers decide). */
  async function currentUserOrNull() {
    const { data: { user } } = await window.supabaseClient.auth.getUser();
    return user || null;
  }

  /** Fetch a single quest with its live joined_count/volunteer_limit. */
  async function fetchQuest(questId) {
    return window.supabaseClient
      .from("quests")
      .select("*, creator:creator_id(id)")
      .eq("id", questId)
      .single();
  }

  /** Is the given user currently joined (status='joined') to this quest? */
  async function getMyParticipation(questId, userId) {
    if (!userId) return null;
    const { data, error } = await window.supabaseClient
      .from("quest_participants")
      .select("id,status,joined_at")
      .eq("quest_id", questId)
      .eq("user_id", userId)
      .eq("status", "joined")
      .maybeSingle();
    if (error) {
      console.error("getMyParticipation failed", error);
      return null;
    }
    return data;
  }

  /** Join a quest. Server-side trigger enforces capacity, duplicate joins, and quest status. */
  async function joinQuest(questId) {
    const user = await currentUserOrNull();
    if (!user) {
      window.location.href = `login.html?next=${encodeURIComponent(window.location.pathname + window.location.search)}`;
      return { error: { message: "Not signed in" } };
    }
    const { data, error } = await window.supabaseClient
      .from("quest_participants")
      .insert({ quest_id: questId, user_id: user.id })
      .select()
      .single();
    return { data, error };
  }

  /** Leave a quest previously joined. Server-side trigger blocks leaving after the quest date. */
  async function leaveQuest(questId) {
    const user = await currentUserOrNull();
    if (!user) return { error: { message: "Not signed in" } };
    const { error } = await window.supabaseClient
      .from("quest_participants")
      .delete()
      .eq("quest_id", questId)
      .eq("user_id", user.id)
      .eq("status", "joined");
    return { error };
  }

  /** Organizer-only: cancel an approved quest via the cancel_quest RPC. */
  async function cancelQuest(questId, reason) {
    return window.supabaseClient.rpc("cancel_quest", { p_quest_id: questId, p_reason: reason || null });
  }

  /** Organizer-only: pin an announcement, notifying every joined participant. */
  async function postAnnouncement(questId, message) {
    return window.supabaseClient.rpc("post_quest_announcement", { p_quest_id: questId, p_message: message });
  }

  /** Organizer-only: full participant roster with profile details. */
  async function loadParticipants(questId) {
    const { data, error } = await window.supabaseClient
      .from("quest_participants")
      .select("id,joined_at,status,user_id,profiles:user_id(display_name,avatar_url,trust_score,verification_status)")
      .eq("quest_id", questId)
      .eq("status", "joined")
      .order("joined_at", { ascending: true });
    return { data: data || [], error };
  }

  /** Recent activity for the Quest Lobby (joins, leaves, announcements, cancellations). */
  async function loadActivity(questId, limit = 25) {
    const { data, error } = await window.supabaseClient
      .from("quest_activity")
      .select("id,type,message,created_at")
      .eq("quest_id", questId)
      .order("created_at", { ascending: false })
      .limit(limit);
    return { data: data || [], error };
  }

  /**
   * Subscribes to realtime changes on a quest's row so joined_count and
   * volunteer_limit stay live without polling. Returns an unsubscribe fn.
   */
  function subscribeToQuest(questId, onChange) {
    const channel = window.supabaseClient
      .channel(`quest-live-${questId}`)
      .on(
        "postgres_changes",
        { event: "UPDATE", schema: "public", table: "quests", filter: `id=eq.${questId}` },
        (payload) => onChange(payload.new)
      )
      .subscribe();
    return () => window.supabaseClient.removeChannel(channel);
  }

  /** Subscribes to new/removed participant rows for a quest (drives the participant list live). */
  function subscribeToParticipants(questId, onChange) {
    const channel = window.supabaseClient
      .channel(`quest-participants-${questId}`)
      .on(
        "postgres_changes",
        { event: "*", schema: "public", table: "quest_participants", filter: `quest_id=eq.${questId}` },
        onChange
      )
      .subscribe();
    return () => window.supabaseClient.removeChannel(channel);
  }

  /** Subscribes to new quest_activity rows (organizer announcements, joins, leaves) for the Lobby feed. */
  function subscribeToActivity(questId, onInsert) {
    const channel = window.supabaseClient
      .channel(`quest-activity-${questId}`)
      .on(
        "postgres_changes",
        { event: "INSERT", schema: "public", table: "quest_activity", filter: `quest_id=eq.${questId}` },
        (payload) => onInsert(payload.new)
      )
      .subscribe();
    return () => window.supabaseClient.removeChannel(channel);
  }

  function slotsRemaining(quest) {
    return Math.max((quest.volunteer_limit || 0) - (quest.joined_count || 0), 0);
  }

  function isFull(quest) {
    return (quest.joined_count || 0) >= (quest.volunteer_limit || 0);
  }

  function verificationBadge(status) {
    if (status === "approved") return `<span class="verify-badge">✓ Verified</span>`;
    return `<span class="verify-badge not-verified">Unverified</span>`;
  }

  function formatTrust(score) {
    const n = Number(score || 0);
    return n > 0 ? `<span class="trust-badge">★ ${n.toFixed(1)}</span>` : "";
  }

  function timeAgo(iso) {
    const diffMs = Date.now() - new Date(iso).getTime();
    const mins = Math.round(diffMs / 60000);
    if (mins < 1) return "just now";
    if (mins < 60) return `${mins}m ago`;
    const hours = Math.round(mins / 60);
    if (hours < 24) return `${hours}h ago`;
    const days = Math.round(hours / 24);
    return `${days}d ago`;
  }

  // Exposed API used by inline page scripts.
  window.IQParticipation = {
    safe,
    currentUserOrNull,
    fetchQuest,
    getMyParticipation,
    joinQuest,
    leaveQuest,
    cancelQuest,
    postAnnouncement,
    loadParticipants,
    loadActivity,
    subscribeToQuest,
    subscribeToParticipants,
    subscribeToActivity,
    slotsRemaining,
    isFull,
    verificationBadge,
    formatTrust,
    timeAgo,
  };
})();
