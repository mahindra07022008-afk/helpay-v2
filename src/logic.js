/** Pure, dependency-free business logic, shared by UI and Node tests. */
export const CATEGORIES = ['Shopping', 'Food', 'Education', 'Travel', 'Fashion', 'Services'];
export const MAX_TITLE_LENGTH = 90;

export function escapeHtml(value) {
  return String(value ?? '').replace(/[&<>"']/g, char => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'
  })[char]);
}

export function isValidOfferUrl(value) {
  try {
    const url = new URL(value);
    return url.protocol === 'https:' && Boolean(url.hostname) &&
      !url.username && !url.password && !['localhost', '127.0.0.1'].includes(url.hostname) &&
      !/^(10\.|127\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.)/.test(url.hostname);
  } catch { return false; }
}

export function validateOffer(data) {
  const errors = [];
  if (!data.title?.trim() || data.title.trim().length > MAX_TITLE_LENGTH) errors.push('Title must contain 1–90 characters.');
  if (!data.brand?.trim() || data.brand.trim().length > 70) errors.push('Brand must contain 1–70 characters.');
  if (!CATEGORIES.includes(data.category)) errors.push('Select a supported category.');
  if (!data.description?.trim() || data.description.trim().length > 500) errors.push('Description must contain 1–500 characters.');
  if (!isValidOfferUrl(data.source_url)) errors.push('Use a valid public HTTPS offer URL (no private codes).');
  if (!data.terms?.trim() || data.terms.trim().length > 1000) errors.push('Add clear terms, up to 1,000 characters.');
  if (!['flat', 'percent'].includes(data.discount_type)) errors.push('Select a discount type.');
  const value = Number(data.discount_value);
  if (!Number.isFinite(value) || value <= 0 || value > 100000 || (data.discount_type === 'percent' && value > 100)) errors.push('Discount value is invalid.');
  const minimum = Number(data.min_spend);
  if (!Number.isFinite(minimum) || minimum < 0 || minimum > 10000000) errors.push('Minimum spend is invalid.');
  const expiry = new Date(data.expires_at);
  if (!Number.isFinite(expiry.getTime()) || expiry.getTime() <= Date.now()) errors.push('Offer must expire in the future.');
  if (data.acknowledged !== true) errors.push('Confirm that this is a public offer, not a private or non-transferable reward.');
  return errors;
}

export function calculateSavings({ subtotal, type, amount, cap = null, minimumSpend = 0 }) {
  const spend = Number(subtotal), value = Number(amount), min = Number(minimumSpend);
  const maximum = cap == null || cap === '' ? Infinity : Number(cap);
  if (![spend, value, min].every(Number.isFinite) || (maximum !== Infinity && !Number.isFinite(maximum))) return { error: 'Enter valid numeric values.' };
  if (spend < 0 || value < 0 || min < 0 || maximum < 0 || !['flat', 'percent'].includes(type) || (type === 'percent' && value > 100)) return { error: 'Enter valid positive amounts and a percentage up to 100.' };
  if (spend < min) return { eligible: false, savings: 0, finalPrice: spend, missing: min - spend };
  const raw = type === 'percent' ? (spend * value) / 100 : value;
  const savings = Math.round(Math.max(0, Math.min(raw, maximum, spend)) * 100) / 100;
  return { eligible: true, savings, finalPrice: Math.round((spend - savings) * 100) / 100, missing: 0 };
}

export function formatINR(value) {
  return new Intl.NumberFormat('en-IN', { style: 'currency', currency: 'INR', maximumFractionDigits: 2 }).format(Number(value) || 0);
}

export function offerExpired(offer) { return Date.parse(offer.expires_at) <= Date.now(); }

export function filterOffers(offers, { query = '', category = 'All', sort = 'newest' } = {}) {
  const term = query.toLocaleLowerCase().trim();
  const items = offers.filter(item => !offerExpired(item) && item.status === 'published' &&
    (category === 'All' || item.category === category) &&
    (!term || [item.title, item.brand, item.category, item.description].some(v => String(v).toLowerCase().includes(term))));
  return items.sort((a, b) => sort === 'expiring' ? new Date(a.expires_at) - new Date(b.expires_at) :
    sort === 'value' ? Number(b.discount_value) - Number(a.discount_value) :
    new Date(b.created_at) - new Date(a.created_at));
}



export function categoryIcon(category) {
  return ({Shopping:'🛍️',Food:'🍜',Education:'🎓',Travel:'✈️',Fashion:'👟',Services:'🧰'})[category] || '🎟️';
}
