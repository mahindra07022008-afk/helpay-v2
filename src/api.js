import { CONFIG } from './config.js';

const url = String(CONFIG.SUPABASE_URL || '').replace(/\/+$/, '');
const key = CONFIG.SUPABASE_PUBLISHABLE_KEY;
export const isLive = /^https:\/\/[-a-z0-9]+\.supabase\.co$/i.test(url) && !!key;
const SESSION_KEY = 'helpay_session_v1';
let session = null;
try { session = JSON.parse(localStorage.getItem(SESSION_KEY) || 'null'); } catch { localStorage.removeItem(SESSION_KEY); }

function remember(next) {
  session = next;
  if (session) localStorage.setItem(SESSION_KEY, JSON.stringify(session));
  else localStorage.removeItem(SESSION_KEY);
}

async function request(path, { method = 'GET', body, authenticated = false, prefer } = {}) {
  if (!isLive) throw new Error('Connect Supabase first. See README.md.');
  const headers = { apikey: key, Accept: 'application/json' };
  if (body !== undefined) headers['Content-Type'] = 'application/json';
  if (authenticated) {
    if (!session?.access_token) throw new Error('Sign in first.');
    headers.Authorization = `Bearer ${session.access_token}`;
  } // For anonymous requests, the apikey header alone identifies the public client.
  if (prefer) headers.Prefer = prefer;
  let response;
  try {
    response = await fetch(url + path, { method, headers, body: body === undefined ? undefined : JSON.stringify(body) });
  } catch { throw new Error('Network error. Check your internet and Supabase project.'); }
  let payload = null;
  try { payload = await response.json(); } catch { /* HTTP 204 / empty result */ }
  if (!response.ok) {
    if (response.status === 401 && authenticated) remember(null);
    throw new Error(payload?.msg || payload?.message || payload?.error_description || payload?.error || `Request failed (${response.status}).`);
  }
  return payload;
}

export async function getSession() {
  if (!isLive || !session?.access_token) return null;
  if (session.expires_at && Date.now() > (session.expires_at - 60) * 1000) {
    if (!session.refresh_token) { remember(null); return null; }
    try {
      const next = await request('/auth/v1/token?grant_type=refresh_token', {method:'POST',body:{refresh_token:session.refresh_token}});
      remember({...next, expires_at:Math.floor(Date.now()/1000)+next.expires_in});
    } catch { remember(null); return null; }
  }
  try {
    const user = await request('/auth/v1/user', {authenticated:true});
    return user?.id ? user : null;
  } catch { return null; }
}

export async function signIn(email, password) {
  const result = await request('/auth/v1/token?grant_type=password', {method:'POST',body:{email,password}});
  remember({...result, expires_at:Math.floor(Date.now()/1000)+result.expires_in});
  return result.user;
}
export async function signUp(email, password) {
  return request('/auth/v1/signup', { method:'POST', body:{email,password} });
}
export async function signOut() {
  try { if (session?.access_token) await request('/auth/v1/logout', {method:'POST',authenticated:true}); }
  finally { remember(null); }
}
export async function listOffers() {
  // RLS on Supabase is the true authorization boundary. UI filtering is additional.
  return request('/rest/v1/offers?select=id,seller_id,brand,title,category,description,discount_type,discount_value,min_spend,max_saving,expires_at,source_url,terms,status,created_at&status=eq.published&order=created_at.desc&limit=100');
}
export async function myOffers(userId) {
  return request(`/rest/v1/offers?select=*&seller_id=eq.${encodeURIComponent(userId)}&order=created_at.desc`, {authenticated:true});
}
export async function submitOffer(data) {
  return request('/rest/v1/offers', {method:'POST',authenticated:true,prefer:'return=representation',body:data});
}
export async function listFavourites(userId) {
  return request(`/rest/v1/favourites?select=offer_id&user_id=eq.${encodeURIComponent(userId)}`, {authenticated:true});
}
export async function addFavourite(userId, offerId) {
  return request('/rest/v1/favourites', { method:'POST',authenticated:true,prefer:'return=minimal',body:{user_id:userId,offer_id:offerId}});
}
export async function removeFavourite(userId, offerId) {
  return request(`/rest/v1/favourites?user_id=eq.${encodeURIComponent(userId)}&offer_id=eq.${encodeURIComponent(offerId)}`, {method:'DELETE',authenticated:true});
}
export async function reportOffer(userId, offerId, reason) {
  return request('/rest/v1/reports', {method:'POST',authenticated:true,prefer:'return=minimal',body:{reporter_id:userId,offer_id:offerId,reason}});
}
export async function adminRole(userId) {
  const roles = await request(`/rest/v1/user_roles?select=role&user_id=eq.${encodeURIComponent(userId)}`, {authenticated:true});
  return Array.isArray(roles) && roles.some(row => row.role === 'admin');
}
export async function pendingOffers() {
  return request('/rest/v1/offers?select=*&status=eq.pending&order=created_at.asc&limit=100',{authenticated:true});
}
export async function moderateOffer(offerId, action) {
  return request('/rest/v1/rpc/moderate_offer', {method:'POST',authenticated:true,body:{p_offer_id:offerId,p_action:action}});
}
