-- ────────────────────────────────────────────
-- digitalDigm MIS — Supabase Schema v1.2
-- ※ 재실행 가능: 기존 정책 자동 삭제 후 재생성
-- ────────────────────────────────────────────

-- ─── 0. 유틸리티 함수 ───
create or replace function set_updated_at()
returns trigger as $$
begin new.updated_at = now(); return new; end;
$$ language plpgsql;

-- ─── 기존 정책 전체 삭제 (재실행 시 충돌 방지) ───
do $$ begin
  -- profiles
  drop policy if exists "프로필 본인 조회" on profiles;
  drop policy if exists "프로필 전체 조회" on profiles;
  drop policy if exists "프로필 본인 생성" on profiles;
  drop policy if exists "프로필 본인 수정" on profiles;
  drop policy if exists "admin 프로필 관리" on profiles;
  drop policy if exists "본인 프로필 조회" on profiles;
  drop policy if exists "admin 전체 조회" on profiles;
  drop policy if exists "admin 수정" on profiles;
  -- projects
  drop policy if exists "프로젝트 조회" on projects;
  drop policy if exists "프로젝트 편집" on projects;
  -- sales_proposals
  drop policy if exists "제안 조회" on sales_proposals;
  drop policy if exists "제안 편집" on sales_proposals;
  -- clients
  drop policy if exists "고객사 조회" on clients;
  drop policy if exists "고객사 편집" on clients;
  -- integrations
  drop policy if exists "연동 설정 관리" on integrations;
  drop policy if exists "연동 설정 조회·편집" on integrations;
  -- memos
  drop policy if exists "메모 조회" on memos;
  drop policy if exists "메모 편집" on memos;
  drop policy if exists "공지 조회" on memos;
  drop policy if exists "공지 편집" on memos;
exception when undefined_table then null;
end $$;

-- ─── 기존 트리거 삭제 ───
drop trigger if exists trg_projects_updated on projects;
drop trigger if exists trg_sales_updated on sales_proposals;
drop trigger if exists trg_clients_updated on clients;
drop trigger if exists trg_integrations_updated on integrations;
drop trigger if exists on_auth_user_created on auth.users;

-- ─── 1. 사용자 프로필 ───
create table if not exists profiles (
  id uuid references auth.users on delete cascade primary key,
  name text not null default '사용자',
  email text,
  role text default 'editor' check (role in ('admin','editor','viewer')),
  bu text default '전사',
  title text,
  created_at timestamptz default now()
);
alter table profiles enable row level security;

create policy "프로필 본인 조회" on profiles
  for select using (auth.uid() = id);
create policy "프로필 전체 조회" on profiles
  for select using (auth.role() = 'authenticated');
create policy "프로필 본인 생성" on profiles
  for insert with check (auth.uid() = id);
create policy "프로필 본인 수정" on profiles
  for update using (auth.uid() = id);
create policy "admin 프로필 관리" on profiles
  for all using (
    exists (select 1 from profiles where id = auth.uid() and role = 'admin')
  );

-- ─── 회원가입 시 자동 프로필 생성 ───
create or replace function handle_new_user()
returns trigger as $$
begin
  insert into public.profiles (id, name, email, role, bu)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'name', split_part(new.email,'@',1)),
    new.email,
    case when (select count(*) from public.profiles) = 0 then 'admin' else 'editor' end,
    '전사'
  )
  on conflict (id) do nothing;
  return new;
end;
$$ language plpgsql security definer;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function handle_new_user();

-- ─── 2. 프로젝트 ───
create table if not exists projects (
  id uuid default gen_random_uuid() primary key,
  name text not null,
  client text,
  bu text check (bu in ('DX','AD','SM','대관')),
  type text,
  amt numeric default 0,
  team int default 0,
  margin numeric default 0,
  pct int default 0,
  due text,
  stat text default '진행중' check (stat in ('진행중','완료','보류','취소')),
  pm text,
  c_start text,
  c_end text,
  plan_mm numeric default 0,
  actual_mm numeric default 0,
  memo text,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);
alter table projects enable row level security;
create policy "프로젝트 조회" on projects
  for select using (auth.role() = 'authenticated');
create policy "프로젝트 편집" on projects
  for all using (
    exists (select 1 from profiles where id = auth.uid() and role in ('admin','editor'))
  );
create trigger trg_projects_updated before update on projects
  for each row execute function set_updated_at();

-- ─── 3. 제안/영업 ───
create table if not exists sales_proposals (
  id uuid default gen_random_uuid() primary key,
  bu text check (bu in ('DX','AD')),
  category text,
  pm text,
  name text not null,
  client text,
  client_contact text,
  status text default '검토중' check (status in ('검토중','제안중','PT준비','수주','탈락','보류')),
  prop_start text,
  prop_end text,
  pt_date text,
  budget numeric default 0,
  competitor text,
  contact_route text,
  req_date text,
  tf text,
  sales_pm text,
  memo text,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);
alter table sales_proposals enable row level security;
create policy "제안 조회" on sales_proposals
  for select using (auth.role() = 'authenticated');
create policy "제안 편집" on sales_proposals
  for all using (
    exists (select 1 from profiles where id = auth.uid() and role in ('admin','editor'))
  );
create trigger trg_sales_updated before update on sales_proposals
  for each row execute function set_updated_at();

-- ─── 4. 고객사 ───
create table if not exists clients (
  id uuid default gen_random_uuid() primary key,
  name text not null,
  bu text,
  type text,
  amt text,
  contact text,
  tel text,
  expire text,
  memo text,
  stat text default '정상' check (stat in ('정상','주의','위험')),
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);
alter table clients enable row level security;
create policy "고객사 조회" on clients
  for select using (auth.role() = 'authenticated');
create policy "고객사 편집" on clients
  for all using (
    exists (select 1 from profiles where id = auth.uid() and role in ('admin','editor'))
  );
create trigger trg_clients_updated before update on clients
  for each row execute function set_updated_at();

-- ─── 5. 시스템 연동 ───
create table if not exists integrations (
  id uuid default gen_random_uuid() primary key,
  type text check (type in ('erp','gs')),
  name text not null,
  bu text,
  url text,
  api_key text,
  sync_interval text default '수동',
  stat text default '준비중',
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);
alter table integrations enable row level security;
create policy "연동 설정 관리" on integrations
  for all using (
    exists (select 1 from profiles where id = auth.uid() and role = 'admin')
  );
create trigger trg_integrations_updated before update on integrations
  for each row execute function set_updated_at();

-- ─── 6. 메모 / 공지 ───
create table if not exists memos (
  id text primary key,
  content text,
  updated_by uuid references auth.users,
  updated_at timestamptz default now()
);
alter table memos enable row level security;
create policy "메모 조회" on memos
  for select using (auth.role() = 'authenticated');
create policy "메모 편집" on memos
  for all using (
    exists (select 1 from profiles where id = auth.uid() and role in ('admin','editor'))
  );

-- ─── 완료 ───
do $$ begin raise notice 'digitalDigm MIS 스키마 설치 완료 ✅'; end $$;
