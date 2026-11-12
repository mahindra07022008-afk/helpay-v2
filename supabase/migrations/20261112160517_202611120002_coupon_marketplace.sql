/*
# Coupon marketplace: pricing, seller uploads, sandbox checkout, ledgers

1. New tables
- pricing_tiers: five fixed buyer prices (10, 20, 30, 50, 70 INR). Admin-only.
- platform_settings: commission rate (30), admin UPI destination, payment mode ("sandbox"). Admin-only.
- coupons: seller-uploaded coupons. Buyers see only admin-approved, unexpired coupons.
- coupon_secrets: coupon codes. No browser role can read them; buyers get the code only through reveal_coupon_code after a paid order. Admins can read them for review.
- coupon_pricing_admin: suggested and final pricing tier per coupon. Admin-only.
- orders: buyer purchases. Sandbox provider only until a live provider is approved.
- wallet_entries: seller wallet ledger (sale credits, refund reversals, withdrawal holds and reversals).
- commission_ledger: platform commission per paid order with settlement status. Admin-only.
- withdrawals: seller payout requests, processed manually by an admin.

2. Functions
- Pricing: tier_for_value, tier_for_percent, quote_coupon (value bands 0-100, 100-500, 500-700, 700-1000, 1000-2000; discount bands 0-10%, 10-50%, 50-70%, 70-100%; value and discount bands must agree or the coupon goes to admin review; tier 5 has no discount band).
- Seller: create_coupon, seller_sales, request_withdrawal.
- Admin: is_coupon_admin, admin_approve_coupon, admin_reject_coupon, admin_refund_order, admin_process_withdrawal, admin_settle_commission, admin_set_tier_price, admin_set_commission_rate.
- Buyer: start_checkout, complete_sandbox_payment, mark_checkout_failed, reveal_coupon_code.
- All functions check auth.uid() or admin status. Only authenticated may execute them.

3. Security
- RLS is enabled on every new table.
- Browser roles hold SELECT grants only. Every write goes through a function that checks the caller.
- Commission rate, commission records, admin UPI and payout references are readable only by admins.
- Sellers see the selling price and their own net earnings. They never see the commission.
- Buyers see the selling price and coupon details. They never see seller earnings or commission.
- Duplicate protection: unique indexes ensure one seller credit per order, one paid order per coupon, and one hold/reversal per withdrawal.

4. Important notes
- Payments are sandbox only: complete_sandbox_payment marks an order paid with no money movement. Replace it with a verified provider callback before live use.
- Commissions are recorded as pending until an admin settles them with admin_settle_commission and a UPI reference.
- Refunding an already-settled commission must be recovered manually; the ledger marks it reversed.
- Coupons whose names or brands mention PhonePe, GPay, Google Pay or Paytm are rejected at submission.
*/

create table if not exists public.pricing_tiers (
  tier smallint primary key check (tier between 1 and 5),
  value_range text not null,
  discount_range text not null,
  buyer_price numeric(10,2) not null check (buyer_price > 0)
);

insert into public.pricing_tiers (tier, value_range, discount_range, buyer_price) values
  (1, '₹0–₹100', '0–10%', 10),
  (2, '₹100–₹500', '10–50%', 20),
  (3, '₹500–₹700', '50–70%', 30),
  (4, '₹700–₹1,000', '70–100%', 50),
  (5, '₹1,000–₹2,000', 'Not specified', 70)
on conflict (tier) do nothing;

create table if not exists public.platform_settings (
  key text primary key,
  value text not null
);

insert into public.platform_settings (key, value) values
  ('commission_rate', '30'),
  ('admin_upi', '9390465299@fam'),
  ('payment_mode', 'sandbox')
on conflict (key) do nothing;

