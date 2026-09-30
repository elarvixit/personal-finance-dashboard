-- =====================================================================
-- Ledgerline personal finance dashboard: Supabase schema
--
-- Run this once in Supabase: Dashboard > SQL Editor > New query > paste > Run.
-- It is safe to run again; every statement is idempotent.
--
-- Every table is prefixed vidhya_personal_finance_dashboard_ and protected
-- by row-level security, so a signed-in user can only see and change their
-- own rows. The anon (signed-out) role gets no access at all.
-- =====================================================================


-- ---------------------------------------------------------------------
-- Shared helper: keep updated_at current on every UPDATE
-- ---------------------------------------------------------------------
create or replace function public.vidhya_personal_finance_dashboard_set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;


-- ---------------------------------------------------------------------
-- 1. Profiles: one row per user, records when default rules were added
-- ---------------------------------------------------------------------
create table if not exists public.vidhya_personal_finance_dashboard_profiles (
  user_id               uuid primary key default auth.uid() references auth.users (id) on delete cascade,
  default_rules_seeded  boolean not null default true,
  created_at            timestamptz not null default now()
);


-- ---------------------------------------------------------------------
-- 2. Statements: one row per imported CSV file
-- ---------------------------------------------------------------------
create table if not exists public.vidhya_personal_finance_dashboard_statements (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null default auth.uid() references auth.users (id) on delete cascade,
  file_name       text not null check (char_length(file_name) between 1 and 255),
  row_count       integer not null default 0 check (row_count >= 0),
  skipped_rows    integer not null default 0 check (skipped_rows >= 0),
  period_start    date,
  period_end      date,
  column_mapping  jsonb not null default '{}'::jsonb,
  created_at      timestamptz not null default now(),
  constraint vidhya_pfd_statements_id_user_key unique (id, user_id),
  constraint vidhya_pfd_statements_period_chk check (period_start is null or period_end is null or period_start <= period_end)
);

create index if not exists vidhya_personal_finance_dashboard_statements_user_idx
  on public.vidhya_personal_finance_dashboard_statements (user_id, created_at desc);


-- ---------------------------------------------------------------------
-- 3. Transactions: rows from a statement
-- ---------------------------------------------------------------------
create table if not exists public.vidhya_personal_finance_dashboard_transactions (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null default auth.uid() references auth.users (id) on delete cascade,
  statement_id  uuid not null,
  txn_date      date not null,
  description   text not null check (char_length(description) between 1 and 1000),
  merchant      text not null check (char_length(merchant) between 1 and 200),
  category      text not null check (category in ('Food','Transport','Shopping','Bills','Rent','Salary','Transfers','Entertainment','Health','Other')),
  amount        numeric(14,2) not null check (amount >= 0),
  txn_type      text not null check (txn_type in ('debit','credit')),
  balance       numeric(14,2),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  constraint vidhya_pfd_transactions_id_user_key unique (id, user_id),
  -- A transaction can only belong to a statement owned by the same user.
  constraint vidhya_pfd_transactions_statement_fkey foreign key (statement_id, user_id)
    references public.vidhya_personal_finance_dashboard_statements (id, user_id) on delete cascade
);

create index if not exists vidhya_personal_finance_dashboard_transactions_stmt_idx
  on public.vidhya_personal_finance_dashboard_transactions (user_id, statement_id, txn_date);

drop trigger if exists vidhya_personal_finance_dashboard_transactions_updated
  on public.vidhya_personal_finance_dashboard_transactions;
create trigger vidhya_personal_finance_dashboard_transactions_updated
  before update on public.vidhya_personal_finance_dashboard_transactions
  for each row execute function public.vidhya_personal_finance_dashboard_set_updated_at();


