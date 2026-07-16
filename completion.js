/**
 * Impact Quest v0.11.0 — Reputation & Completion Module
 * Submitting proof of completion, organizer attendance review, badges,
 * XP levels, reputation history, and the global leaderboard. Uses the
 * global window.supabaseClient created in config.js. All scoring logic
 * lives in SECURITY DEFINER database functions (see supabase-setup.sql,
 * v0.11.0 section) — this module is a thin client, same pattern as
 * participation.js.
 */
(function () {
  "use strict";

  const safe = (value) =>
    String(value ?? "").replace(/[&<>'"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", "'": "&#39;", '"': "&quot;" }[c]));

  async function currentUserOrNull() {
    const { data: { user } } = await window.supabaseClient.auth.getUser();
    return user || null;
  }

  async function getMyAttendance(questId, userId) {
    if (!userId) return null;
    const { data, error } = await window.supabaseClient
      .from("quest_attendance")
      .select("id,status,proof_text,proof_url,submitted_at,reviewed_at,review_notes")
      .eq("quest_id", questId)
      .eq("user_id", userId)
      .maybeSingle();
    if (error) { console.error("getMyAttendance failed", error); return null; }
    return data;
  }

  async function submitCompletion(questId, proofText, proofUrl) {
    const { error } = await window.supabaseClient.rpc("submit_quest_completion", {
      p_quest_id: questId,
      p_proof_text: proofText,
      p_proof_url: proofUrl || null,
    });
    return { error };
  }

  async function loadAttendanceForQuest(questId) {
    return window.supabaseClient
      .from("quest_attendance")
      .select("id,user_id,proof_text,proof_url,submitted_at,status,reviewed_at,review_notes,profiles:user_id(display_name,trust_score,verification_status)")
      .eq("quest_id", questId)
      .order("submitted_at", { ascending: false });
  }

  async function decideCompletion(questId, targetUserId, decision, notes) {
    const { error } = await window.supabaseClient.rpc("decide_quest_completion", {
      p_quest_id: questId,
      p_target_user_id: targetUserId,
      p_decision: decision,
      p_notes: notes || null,
    });
    return { error };
  }

  async function loadMyCompletionHistory(userId) {
    return window.supabaseClient
      .from("quest_attendance")
      .select("id,status,proof_text,submitted_at,reviewed_at,review_notes,quests:quest_id(id,title,category,quest_date)")
      .eq("user_id", userId)
      .order("submitted_at", { ascending: false });
  }

  async function loadReputationHistory(profileId, limit = 30) {
    return window.supabaseClient
      .from("reputation_history")
      .select("id,event_type,xp_delta,impact_points_delta,trust_score_delta,description,created_at,quest_id")
      .eq("profile_id", profileId)
      .order("created_at", { ascending: false })
      .limit(limit);
  }

  async function loadAllBadges() {
    return window.supabaseClient.from("badges").select("id,code,name,description,icon,criteria_type,criteria_value").order("criteria_value");
  }

  async function loadEarnedBadges(profileId) {
    return window.supabaseClient
      .from("profile_badges")
      .select("badge_id,earned_at,badges:badge_id(code,name,description,icon)")
      .eq("profile_id", profileId)
      .order("earned_at", { ascending: false });
  }

  async function loadXpLevels() {
    return window.supabaseClient.from("xp_levels").select("level,xp_required,title").order("level");
  }

  function levelProgress(levels, xp, level) {
    const sorted = [...levels].sort((a, b) => a.level - b.level);
    const current = sorted.find((l) => l.level === level) || sorted[0];
    const next = sorted.find((l) => l.level === level + 1);
    if (!next) return { title: current?.title || "", percent: 100, label: "Max level reached" };
    const span = next.xp_required - current.xp_required;
    const into = xp - current.xp_required;
    const percent = span > 0 ? Math.max(0, Math.min(100, Math.round((into / span) * 100))) : 100;
    return { title: current?.title || "", nextTitle: next.title, percent, label: `${xp} / ${next.xp_required} XP to Level ${next.level}` };
  }

  async function getLeaderboard(limit = 20) {
    return window.supabaseClient.rpc("get_leaderboard", { p_limit: limit });
  }

  function timeAgo(iso) {
    if (!iso) return "";
    const seconds = Math.floor((Date.now() - new Date(iso).getTime()) / 1000);
    if (seconds < 60) return "just now";
    const mins = Math.floor(seconds / 60);
    if (mins < 60) return `${mins}m ago`;
    const hours = Math.floor(mins / 60);
    if (hours < 24) return `${hours}h ago`;
    const days = Math.floor(hours / 24);
    if (days < 30) return `${days}d ago`;
    return new Date(iso).toLocaleDateString();
  }

  window.IQCompletion = {
    safe,
    currentUserOrNull,
    getMyAttendance,
    submitCompletion,
    loadAttendanceForQuest,
    decideCompletion,
    loadMyCompletionHistory,
    loadReputationHistory,
    loadAllBadges,
    loadEarnedBadges,
    loadXpLevels,
    levelProgress,
    getLeaderboard,
    timeAgo,
  };
})();
