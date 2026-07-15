/**
 * Impact Quest – Auth Module
 * Uses the global `supabase` client from supabase-client.js
 */

// ---------- Registration ----------
async function registerUser(email, password, displayName) {
  const { data, error } = await supabase.auth.signUp({
    email,
    password,
    options: {
      data: {
        display_name: displayName,
      },
      emailRedirectTo: `${window.location.origin}/email-verified.html`,
    },
  });
  return { data, error };
}

// ---------- Login ----------
async function loginUser(email, password) {
  const { data, error } = await supabase.auth.signInWithPassword({
    email,
    password,
  });
  return { data, error };
}

// ---------- Logout ----------
async function logoutUser() {
  const { error } = await supabase.auth.signOut();
  if (error) console.error('Logout error:', error);
  window.location.href = '/index.html';
}

// ---------- Get current session/user ----------
async function getCurrentUser() {
  const { data: { user } } = await supabase.auth.getUser();
  return user;
}

// ---------- Send password reset email ----------
async function sendPasswordReset(email) {
  const { data, error } = await supabase.auth.resetPasswordForEmail(email, {
    redirectTo: `${window.location.origin}/reset-password.html`,
  });
  return { data, error };
}

// ---------- Update password (after reset) ----------
async function updatePassword(newPassword) {
  const { data, error } = await supabase.auth.updateUser({
    password: newPassword,
  });
  return { data, error };
}

// ---------- Listen for auth state changes ----------
supabase.auth.onAuthStateChange((event, session) => {
  // Optional: handle session changes globally
  if (event === 'SIGNED_IN') {
    console.log('User signed in:', session.user.email);
  }
  if (event === 'SIGNED_OUT') {
    console.log('User signed out');
  }
});