-- ---------------------------------------------------------------------
-- 4. Category rules: pattern -> category, per user
-- ---------------------------------------------------------------------
create table if not exists public.vidhya_personal_finance_dashboard_category_rules (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null default auth.uid() references auth.users (id) on delete cascade,
  pattern     text not null check (char_length(btrim(pattern)) between 2 and 100),
  category    text not null check (category in ('Food','Transport','Shopping','Bills','Rent','Salary','Transfers','Entertainment','Health','Other')),
  created_by  text not null default 'user' check (created_by in ('system','user','table_edit')),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create unique index if not exists vidhya_personal_finance_dashboard_rules_pattern_uidx
  on public.vidhya_personal_finance_dashboard_category_rules (user_id, upper(pattern));

drop trigger if exists vidhya_personal_finance_dashboard_rules_updated
  on public.vidhya_personal_finance_dashboard_category_rules;
create trigger vidhya_personal_finance_dashboard_rules_updated
  before update on public.vidhya_personal_finance_dashboard_category_rules
  for each row execute function public.vidhya_personal_finance_dashboard_set_updated_at();


-- ---------------------------------------------------------------------
-- 5. Anomaly reviews: flagged payments the user marked as expected
-- ---------------------------------------------------------------------
create table if not exists public.vidhya_personal_finance_dashboard_anomaly_reviews (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null default auth.uid() references auth.users (id) on delete cascade,
  transaction_id  uuid not null,
  status          text not null default 'expected' check (status in ('expected')),
  reviewed_at     timestamptz not null default now(),
  constraint vidhya_pfd_anomaly_reviews_txn_key unique (user_id, transaction_id),
  constraint vidhya_pfd_anomaly_reviews_txn_fkey foreign key (transaction_id, user_id)
    references public.vidhya_personal_finance_dashboard_transactions (id, user_id) on delete cascade
);


-- ---------------------------------------------------------------------
-- Row-level security: every table, owner-only
-- ---------------------------------------------------------------------
alter table public.vidhya_personal_finance_dashboard_profiles        enable row level security;
alter table public.vidhya_personal_finance_dashboard_statements      enable row level security;
alter table public.vidhya_personal_finance_dashboard_transactions    enable row level security;
alter table public.vidhya_personal_finance_dashboard_category_rules  enable row level security;
alter table public.vidhya_personal_finance_dashboard_anomaly_reviews enable row level security;

-- profiles
drop policy if exists "Own profile: read"   on public.vidhya_personal_finance_dashboard_profiles;
drop policy if exists "Own profile: create" on public.vidhya_personal_finance_dashboard_profiles;
create policy "Own profile: read"   on public.vidhya_personal_finance_dashboard_profiles
  for select to authenticated using ((select auth.uid()) = user_id);
create policy "Own profile: create" on public.vidhya_personal_finance_dashboard_profiles
  for insert to authenticated with check ((select auth.uid()) = user_id);

-- statements
drop policy if exists "Own statements: read"   on public.vidhya_personal_finance_dashboard_statements;
drop policy if exists "Own statements: create" on public.vidhya_personal_finance_dashboard_statements;
drop policy if exists "Own statements: delete" on public.vidhya_personal_finance_dashboard_statements;
create policy "Own statements: read"   on public.vidhya_personal_finance_dashboard_statements
  for select to authenticated using ((select auth.uid()) = user_id);
create policy "Own statements: create" on public.vidhya_personal_finance_dashboard_statements
  for insert to authenticated with check ((select auth.uid()) = user_id);
create policy "Own statements: delete" on public.vidhya_personal_finance_dashboard_statements
  for delete to authenticated using ((select auth.uid()) = user_id);

-- transactions
drop policy if exists "Own transactions: read"   on public.vidhya_personal_finance_dashboard_transactions;
drop policy if exists "Own transactions: create" on public.vidhya_personal_finance_dashboard_transactions;
drop policy if exists "Own transactions: update" on public.vidhya_personal_finance_dashboard_transactions;
create policy "Own transactions: read"   on public.vidhya_personal_finance_dashboard_transactions
  for select to authenticated using ((select auth.uid()) = user_id);
create policy "Own transactions: create" on public.vidhya_personal_finance_dashboard_transactions
  for insert to authenticated with check ((select auth.uid()) = user_id);
create policy "Own transactions: update" on public.vidhya_personal_finance_dashboard_transactions
  for update to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);

