/** Impact Quest v0.9.7 - Moderator review workflow. */
(function () {
  "use strict";
  const queue = document.getElementById("moderatorQueue");
  const review = document.getElementById("reviewQuest");
  const message = document.getElementById("moderatorMessage");
  const safe = (v) => String(v ?? "").replace(/[&<>'"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", "'": "&#39;", '"': "&quot;" })[c]);

  function say(text, type = "info") { if (message) { message.textContent = text; message.className = `quest-message ${type}`; message.hidden = false; } }

  async function moderatorUser() {
    const { data: { user } } = await window.supabaseClient.auth.getUser();
    if (!user) { location.href = "login.html"; return null; }
    const { data: profile, error } = await window.supabaseClient.from("profiles").select("role,display_name").eq("user_id", user.id).single();
    if (error || !["moderator", "admin"].includes(profile?.role)) {
      document.body.innerHTML = `<main class="quest-container"><section class="empty-state"><h1>Moderator access required</h1><p>This area is only for assigned community moderators.</p><a class="btn btn-primary" href="profile.html">Return to Profile</a></section></main>`;
      return null;
    }
    return user;
  }

  async function loadQueue() {
    const user = await moderatorUser(); if (!user || !queue) return;
    const { data, error } = await window.supabaseClient.from("quests").select("id,title,category,city,barangay,created_at,creator_id").eq("status", "submitted").order("created_at", { ascending: true });
    if (error) { say(`Could not load the review queue: ${error.message}`, "error"); return; }
    document.getElementById("pendingCount").textContent = data.length;
    queue.innerHTML = data.length ? data.map((q) => `<article class="quest-card"><span class="status-pill submitted">Awaiting review</span><h2>${safe(q.title)}</h2><p class="quest-meta">${safe(q.category)} · ${safe(q.city)}, ${safe(q.barangay)}</p><a class="btn btn-primary" href="review-quest.html?id=${encodeURIComponent(q.id)}">Review Quest</a></article>`).join("") : `<section class="empty-state"><h2>The review queue is clear.</h2><p>New submitted Community Quests will appear here.</p></section>`;
  }

  async function loadReview() {
    const user = await moderatorUser(); if (!user || !review) return;
    const id = new URLSearchParams(location.search).get("id");
    if (!id) { say("Choose a quest from the moderator queue.", "error"); return; }
    const { data: q, error } = await window.supabaseClient.from("quests").select("*").eq("id", id).single();
    if (error || q.status !== "submitted") { say("This quest is unavailable for review.", "error"); return; }
    review.innerHTML = `<article class="quest-card"><span class="status-pill submitted">Submitted for review</span><h1>${safe(q.title)}</h1><p class="quest-meta">${safe(q.category)} · ${safe(q.city)}, ${safe(q.barangay)}</p><h2>Why this matters</h2><p>${safe(q.why_it_matters)}</p><h2>Quest details</h2><p>${safe(q.description)}</p><dl class="quest-details-list"><div><dt>Meeting point</dt><dd>${safe(q.meeting_point || "Not specified")}</dd></div><div><dt>Schedule</dt><dd>${safe(q.quest_date || "Not set")} ${safe(q.quest_time || "")}</dd></div><div><dt>Volunteers</dt><dd>${q.volunteer_limit}</dd></div><div><dt>Verification</dt><dd>${safe(q.verification_method)}</dd></div></dl><h2>Safety notes</h2><p>${safe(q.safety_notes || "None provided")}</p><label>Feedback for the quest giver<textarea id="reviewNotes" maxlength="1000" placeholder="Required for requested changes or rejection."></textarea></label><div class="form-actions"><button class="btn btn-secondary" data-action="needs_changes">Request Changes</button><button class="btn btn-danger" data-action="rejected">Reject</button><button class="btn btn-primary" data-action="approved">Approve Quest</button></div></article>`;
    review.querySelectorAll("[data-action]").forEach((button) => button.addEventListener("click", () => updateReview(q.id, button.dataset.action, user.id)));
  }

  async function updateReview(id, status, moderatorId) {
    const notes = document.getElementById("reviewNotes").value.trim();
    if (["needs_changes", "rejected"].includes(status) && !notes) { say("Please give the quest giver clear feedback before continuing.", "error"); return; }
    const { error } = await window.supabaseClient.from("quests").update({ status, review_notes: notes || null, reviewed_by: moderatorId, reviewed_at: new Date().toISOString() }).eq("id", id);
    if (error) { say(`Review could not be saved: ${error.message}`, "error"); return; }
    location.href = "moderator-dashboard.html";
  }

  document.addEventListener("DOMContentLoaded", () => { if (queue) loadQueue(); if (review) loadReview(); });
})();