create table if not exists public.coupons (
  id uuid primary key default gen_random_uuid(),
  seller_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  brand text not null check (char_length(btrim(brand)) between 1 and 70),
  title text not null check (char_length(btrim(title)) between 1 and 90),
  coupon_value numeric(10,2) not null check (coupon_value > 0 and coupon_value <= 2000),
  discount_type text not null check (discount_type in ('flat','percent')),
  discount_value numeric(10,2) not null check (discount_value > 0),
  expires_at timestamptz not null,
  terms text not null check (char_length(btrim(terms)) between 1 and 1000),
  transferable_confirmed boolean not null check (transferable_confirmed),
  buyer_price numeric(10,2) check (buyer_price > 0),
  status text not null default 'pending' check (status in ('pending','approved','rejected','sold','refunded')),
  created_at timestamptz not null default now(),
  moderated_at timestamptz,
  constraint coupons_approved_priced check (status <> 'approved' or buyer_price is not null)
);
create index if not exists coupons_seller_idx on public.coupons(seller_id);
create index if not exists coupons_status_idx on public.coupons(status);

create table if not exists public.coupon_secrets (
  coupon_id uuid primary key references public.coupons(id) on delete cascade,
  code text not null check (char_length(code) between 1 and 100)
);

create table if not exists public.coupon_pricing_admin (
  coupon_id uuid primary key references public.coupons(id) on delete cascade,
  suggested_tier smallint not null check (suggested_tier between 1 and 5),
  final_tier smallint check (final_tier between 1 and 5),
  review_required boolean not null default false
);

create table if not exists public.withdrawals (
  id uuid primary key default gen_random_uuid(),
  seller_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  amount numeric(10,2) not null check (amount > 0),
  status text not null default 'requested' check (status in ('requested','paid','rejected')),
  payout_reference text,
  created_at timestamptz not null default now(),
  processed_at timestamptz
);
create index if not exists withdrawals_seller_idx on public.withdrawals(seller_id);

create table if not exists public.orders (
  id uuid primary key default gen_random_uuid(),
  buyer_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  coupon_id uuid not null references public.coupons(id),
  amount numeric(10,2) not null check (amount > 0),
  status text not null default 'pending' check (status in ('pending','paid','failed','refunded')),
  provider text not null default 'sandbox' check (provider = 'sandbox'),
  provider_reference text unique,
  created_at timestamptz not null default now(),
  paid_at timestamptz
);
create index if not exists orders_buyer_idx on public.orders(buyer_id);
create index if not exists orders_coupon_idx on public.orders(coupon_id);
create unique index if not exists orders_one_sale_per_coupon on public.orders(coupon_id) where status in ('paid','refunded');

create table if not exists public.wallet_entries (
  id bigint generated always as identity primary key,
  seller_id uuid not null references auth.users(id) on delete cascade,
  order_id uuid references public.orders(id),
  withdrawal_id uuid references public.withdrawals(id),
  entry_type text not null check (entry_type in ('sale_credit','refund_debit','withdrawal_hold','withdrawal_reversal')),
  amount numeric(10,2) not null check (amount <> 0),
  created_at timestamptz not null default now(),
  constraint wallet_entry_reference check (
    (entry_type in ('sale_credit','refund_debit') and order_id is not null)
    or (entry_type in ('withdrawal_hold','withdrawal_reversal') and withdrawal_id is not null)
  )
);
create index if not exists wallet_entries_seller_idx on public.wallet_entries(seller_id);
create unique index if not exists wallet_one_order_entry on public.wallet_entries(order_id, entry_type) where order_id is not null;
create unique index if not exists wallet_one_withdrawal_entry on public.wallet_entries(withdrawal_id, entry_type) where withdrawal_id is not null;

create table if not exists public.commission_ledger (
  order_id uuid primary key references public.orders(id),
  seller_id uuid not null references auth.users(id) on delete cascade,
  gross_amount numeric(10,2) not null,
  commission_rate integer not null,
  commission_amount numeric(10,2) not null,
  settlement_status text not null default 'pending' check (settlement_status in ('pending','settled','reversed')),
  settlement_reference text,
  settled_at timestamptz,
  created_at timestamptz not null default now()
);

