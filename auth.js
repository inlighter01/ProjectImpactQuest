/**
 * Impact Quest – Authentication Module
 * Uses the global window.supabaseClient from config.js
 */

// ---------- Registration ----------
async function registerUser(email, password, displayName) {
  const { data, error } = await window.supabaseClient.auth.signUp({
    email,
    password,
    options: {
      data: {
        display_name: displayName,
      },
      emailRedirectTo: `${window.location.origin}/ProjectImpactQuest/email-verified.html`,
    },
  });

  return { data, error };
}

// ---------- Login ----------
async function loginUser(email, password) {
  return await window.supabaseClient.auth.signInWithPassword({
    email,
    password,
  });
}

// ---------- Logout ----------
async function logoutUser() {
  const { error } = await window.supabaseClient.auth.signOut();

  if (error) {
    console.error(error);
    return;
  }

  window.location.href = "login.html";
}

// ---------- Current User ----------
async function getCurrentUser() {
  const {
    data: { user },
  } = await window.supabaseClient.auth.getUser();

  return user;
}

// ---------- Password Reset ----------
async function sendPasswordReset(email) {
  return await window.supabaseClient.auth.resetPasswordForEmail(email, {
    redirectTo: `${window.location.origin}/ProjectImpactQuest/reset-password.html`,
  });
}

// ---------- Update Password ----------
async function updatePassword(password) {
  return await window.supabaseClient.auth.updateUser({
    password,
  });
}

// ---------- Auth Listener ----------
window.supabaseClient.auth.onAuthStateChange((event, session) => {
  console.log("Auth Event:", event);

  if (session) {
    console.log("Logged in:", session.user.email);
  }
});