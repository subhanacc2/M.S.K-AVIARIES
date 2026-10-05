-- Aviary: core schema, storage, automation, and admin security
-- Run in Supabase SQL Editor (part 1 of 2)

create extension if not exists "pgcrypto";

-- ─── Tables ───────────────────────────────────────────────────────────────

create table birds (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  species text,
  sex text not null default 'unknown' check (sex in ('male', 'female', 'unknown')),
  ring_number text,
  hatch_date date,
  phenotype text,
  genotype text,
  status text,
  father_id uuid references birds (id) on delete set null,
  mother_id uuid references birds (id) on delete set null,
  bred_by text,
  line_name text,
  video_url text,
  origin_description text,
  parents_note text,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table pairings (
  id uuid primary key default gen_random_uuid(),
  male_id uuid not null references birds (id) on delete restrict,
  female_id uuid not null references birds (id) on delete restrict,
  started_on date default current_date,
  ended_on date,
  show_after_end boolean not null default false,
  notes text,
  created_at timestamptz not null default now(),
  check (male_id <> female_id),
  check (ended_on is null or ended_on >= started_on)
);

create table clutches (
  id uuid primary key default gen_random_uuid(),
  pairing_id uuid not null references pairings (id) on delete cascade,
  label text,
  laid_on date,
  eggs_laid int,
  notes text,
  created_at timestamptz not null default now()
);

alter table birds
  add column clutch_id uuid references clutches (id) on delete set null;

create table bird_photos (
  id uuid primary key default gen_random_uuid(),
  bird_id uuid not null references birds (id) on delete cascade,
  path text not null,
  is_primary boolean not null default false,
  sort_order int not null default 0,
  created_at timestamptz not null default now()
);

create table bird_history (
  id uuid primary key default gen_random_uuid(),
  bird_id uuid not null references birds (id) on delete cascade,
  person_name text not null,
  role text not null default 'breeder' check (role in ('breeder', 'owner')),
  from_year int,
  to_year int,
  notes text,
  show_publicly boolean not null default true,
  sort_order int not null default 0,
  created_at timestamptz not null default now()
);

create table bird_private (
  bird_id uuid primary key references birds (id) on delete cascade,
  bought_from_name text,
  bought_from_phone text,
  bought_on date,
  bought_price numeric(12, 2),
  sold_to_name text,
  sold_to_phone text,
  sold_on date,
  sold_price numeric(12, 2),
  asking_price numeric(12, 2),
  notes text,
  updated_at timestamptz not null default now()
);

create index birds_name_idx on birds (name);
create index birds_parents_idx on birds (father_id, mother_id);
create index pairings_active_idx on pairings (male_id, female_id) where ended_on is null;
create index clutches_pairing_idx on clutches (pairing_id);
create index bird_photos_bird_idx on bird_photos (bird_id, sort_order);
create index bird_history_bird_idx on bird_history (bird_id, sort_order);

-- ─── updated_at ───────────────────────────────────────────────────────────

create or replace function set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create trigger birds_updated_at
  before update on birds
  for each row execute function set_updated_at();

create trigger bird_private_updated_at
  before update on bird_private
  for each row execute function set_updated_at();

-- ─── Pairing automation & validation ──────────────────────────────────────

create or replace function validate_and_close_pairings()
returns trigger
language plpgsql
as $$
declare
  m_sex text;
  f_sex text;
begin
  select sex into m_sex from birds where id = new.male_id;
  if m_sex is distinct from 'male' then
    raise exception 'Pairing male must be a bird with sex male';
  end if;

  select sex into f_sex from birds where id = new.female_id;
  if f_sex is distinct from 'female' then
    raise exception 'Pairing female must be a bird with sex female';
  end if;

  if new.ended_on is null then
    update pairings
    set ended_on = coalesce(new.started_on, current_date)
    where ended_on is null
      and id is distinct from coalesce(new.id, '00000000-0000-0000-0000-000000000000'::uuid)
      and (
        male_id in (new.male_id, new.female_id)
        or female_id in (new.male_id, new.female_id)
      );
  end if;

  return new;
end;
$$;

create trigger pairings_validate_insert
  before insert on pairings
  for each row execute function validate_and_close_pairings();

create trigger pairings_validate_update
  before update on pairings
  for each row execute function validate_and_close_pairings();

-- ─── Chick parents from clutch (permanent) ────────────────────────────────

create or replace function set_bird_parents_from_clutch()
returns trigger
language plpgsql
as $$
declare
  v_male uuid;
  v_female uuid;
begin
  if new.clutch_id is null then
    return new;
  end if;

  select p.male_id, p.female_id
  into v_male, v_female
  from clutches c
  join pairings p on p.id = c.pairing_id
  where c.id = new.clutch_id;

  if not found then
    raise exception 'Clutch not found';
  end if;

  new.father_id := v_male;
  new.mother_id := v_female;
  return new;
end;
$$;

create trigger birds_clutch_parents_insert
  before insert on birds
  for each row execute function set_bird_parents_from_clutch();

create trigger birds_clutch_parents_update
  before update of clutch_id on birds
  for each row execute function set_bird_parents_from_clutch();

create or replace function lock_bird_parents_when_clutch()
returns trigger
language plpgsql
as $$
begin
  if old.clutch_id is not null
     and (new.father_id is distinct from old.father_id
          or new.mother_id is distinct from old.mother_id) then
    raise exception 'Parents are fixed when a bird is linked to a clutch';
  end if;
  return new;
end;
$$;

create trigger birds_lock_parents
  before update of father_id, mother_id on birds
  for each row execute function lock_bird_parents_when_clutch();

-- ─── Photo storage bucket ─────────────────────────────────────────────────

insert into storage.buckets (id, name, public)
values ('bird-photos', 'bird-photos', true)
on conflict (id) do update set public = true;

-- ─── Row level security ───────────────────────────────────────────────────

alter table birds enable row level security;
alter table pairings enable row level security;
alter table clutches enable row level security;
alter table bird_photos enable row level security;
alter table bird_history enable row level security;
alter table bird_private enable row level security;

-- Authenticated admin: full access
create policy birds_admin_all on birds
  for all to authenticated using (true) with check (true);

create policy pairings_admin_all on pairings
  for all to authenticated using (true) with check (true);

create policy clutches_admin_all on clutches
  for all to authenticated using (true) with check (true);

create policy bird_photos_admin_all on bird_photos
  for all to authenticated using (true) with check (true);

create policy bird_history_admin_all on bird_history
  for all to authenticated using (true) with check (true);

create policy bird_private_admin_all on bird_private
  for all to authenticated using (true) with check (true);

-- Public gallery: photos only (bird list uses public_birds view in part 2)
create policy bird_photos_public_read on bird_photos
  for select to anon using (true);

-- Storage policies
create policy bird_photos_storage_public_read on storage.objects
  for select to anon, authenticated
  using (bucket_id = 'bird-photos');

create policy bird_photos_storage_auth_write on storage.objects
  for insert to authenticated
  with check (bucket_id = 'bird-photos');

create policy bird_photos_storage_auth_update on storage.objects
  for update to authenticated
  using (bucket_id = 'bird-photos')
  with check (bucket_id = 'bird-photos');

create policy bird_photos_storage_auth_delete on storage.objects
  for delete to authenticated
  using (bucket_id = 'bird-photos');