alter table public.pricing_tiers enable row level security;
alter table public.platform_settings enable row level security;
alter table public.coupons enable row level security;
alter table public.coupon_secrets enable row level security;
alter table public.coupon_pricing_admin enable row level security;
alter table public.withdrawals enable row level security;
alter table public.orders enable row level security;
alter table public.wallet_entries enable row level security;
alter table public.commission_ledger enable row level security;

create or replace function public.is_coupon_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.user_roles r where r.user_id = auth.uid() and r.role = 'admin');
$$;

create or replace function public.tier_for_value(p_value numeric)
returns smallint language sql immutable as $$
  select case
    when p_value <= 0 then null
    when p_value <= 100 then 1
    when p_value <= 500 then 2
    when p_value <= 700 then 3
    when p_value <= 1000 then 4
    when p_value <= 2000 then 5
  end::smallint;
$$;

create or replace function public.tier_for_percent(p_percent numeric)
returns smallint language sql immutable as $$
  select case
    when p_percent <= 0 then null
    when p_percent <= 10 then 1
    when p_percent <= 50 then 2
    when p_percent <= 70 then 3
    when p_percent <= 100 then 4
  end::smallint;
$$;

create or replace function public.quote_coupon(p_value numeric, p_discount_type text, p_discount_value numeric)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_percent numeric;
  v_value_tier smallint;
  v_final smallint;
  v_price numeric(10,2);
  v_rate integer;
  v_commission numeric(10,2);
begin
  if p_value is null or p_discount_value is null or p_value <= 0 or p_value > 2000 or p_discount_value <= 0 then
    raise exception 'Enter a coupon value up to ₹2,000 and a discount above zero.';
  end if;
  if p_discount_type = 'percent' then
    v_percent := p_discount_value;
  elsif p_discount_type = 'flat' then
    v_percent := p_discount_value * 100 / p_value;
  else
    raise exception 'Choose a valid discount type.';
  end if;
  if v_percent > 100 then
    raise exception 'The discount cannot be more than the coupon value.';
  end if;

  v_value_tier := public.tier_for_value(p_value);
  if v_value_tier = 5 then
    v_final := 5;
  elsif public.tier_for_percent(v_percent) = v_value_tier then
    v_final := v_value_tier;
  end if;

  if v_final is not null then
    select pt.buyer_price into v_price from public.pricing_tiers pt where pt.tier = v_final;
    select s.value::integer into v_rate from public.platform_settings s where s.key = 'commission_rate';
    v_commission := round(v_price * v_rate / 100, 2);
  end if;

  return jsonb_build_object(
    'suggested_tier', v_value_tier,
    'final_tier', v_final,
    'review_required', v_final is null,
    'buyer_price', v_price,
    'seller_earning', v_price - v_commission
  );
end $$;

create or replace function public.create_coupon(
  p_brand text, p_title text, p_code text, p_value numeric, p_discount_type text,
  p_discount_value numeric, p_expires_at timestamptz, p_terms text, p_transferable boolean
)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_quote jsonb;
  v_id uuid;
