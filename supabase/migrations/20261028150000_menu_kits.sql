-- Weekly meal-kit PDFs: the week, both menus, both shopping lists and every
-- recipe, as read by the app's MenuKitParser (tool/menu_kit_ingest.dart).
--
-- Writes go through ingest_menu_kit(), callable with the service-role key
-- only. Signed-in users may read; anonymous clients see nothing.

create table public.menu_kits (
  id uuid primary key default gen_random_uuid(),
  title text not null check (title <> ''),
  week_label text,
  week_start date,
  place text,
  source_file text not null,
  pdf_sha256 text not null unique check (pdf_sha256 ~ '^[0-9a-f]{64}$'),
  -- Object path inside the private "menu-kits" storage bucket.
  pdf_path text,
  imported_at timestamptz not null default now(),
  unique (title, week_start)
);

comment on table public.menu_kits is
  'One weekly meal-kit PDF. Re-importing the same file or the same week replaces its contents.';

create table public.menu_kit_dishes (
  kit_id uuid not null references public.menu_kits (id) on delete cascade,
  variant text not null check (variant in ('regular', 'vegetarian')),
  day text not null check (day in ('Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun')),
  position smallint not null check (position >= 0),
  dish text not null,
  primary key (kit_id, variant, day, position)
);

create table public.menu_kit_items (
  kit_id uuid not null references public.menu_kits (id) on delete cascade,
  variant text not null check (variant in ('regular', 'vegetarian')),
  position smallint not null check (position >= 0),
  name text not null check (name <> ''),
  aisle text not null,
  -- Either a structured amount (quantity_amount + quantity_unit) or the
  -- amount as printed (amount_text, e.g. '4 medium bulbs'), or neither.
  amount_text text,
  quantity_amount numeric,
  quantity_unit text,
  note text,
  cost_cents integer check (cost_cents >= 0),
  days text[] not null default '{}'
    check (days <@ array['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']),
  pantry boolean not null default false,
  primary key (kit_id, variant, position),
  check ((quantity_amount is null) = (quantity_unit is null))
);

create table public.menu_kit_recipes (
  id uuid primary key default gen_random_uuid(),
  kit_id uuid not null references public.menu_kits (id) on delete cascade,
  position smallint not null check (position >= 0),
  title text not null check (title <> ''),
  servings smallint not null check (servings > 0),
  side boolean not null default false,
  -- The menus that cook this recipe.
  variants text[] not null
    check (variants <> '{}' and variants <@ array['regular', 'vegetarian']),
  unique (kit_id, title)
);

create table public.menu_kit_recipe_ingredients (
  recipe_id uuid not null references public.menu_kit_recipes (id) on delete cascade,
  position smallint not null check (position >= 0),
  name text not null check (name <> ''),
  quantity_amount numeric,
  quantity_unit text,
  note text,
  primary key (recipe_id, position),
  check ((quantity_amount is null) = (quantity_unit is null))
);

create index menu_kit_recipes_kit_id_idx on public.menu_kit_recipes (kit_id);

alter table public.menu_kits enable row level security;
alter table public.menu_kit_dishes enable row level security;
alter table public.menu_kit_items enable row level security;
alter table public.menu_kit_recipes enable row level security;
alter table public.menu_kit_recipe_ingredients enable row level security;

create policy "signed-in users read menu kits" on public.menu_kits
  for select to authenticated using (true);
create policy "signed-in users read menu kit dishes" on public.menu_kit_dishes
  for select to authenticated using (true);
create policy "signed-in users read menu kit items" on public.menu_kit_items
  for select to authenticated using (true);
create policy "signed-in users read menu kit recipes" on public.menu_kit_recipes
  for select to authenticated using (true);
create policy "signed-in users read menu kit recipe ingredients"
  on public.menu_kit_recipe_ingredients
  for select to authenticated using (true);

-- Stores one parsed kit in a single transaction and returns its id.
--
-- A kit already stored under the same PDF hash or the same title and week is
-- updated in place: its menus, lists and ingredients are replaced, and its
-- recipes keep their ids when their titles are unchanged.
create or replace function public.ingest_menu_kit(kit jsonb)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
<<ingest>>
declare
  kit_id uuid;
  week date := nullif(kit ->> 'week_start', '')::date;
  recipe jsonb;
  recipe_id uuid;
  recipe_ids uuid[] := '{}';
