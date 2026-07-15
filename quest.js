/** Impact Quest v0.9.6 - Community Quest data module. */
(function () {
  "use strict";

  const form = document.getElementById("questForm");
  const message = document.getElementById("questMessage");
  const preview = document.getElementById("preview");
  const questList = document.getElementById("questList");

  function notify(text, type = "info") {
    if (message) {
      message.textContent = text;
      message.className = `quest-message ${type}`;
      message.hidden = false;
    } else {
      alert(text);
    }
  }

  async function requireUser() {
    const { data: { user }, error } = await window.supabaseClient.auth.getUser();
    if (error || !user) {
      window.location.href = "login.html";
      return null;
    }
    return user;
  }

  function value(id) {
    return document.getElementById(id)?.value.trim() || "";
  }

  function readQuest() {
    return {
      title: value("title"),
      category: value("category"),
      description: value("description"),
      why_it_matters: value("whyItMatters"),
      city: value("city"),
      barangay: value("barangay"),
      meeting_point: value("meetingPoint") || null,
      quest_date: value("questDate") || null,
      quest_time: value("questTime") || null,
      duration: value("duration") || null,
      volunteer_limit: Number.parseInt(value("volunteerLimit"), 10) || 1,
      verification_method: value("verificationMethod"),
      safety_notes: value("safetyNotes") || null
    };
  }

  function validateQuest(quest, submitting) {
    const required = ["title", "category", "description", "why_it_matters", "city", "barangay", "verification_method"];
    if (submitting && required.some((key) => !quest[key])) {
      notify("Please complete all required quest details before submitting for review.", "error");
      return false;
    }
    return true;
  }

  async function saveQuest(status) {
    const user = await requireUser();
    if (!user) return;
    const quest = readQuest();
    const submitting = status === "submitted";
    if (!validateQuest(quest, submitting)) return;

    const submitButton = document.getElementById("submitQuest");
    if (submitButton) submitButton.disabled = true;

    const { data, error } = await window.supabaseClient
      .from("quests")
      .insert({ ...quest, creator_id: user.id, status })
      .select("id")
      .single();

    if (submitButton) submitButton.disabled = false;
    if (error) {
      console.error("Quest save failed", error);
      notify(`We could not save this quest: ${error.message}`, "error");
      return;
    }

    sessionStorage.removeItem("iqQuestPreview");
    notify(status === "draft" ? "Draft saved in My Quests." : "Quest submitted for moderator review.", "success");
    window.setTimeout(() => { window.location.href = "my-quests.html"; }, 650);
    return data;
  }

  function renderPreview(quest) {
    if (!preview) return;
    preview.innerHTML = `
      <article class="quest-card quest-preview-card">
        <span class="status-pill pending">Preview</span>
        <h2>${escapeHtml(quest.title || "Untitled Community Quest")}</h2>
        <p class="quest-meta">${escapeHtml(quest.category || "Category not selected")} · ${escapeHtml(quest.city || "City not set")}${quest.barangay ? `, ${escapeHtml(quest.barangay)}` : ""}</p>
        <h3>Why it matters</h3><p>${escapeHtml(quest.why_it_matters || "Tell your community why this quest matters.")}</p>
        <h3>Quest details</h3><p>${escapeHtml(quest.description || "No description added yet.")}</p>
        <dl class="quest-details-list">
          <div><dt>Volunteers</dt><dd>${quest.volunteer_limit || 1}</dd></div>
          <div><dt>Verification</dt><dd>${escapeHtml(quest.verification_method || "Not selected")}</dd></div>
          <div><dt>Schedule</dt><dd>${escapeHtml(quest.quest_date || "To be confirmed")} ${escapeHtml(quest.quest_time || "")}</dd></div>
        </dl>
      </article>`;
  }

  function escapeHtml(value) {
    return String(value).replace(/[&<>'"]/g, (character) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", "'": "&#39;", '"': "&quot;" })[character]);
  }

  async function loadMyQuests() {
    const user = await requireUser();
    if (!user || !questList) return;
    const { data, error } = await window.supabaseClient
      .from("quests")
      .select("id,title,category,city,barangay,status,created_at,quest_date")
      .eq("creator_id", user.id)
      .order("created_at", { ascending: false });
    if (error) {
      questList.innerHTML = `<p class="quest-message error">We could not load your quests: ${escapeHtml(error.message)}</p>`;
      return;
    }
    if (!data.length) {
      questList.innerHTML = `<section class="empty-state"><h2>Your first quest can start a ripple.</h2><p>Create a Community Quest when your neighborhood needs help.</p><a class="btn btn-primary" href="create-quest.html">Create a Community Quest</a></section>`;
      return;
    }
    questList.innerHTML = data.map((quest) => `
      <article class="quest-card">
        <span class="status-pill ${escapeHtml(quest.status)}">${escapeHtml(formatStatus(quest.status))}</span>
        <h2>${escapeHtml(quest.title)}</h2>
        <p class="quest-meta">${escapeHtml(quest.category)} · ${escapeHtml(quest.city)}, ${escapeHtml(quest.barangay)}</p>
        <p>${quest.quest_date ? `Scheduled for ${escapeHtml(quest.quest_date)}` : "Schedule to be confirmed"}</p>
      </article>`).join("");
  }

  function formatStatus(status) { return String(status).replace(/(^|_)([a-z])/g, (_, __, letter) => ` ${letter.toUpperCase()}`).trim(); }

  document.addEventListener("DOMContentLoaded", () => {
    if (form) {
      requireUser();
      document.getElementById("saveDraft")?.addEventListener("click", () => saveQuest("draft"));
      document.getElementById("previewBtn")?.addEventListener("click", () => {
        sessionStorage.setItem("iqQuestPreview", JSON.stringify(readQuest()));
        window.location.href = "quest-preview.html";
      });
      form.addEventListener("submit", (event) => { event.preventDefault(); saveQuest("submitted"); });
    }
    if (preview) renderPreview(JSON.parse(sessionStorage.getItem("iqQuestPreview") || "{}"));
    if (questList) loadMyQuests();
  });
})();
