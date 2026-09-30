-- =====================================================================
-- Ledgerline: monthly budgets per category
--
-- Run once in Supabase: SQL Editor > New query > paste > Run.
-- Safe to run again. Needs schema.sql to have been run first (it uses
-- vidhya_personal_finance_dashboard_set_updated_at from there).
-- =====================================================================

create table if not exists public.vidhya_personal_finance_dashboard_budgets (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null default auth.uid() references auth.users (id) on delete cascade,
  category       text not null check (category in ('Food','Transport','Shopping','Bills','Rent','Salary','Transfers','Entertainment','Health','Other')),
  monthly_limit  numeric(14,2) not null check (monthly_limit > 0 and monthly_limit < 100000000000),
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  constraint vidhya_pfd_budgets_user_category_key unique (user_id, category)
);

drop trigger if exists vidhya_personal_finance_dashboard_budgets_updated
  on public.vidhya_personal_finance_dashboard_budgets;
create trigger vidhya_personal_finance_dashboard_budgets_updated
  before update on public.vidhya_personal_finance_dashboard_budgets
  for each row execute function public.vidhya_personal_finance_dashboard_set_updated_at();

alter table public.vidhya_personal_finance_dashboard_budgets enable row level security;

drop policy if exists "Own budgets: read"   on public.vidhya_personal_finance_dashboard_budgets;
drop policy if exists "Own budgets: create" on public.vidhya_personal_finance_dashboard_budgets;
drop policy if exists "Own budgets: update" on public.vidhya_personal_finance_dashboard_budgets;
drop policy if exists "Own budgets: delete" on public.vidhya_personal_finance_dashboard_budgets;
create policy "Own budgets: read"   on public.vidhya_personal_finance_dashboard_budgets
  for select to authenticated using ((select auth.uid()) = user_id);
create policy "Own budgets: create" on public.vidhya_personal_finance_dashboard_budgets
  for insert to authenticated with check ((select auth.uid()) = user_id);
create policy "Own budgets: update" on public.vidhya_personal_finance_dashboard_budgets
  for update to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy "Own budgets: delete" on public.vidhya_personal_finance_dashboard_budgets
  for delete to authenticated using ((select auth.uid()) = user_id);

revoke all on public.vidhya_personal_finance_dashboard_budgets from anon, authenticated;
grant select, insert, update, delete on public.vidhya_personal_finance_dashboard_budgets to authenticated;
