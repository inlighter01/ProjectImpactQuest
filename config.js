/**
 * Impact Quest – Supabase Client Configuration
 *
 * IMPORTANT: Replace the placeholder values below with your actual
 * Supabase project URL and anon key.
 * These are public values – they are safe to include in frontend code.
 * Never commit service_role keys.
 *
 * (This file was named `supabase-client.js` in v0.4.0. It has been
 * renamed to `config.js` in this build because the v0.5.0 pages
 * reference it under that name. Nothing else changed.)
 */

const SUPABASE_URL = 'https://tkzwqjcosmjbufbrdned.supabase.co';
const SUPABASE_ANON_KEY = 'sb_publishable_QoFTQjnIMbgY2by9jj1CCQ_85mnRBVG';

// True once you've replaced the placeholders above with real values.
// Auth/profile pages check this and redirect home if setup isn't finished yet.
const isConfigured = !SUPABASE_URL.includes('your-project-id') && !SUPABASE_ANON_KEY.includes('...');

// Initialize Supabase client
const supabase = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
