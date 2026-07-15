/**
 * Impact Quest v0.10.0 — Notifications Module
 * Backed by public.notifications (see supabase-setup.sql). Notifications
 * are only ever written by SECURITY DEFINER triggers/RPCs — this module
 * only reads them and marks them read for the signed-in user.
 */
(function () {
  "use strict";

  const ICONS = {
    quest_joined: "✅",
    quest_left: "↩️",
    quest_approved: "🎉",
    quest_rejected: "⚠️",
    organizer_announcement: "📣",
    quest_cancelled: "🚫",
    quest_reminder: "⏰",
    new_participant: "🙋",
  };

  async function loadNotifications(limit = 50) {
    const { data: { user } } = await window.supabaseClient.auth.getUser();
    if (!user) return { data: [], error: null, user: null };
    const { data, error } = await window.supabaseClient
      .from("notifications")
      .select("id,type,title,body,quest_id,is_read,created_at")
      .eq("user_id", user.id)
      .order("created_at", { ascending: false })
      .limit(limit);
    return { data: data || [], error, user };
  }

  async function unreadCount(userId) {
    const { count, error } = await window.supabaseClient
      .from("notifications")
      .select("id", { count: "exact", head: true })
      .eq("user_id", userId)
      .eq("is_read", false);
    if (error) {
      console.error("unreadCount failed", error);
      return 0;
    }
    return count || 0;
  }

  async function markRead(notificationId) {
    return window.supabaseClient.from("notifications").update({ is_read: true }).eq("id", notificationId);
  }

  async function markAllRead(userId) {
    return window.supabaseClient.from("notifications").update({ is_read: true }).eq("user_id", userId).eq("is_read", false);
  }

  /**
   * Wires up a notification bell + badge already present in the page
   * (elements with ids #notifBell and #notifBadge). Loads the initial
   * unread count and subscribes to realtime inserts so the badge updates
   * live without a page refresh.
   */
  async function mountBell() {
    const bell = document.getElementById("notifBell");
    const badge = document.getElementById("notifBadge");
    if (!bell || !badge) return;

    const { data: { user } } = await window.supabaseClient.auth.getUser();
    if (!user) {
      bell.closest(".notif-bell-wrap")?.setAttribute("hidden", "");
      return;
    }

    const refresh = async () => {
      const count = await unreadCount(user.id);
      if (count > 0) {
        badge.textContent = count > 99 ? "99+" : String(count);
        badge.hidden = false;
      } else {
        badge.hidden = true;
      }
    };

    await refresh();

    window.supabaseClient
      .channel(`notifications-${user.id}`)
      .on(
        "postgres_changes",
        { event: "INSERT", schema: "public", table: "notifications", filter: `user_id=eq.${user.id}` },
        refresh
      )
      .subscribe();
  }

  window.IQNotifications = { ICONS, loadNotifications, unreadCount, markRead, markAllRead, mountBell };

  document.addEventListener("DOMContentLoaded", () => {
    if (window.supabaseClient) mountBell();
  });
})();