begin
  if auth.uid() is null then raise exception 'Sign in first.'; end if;
  if not coalesce(p_transferable, false) then
    raise exception 'Only coupons whose issuer allows resale or transfer can be listed.';
  end if;
  if lower(coalesce(p_brand, '') || ' ' || coalesce(p_title, '')) ~ '(phonepe|phone pe|gpay|g pay|google pay|paytm)' then
    raise exception 'PhonePe, GPay, Google Pay and Paytm rewards cannot be listed.';
  end if;
  if p_expires_at is null or p_expires_at <= now() then raise exception 'The expiry date must be in the future.'; end if;
  if char_length(btrim(coalesce(p_code, ''))) not between 1 and 100 then raise exception 'Enter the coupon code.'; end if;

  v_quote := public.quote_coupon(p_value, p_discount_type, p_discount_value);

  insert into public.coupons (seller_id, brand, title, coupon_value, discount_type, discount_value, expires_at, terms, transferable_confirmed, buyer_price)
  values (auth.uid(), btrim(p_brand), btrim(p_title), p_value, p_discount_type, p_discount_value, p_expires_at, btrim(p_terms), true, (v_quote->>'buyer_price')::numeric)
  returning id into v_id;

  insert into public.coupon_secrets (coupon_id, code) values (v_id, btrim(p_code));
  insert into public.coupon_pricing_admin (coupon_id, suggested_tier, final_tier, review_required)
  values (v_id, (v_quote->>'suggested_tier')::smallint, (v_quote->>'final_tier')::smallint, (v_quote->>'review_required')::boolean);
  return v_id;
end $$;

create or replace function public.admin_approve_coupon(p_coupon_id uuid, p_tier smallint)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_status text;
  v_expires timestamptz;
  v_suggested smallint;
  v_tier smallint;
  v_price numeric(10,2);
begin
  if not public.is_coupon_admin() then raise exception 'Not authorised.'; end if;
  select c.status, c.expires_at, p.suggested_tier into v_status, v_expires, v_suggested
  from public.coupons c join public.coupon_pricing_admin p on p.coupon_id = c.id
  where c.id = p_coupon_id for update of c;
  if not found then raise exception 'Coupon not found.'; end if;
  if v_status <> 'pending' then raise exception 'Only pending coupons can be approved.'; end if;
  if v_expires <= now() then raise exception 'This coupon has already expired.'; end if;
  v_tier := coalesce(p_tier, v_suggested);
  select pt.buyer_price into v_price from public.pricing_tiers pt where pt.tier = v_tier;
  if v_price is null then raise exception 'Choose a valid pricing tier.'; end if;
  update public.coupon_pricing_admin set final_tier = v_tier where coupon_id = p_coupon_id;
  update public.coupons set status = 'approved', buyer_price = v_price, moderated_at = now() where id = p_coupon_id;
end $$;