-- category rules
drop policy if exists "Own rules: read"   on public.vidhya_personal_finance_dashboard_category_rules;
drop policy if exists "Own rules: create" on public.vidhya_personal_finance_dashboard_category_rules;
drop policy if exists "Own rules: update" on public.vidhya_personal_finance_dashboard_category_rules;
drop policy if exists "Own rules: delete" on public.vidhya_personal_finance_dashboard_category_rules;
create policy "Own rules: read"   on public.vidhya_personal_finance_dashboard_category_rules
  for select to authenticated using ((select auth.uid()) = user_id);
create policy "Own rules: create" on public.vidhya_personal_finance_dashboard_category_rules
  for insert to authenticated with check ((select auth.uid()) = user_id);
create policy "Own rules: update" on public.vidhya_personal_finance_dashboard_category_rules
  for update to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy "Own rules: delete" on public.vidhya_personal_finance_dashboard_category_rules
  for delete to authenticated using ((select auth.uid()) = user_id);

-- anomaly reviews
drop policy if exists "Own reviews: read"   on public.vidhya_personal_finance_dashboard_anomaly_reviews;
drop policy if exists "Own reviews: create" on public.vidhya_personal_finance_dashboard_anomaly_reviews;
drop policy if exists "Own reviews: delete" on public.vidhya_personal_finance_dashboard_anomaly_reviews;
create policy "Own reviews: read"   on public.vidhya_personal_finance_dashboard_anomaly_reviews
  for select to authenticated using ((select auth.uid()) = user_id);
create policy "Own reviews: create" on public.vidhya_personal_finance_dashboard_anomaly_reviews
  for insert to authenticated with check ((select auth.uid()) = user_id);
create policy "Own reviews: delete" on public.vidhya_personal_finance_dashboard_anomaly_reviews
  for delete to authenticated using ((select auth.uid()) = user_id);


-- ---------------------------------------------------------------------
-- Table privileges: nothing for anon, only what the app needs for authenticated
-- ---------------------------------------------------------------------
revoke all on public.vidhya_personal_finance_dashboard_profiles        from anon, authenticated;
revoke all on public.vidhya_personal_finance_dashboard_statements      from anon, authenticated;
revoke all on public.vidhya_personal_finance_dashboard_transactions    from anon, authenticated;
revoke all on public.vidhya_personal_finance_dashboard_category_rules  from anon, authenticated;
revoke all on public.vidhya_personal_finance_dashboard_anomaly_reviews from anon, authenticated;

grant select, insert                 on public.vidhya_personal_finance_dashboard_profiles        to authenticated;
grant select, insert, delete         on public.vidhya_personal_finance_dashboard_statements      to authenticated;
grant select, insert                 on public.vidhya_personal_finance_dashboard_transactions    to authenticated;
grant update (category)              on public.vidhya_personal_finance_dashboard_transactions    to authenticated;
grant select, insert, update, delete on public.vidhya_personal_finance_dashboard_category_rules  to authenticated;
grant select, insert, delete         on public.vidhya_personal_finance_dashboard_anomaly_reviews to authenticated;


