-- COOSH Finance Control — Alina-only visibility hardening
-- Generated 2026-10-20. REVIEW in Supabase SQL Editor before executing.
--
-- Scope: an authenticated owner profile with approval_person='alina'
-- may read only payment expenses assigned to 'alina'. Other existing users
-- retain their existing grants and row-level policies.
--
-- Important: requires existing permissive RLS policies for these tables.
-- Restrictive policies narrow those permissions; they never grant access.
-- This migration does not rewrite SECURITY DEFINER RPC functions. Review
-- finalize_month, delete_expense_owner, create_saving, delete_saving_owner,
-- approve_expense, reject_expense and other exposed RPCs separately.
--
-- Preflight: verify that exactly one intended owner profile has
-- approval_person='alina' and that it is Alina's own user_id:
-- select user_id, display_name, email, role, approval_person
-- from public.profiles where approval_person='alina';

begin;

create or replace function public.coosh_is_alina_owner()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists(
    select 1
    from public.profiles p
    where p.user_id = (select auth.uid())
      and p.role = 'owner'
      and p.approval_person = 'alina'
  );
$$;

revoke all on function public.coosh_is_alina_owner() from public;
grant execute on function public.coosh_is_alina_owner() to authenticated;

-- These tables should already have an appropriate permissive SELECT policy.
alter table public.expenses enable row level security;
drop policy if exists coosh_alina_private_expenses on public.expenses;
create policy coosh_alina_private_expenses on public.expenses
  as restrictive for select to authenticated
  using (
    not (select public.coosh_is_alina_owner())
    or (
      expense_person = 'alina'
      and coalesce(request_kind, 'payment') = 'payment'
    )
  );

alter table public.audit_log enable row level security;
drop policy if exists coosh_alina_private_audit on public.audit_log;
create policy coosh_alina_private_audit on public.audit_log
  as restrictive for select to authenticated
  using (
    not (select public.coosh_is_alina_owner())
    or exists (
      select 1
      from public.expenses e
      where e.id = audit_log.expense_id
        and e.expense_person = 'alina'
        and coalesce(e.request_kind, 'payment') = 'payment'
    )
  );

alter table public.savings enable row level security;
drop policy if exists coosh_alina_no_savings on public.savings;
create policy coosh_alina_no_savings on public.savings
  as restrictive for select to authenticated
  using (not (select public.coosh_is_alina_owner()));

alter table public.profiles enable row level security;
drop policy if exists coosh_alina_own_profile on public.profiles;
create policy coosh_alina_own_profile on public.profiles
  as restrictive for select to authenticated
  using (
    not (select public.coosh_is_alina_owner())
    or user_id = (select auth.uid())
  );

-- Restrict downloadable attachments as well as expense records.
-- The document path is stored in public.expenses.attachment_path.
-- Keep existing Storage policies; this is an additional restrictive policy.
drop policy if exists coosh_alina_private_documents on storage.objects;
create policy coosh_alina_private_documents on storage.objects
  as restrictive for select to authenticated
  using (
    bucket_id <> 'expense-documents'
    or not (select public.coosh_is_alina_owner())
    or exists (
      select 1
      from public.expenses e
      where e.attachment_path = storage.objects.name
        and e.expense_person = 'alina'
        and coalesce(e.request_kind, 'payment') = 'payment'
    )
  );

commit;

-- Follow-up required before claiming complete authorization isolation:
-- 1) Test as Alina: public.expenses/petro records, audit_log, savings,
--    profiles, and Storage download of Petro's attachment must be denied.
-- 2) Test as Petro and accountant: legitimate access must still work.
-- 3) Inspect SECURITY DEFINER RPCs for authorization by auth.uid().
--    In particular, Alina must not be able to invoke finalize_month()
--    on global data or delete/approve Petro's records by supplying IDs.
-- 4) Ensure users cannot update public.profiles.role/approval_person
--    or impersonate another profile.
-- 5) Check direct Storage signed URL generation and SQL views for leaks.