begin
  if coalesce(kit ->> 'title', '') = '' then
    raise exception 'ingest_menu_kit: title is required';
  end if;
  if jsonb_array_length(coalesce(kit -> 'items', '[]')) = 0 then
    raise exception 'ingest_menu_kit: a kit needs at least one shopping-list item';
  end if;

  select m.id into kit_id
  from public.menu_kits m
  where m.pdf_sha256 = kit ->> 'pdf_sha256'
     or (m.title = kit ->> 'title' and m.week_start = week)
  order by (m.pdf_sha256 = kit ->> 'pdf_sha256') desc
  limit 1;

  if kit_id is null then
    insert into public.menu_kits
      (title, week_label, week_start, place, source_file, pdf_sha256, pdf_path)
    values (
      kit ->> 'title', kit ->> 'week_label', week, kit ->> 'place',
      kit ->> 'source_file', kit ->> 'pdf_sha256', kit ->> 'pdf_path'
    )
    returning id into kit_id;
  else
    update public.menu_kits m set
      title = kit ->> 'title',
      week_label = kit ->> 'week_label',
      week_start = week,
      place = kit ->> 'place',
      source_file = kit ->> 'source_file',
      pdf_sha256 = kit ->> 'pdf_sha256',
      pdf_path = kit ->> 'pdf_path',
      imported_at = now()
    where m.id = ingest.kit_id;
    delete from public.menu_kit_dishes d where d.kit_id = ingest.kit_id;
    delete from public.menu_kit_items i where i.kit_id = ingest.kit_id;
  end if;

  insert into public.menu_kit_dishes (kit_id, variant, day, position, dish)
  select ingest.kit_id, d ->> 'variant', d ->> 'day',
         (dish.ordinality - 1)::smallint, dish.value
  from jsonb_array_elements(coalesce(kit -> 'menus', '[]')) d,
       jsonb_array_elements_text(d -> 'dishes') with ordinality dish;

  insert into public.menu_kit_items (
    kit_id, variant, position, name, aisle, amount_text, quantity_amount,
    quantity_unit, note, cost_cents, days, pantry
  )
  select ingest.kit_id, i ->> 'variant', (i ->> 'position')::smallint,
         i ->> 'name', i ->> 'aisle', i ->> 'amount_text',
         (i ->> 'quantity_amount')::numeric, i ->> 'quantity_unit', i ->> 'note',
         (i ->> 'cost_cents')::integer,
         array(select jsonb_array_elements_text(coalesce(i -> 'days', '[]'))),
         coalesce((i ->> 'pantry')::boolean, false)
  from jsonb_array_elements(kit -> 'items') i;

  for recipe in select * from jsonb_array_elements(coalesce(kit -> 'recipes', '[]'))
  loop
    insert into public.menu_kit_recipes
      (kit_id, position, title, servings, side, variants)
    values (
      ingest.kit_id, (recipe ->> 'position')::smallint,
      recipe ->> 'title', (recipe ->> 'servings')::smallint,
      coalesce((recipe ->> 'side')::boolean, false),
      array(select jsonb_array_elements_text(recipe -> 'variants'))
    )
    on conflict on constraint menu_kit_recipes_kit_id_title_key do update set
      position = excluded.position,
      servings = excluded.servings,
      side = excluded.side,
      variants = excluded.variants
    returning id into recipe_id;

    recipe_ids := recipe_ids || recipe_id;
    delete from public.menu_kit_recipe_ingredients ri
    where ri.recipe_id = ingest.recipe_id;

    insert into public.menu_kit_recipe_ingredients
      (recipe_id, position, name, quantity_amount, quantity_unit, note)
    select ingest.recipe_id, (g.ordinality - 1)::smallint,
           g.value ->> 'name', (g.value ->> 'quantity_amount')::numeric,
           g.value ->> 'quantity_unit', g.value ->> 'note'
    from jsonb_array_elements(coalesce(recipe -> 'ingredients', '[]'))
         with ordinality g;
  end loop;

  delete from public.menu_kit_recipes r
  where r.kit_id = ingest.kit_id and r.id <> all (recipe_ids);

  return kit_id;
end;
$$;

comment on function public.ingest_menu_kit(jsonb) is
  'Stores one parsed meal kit (see tool/menu_kit_ingest.dart for the payload). Service role only.';

revoke execute on function public.ingest_menu_kit(jsonb) from public, anon, authenticated;
grant execute on function public.ingest_menu_kit(jsonb) to service_role;

-- The original PDFs, keyed by content hash. Private: no storage policies,
-- so only the service role can read or write them.
insert into storage.buckets (id, name, public, allowed_mime_types)
values ('menu-kits', 'menu-kits', false, array['application/pdf'])
on conflict (id) do nothing;