-- ---------------------------------------------------------------------
-- RPC: first sign-in setup. Creates the profile and, only the first time,
-- the default category rules. Runs as the caller, so RLS still applies.
-- ---------------------------------------------------------------------
create or replace function public.vidhya_personal_finance_dashboard_init_user()
returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'You need to be signed in.' using errcode = '28000';
  end if;

  insert into public.vidhya_personal_finance_dashboard_profiles (user_id)
  values (v_uid)
  on conflict (user_id) do nothing;

  if found then
    insert into public.vidhya_personal_finance_dashboard_category_rules (user_id, pattern, category, created_by)
    values
      (v_uid, 'SWIGGY',    'Food',          'system'),
      (v_uid, 'ZOMATO',    'Food',          'system'),
      (v_uid, 'BIGBASKET', 'Food',          'system'),
      (v_uid, 'UBER',      'Transport',     'system'),
      (v_uid, 'NETFLIX',   'Entertainment', 'system'),
      (v_uid, 'PAYROLL',   'Salary',        'system'),
      (v_uid, 'RENT',      'Rent',          'system'),
      (v_uid, 'AIRTEL',    'Bills',         'system'),
      (v_uid, 'APOLLO',    'Health',        'system'),
      (v_uid, 'TRF TO FD', 'Transfers',     'system')
    on conflict do nothing;
  end if;
end;
$$;

revoke execute on function public.vidhya_personal_finance_dashboard_init_user() from public, anon;
grant  execute on function public.vidhya_personal_finance_dashboard_init_user() to authenticated;


-- ---------------------------------------------------------------------
-- RPC: import a statement and all its transactions in one transaction.
-- If any row is invalid, nothing is saved.
--
-- p_statement:    {"file_name": "...", "skipped_rows": 0, "period_start": "2026-04-01",
--                  "period_end": "2026-09-28", "column_mapping": {...}}
-- p_transactions: [{"id": "<uuid>", "txn_date": "2026-04-01", "description": "...",
--                   "merchant": "...", "category": "Food", "amount": 412.00,
--                   "txn_type": "debit", "balance": 1234.50}, ...]
-- ---------------------------------------------------------------------
create or replace function public.vidhya_personal_finance_dashboard_import_statement(
  p_statement    jsonb,
  p_transactions jsonb
)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_uid   uuid := auth.uid();
  v_id    uuid;
  v_count integer;
begin
  if v_uid is null then
    raise exception 'You need to be signed in.' using errcode = '28000';
  end if;
  if jsonb_typeof(p_transactions) is distinct from 'array' then
    raise exception 'Transactions must be a JSON array.';
  end if;
  v_count := jsonb_array_length(p_transactions);
  if v_count = 0 then
    raise exception 'The statement has no transactions to import.';
  end if;
  if v_count > 20000 then
    raise exception 'A statement can have at most 20,000 transactions (this one has %).', v_count;
  end if;

  insert into public.vidhya_personal_finance_dashboard_statements
    (user_id, file_name, row_count, skipped_rows, period_start, period_end, column_mapping)
  values (
    v_uid,
    left(coalesce(nullif(btrim(p_statement ->> 'file_name'), ''), 'statement.csv'), 255),
    v_count,
    greatest(coalesce((p_statement ->> 'skipped_rows')::integer, 0), 0),
    (p_statement ->> 'period_start')::date,
    (p_statement ->> 'period_end')::date,
    coalesce(p_statement -> 'column_mapping', '{}'::jsonb)
  )
  returning id into v_id;

  insert into public.vidhya_personal_finance_dashboard_transactions
    (id, user_id, statement_id, txn_date, description, merchant, category, amount, txn_type, balance)
  select
    coalesce(t.id, gen_random_uuid()), v_uid, v_id, t.txn_date,
    left(t.description, 1000), left(t.merchant, 200), t.category, round(t.amount, 2), t.txn_type, round(t.balance, 2)
  from jsonb_to_recordset(p_transactions) as t(
    id uuid, txn_date date, description text, merchant text, category text,
    amount numeric, txn_type text, balance numeric
  );

  return v_id;
end;
$$;

revoke execute on function public.vidhya_personal_finance_dashboard_import_statement(jsonb, jsonb) from public, anon;
grant  execute on function public.vidhya_personal_finance_dashboard_import_statement(jsonb, jsonb) to authenticated;
