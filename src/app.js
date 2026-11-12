import { isLive, getSession, signIn, signUp, signOut, listOffers, myOffers, submitOffer, listFavourites, addFavourite, removeFavourite, reportOffer, adminRole, pendingOffers, moderateOffer } from './api.js';
import { CATEGORIES, escapeHtml as esc, validateOffer, calculateSavings, formatINR, filterOffers, categoryIcon, offerExpired } from './logic.js';

const root = document.querySelector('#app');
const state = {view:'explore', query:'', category:'All', sort:'newest', user:null, admin:false, offers:[], mine:[], pending:[], favourites:new Set(), detail:null, status:'', statusType:'', mode:'signin'};
const base = () => isLive ? 'Connected to Supabase' : 'Backend configuration required';
function setStatus(message, type='info') {state.status=message;state.statusType=type;render();}
function money(x) { return formatINR(x); }
const input = (name, label, type='text', value='', extra='') => `<label class="field"><span>${label}</span><input name="${name}" type="${type}" value="${esc(value)}" ${extra} required /></label>`;
const header = () => `<header class="header"><a href="#explore" class="brand" aria-label="Helpay home"><span class="brand-symbol">H</span><span>helpay<span class="brand-dot">.</span></span></a>
<nav class="nav" aria-label="Main navigation"><a href="#explore" class="nav-link ${state.view==='explore'?'active':''}">Discover</a><a href="#calculator" class="nav-link ${state.view==='calculator'?'active':''}">Savings calculator</a><a href="#submit" class="nav-link ${state.view==='submit'?'active':''}">Share an offer</a>${state.user?`<a href="#my-offers" class="nav-link ${state.view==='my-offers'?'active':''}">My offers</a>`:''}${state.admin?`<a href="#admin" class="nav-link ${state.view==='admin'?'active':''}">Moderation</a>`:''}</nav>
<div class="header-actions">${state.user?`<button class="btn btn-outline btn-small" data-action="logout">Sign out</button>`:`<button class="btn btn-outline btn-small" data-action="login">Sign in</button>`}</div></header>`;
const empty = (icon, title, body, action='') => `<section class="empty"><div class="empty-icon">${icon}</div><h3>${esc(title)}</h3><p>${esc(body)}</p>${action}</section>`;
function offerCard(o) {
  const liked=state.favourites.has(o.id);
  return `<article class="offer-card"><div class="offer-top"><div class="offer-icon">${categoryIcon(o.category)}</div><span class="pill">${esc(o.category)}</span></div><div class="offer-brand">${esc(o.brand)}</div><h3>${esc(o.title)}</h3><p class="offer-description">${esc(o.description)}</p><div class="offer-bottom"><div><span class="eyebrow">OFFER VALUE</span><div class="discount">${o.discount_type==='percent'?`${Number(o.discount_value)}% OFF`:`${money(o.discount_value)} OFF`}</div></div><button class="heart ${liked?'liked':''}" aria-label="${liked?'Remove favourite':'Save favourite'}" data-action="favourite" data-id="${esc(o.id)}">${liked?'♥':'♡'}</button></div><button class="btn btn-card" data-action="details" data-id="${esc(o.id)}">View details <span>↗</span></button></article>`;
}
function explore() {
 const visible=filterOffers(state.offers,state); const c=state.offers.filter(o=>o.status==='published'&&!offerExpired(o)).length;
 return `<section class="hero"><div class="hero-copy"><span class="topline">✦ DISCOVER SMARTER · SAVE SAFELY</span><h1>Find better offers.<br><span>Keep more of your money.</span></h1><p>Explore publicly available promotions, understand their terms and calculate potential savings — without risky coupon resale.</p><div class="hero-cta"><a class="btn btn-primary" href="#offers">Explore offers <span>↗</span></a><a class="btn btn-light" href="#calculator">Calculate savings</a></div><div class="hero-trust">✓ Clear terms &nbsp;&nbsp; ✓ Moderated submissions &nbsp;&nbsp; ✓ No hidden resale</div></div><div class="hero-illustration" aria-hidden="true"><div class="float float-a">✨ Smart savings</div><div class="hero-ticket"><div class="ticket-mark">H<span>•</span></div><div class="ticket-small">WELCOME TO HELPAY</div><div class="ticket-big">SAVE<br>SMARTER.</div><div class="ticket-bottom">DISCOVER MORE <span>✦ ✦ ✦</span></div></div><div class="float float-b">🛡️ Transparent offers</div></div></section>
 <section class="stats"><div><b>${c}</b><span>Available offers</span></div><div><b>${new Set(state.offers.map(o=>o.category)).size}</b><span>Categories</span></div><div><b>100%</b><span>Free to explore</span></div></section>
 <section id="offers" class="market"><div class="section-heading"><div><span class="topline dark">CURATED OPPORTUNITIES</span><h2>Discover available offers</h2><p>Review offer details and visit the official source to verify eligibility.</p></div><span class="result-count">${visible.length} results</span></div>
 <div class="filters"><label class="search-wrap"><span aria-hidden="true">⌕</span><input id="search" type="search" value="${esc(state.query)}" placeholder="Search offers, brands, categories..." aria-label="Search offers"/></label><label class="select-wrap"><span class="sr-only">Category</span><select id="category">${['All',...CATEGORIES].map(c=>`<option ${state.category===c?'selected':''}>${esc(c)}</option>`).join('')}</select></label><label class="select-wrap"><span class="sr-only">Sort</span><select id="sort"><option value="newest" ${state.sort==='newest'?'selected':''}>Newest first</option><option value="expiring" ${state.sort==='expiring'?'selected':''}>Expiring soon</option><option value="value" ${state.sort==='value'?'selected':''}>Highest discount</option></select></label></div>
 ${visible.length?`<div class="offer-grid">${visible.map(offerCard).join('')}</div>`:empty('🔎','No matching offers','Try another category or search term. Live offers only appear after admin approval.')}
 </section>`;
}
function calculator() {
 return `<section class="inner-page"><div class="section-heading"><div><span class="topline dark">THE NUMBERS, MADE SIMPLE</span><h2>Savings calculator</h2><p>Estimate a public promotion's discount. Actual eligibility depends on issuer terms.</p></div></div><div class="two-columns"><form id="calc-form" class="panel form-panel"><h3>Enter offer details</h3>${input('subtotal','Your planned purchase (₹)','number','1500','min="0" step="0.01"')}<label class="field"><span>Discount type</span><select name="type"><option value="percent">Percentage off</option><option value="flat">Flat amount off</option></select></label>${input('amount','Discount amount (₹ or %)','number','20','min="0" step="0.01"')}${input('minimumSpend','Minimum order (₹)','number','500','min="0" step="0.01"')}<label class="field"><span>Maximum discount cap (₹, optional)</span><input name="cap" type="number" min="0" step="0.01" placeholder="No cap" /></label><button class="btn btn-primary btn-wide">Calculate savings →</button></form><aside class="panel result-panel"><span class="topline dark">ESTIMATED RESULT</span><div class="result-emoji">💸</div><div id="calc-output"><h3>See your potential savings</h3><p>Enter the details, then choose Calculate savings to see a transparent estimate.</p></div><div class="result-note">This is a calculation tool, not a coupon validity check or purchase guarantee.</div></aside></div></section>`;
}
const offerForm = () => `<section class="inner-page"><div class="section-heading"><div><span class="topline dark">SHARE SOMETHING USEFUL</span><h2>Submit a public promotion</h2><p>Every offer requires review. Private payment-app rewards and resale listings are not supported.</p></div></div><div class="two-columns form-columns"><form id="offer-form" class="panel form-panel"><h3>Offer information</h3><div class="form-two">${input('brand','Brand name','text','','maxlength="70"')}${input('title','Offer title','text','','maxlength="90"')}</div><div class="form-two"><label class="field"><span>Category</span><select name="category">${CATEGORIES.map(c=>`<option>${esc(c)}</option>`).join('')}</select></label><label class="field"><span>Discount type</span><select name="discount_type"><option value="flat">Flat ₹ off</option><option value="percent">Percentage off</option></select></label></div><div class="form-two">${input('discount_value','Discount amount','number','','min="0.01" max="100000" step="0.01"')}${input('min_spend','Minimum spend (₹)','number','0','min="0" step="0.01"')}</div><div class="form-two"><label class="field"><span>Discount cap (₹, optional)</span><input name="max_saving" type="number" min="0" step="0.01" placeholder="No cap"/></label>${input('expires_at','Expiry date','date','','')}</div><label class="field"><span>Public source link (official HTTPS URL)</span><input type="url" name="source_url" placeholder="https://brand.example/offer" required maxlength="800" /></label><label class="field"><span>Offer description</span><textarea name="description" rows="3" maxlength="500" placeholder="What does this public offer include?" required></textarea></label><label class="field"><span>Eligibility and restrictions</span><textarea name="terms" rows="3" maxlength="1000" placeholder="Minimum order, exclusions, location, end date..." required></textarea></label><label class="check-row"><input type="checkbox" name="acknowledged" required/><span>I confirm this is a publicly advertised promotion, not a private or non-transferable voucher, and I have reviewed the source terms.</span></label><button class="btn btn-primary btn-wide" ${!state.user?'disabled title="Sign in first"':''}>Submit for review →</button>${!state.user?'<p class="hint">Sign in to submit a verified public offer.</p>':''}</form><aside class="panel guidance"><h3>Before you submit</h3><div class="guide-line">🛡️ <span>No private coupon codes or personal payment rewards.</span></div><div class="guide-line">🔗 <span>Provide a public official HTTPS source.</span></div><div class="guide-line">📋 <span>State applicable rules, minimum spend and expiry.</span></div><div class="guide-line">⏳ <span>New submissions stay pending until an administrator reviews them.</span></div><div class="notice">Submissions are stored in Supabase and remain pending until an administrator reviews them.</div></aside></div></section>`;
const statusPill = status => `<span class="pill ${status==='published'?'pill-live':status==='rejected'?'pill-red':''}">${esc(status)}</span>`;
function mine() {
 const rows=state.mine;
 return `<section class="inner-page"><div class="section-heading"><div><span class="topline dark">YOUR WORKSPACE</span><h2>My submissions</h2><p>Track whether offers are awaiting review, published, or rejected.</p></div><a class="btn btn-primary" href="#submit">+ Add an offer</a></div>${rows.length?`<div class="table-wrap"><table><thead><tr><th>Offer</th><th>Brand</th><th>Status</th><th>Expiry</th></tr></thead><tbody>${rows.map(o=>`<tr><td><strong>${esc(o.title)}</strong></td><td>${esc(o.brand)}</td><td>${statusPill(o.status)}</td><td>${new Date(o.expires_at).toLocaleDateString('en-IN')}</td></tr>`).join('')}</tbody></table></div>`:empty('📭','No submissions yet','Share your first public promotion using the submission form.')}</section>`;
}
function admin() {
 return `<section class="inner-page"><div class="section-heading"><div><span class="topline dark">TRUST & SAFETY</span><h2>Moderation queue</h2><p>Approve only publicly advertised promotions with verified sources and clear issuer terms.</p></div></div>${state.pending.length?`<div class="admin-list">${state.pending.map(o=>`<div class="panel admin-row"><div><h3>${esc(o.title)}</h3><p>${esc(o.brand)} · ${esc(o.category)} · ${esc(o.terms)}</p><a class="safe-link" href="${esc(o.source_url)}" rel="noopener noreferrer" target="_blank">Review source ↗</a></div><div class="admin-buttons"><button class="btn btn-primary" data-action="moderate" data-status="published" data-id="${esc(o.id)}">Approve</button><button class="btn btn-danger" data-action="moderate" data-status="rejected" data-id="${esc(o.id)}">Reject</button></div></div>`).join('')}</div>`:empty('✅','Queue is empty','No pending offers need approval.')}</section>`;
}
function detail() {
 const o=state.detail; if(!o)return '';
 return `<div class="modal-layer" role="presentation"><section class="modal" role="dialog" aria-modal="true" aria-label="Offer details"><div class="modal-head"><div class="offer-icon">${categoryIcon(o.category)}</div><button class="modal-close" data-action="close" aria-label="Close dialog">×</button></div><span class="pill">${esc(o.category)}</span><div class="offer-brand spaced">${esc(o.brand)}</div><h2>${esc(o.title)}</h2><p>${esc(o.description)}</p><div class="detail-grid"><div><span>Discount</span><b>${o.discount_type==='percent'?`${Number(o.discount_value)}%`:`${money(o.discount_value)}`}</b></div><div><span>Minimum spend</span><b>${money(o.min_spend)}</b></div><div><span>Expiry</span><b>${new Date(o.expires_at).toLocaleDateString('en-IN')}</b></div><div><span>Max savings</span><b>${o.max_saving==null?'See terms':money(o.max_saving)}</b></div></div><div class="terms"><b>Eligibility and conditions</b><p>${esc(o.terms)}</p></div><div class="modal-actions"><a class="btn btn-primary" href="${esc(o.source_url)}" target="_blank" rel="noopener noreferrer">Verify at source ↗</a><button class="btn btn-light" data-action="report" data-id="${esc(o.id)}">Report listing</button></div></section></div>`;
}
function authDialog() {
 return `<div class="modal-layer" role="presentation"><section class="modal auth-modal" role="dialog" aria-modal="true" aria-label="Account sign in"><button class="modal-close auth-close" data-action="close" aria-label="Close dialog">×</button><div class="brand auth-brand"><span class="brand-symbol">H</span>helpay<span class="brand-dot">.</span></div><h2>${state.mode==='signup'?'Create your account':'Welcome back'}</h2><p>${state.mode==='signup'?'Sign up to submit publicly listed offers.':'Sign in to track and submit your offers.'}</p><div class="auth-tabs"><button class="${state.mode==='signin'?'selected':''}" data-action="auth-mode" data-mode="signin">Sign in</button><button class="${state.mode==='signup'?'selected':''}" data-action="auth-mode" data-mode="signup">Sign up</button></div><form id="auth-form">${input('email','Email','email','','autocomplete="email"')}${input('password','Password','password','','minlength="8" autocomplete="current-password"')}<button class="btn btn-primary btn-wide">${state.mode==='signup'?'Create account':'Sign in'} →</button></form><p class="hint">Email confirmation may be required by your Supabase authentication settings.</p></section></div>`;
}
function footer() { return `<footer class="footer"><div><div class="brand"><span class="brand-symbol">H</span>helpay<span class="brand-dot">.</span></div><p>Better offers. Clearer terms. Smarter savings.</p></div><div class="foot-right"><p>Discover responsibly · © ${new Date().getFullYear()} Helpay</p><p>Independent offer-discovery platform · No brand partnerships implied · No coupon resale or payments</p></div></footer>`; }
function render() {
 const hash = location.hash.slice(1).split('?')[0]; if(hash==='offers') state.view='explore'; else if(['explore','calculator','submit','my-offers','admin'].includes(hash)) state.view=hash;
 if(state.view==='admin'&&!state.admin)state.view='explore';
 const page = ({explore,calculator,submit:offerForm,'my-offers':mine,admin})[state.view]();
 root.innerHTML = `${header()}<div class="mode-banner"><span class="status-dot"></span>${esc(base())}</div><main>${page}</main>${footer()}${state.status?`<div class="toast ${esc(state.statusType)}" role="status">${esc(state.status)}<button data-action="dismiss" aria-label="Dismiss">×</button></div>`:''}${state.detail==='auth'?authDialog():state.detail?detail():''}`;
 if(location.hash==='#offers')document.querySelector('#offers')?.scrollIntoView({behavior:'smooth'});
}
async function reload() {
 if(!isLive){state.offers=[];state.mine=[];state.favourites=new Set();setStatus('Supabase is not configured. Publication is blocked until the backend is connected.','error');return;}
 try {
  state.user=await getSession(); state.admin=state.user?await adminRole(state.user.id):false;
  state.offers=await listOffers(); state.mine=state.user?await myOffers(state.user.id):[];
  state.favourites=new Set(state.user?(await listFavourites(state.user.id)).map(x=>x.offer_id):[]);
  state.pending=state.admin?await pendingOffers():[];
  state.status='';render();
 } catch(err) {state.offers=[];setStatus(`Could not load live offers: ${err.message}`,'error');}
}
window.addEventListener('hashchange',()=>{state.detail=null;render();});
document.addEventListener('input',e=>{if(e.target.id==='search'){state.query=e.target.value;const focus=e.target.selectionStart;render();const el=document.querySelector('#search');el?.focus();el?.setSelectionRange(focus,focus);}});
document.addEventListener('change',e=>{if(e.target.id==='category'){state.category=e.target.value;render();}if(e.target.id==='sort'){state.sort=e.target.value;render();}});
document.addEventListener('click',async e=>{
 const el=e.target.closest('[data-action]');if(!el)return;
 const {action,id,status,mode}=el.dataset;
 try {
  if(action==='close'){state.detail=null;render();}
  if(action==='dismiss'){state.status='';render();}
  if(action==='login'){if(!isLive){setStatus('Add your Supabase URL and publishable key in src/config.js first. See README.md.');return;}state.mode='signin';state.detail='auth';render();}
  if(action==='auth-mode'){state.mode=mode;render();}
  if(action==='logout'){await signOut();state.user=null;state.admin=false;await reload();setStatus('Signed out.','success');}
  if(action==='details'){state.detail=state.offers.find(x=>x.id===id);render();}
  if(action==='favourite'){
   if(!state.user){setStatus('Sign in to save offers.');return;}
   const liked=state.favourites.has(id);
   if(liked)await removeFavourite(state.user.id,id);else await addFavourite(state.user.id,id); 
   if(liked)state.favourites.delete(id);else state.favourites.add(id);
      render();
  }
  if(action==='moderate') {if(!state.admin)return; if(!confirm(`${status==='published'?'Approve':'Reject'} this listing after reviewing the issuer terms?`))return;await moderateOffer(id,status);await reload();setStatus('Moderation decision saved.','success');}
  if(action==='report'){if(!state.user){state.detail=null;setStatus('Sign in to report a listing.');return;}const reason=prompt('Describe the concern (at least 10 characters):');if(reason===null)return;if(reason.trim().length<10){setStatus('Please provide at least 10 characters.','error');return;}await reportOffer(state.user.id,id,reason.trim());state.detail=null;setStatus('Report submitted for review.','success');}
 }catch(err){setStatus(err.message,'error');}
});
document.addEventListener('submit',async e=>{
 if(!['calc-form','offer-form','auth-form'].includes(e.target.id))return;
 e.preventDefault();const id=e.target.id;const form=e.target;const data=Object.fromEntries(new FormData(form));
 try {
  if(id==='calc-form'){
   const result=calculateSavings({subtotal:data.subtotal,type:data.type,amount:data.amount,minimumSpend:data.minimumSpend,cap:data.cap});
   const out=document.querySelector('#calc-output');
   if(result.error){out.innerHTML=`<h3>Check the inputs</h3><p>${esc(result.error)}</p>`;return;}
   out.innerHTML=result.eligible?`<span class="eyebrow">YOU COULD SAVE</span><div class="result-number">${money(result.savings)}</div><h3>Estimated final price: ${money(result.finalPrice)}</h3><p>Before discount: ${money(data.subtotal)}</p>`:`<h3>Minimum spend not reached</h3><p>Add ${money(result.missing)} to reach the stated minimum order value.</p>`;return;
  }
  if(id==='auth-form'){
   if(data.password.length<8)throw new Error('Password must contain at least 8 characters.');
   if(state.mode==='signup'){const res=await signUp(data.email.trim(),data.password);state.detail=null;if(res.session){await reload();setStatus('Account created and signed in.','success');}else setStatus('Check your email to confirm your account, then sign in.','success');}
   else {await signIn(data.email.trim(),data.password);state.detail=null;await reload();setStatus('Signed in.','success');}return;
  }
  if(id==='offer-form'){
   const item={brand:data.brand.trim(),title:data.title.trim(),category:data.category,description:data.description.trim(),discount_type:data.discount_type,discount_value:Number(data.discount_value),min_spend:Number(data.min_spend),max_saving:data.max_saving?Number(data.max_saving):null,expires_at:new Date(data.expires_at+'T23:59:00').toISOString(),source_url:data.source_url.trim(),terms:data.terms.trim(),acknowledged:data.acknowledged==='on'};
   const errors=validateOffer(item);if(errors.length)throw new Error(errors[0]);
   delete item.acknowledged;
   if(!state.user)throw new Error('Sign in before submitting.');
   await submitOffer({...item,seller_id:state.user.id});await reload();
   location.hash='#my-offers';state.view='my-offers';setStatus('Submitted for administrator review.','success');
  }
 }catch(err){setStatus(err.message,'error');}
});
reload();
