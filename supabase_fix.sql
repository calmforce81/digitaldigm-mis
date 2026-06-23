-- ────────────────────────────────────────────
-- digitalDigm MIS — 긴급 픽스 v1.0
-- ※ Supabase SQL Editor에서 실행하세요
-- ────────────────────────────────────────────

-- ─── 1. 무한루프 정책 전체 삭제 ───
drop policy if exists "admin 프로필 관리" on profiles;
drop policy if exists "프로필 본인 조회" on profiles;
drop policy if exists "프로필 전체 조회" on profiles;
drop policy if exists "프로필 본인 생성" on profiles;
drop policy if exists "프로필 본인 수정" on profiles;
drop policy if exists "프로젝트 조회" on projects;
drop policy if exists "프로젝트 편집" on projects;
drop policy if exists "제안 조회" on sales_proposals;
drop policy if exists "제안 편집" on sales_proposals;
drop policy if exists "고객사 조회" on clients;
drop policy if exists "고객사 편집" on clients;
drop policy if exists "연동 설정 관리" on integrations;
drop policy if exists "메모 조회" on memos;
drop policy if exists "메모 편집" on memos;

-- ─── 2. 핵심 해결책: security definer 함수 ───
-- profiles를 직접 참조하는 대신 이 함수를 사용 → 무한루프 방지
create or replace function get_my_role()
returns text as $$
  select role from public.profiles where id = auth.uid();
$$ language sql security definer stable;

-- ─── 3. profiles 정책 재생성 (재귀 없음) ───
create policy "프로필 본인 조회" on profiles
  for select using (auth.uid() = id);

create policy "프로필 전체 조회" on profiles
  for select using (auth.role() = 'authenticated');

create policy "프로필 본인 생성" on profiles
  for insert with check (auth.uid() = id);

create policy "프로필 본인 수정" on profiles
  for update using (auth.uid() = id);

create policy "admin 프로필 관리" on profiles
  for all using (get_my_role() = 'admin');

-- ─── 4. 다른 테이블 정책 재생성 ───
create policy "프로젝트 조회" on projects
  for select using (auth.role() = 'authenticated');
create policy "프로젝트 편집" on projects
  for all using (get_my_role() in ('admin','editor'));

create policy "제안 조회" on sales_proposals
  for select using (auth.role() = 'authenticated');
create policy "제안 편집" on sales_proposals
  for all using (get_my_role() in ('admin','editor'));

create policy "고객사 조회" on clients
  for select using (auth.role() = 'authenticated');
create policy "고객사 편집" on clients
  for all using (get_my_role() in ('admin','editor'));

create policy "연동 설정 관리" on integrations
  for all using (get_my_role() = 'admin');

create policy "메모 조회" on memos
  for select using (auth.role() = 'authenticated');
create policy "메모 편집" on memos
  for all using (get_my_role() in ('admin','editor'));

-- ─── 5. 기존 Auth 사용자 → 프로필 수동 생성 ───
-- (트리거 이전에 가입한 계정 처리)
insert into public.profiles (id, name, email, role, bu)
select
  u.id,
  coalesce(u.raw_user_meta_data->>'name', split_part(u.email,'@',1)),
  u.email,
  'admin',  -- 첫 사용자이므로 admin
  '전사'
from auth.users u
where not exists (select 1 from public.profiles p where p.id = u.id)
on conflict (id) do nothing;

-- ─── 완료 ───
do $$ begin raise notice 'MIS 픽스 완료 ✅ - 이제 로그인 후 새로고침하세요'; end $$;
