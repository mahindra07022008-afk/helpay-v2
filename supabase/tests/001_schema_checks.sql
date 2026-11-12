-- Run AFTER applying the migration, in Supabase SQL Editor.
-- Each row should return ok = true. These are policy-presence checks,
-- NOT a substitute for authenticated/anonymous permission integration tests.
select 'All six public tables have RLS enabled' as check_name,
  count(*) = 6 as ok
from pg_class c join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relname in ('profiles','user_roles','offers','favourites','reports','moderation_audit')
  and c.relrowsecurity;

select 'Public visitors cannot INSERT offers' as check_name,
  not has_table_privilege('anon','public.offers','INSERT') as ok;

select 'Logged-in users cannot update offer status' as check_name,
  not has_column_privilege('authenticated','public.offers','status','UPDATE') as ok;

select 'Logged-in users cannot insert admin roles' as check_name,
  not has_table_privilege('authenticated','public.user_roles','INSERT') as ok;

select 'Admin moderation function exists' as check_name,
  to_regprocedure('public.moderate_offer(uuid,text)') is not null as ok;