create or replace function public.admin_reject_coupon(p_coupon_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_coupon_admin() then raise exception 'Not authorised.'; end if;
  update public.coupons set status = 'rejected', moderated_at = now() where id = p_coupon_id and status = 'pending';
  if not found then raise exception 'Only pending coupons can be rejected.'; end if;
end $$;

create or replace function public.start_checkout(p_coupon_id uuid)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_coupon public.coupons%rowtype;
  v_order uuid;
begin
  if auth.uid() is null then raise exception 'Sign in before buying.'; end if;
  select * into v_coupon from public.coupons where id = p_coupon_id;
  if not found or v_coupon.status <> 'approved' or v_coupon.expires_at <= now() then
    raise exception 'This coupon is no longer available.';
  end if;
  if v_coupon.seller_id = auth.uid() then raise exception 'You cannot buy your own coupon.'; end if;
  insert into public.orders (buyer_id, coupon_id, amount)
  values (auth.uid(), p_coupon_id, v_coupon.buyer_price)
  returning id into v_order;
  return v_order;
end $$;

create or replace function public.complete_sandbox_payment(p_order_id uuid)
returns text language plpgsql security definer set search_path = public as $$
declare
  o public.orders%rowtype;
  c public.coupons%rowtype;
  v_mode text;
  v_rate integer;
  v_commission numeric(10,2);
begin
  if auth.uid() is null then raise exception 'Sign in first.'; end if;
  select s.value into v_mode from public.platform_settings s where s.key = 'payment_mode';
  if v_mode is distinct from 'sandbox' then raise exception 'Live payments are not enabled yet.'; end if;

  select * into o from public.orders where id = p_order_id and buyer_id = auth.uid() for update;
  if not found then raise exception 'Order not found.'; end if;
  if o.status = 'paid' then return 'paid'; end if;
  if o.status <> 'pending' then raise exception 'This order can no longer be paid.'; end if;

  select * into c from public.coupons where id = o.coupon_id for update;
  if c.status <> 'approved' or c.expires_at <= now() then
    update public.orders set status = 'failed' where id = o.id;
    return 'failed';
  end if;

  select s.value::integer into v_rate from public.platform_settings s where s.key = 'commission_rate';
  v_commission := round(o.amount * v_rate / 100, 2);

  update public.orders set status = 'paid', paid_at = now(), provider_reference = 'sandbox_' || o.id::text where id = o.id;
  update public.coupons set status = 'sold' where id = c.id;
  insert into public.wallet_entries (seller_id, order_id, entry_type, amount)
  values (c.seller_id, o.id, 'sale_credit', o.amount - v_commission);
  insert into public.commission_ledger (order_id, seller_id, gross_amount, commission_rate, commission_amount)
  values (o.id, c.seller_id, o.amount, v_rate, v_commission);
  return 'paid';
end $$;

create or replace function public.mark_checkout_failed(p_order_id uuid)
returns void language sql security definer set search_path = public as $$
  update public.orders set status = 'failed' where id = p_order_id and buyer_id = auth.uid() and status = 'pending';
$$;

create or replace function public.reveal_coupon_code(p_order_id uuid)
returns text language plpgsql security definer set search_path = public as $$
declare
  v_code text;
begin
  select s.code into v_code
  from public.orders o join public.coupon_secrets s on s.coupon_id = o.coupon_id
  where o.id = p_order_id and o.buyer_id = auth.uid() and o.status = 'paid';
  if v_code is null then raise exception 'The code is available only after a verified purchase.'; end if;
  return v_code;
end $$;

create or replace function public.admin_refund_order(p_order_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  o public.orders%rowtype;
  v_seller uuid;
  v_credit numeric(10,2);
begin
  if not public.is_coupon_admin() then raise exception 'Not authorised.'; end if;
  select * into o from public.orders where id = p_order_id for update;
  if not found or o.status <> 'paid' then raise exception 'Only paid orders can be refunded.'; end if;
  select c.seller_id into v_seller from public.coupons c where c.id = o.coupon_id;
  select w.amount into v_credit from public.wallet_entries w where w.order_id = o.id and w.entry_type = 'sale_credit';
  update public.orders set status = 'refunded' where id = o.id;
  update public.coupons set status = 'refunded' where id = o.coupon_id;
  insert into public.wallet_entries (seller_id, order_id, entry_type, amount) values (v_seller, o.id, 'refund_debit', -v_credit);
  update public.commission_ledger set settlement_status = 'reversed' where order_id = o.id;
end $$;

create or replace function public.request_withdrawal(p_amount numeric)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_balance numeric(10,2);
  v_id uuid;
begin
  if auth.uid() is null then raise exception 'Sign in first.'; end if;
  p_amount := round(p_amount, 2);
  if p_amount is null or p_amount <= 0 then raise exception 'Enter an amount above zero.'; end if;
  perform pg_advisory_xact_lock(hashtext(auth.uid()::text));
  select coalesce(sum(w.amount), 0) into v_balance from public.wallet_entries w where w.seller_id = auth.uid();
  if p_amount > v_balance then raise exception 'The amount is more than your available balance.'; end if;
  insert into public.withdrawals (seller_id, amount) values (auth.uid(), p_amount) returning id into v_id;
  insert into public.wallet_entries (seller_id, withdrawal_id, entry_type, amount) values (auth.uid(), v_id, 'withdrawal_hold', -p_amount);
  return v_id;
end $$;

create or replace function public.admin_process_withdrawal(p_withdrawal_id uuid, p_action text, p_reference text)
returns void language plpgsql security definer set search_path = public as $$
declare
  w public.withdrawals%rowtype;
begin
  if not public.is_coupon_admin() then raise exception 'Not authorised.'; end if;
  select * into w from public.withdrawals where id = p_withdrawal_id for update;
  if not found or w.status <> 'requested' then raise exception 'This withdrawal is already processed.'; end if;
  if p_action = 'paid' then
    if char_length(btrim(coalesce(p_reference, ''))) < 1 then raise exception 'Enter the payout reference.'; end if;
    update public.withdrawals set status = 'paid', payout_reference = btrim(p_reference), processed_at = now() where id = w.id;
  elsif p_action = 'rejected' then
    update public.withdrawals set status = 'rejected', processed_at = now() where id = w.id;
    insert into public.wallet_entries (seller_id, withdrawal_id, entry_type, amount) values (w.seller_id, w.id, 'withdrawal_reversal', w.amount);
  else
    raise exception 'Choose paid or rejected.';
  end if;
end $$;

create or replace function public.admin_settle_commission(p_order_id uuid, p_reference text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_coupon_admin() then raise exception 'Not authorised.'; end if;
  if char_length(btrim(coalesce(p_reference, ''))) < 1 then raise exception 'Enter the settlement reference.'; end if;
  update public.commission_ledger
  set settlement_status = 'settled', settlement_reference = btrim(p_reference), settled_at = now()
  where order_id = p_order_id and settlement_status = 'pending';
  if not found then raise exception 'No pending commission for this order.'; end if;
end $$;

create or replace function public.admin_set_tier_price(p_tier smallint, p_price numeric)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_coupon_admin() then raise exception 'Not authorised.'; end if;
  if p_price is null or p_price <= 0 or p_price > 100000 then raise exception 'Enter a price between ₹1 and ₹100,000.'; end if;
  update public.pricing_tiers set buyer_price = round(p_price, 2) where tier = p_tier;
  if not found then raise exception 'Unknown pricing tier.'; end if;
end $$;

create or replace function public.admin_set_commission_rate(p_rate integer)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_coupon_admin() then raise exception 'Not authorised.'; end if;
  if p_rate is null or p_rate < 0 or p_rate > 100 then raise exception 'Enter a rate between 0 and 100.'; end if;
  update public.platform_settings set value = p_rate::text where key = 'commission_rate';
end $$;

create or replace function public.seller_sales()
returns table (coupon_id uuid, brand text, title text, sale_price numeric, earning numeric, sold_at timestamptz)
language sql stable security definer set search_path = public as $$
  select c.id, c.brand, c.title, o.amount, w.amount, o.paid_at
  from public.orders o
  join public.coupons c on c.id = o.coupon_id
  join public.wallet_entries w on w.order_id = o.id and w.entry_type = 'sale_credit'
  where c.seller_id = auth.uid() and o.status = 'paid'
  order by o.paid_at desc;
$$;

revoke all on public.pricing_tiers, public.platform_settings, public.coupons, public.coupon_secrets,
  public.coupon_pricing_admin, public.withdrawals, public.orders, public.wallet_entries, public.commission_ledger
  from anon, authenticated;
grant select on public.coupons to anon, authenticated;
grant select on public.pricing_tiers, public.platform_settings, public.coupon_secrets, public.coupon_pricing_admin,
  public.withdrawals, public.orders, public.wallet_entries, public.commission_ledger to authenticated;

drop policy if exists "approved_coupons_public_read" on public.coupons;
create policy "approved_coupons_public_read" on public.coupons for select to anon, authenticated
  using (status = 'approved' and expires_at > now());
drop policy if exists "sellers_read_own_coupons" on public.coupons;
create policy "sellers_read_own_coupons" on public.coupons for select to authenticated
  using (seller_id = auth.uid());
drop policy if exists "buyers_read_purchased_coupons" on public.coupons;
create policy "buyers_read_purchased_coupons" on public.coupons for select to authenticated
  using (exists (select 1 from public.orders o where o.coupon_id = coupons.id and o.buyer_id = auth.uid()));
drop policy if exists "admins_read_all_coupons" on public.coupons;
create policy "admins_read_all_coupons" on public.coupons for select to authenticated
  using (public.is_coupon_admin());

drop policy if exists "admins_read_coupon_codes" on public.coupon_secrets;
create policy "admins_read_coupon_codes" on public.coupon_secrets for select to authenticated
  using (public.is_coupon_admin());
drop policy if exists "admins_read_pricing" on public.coupon_pricing_admin;
create policy "admins_read_pricing" on public.coupon_pricing_admin for select to authenticated
  using (public.is_coupon_admin());
drop policy if exists "admins_read_tiers" on public.pricing_tiers;
create policy "admins_read_tiers" on public.pricing_tiers for select to authenticated
  using (public.is_coupon_admin());
drop policy if exists "admins_read_settings" on public.platform_settings;
create policy "admins_read_settings" on public.platform_settings for select to authenticated
  using (public.is_coupon_admin());
drop policy if exists "buyers_read_own_orders" on public.orders;
create policy "buyers_read_own_orders" on public.orders for select to authenticated
  using (buyer_id = auth.uid());
drop policy if exists "admins_read_orders" on public.orders;
create policy "admins_read_orders" on public.orders for select to authenticated
  using (public.is_coupon_admin());
drop policy if exists "sellers_read_own_wallet" on public.wallet_entries;
create policy "sellers_read_own_wallet" on public.wallet_entries for select to authenticated
  using (seller_id = auth.uid());
drop policy if exists "admins_read_wallets" on public.wallet_entries;
create policy "admins_read_wallets" on public.wallet_entries for select to authenticated
  using (public.is_coupon_admin());
drop policy if exists "sellers_read_own_withdrawals" on public.withdrawals;
create policy "sellers_read_own_withdrawals" on public.withdrawals for select to authenticated
  using (seller_id = auth.uid());
drop policy if exists "admins_read_withdrawals" on public.withdrawals;
create policy "admins_read_withdrawals" on public.withdrawals for select to authenticated
  using (public.is_coupon_admin());
drop policy if exists "admins_read_commissions" on public.commission_ledger;
create policy "admins_read_commissions" on public.commission_ledger for select to authenticated
  using (public.is_coupon_admin());

revoke execute on function public.is_coupon_admin(), public.tier_for_value(numeric), public.tier_for_percent(numeric) from public, anon, authenticated;
grant execute on function public.is_coupon_admin() to authenticated;

revoke execute on function public.quote_coupon(numeric, text, numeric),
  public.create_coupon(text, text, text, numeric, text, numeric, timestamptz, text, boolean),
  public.admin_approve_coupon(uuid, smallint), public.admin_reject_coupon(uuid),
  public.start_checkout(uuid), public.complete_sandbox_payment(uuid), public.mark_checkout_failed(uuid),
  public.reveal_coupon_code(uuid), public.admin_refund_order(uuid), public.request_withdrawal(numeric),
  public.admin_process_withdrawal(uuid, text, text), public.admin_settle_commission(uuid, text),
  public.admin_set_tier_price(smallint, numeric), public.admin_set_commission_rate(integer),
  public.seller_sales() from public, anon;
grant execute on function public.quote_coupon(numeric, text, numeric),
  public.create_coupon(text, text, text, numeric, text, numeric, timestamptz, text, boolean),
  public.admin_approve_coupon(uuid, smallint), public.admin_reject_coupon(uuid),
  public.start_checkout(uuid), public.complete_sandbox_payment(uuid), public.mark_checkout_failed(uuid),
  public.reveal_coupon_code(uuid), public.admin_refund_order(uuid), public.request_withdrawal(numeric),
  public.admin_process_withdrawal(uuid, text, text), public.admin_settle_commission(uuid, text),
  public.admin_set_tier_price(smallint, numeric), public.admin_set_commission_rate(integer),
  public.seller_sales() to authenticated;
