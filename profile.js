/**
 * Impact Quest – Profile Module
 * Handles fetching, updating, and creating profile data.
 */

// ---------- Get or create profile ----------
async function getOrCreateProfile(user) {
  const { data: existing, error: fetchError } = await window.supabaseClient
    .from('profiles')
    .select('*')
    .eq('user_id', user.id)
    .single();

  if (existing) return existing;

  // If no profile exists (e.g., user registered before this table was created), create one
  const { data: created, error: insertError } = await window.supabaseClient
    .from('profiles')
    .insert({
      user_id: user.id,
      display_name: user.user_metadata?.display_name || user.email?.split('@')[0] || 'Member',
      avatar_url: null
    })
    .select()
    .single();

  if (insertError) throw insertError;
  return created;
}

// ---------- Update profile ----------
async function updateProfile(userId, updates) {
  const { data, error } = await window.supabaseClient
    .from('profiles')
    .update(updates)
    .eq('user_id', userId)
    .select()
    .single();
  return { data, error };
}

// ---------- Upload avatar placeholder ----------
async function uploadAvatar(file) {
  // Placeholder – will be connected to Supabase Storage in a future version
  // For now, we just return a fake URL or show the file as a data URL
  return new Promise((resolve) => {
    const reader = new FileReader();
    reader.onload = (e) => resolve(e.target.result);
    reader.readAsDataURL(file);
  });
}