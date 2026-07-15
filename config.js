/**
 * Impact Quest – Supabase Client Configuration
 *
 * Creates ONE global Supabase client.
 * Prevents duplicate initialization.
 * Safe to load on every page.
 */

const SUPABASE_URL = "https://tkzwqjcosmjbufbrdned.supabase.co";
const SUPABASE_ANON_KEY = "sb_publishable_QoFTQjnIMbgY2by9jj1CCQ_85mnRBVG";

// Check if configuration exists
const isConfigured =
  SUPABASE_URL &&
  SUPABASE_ANON_KEY &&
  !SUPABASE_URL.includes("your-project-id") &&
  !SUPABASE_ANON_KEY.includes("your-anon-key");

// Stop immediately if Supabase JS wasn't loaded
if (!window.supabase) {
  console.error("❌ Supabase library failed to load.");
} else {
  // Create the client ONLY ONCE
 if (!window.supabaseClient) {
  window.supabaseClient = window.supabase.createClient(
    SUPABASE_URL,
    SUPABASE_ANON_KEY
  );
}