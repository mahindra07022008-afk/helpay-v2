-- Helpay 2.0 MVP: PUBLIC promotion discovery ONLY.
-- No coupon redemption codes, resale, escrow or payment information are stored.
-- Run in a NEW Supabase project using SQL editor or Supabase CLI.
begin;

create extension if not exists pgcrypto;
create schema if not exists private;
revoke all on schema private from public, anon, authenticated;
grant usage on schema private to authenticated;

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default 'Helpay member' check (char_length(display_name) between 1 and 70),
  created_at timestamptz not null default now()
);

create table public.user_roles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  role text not null check (role in ('admin')),
  created_at timestamptz not null default now()
);

create function private.is_admin() returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.user_roles
    where user_id = (select auth.uid()) and role = 'admin'
  );
$$;
revoke all on function private.is_admin() from public;
grant execute on function private.is_admin() to authenticated;

create function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles(id, display_name)
  values (new.id, left(coalesce(nullif(trim(new.raw_user_meta_data ->> 'display_name'), ''), split_part(new.email, '@', 1), 'Helpay member'), 70));
  return new;
end;
$$;
revoke all on function public.handle_new_user() from public, anon, authenticated;
create trigger on_auth_user_created after insert on auth.users
for each row execute function public.handle_new_user();

create table public.offers (
  id uuid primary key default gen_random_uuid(),
  seller_id uuid not null references auth.users(id) on delete cascade,
  brand text not null check (char_length(btrim(brand)) between 1 and 70),
  title text not null check (char_length(btrim(title)) between 1 and 90),
  category text not null check (category in ('Shopping', 'Food', 'Education', 'Travel', 'Fashion', 'Services')),
  description text not null check (char_length(btrim(description)) between 1 and 500),
  discount_type text not null check (discount_type in ('flat', 'percent')),
  discount_value numeric(12,2) not null check (discount_value > 0 and discount_value <= 100000),
  min_spend numeric(12,2) not null default 0 check (min_spend >= 0),
  max_saving numeric(12,2) check (max_saving is null or max_saving >= 0),
  expires_at timestamptz not null,
  source_url text not null check (char_length(source_url) <= 800 and source_url ~* '^https://[^/@ ]+'),
  terms text not null check (char_length(btrim(terms)) between 1 and 1000),
  -- All offers in this MVP must be publicly advertised promotions.
  kind text not null default 'public_promotion' check (kind = 'public_promotion'),
  status text not null default 'pending' check (status in ('pending','published','rejected')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  moderated_at timestamptz,
  constraint valid_percentage check (discount_type <> 'percent' or discount_value <= 100)
);
create index offers_published_idx on public.offers(status, expires_at, created_at desc);
create index offers_seller_idx on public.offers(seller_id, created_at desc);

create function public.touch_offer() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  new.updated_at := now();
  return new;
end;
$$;
revoke all on function public.touch_offer() from public, anon, authenticated;
create trigger offers_updated before update on public.offers
for each row execute function public.touch_offer();

create table public.favourites (
  user_id uuid not null references auth.users(id) on delete cascade,
  offer_id uuid not null references public.offers(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key(user_id, offer_id)
);
create index favourites_offer_idx on public.favourites(offer_id);

create table public.reports (
  id uuid primary key default gen_random_uuid(),
  offer_id uuid not null references public.offers(id) on delete cascade,
  reporter_id uuid not null references auth.users(id) on delete cascade,
  reason text not null check (char_length(btrim(reason)) between 10 and 600),
  status text not null default 'open' check (status in ('open','resolved')),
  created_at timestamptz not null default now()
);
create index reports_offer_idx on public.reports(offer_id);

create table public.moderation_audit (
  id bigint generated always as identity primary key,
  actor_id uuid not null references auth.users(id) on delete cascade,
  offer_id uuid not null references public.offers(id) on delete cascade,
  action text not null check (action in ('published','rejected')),
  created_at timestamptz not null default now()
);

-- Enable RLS and revoke Supabase's potentially permissive DEFAULT table grants.
alter table public.profiles enable row level security;
alter table public.user_roles enable row level security;
alter table public.offers enable row level security;
alter table public.favourites enable row level security;
alter table public.reports enable row level security;
alter table public.moderation_audit enable row level security;
revoke all on public.profiles, public.user_roles, public.offers, public.favourites, public.reports, public.moderation_audit from anon, authenticated;

-- Only grant the minimum API rights needed for the UI.
grant select on public.profiles, public.user_roles to authenticated;
grant update(display_name) on public.profiles to authenticated;
grant select on public.offers to anon, authenticated;
grant insert on public.offers to authenticated;
grant update(brand, title, category, description, discount_type, discount_value, min_spend, max_saving, expires_at, source_url, terms) on public.offers to authenticated;
grant select, insert, delete on public.favourites to authenticated;
grant select, insert on public.reports to authenticated;
grant select on public.moderation_audit to authenticated;

create policy "profiles_self_select" on public.profiles for select to authenticated
using (id = (select auth.uid()));
create policy "profiles_self_update" on public.profiles for update to authenticated
using (id = (select auth.uid())) with check (id = (select auth.uid()));

create policy "user_roles_self_select" on public.user_roles for select to authenticated
using (user_id = (select auth.uid()));

create policy "offers_public_select" on public.offers for select to anon, authenticated
using (status = 'published' and expires_at > now());
create policy "offers_owner_admin_select" on public.offers for select to authenticated
using (seller_id = (select auth.uid()) or (select private.is_admin()));
create policy "offers_own_pending_insert" on public.offers for insert to authenticated
with check (seller_id = (select auth.uid()) and status = 'pending' and kind = 'public_promotion' and expires_at > now());
create policy "offers_own_pending_update" on public.offers for update to authenticated
using (seller_id = (select auth.uid()) and status = 'pending')
with check (seller_id = (select auth.uid()) and status = 'pending' and kind = 'public_promotion');

create policy "favourites_self_select" on public.favourites for select to authenticated
using (user_id = (select auth.uid()));
create policy "favourites_self_insert" on public.favourites for insert to authenticated
with check (user_id = (select auth.uid()) and exists (
  select 1 from public.offers o where o.id = offer_id and o.status = 'published' and o.expires_at > now()
));
create policy "favourites_self_delete" on public.favourites for delete to authenticated
using (user_id = (select auth.uid()));

create policy "reports_owner_admin_select" on public.reports for select to authenticated
using (reporter_id = (select auth.uid()) or (select private.is_admin()));
create policy "reports_owner_insert" on public.reports for insert to authenticated
with check (reporter_id = (select auth.uid()) and status = 'open');
create policy "audit_admin_select" on public.moderation_audit for select to authenticated
using ((select private.is_admin()));

-- Server-controlled moderation: signed-in users can invoke, but admin check
-- is enforced inside a security-definer transaction, with an audit trail.
create function public.moderate_offer(p_offer_id uuid, p_action text) returns void
language plpgsql security definer set search_path = '' as $$
declare v_current text;
begin
  if not private.is_admin() then
    raise exception 'Not authorized to moderate' using errcode = '42501';
  end if;
  if p_action not in ('published', 'rejected') then
    raise exception 'Unknown moderation action' using errcode = '22023';
  end if;
  select status into v_current from public.offers
    where id = p_offer_id for update;
  if not found or v_current <> 'pending' then
    raise exception 'Offer is missing or not pending review' using errcode = '22023';
  end if;
  if p_action = 'published' and not exists (
      select 1 from public.offers where id = p_offer_id and expires_at > now() and kind = 'public_promotion'
    ) then
    raise exception 'Offer has expired or is ineligible' using errcode = '22023';
  end if;
  update public.offers set status = p_action, moderated_at = now() where id = p_offer_id;
  insert into public.moderation_audit(actor_id, offer_id, action)
  values ((select auth.uid()), p_offer_id, p_action);
end;
$$;
revoke all on function public.moderate_offer(uuid, text) from public, anon;
grant execute on function public.moderate_offer(uuid, text) to authenticated;

comment on table public.offers is 'Public offer discovery metadata only. Never store private redemption codes or payment data.';
comment on table public.user_roles is 'Privileged role assignment by trusted operator only, not browser API.';
commit;
