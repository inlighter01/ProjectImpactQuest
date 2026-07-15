/** Impact Quest v0.9.6 - Approved community quest feed. */
(function () {
  "use strict";
  const list = document.getElementById("feedList");
  const featured = document.getElementById("featuredQuest");
  const search = document.getElementById("questSearch");
  const filter = document.getElementById("categoryFilter");
  let quests = [];

  const safe = (value) => String(value ?? "").replace(/[&<>'"]/g, (char) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", "'": "&#39;", '"': "&quot;" })[char]);

  function render(items) {
    if (!list) return;
    if (!items.length) {
      list.innerHTML = `<section class="empty-state"><h2>Your community is waiting for its next act of kindness.</h2><p>There are no approved quests matching this search yet.</p><a class="btn btn-primary" href="create-quest.html">Create the First Community Quest</a></section>`;
      if (featured) featured.hidden = true;
      return;
    }
    const [first, ...rest] = items;
    if (featured) {
      featured.hidden = false;
      featured.innerHTML = `<article class="quest-card"><span class="status-pill approved">Featured quest</span><h2>${safe(first.title)}</h2><p>${safe(first.why_it_matters || first.description)}</p><p class="quest-meta">${safe(first.category)} · ${safe(first.city)}, ${safe(first.barangay)}</p><a class="btn btn-primary" href="quest-details.html?id=${encodeURIComponent(first.id)}">View Quest</a></article>`;
    }
    list.innerHTML = rest.map(card).join("") || `<p class="quest-message">This is currently the featured community quest.</p>`;
  }

  function card(quest) {
    return `<article class="quest-card"><span class="status-pill approved">Approved</span><h2>${safe(quest.title)}</h2><p class="quest-meta">${safe(quest.category)} · ${safe(quest.city)}, ${safe(quest.barangay)}</p><p>${safe(quest.description)}</p><dl class="quest-details-list"><div><dt>Volunteers</dt><dd>${quest.joined_count || 0}/${quest.volunteer_limit || 1}</dd></div><div><dt>Date</dt><dd>${safe(quest.quest_date || "To be confirmed")}</dd></div></dl><a class="btn btn-outline" href="quest-details.html?id=${encodeURIComponent(quest.id)}">View Quest</a></article>`;
  }

  function applyFilters() {
    const term = search?.value.trim().toLowerCase() || "";
    const category = filter?.value || "";
    const filtered = quests.filter((quest) => {
      const haystack = [quest.title, quest.category, quest.city, quest.barangay, quest.description].join(" ").toLowerCase();
      return (!term || haystack.includes(term)) && (!category || quest.category === category);
    });
    render(filtered);
  }

  async function load() {
    if (!window.supabaseClient) return;
    const { data, error } = await window.supabaseClient.from("quests").select("id,title,category,description,why_it_matters,city,barangay,quest_date,volunteer_limit,joined_count,status").eq("status", "approved").order("created_at", { ascending: false });
    if (error) {
      list.innerHTML = `<p class="quest-message error">We could not load community quests: ${safe(error.message)}</p>`;
      return;
    }
    quests = data || [];
    const categories = [...new Set(quests.map((quest) => quest.category).filter(Boolean))];
    if (filter) filter.insertAdjacentHTML("beforeend", categories.map((category) => `<option value="${safe(category)}">${safe(category)}</option>`).join(""));
    applyFilters();
  }

  document.addEventListener("DOMContentLoaded", () => { search?.addEventListener("input", applyFilters); filter?.addEventListener("change", applyFilters); load(); });
})();
