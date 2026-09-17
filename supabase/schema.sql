-- ============================================================================
-- QuizRail — backend Supabase v1 (remplace Firebase : Firestore + Functions).
-- GRATUIT, sans carte bancaire (plan Free Supabase).
--
-- Installation (10 min) :
--   1. supabase.com → New project (nom : quizrail) → copier URL + anon key.
--   2. Dashboard → Authentication → Providers → activer "Anonymous".
--   3. Dashboard → SQL Editor → coller TOUT ce fichier → Run.
--   4. Storage : le bucket "tunnel-images" est créé ci-dessous.
--   5. Edge Function IA : voir supabase/functions/generate-tunnel/.
--   6. Donner URL + anon key à l'app (lib/core/data/supabase_config.dart).
--
-- Parité avec l'ancien backend :
--   - file FIFO duel, arbitrage 100 % serveur (scores, streaks, pouvoirs,
--     forfaits, revanches), rooms party (12 max, host, codes 6 caractères),
--     réponses validées serveur, jetons + battle pass x2, classements,
--     quota IA 5/jour. Les erreurs métier remontent en français (P0001).
-- ============================================================================

create extension if not exists pgcrypto;

-- ----------------------------------------------------------------------------
-- Tables
-- ----------------------------------------------------------------------------

create table if not exists profiles (
  uid uuid primary key references auth.users (id) on delete cascade,
  display_name text not null default '',
  country text not null default '--',
  tokens integer not null default 120,
  lang text not null default 'fr',
  friend_ids text[] not null default '{}',
  battle_pass boolean not null default false,
  created_at timestamptz not null default now()
);

create table if not exists entitlements (
  uid uuid primary key references auth.users (id) on delete cascade,
  remove_ads boolean not null default false,
  battle_pass boolean not null default false,
  skins text[] not null default '{}'
);

create table if not exists duel_queue (
  uid uuid primary key references auth.users (id) on delete cascade,
  lang text not null default 'fr',
  joined_at timestamptz not null default now()
);

create table if not exists duels (
  id text primary key default gen_random_uuid()::text,
  player_ids text[] not null,
  status text not null default 'running',
  questions jsonb not null default '[]'::jsonb,
  players jsonb not null default '{}'::jsonb,
  winner_uid text,
  is_draw boolean not null default false,
  finish_reason text,
  rematch_requests text[] not null default '{}',
  rematch_duel_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Réponses du duel : AUCUNE policy → illisible côté client (RPC only).
create table if not exists duel_secrets (
  duel_id text primary key references duels (id) on delete cascade,
  answers jsonb not null
);

create table if not exists rooms (
  id text primary key default gen_random_uuid()::text,
  code text not null unique,
  host_id text not null,
  status text not null default 'lobby',
  theme text not null default 'Party',
  questions jsonb not null default '[]'::jsonb,
  question_index integer not null default 0,
  player_ids text[] not null default '{}',
  max_players integer not null default 12,
  winner_uid text,
  is_draw boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists room_players (
  room_id text not null references rooms (id) on delete cascade,
  uid text not null,
  display_name text not null default '',
  score integer not null default 0,
  correct integer not null default 0,
  answered integer not null default 0,
  streak integer not null default 0,
  best_streak integer not null default 0,
  last_question_index integer not null default -1,
  finished boolean not null default false,
  finished_at bigint not null default 0,
  connected boolean not null default true,
  last_seen bigint not null default 0,
  primary key (room_id, uid)
);

-- Réponses de la room : AUCUNE policy → illisible côté client (RPC only).
create table if not exists room_secrets (
  room_id text primary key references rooms (id) on delete cascade,
  answers jsonb not null
);

create table if not exists leaderboard (
  uid text primary key,
  display_name text not null default '',
  country text not null default '--',
  best_score integer not null default 0,
  wins integer not null default 0,
  games integer not null default 0,
  updated_at timestamptz not null default now()
);

create table if not exists tunnels (
  id text primary key default gen_random_uuid()::text,
  theme text not null,
  questions jsonb not null default '[]'::jsonb,
  creator_id text not null,
  is_public boolean not null default false,
  lang text not null default 'fr',
  image_url text,
  rating_sum integer not null default 0,
  rating_count integer not null default 0,
  rating_avg double precision not null default 0,
  created_at timestamptz not null default now()
);

-- Notes individuelles : AUCUNE policy → écriture RPC only, jamais lisibles.
create table if not exists tunnel_ratings (
  tunnel_id text not null references tunnels (id) on delete cascade,
  uid text not null,
  stars integer not null,
  primary key (tunnel_id, uid)
);

-- Signalements : AUCUNE policy → écriture RPC only.
create table if not exists reports (
  id text primary key default gen_random_uuid()::text,
  tunnel_id text not null,
  reporter_uid text not null,
  reason text not null,
  status text not null default 'pending',
  created_at timestamptz not null default now()
);

-- Quota IA : AUCUNE policy → edge function (service_role) only.
create table if not exists ai_quotas (
  uid text not null,
  day date not null,
  count integer not null default 0,
  primary key (uid, day)
);

create table if not exists sessions (
  id text primary key default gen_random_uuid()::text,
  tunnel_id text not null default '',
  participant_ids text[] not null default '{}',
  score integer not null default 0,
  best_streak integer not null default 0,
  tokens_earned integer not null default 0,
  position integer not null default 0,
  total_tiles integer not null default 12,
  finished boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Preuves d'achat : AUCUNE policy → edge function (service_role) only.
-- L'idempotence est assurée par l'unicité du purchase_token.
create table if not exists purchases (
  id text primary key default gen_random_uuid()::text,
  uid text not null,
  product_id text not null,
  purchase_token text not null unique,
  tokens integer not null default 0,
  created_at timestamptz not null default now()
);

-- Bucket public pour les images de tunnels (offre gratuite : 1 Go).
insert into storage.buckets (id, name, public)
values ('tunnel-images', 'tunnel-images', true)
on conflict (id) do nothing;

-- ----------------------------------------------------------------------------
-- RLS
-- ----------------------------------------------------------------------------

alter table profiles enable row level security;
alter table entitlements enable row level security;
alter table duel_queue enable row level security;
alter table duels enable row level security;
alter table duel_secrets enable row level security;
alter table rooms enable row level security;
alter table room_players enable row level security;
alter table room_secrets enable row level security;
alter table leaderboard enable row level security;
alter table tunnels enable row level security;
alter table tunnel_ratings enable row level security;
alter table reports enable row level security;
alter table ai_quotas enable row level security;
alter table sessions enable row level security;
alter table purchases enable row level security;

drop policy if exists "own profile" on profiles;
create policy "own profile" on profiles
  for all to authenticated using (uid = auth.uid()) with check (uid = auth.uid());

drop policy if exists "own entitlements read" on entitlements;
create policy "own entitlements read" on entitlements
  for select to authenticated using (uid = auth.uid());

drop policy if exists "own queue row" on duel_queue;
create policy "own queue row" on duel_queue
  for all to authenticated using (uid = auth.uid()) with check (uid = auth.uid());

drop policy if exists "duel participants read" on duels;
create policy "duel participants read" on duels
  for select to authenticated using (auth.uid()::text = any (player_ids));

drop policy if exists "room members read" on rooms;
create policy "room members read" on rooms
  for select to authenticated using (auth.uid()::text = any (player_ids));

drop policy if exists "room players read" on room_players;
create policy "room players read" on room_players
  for select to authenticated using (
    exists (
      select 1 from rooms r
      where r.id = room_players.room_id
        and auth.uid()::text = any (r.player_ids)
    )
  );

drop policy if exists "leaderboard read" on leaderboard;
create policy "leaderboard read" on leaderboard
  for select to authenticated using (true);

drop policy if exists "tunnels public read" on tunnels;
create policy "tunnels public read" on tunnels
  for select to authenticated using (is_public or creator_id = auth.uid()::text);

drop policy if exists "tunnels owner insert" on tunnels;
create policy "tunnels owner insert" on tunnels
  for insert to authenticated with check (creator_id = auth.uid()::text);

drop policy if exists "tunnels owner write" on tunnels;
create policy "tunnels owner write" on tunnels
  for update to authenticated
  using (creator_id = auth.uid()::text)
  with check (creator_id = auth.uid()::text);

drop policy if exists "tunnels owner delete" on tunnels;
create policy "tunnels owner delete" on tunnels
  for delete to authenticated using (creator_id = auth.uid()::text);

drop policy if exists "own sessions" on sessions;
create policy "own sessions" on sessions
  for all to authenticated
  using (auth.uid()::text = any (participant_ids))
  with check (auth.uid()::text = any (participant_ids));

drop policy if exists "tunnel images public read" on storage.objects;
create policy "tunnel images public read" on storage.objects
  for select to authenticated using (bucket_id = 'tunnel-images');

drop policy if exists "tunnel images own upload" on storage.objects;
create policy "tunnel images own upload" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'tunnel-images'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

-- Temps réel : lignes + classements + marché suivis en direct par l'appli.
alter publication supabase_realtime add table duels;
alter publication supabase_realtime add table rooms;
alter publication supabase_realtime add table room_players;
alter publication supabase_realtime add table leaderboard;
alter publication supabase_realtime add table tunnels;

-- ----------------------------------------------------------------------------
-- Utilitaires
-- ----------------------------------------------------------------------------

create or replace function now_ms() returns bigint
language sql immutable as $$ select (extract(epoch from now()) * 1000)::bigint $$;

-- Pseudo repli déterministe (même convention que l'ancien serveur).
create or replace function short_name(p_uid text) returns text
language sql immutable as $$
  select 'Joueur ' || upper(substring(replace(p_uid, '-', ''), 1, 4))
$$;

create or replace function profile_name(p_uid uuid) returns text
language sql stable as $$
  select coalesce(nullif((select display_name from profiles where uid = p_uid), ''), short_name(p_uid::text))
$$;

create or replace function ensure_profile() returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then
    raise exception 'Connexion requise.' using errcode = 'P0001';
  end if;
  insert into profiles (uid) values (auth.uid()) on conflict (uid) do nothing;
end $$;

create or replace function pass_active(p_uid uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select battle_pass from entitlements where uid = p_uid), false)
      or coalesce((select battle_pass from profiles where uid = p_uid), false)
$$;

create or replace function bump_leaderboard(p_uid text, p_score integer, p_won boolean)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid;
begin
  begin
    v_uid := p_uid::uuid;
  exception when others then
    return;
  end;
  insert into leaderboard (uid, display_name, country, best_score, wins, games, updated_at)
  values (
    p_uid,
    coalesce((select nullif(display_name, '') from profiles where uid = v_uid), short_name(p_uid)),
    coalesce((select country from profiles where uid = v_uid), '--'),
    p_score, case when p_won then 1 else 0 end, 1, now()
  )
  on conflict (uid) do update set
    display_name = excluded.display_name,
    country = excluded.country,
    best_score = greatest(leaderboard.best_score, excluded.best_score),
    wins = leaderboard.wins + excluded.wins,
    games = leaderboard.games + 1,
    updated_at = now();
end $$;

-- ----------------------------------------------------------------------------
-- Banque duel standard (8 questions FR/EN/AR — mêmes que l'appli).
-- ----------------------------------------------------------------------------

create or replace function duel_bank() returns jsonb
language sql immutable as $$
  select jsonb_build_array(
    jsonb_build_object('prompt', jsonb_build_object('fr', 'Capitale de la France ?', 'en', 'Capital of France?', 'ar', 'ما عاصمة فرنسا؟'), 'answers', jsonb_build_object('fr', jsonb_build_array('paris'), 'en', jsonb_build_array('paris'), 'ar', jsonb_build_array('باريس', 'paris')), 'difficulty', 'easy'),
    jsonb_build_object('prompt', jsonb_build_object('fr', 'Combien font 2 + 6 ?', 'en', 'How much is 2 + 6?', 'ar', 'كم يساوي 2 + 6؟'), 'answers', jsonb_build_object('fr', jsonb_build_array('8', 'huit'), 'en', jsonb_build_array('8', 'eight'), 'ar', jsonb_build_array('8', '٨', 'ثمانية')), 'difficulty', 'easy'),
    jsonb_build_object('prompt', jsonb_build_object('fr', 'Couleur du ciel par beau temps ?', 'en', 'Color of a clear sky?', 'ar', 'ما لون السماء الصافية؟'), 'answers', jsonb_build_object('fr', jsonb_build_array('bleu'), 'en', jsonb_build_array('blue'), 'ar', jsonb_build_array('أزرق', 'ازرق')), 'difficulty', 'easy'),
    jsonb_build_object('prompt', jsonb_build_object('fr', 'Combien de pattes a une araignée ?', 'en', 'How many legs does a spider have?', 'ar', 'كم عدد أرجل العنكبوت؟'), 'answers', jsonb_build_object('fr', jsonb_build_array('8', 'huit'), 'en', jsonb_build_array('8', 'eight'), 'ar', jsonb_build_array('8', '٨', 'ثمانية')), 'difficulty', 'medium'),
    jsonb_build_object('prompt', jsonb_build_object('fr', 'Le petit du chat s’appelle…', 'en', 'A baby cat is called a…', 'ar', 'ما اسم صغير القط؟'), 'answers', jsonb_build_object('fr', jsonb_build_array('chaton'), 'en', jsonb_build_array('kitten'), 'ar', jsonb_build_array('هريرة', 'قط صغير', 'kitten')), 'difficulty', 'medium'),
    jsonb_build_object('prompt', jsonb_build_object('fr', 'Planète la plus proche du Soleil ?', 'en', 'Closest planet to the Sun?', 'ar', 'ما أقرب كوكب إلى الشمس؟'), 'answers', jsonb_build_object('fr', jsonb_build_array('mercure'), 'en', jsonb_build_array('mercury'), 'ar', jsonb_build_array('عطارد')), 'difficulty', 'medium'),
    jsonb_build_object('prompt', jsonb_build_object('fr', 'Combien font 5 × 3 ?', 'en', 'How much is 5 × 3?', 'ar', 'كم يساوي 5 × 3؟'), 'answers', jsonb_build_object('fr', jsonb_build_array('15', 'quinze'), 'en', jsonb_build_array('15', 'fifteen'), 'ar', jsonb_build_array('15', '١٥', 'خمسة عشر')), 'difficulty', 'hard'),
    jsonb_build_object('prompt', jsonb_build_object('fr', 'Quel animal miaule ?', 'en', 'Which animal meows?', 'ar', 'ما الحيوان الذي يموء؟'), 'answers', jsonb_build_object('fr', jsonb_build_array('chat'), 'en', jsonb_build_array('cat'), 'ar', jsonb_build_array('قط', 'قطة')), 'difficulty', 'hard')
  )
$$;

create or replace function fresh_duel_player(p_lang text) returns jsonb
language sql immutable as $$
  select jsonb_build_object(
    'lang', p_lang, 'score', 0, 'correct', 0, 'wrong', 0, 'streak', 0,
    'bestStreak', 0, 'answered', 0, 'position', 0, 'totalElapsedMs', 0,
    'finished', false, 'connected', true, 'lastSeen', now_ms(),
    'frozenUntil', 0, 'doubleUntil', 0
  )
$$;

-- Valide un set de 9 questions custom (3 par difficulté, réponses non vides).
create or replace function assert_valid_questions(p_qs jsonb) returns void
language plpgsql immutable as $$
declare
  q jsonb; d text; n_easy int := 0; n_med int := 0; n_hard int := 0;
begin
  if p_qs is null or jsonb_typeof(p_qs) <> 'array' or jsonb_array_length(p_qs) <> 9 then
    raise exception '9 questions requises.' using errcode = 'P0001';
  end if;
  for q in select * from jsonb_array_elements(p_qs) loop
    if q->>'prompt' is null or btrim(q->>'prompt') = ''
       or q->>'answer' is null or btrim(q->>'answer') = '' then
      raise exception 'Question invalide.' using errcode = 'P0001';
    end if;
    d := q->>'difficulty';
    if d = 'easy' then n_easy := n_easy + 1;
    elsif d = 'medium' then n_med := n_med + 1;
    elsif d = 'hard' then n_hard := n_hard + 1;
    else raise exception 'Question invalide.' using errcode = 'P0001';
    end if;
  end loop;
  if n_easy <> 3 or n_med <> 3 or n_hard <> 3 then
    raise exception '3 questions par difficulté requises.' using errcode = 'P0001';
  end if;
end $$;

-- ----------------------------------------------------------------------------
-- Duel : matchmaking FIFO atomique.
-- ----------------------------------------------------------------------------

create or replace function find_duel(p_lang text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid text := auth.uid()::text;
  v_lang text := case when p_lang in ('en', 'ar') then p_lang else 'fr' end;
  v_opp_uid uuid;
  v_opp_lang text;
  v_bank jsonb := duel_bank();
  v_prompts jsonb;
  v_answers jsonb;
  v_duel_id text;
begin
  if v_uid is null then
    raise exception 'Connexion requise.' using errcode = 'P0001';
  end if;
  select uid, lang into v_opp_uid, v_opp_lang
  from duel_queue where uid::text <> v_uid order by joined_at asc limit 1;
  if not found then
    insert into duel_queue (uid, lang) values (auth.uid(), v_lang)
    on conflict (uid) do update set lang = excluded.lang, joined_at = now();
    return jsonb_build_object('status', 'waiting');
  end if;
  select jsonb_agg(jsonb_build_object('prompt', e->'prompt', 'difficulty', e->'difficulty'))
    into v_prompts from jsonb_array_elements(v_bank) e;
  select jsonb_agg(e->'answers') into v_answers from jsonb_array_elements(v_bank) e;
  insert into duels (player_ids, status, questions, players)
  values (
    array[v_uid, v_opp_uid::text], 'running', v_prompts,
    jsonb_build_object(v_uid, fresh_duel_player(v_lang), v_opp_uid::text, fresh_duel_player(v_opp_lang))
  )
  returning id into v_duel_id;
  insert into duel_secrets (duel_id, answers) values (v_duel_id, v_answers);
  delete from duel_queue where uid::text in (v_uid, v_opp_uid::text);
  return jsonb_build_object('status', 'matched', 'duelId', v_duel_id, 'opponentUid', v_opp_uid::text);
end $$;

create or replace function leave_queue() returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then
    raise exception 'Connexion requise.' using errcode = 'P0001';
  end if;
  delete from duel_queue where uid = auth.uid();
  return jsonb_build_object('left', true);
end $$;

-- ----------------------------------------------------------------------------
-- Duel : réponse validée serveur.
-- ----------------------------------------------------------------------------

create or replace function submit_duel_answer(
  p_duel_id text, p_answer text, p_elapsed_ms integer, p_lang text
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid text := auth.uid()::text;
  v_duel duels%rowtype;
  v_me jsonb; v_opp_uid text; v_opp jsonb;
  v_lang text := case when p_lang in ('en', 'ar') then p_lang else 'fr' end;
  v_answers jsonb; v_accepted jsonb; v_norm text;
  v_correct boolean := false;
  v_streak int; v_gained int := 0; v_score int; v_correct_n int;
  v_answered int; v_finished boolean; v_now bigint := now_ms();
  v_duel_finished boolean := false; v_winner text := null; v_draw boolean := false;
  v_all jsonb;
begin
  if v_uid is null then raise exception 'Connexion requise.' using errcode = 'P0001'; end if;
  if p_elapsed_ms is null or p_elapsed_ms < 700 then
    raise exception 'Réponse trop rapide — prends le temps de lire.' using errcode = 'P0001';
  end if;
  if p_elapsed_ms > 600000 then
    raise exception 'Réponse périmée.' using errcode = 'P0001';
  end if;
  select * into v_duel from duels where id = p_duel_id for update;
  if not found then raise exception 'Duel introuvable.' using errcode = 'P0001'; end if;
  if v_duel.status <> 'running' then raise exception 'Duel terminé.' using errcode = 'P0001'; end if;
  if not (v_uid = any (v_duel.player_ids)) then raise exception 'Pas ton duel.' using errcode = 'P0001'; end if;
  v_me := coalesce(v_duel.players->v_uid, '{}'::jsonb);
  if coalesce((v_me->>'finished')::boolean, false) then
    raise exception 'Tu as fini tes questions.' using errcode = 'P0001';
  end if;
  -- questionIndex attendu = answered (le client envoie son index courant).
  if coalesce((v_me->>'answered')::int, 0) < 0 or coalesce((v_me->>'answered')::int, 0) >= 8 then
    raise exception 'Question invalide.' using errcode = 'P0001';
  end if;
  if v_now < coalesce((v_me->>'frozenUntil')::bigint, 0) then
    raise exception 'Gelé par l’adversaire !' using errcode = 'P0001';
  end if;
  select answers into v_answers from duel_secrets where duel_id = p_duel_id;
  v_accepted := coalesce(v_answers->(coalesce((v_me->>'answered')::int, 0))->v_lang,
                         v_answers->(coalesce((v_me->>'answered')::int, 0))->'fr', '[]'::jsonb);
  v_norm := lower(btrim(coalesce(p_answer, '')));
  if v_norm <> '' then
    select exists (
      select 1 from jsonb_array_elements_text(v_accepted) a where lower(a) = v_norm
    ) into v_correct;
  end if;
  v_score := coalesce((v_me->>'score')::int, 0);
  v_correct_n := coalesce((v_me->>'correct')::int, 0);
  v_streak := coalesce((v_me->>'streak')::int, 0);
  if v_correct then
    v_streak := v_streak + 1;
    v_gained := 100 + case when v_streak >= 3 then 25 else 0 end;
    if v_now < coalesce((v_me->>'doubleUntil')::bigint, 0) then v_gained := v_gained * 2; end if;
    v_score := v_score + v_gained;
    v_correct_n := v_correct_n + 1;
    update profiles set tokens = tokens + case when pass_active(auth.uid()) then 20 else 10 end
    where uid = auth.uid();
  else
    v_streak := 0;
  end if;
  v_answered := coalesce((v_me->>'answered')::int, 0) + 1;
  v_finished := v_answered >= 8;
  v_me := v_me || jsonb_build_object(
    'score', v_score, 'correct', v_correct_n,
    'wrong', coalesce((v_me->>'wrong')::int, 0) + case when v_correct then 0 else 1 end,
    'streak', v_streak, 'bestStreak', greatest(coalesce((v_me->>'bestStreak')::int, 0), v_streak),
    'answered', v_answered, 'position', v_correct_n,
    'totalElapsedMs', coalesce((v_me->>'totalElapsedMs')::int, 0) + p_elapsed_ms,
    'finished', v_finished, 'lastSeen', v_now
  );
  v_all := jsonb_set(v_duel.players, array[v_uid], v_me);
  select array_to_string(array_agg(x), ',') into v_opp_uid
  from unnest(v_duel.player_ids) x where x <> v_uid;
  v_opp := coalesce(v_all->v_opp_uid, '{}'::jsonb);
  if v_finished and coalesce((v_opp->>'finished')::boolean, false) then
    v_duel_finished := true;
    if (v_me->>'score')::int <> (v_opp->>'score')::int then
      v_winner := case when (v_me->>'score')::int > (v_opp->>'score')::int then v_uid else v_opp_uid end;
    elsif (v_me->>'totalElapsedMs')::int <> (v_opp->>'totalElapsedMs')::int then
      v_winner := case when (v_me->>'totalElapsedMs')::int < (v_opp->>'totalElapsedMs')::int then v_uid else v_opp_uid end;
    else
      v_draw := true;
    end if;
    update duels set players = v_all, status = 'finished', winner_uid = v_winner,
      is_draw = v_draw, finish_reason = 'completed', updated_at = now() where id = p_duel_id;
    perform bump_leaderboard(v_uid, (v_me->>'score')::int, v_winner = v_uid);
    perform bump_leaderboard(v_opp_uid, (v_opp->>'score')::int, v_winner = v_opp_uid);
  else
    update duels set players = v_all, updated_at = now() where id = p_duel_id;
  end if;
  return jsonb_build_object(
    'correct', v_correct, 'gained', v_gained, 'score', v_score,
    'position', v_correct_n, 'answered', v_answered, 'finished', v_finished,
    'duelFinished', v_duel_finished, 'winnerUid', v_winner, 'isDraw', v_draw
  );
end $$;

-- ----------------------------------------------------------------------------
-- Duel : pouvoirs / forfait / revanche / présence.
-- ----------------------------------------------------------------------------

create or replace function use_power(p_duel_id text, p_power text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid text := auth.uid()::text;
  v_duel duels%rowtype;
  v_cost int := case p_power when 'freeze' then 15 when 'double' then 10 when 'steal' then 20 else null end;
  v_wallet int; v_opp_wallet int; v_opp_uid text;
  v_players jsonb; v_now bigint := now_ms(); v_until bigint;
  v_out jsonb;
begin
  if v_uid is null then raise exception 'Connexion requise.' using errcode = 'P0001'; end if;
  if v_cost is null then raise exception 'Pouvoir invalide.' using errcode = 'P0001'; end if;
  select * into v_duel from duels where id = p_duel_id for update;
  if not found then raise exception 'Duel introuvable.' using errcode = 'P0001'; end if;
  if v_duel.status <> 'running' then raise exception 'Duel terminé.' using errcode = 'P0001'; end if;
  if not (v_uid = any (v_duel.player_ids)) then raise exception 'Pas ton duel.' using errcode = 'P0001'; end if;
  select tokens into v_wallet from profiles where uid = auth.uid();
  if coalesce(v_wallet, 0) < v_cost then raise exception 'Pas assez de jetons.' using errcode = 'P0001'; end if;
  select array_to_string(array_agg(x), ',') into v_opp_uid
  from unnest(v_duel.player_ids) x where x <> v_uid;
  v_players := v_duel.players;
  if p_power = 'freeze' then
    if v_now < coalesce((v_players->v_opp_uid->>'frozenUntil')::bigint, 0) then
      raise exception 'Déjà gelé !' using errcode = 'P0001';
    end if;
    v_until := v_now + 5000;
    v_players := jsonb_set(v_players, array[v_opp_uid, 'frozenUntil'], to_jsonb(v_until));
    v_out := jsonb_build_object('frozenUntil', v_until);
  elsif p_power = 'double' then
    if v_now < coalesce((v_players->v_uid->>'doubleUntil')::bigint, 0) then
      raise exception 'Déjà doublé !' using errcode = 'P0001';
    end if;
    v_until := v_now + 20000;
    v_players := jsonb_set(v_players, array[v_uid, 'doubleUntil'], to_jsonb(v_until));
    v_out := jsonb_build_object('doubleUntil', v_until);
  else
    select tokens into v_opp_wallet from profiles where uid = v_opp_uid::uuid;
    if coalesce(v_opp_wallet, 0) < 10 then
      raise exception 'L’adversaire n’a pas assez de jetons.' using errcode = 'P0001';
    end if;
    update profiles set tokens = tokens - 10 where uid = v_opp_uid::uuid;
    update profiles set tokens = tokens + 10 where uid = auth.uid();
    v_out := jsonb_build_object('stolen', 10);
  end if;
  update profiles set tokens = tokens - v_cost where uid = auth.uid();
  v_players := jsonb_set(v_players, array[v_uid, 'lastSeen'], to_jsonb(v_now));
  update duels set players = v_players, updated_at = now() where id = p_duel_id;
  return jsonb_build_object('wallet', coalesce(v_wallet, 0) - v_cost) || v_out;
end $$;

create or replace function claim_forfeit(p_duel_id text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid text := auth.uid()::text;
  v_duel duels%rowtype; v_opp_uid text; v_opp jsonb;
begin
  if v_uid is null then raise exception 'Connexion requise.' using errcode = 'P0001'; end if;
  select * into v_duel from duels where id = p_duel_id for update;
  if not found then raise exception 'Duel introuvable.' using errcode = 'P0001'; end if;
  if v_duel.status <> 'running' then
    return jsonb_build_object('alreadyFinished', true, 'winnerUid', v_duel.winner_uid);
  end if;
  if not (v_uid = any (v_duel.player_ids)) then raise exception 'Pas ton duel.' using errcode = 'P0001'; end if;
  select array_to_string(array_agg(x), ',') into v_opp_uid
  from unnest(v_duel.player_ids) x where x <> v_uid;
  v_opp := coalesce(v_duel.players->v_opp_uid, '{}'::jsonb);
  if now_ms() - coalesce((v_opp->>'lastSeen')::bigint, 0) < 30000 then
    raise exception 'L’adversaire est encore en jeu.' using errcode = 'P0001';
  end if;
  update duels set
    players = jsonb_set(players, array[v_uid, 'finished'], to_jsonb(true)),
    status = 'finished', winner_uid = v_uid, is_draw = false,
    finish_reason = 'forfeit', updated_at = now()
  where id = p_duel_id;
  perform bump_leaderboard(v_uid, coalesce((v_duel.players->v_uid->>'score')::int, 0), true);
  perform bump_leaderboard(v_opp_uid, coalesce((v_opp->>'score')::int, 0), false);
  return jsonb_build_object('winnerUid', v_uid, 'finishReason', 'forfeit');
end $$;

create or replace function request_rematch(p_duel_id text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid text := auth.uid()::text;
  v_duel duels%rowtype;
  v_req text[]; v_a text; v_b text; v_new_id text;
  v_bank jsonb := duel_bank(); v_prompts jsonb; v_answers jsonb;
  v_lang_a text; v_lang_b text;
begin
  if v_uid is null then raise exception 'Connexion requise.' using errcode = 'P0001'; end if;
  select * into v_duel from duels where id = p_duel_id for update;
  if not found then raise exception 'Duel introuvable.' using errcode = 'P0001'; end if;
  if v_duel.status <> 'finished' then raise exception 'Duel non terminé.' using errcode = 'P0001'; end if;
  if not (v_uid = any (v_duel.player_ids)) then raise exception 'Pas ton duel.' using errcode = 'P0001'; end if;
  if v_duel.rematch_duel_id is not null then
    return jsonb_build_object('status', 'matched', 'duelId', v_duel.rematch_duel_id);
  end if;
  v_req := array(select distinct x from unnest(v_duel.rematch_requests || array[v_uid]) x);
  if not (v_duel.player_ids <@ v_req and v_req <@ (v_duel.player_ids || v_req) and array_length(v_duel.player_ids, 1) = array_length(array(select distinct y from unnest(v_req) y where y = any (v_duel.player_ids)), 1)) then
    update duels set rematch_requests = v_req where id = p_duel_id;
    return jsonb_build_object('status', 'waiting');
  end if;
  v_a := v_duel.player_ids[1]; v_b := v_duel.player_ids[2];
  v_lang_a := coalesce(v_duel.players->v_a->>'lang', 'fr');
  v_lang_b := coalesce(v_duel.players->v_b->>'lang', 'fr');
  v_new_id := 'rematch_' || p_duel_id;
  select jsonb_agg(jsonb_build_object('prompt', e->'prompt', 'difficulty', e->'difficulty'))
    into v_prompts from jsonb_array_elements(v_bank) e;
  select jsonb_agg(e->'answers') into v_answers from jsonb_array_elements(v_bank) e;
  insert into duels (id, player_ids, status, questions, players)
  values (v_new_id, array[v_a, v_b], 'running', v_prompts,
    jsonb_build_object(v_a, fresh_duel_player(v_lang_a), v_b, fresh_duel_player(v_lang_b)))
  on conflict (id) do nothing;
  insert into duel_secrets (duel_id, answers) values (v_new_id, v_answers)
  on conflict (duel_id) do nothing;
  update duels set rematch_requests = v_req, rematch_duel_id = v_new_id where id = p_duel_id;
  return jsonb_build_object('status', 'matched', 'duelId', v_new_id);
end $$;

create or replace function touch_duel_presence(p_duel_id text, p_connected boolean)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid text := auth.uid()::text;
begin
  if v_uid is null then return jsonb_build_object('ok', false); end if;
  update duels set players = jsonb_set(players, array[v_uid],
    coalesce(players->v_uid, '{}'::jsonb) || jsonb_build_object('connected', p_connected, 'lastSeen', now_ms()))
  where id = p_duel_id and v_uid = any (player_ids);
  return jsonb_build_object('ok', true);
end $$;

-- ----------------------------------------------------------------------------
-- Party : création (code unique), join, leave, start, réponse, avance, fin.
-- ----------------------------------------------------------------------------

create or replace function create_party(p_theme text, p_prompts jsonb, p_answers jsonb)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid text := auth.uid()::text;
  v_theme text := coalesce(nullif(btrim(coalesce(p_theme, '')), ''), 'Party');
  v_code text := null;
  v_try int; v_n int;
  v_room_id text; v_name text;
begin
  if v_uid is null then raise exception 'Connexion requise.' using errcode = 'P0001'; end if;
  if p_prompts is null or jsonb_array_length(p_prompts) <> 8 then
    -- Banque standard : 8 questions (parité).
    p_prompts := (select jsonb_agg(jsonb_build_object('prompt', e->'prompt', 'difficulty', e->'difficulty')) from jsonb_array_elements(duel_bank()) e);
    p_answers := (select jsonb_agg(e->'answers') from jsonb_array_elements(duel_bank()) e);
    v_theme := case when v_theme = 'Party' then 'QuizRail Party' else v_theme end;
  else
    -- Set custom : 8 questions attendues (banque standard), réponses requises.
    if jsonb_array_length(p_answers) <> jsonb_array_length(p_prompts) then
      raise exception 'Questions et réponses incohérentes.' using errcode = 'P0001';
    end if;
  end if;
  for v_try in 1..5 loop
    v_code := '';
    for v_n in 1..6 loop
      v_code := v_code || substr('ABCDEFGHJKMNPQRSTUVWXYZ23456789', (floor(random() * 32) + 1)::int, 1);
    end loop;
    begin
      insert into rooms (code, host_id, status, theme, questions, question_index, player_ids, max_players)
      values (v_code, v_uid, 'lobby', v_theme, p_prompts, 0, array[v_uid], 12)
      returning id into v_room_id;
      exit;
    exception when unique_violation then
      v_code := null;
    end;
  end loop;
  if v_code is null then raise exception 'Impossible de générer un code.' using errcode = 'P0001'; end if;
  v_name := profile_name(auth.uid());
  insert into room_players (room_id, uid, display_name, connected, last_seen)
  values (v_room_id, v_uid, v_name, true, now_ms());
  insert into room_secrets (room_id, answers) values (v_room_id, p_answers);
  return jsonb_build_object('roomId', v_room_id, 'code', v_code);
end $$;

create or replace function join_party(p_code text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid text := auth.uid()::text;
  v_code text := upper(btrim(coalesce(p_code, '')));
  v_room rooms%rowtype;
begin
  if v_uid is null then raise exception 'Connexion requise.' using errcode = 'P0001'; end if;
  if v_code !~ '^[A-Z0-9]{6}$' then
    raise exception 'Code à 6 caractères requis.' using errcode = 'P0001';
  end if;
  select * into v_room from rooms where code = v_code for update;
  if not found then raise exception 'Room introuvable.' using errcode = 'P0001'; end if;
  if v_room.status <> 'lobby' then raise exception 'Partie déjà lancée.' using errcode = 'P0001'; end if;
  if not (v_uid = any (v_room.player_ids)) then
    if array_length(v_room.player_ids, 1) >= 12 then
      raise exception 'Room complète (12).' using errcode = 'P0001';
    end if;
    insert into room_players (room_id, uid, display_name, connected, last_seen)
    values (v_room.id, v_uid, profile_name(auth.uid()), true, now_ms())
    on conflict (room_id, uid) do nothing;
    update rooms set player_ids = player_ids || v_uid, updated_at = now() where id = v_room.id;
  end if;
  return jsonb_build_object('roomId', v_room.id, 'theme', v_room.theme);
end $$;

create or replace function leave_party(p_room_id text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid text := auth.uid()::text;
  v_room rooms%rowtype; v_rest text[];
begin
  if v_uid is null then raise exception 'Connexion requise.' using errcode = 'P0001'; end if;
  select * into v_room from rooms where id = p_room_id for update;
  if not found then return jsonb_build_object('left', true); end if;
  delete from room_players where room_id = p_room_id and uid = v_uid;
  v_rest := array(select x from unnest(v_room.player_ids) x where x <> v_uid);
  if array_length(v_rest, 1) is null or array_length(v_rest, 1) = 0 then
    delete from room_secrets where room_id = p_room_id;
    delete from rooms where id = p_room_id;
    return jsonb_build_object('left', true);
  end if;
  if v_room.host_id = v_uid then
    update rooms set player_ids = v_rest, host_id = v_rest[1], updated_at = now() where id = p_room_id;
  else
    update rooms set player_ids = v_rest, updated_at = now() where id = p_room_id;
  end if;
  return jsonb_build_object('left', true);
end $$;

create or replace function start_party(p_room_id text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid text := auth.uid()::text; v_room rooms%rowtype;
begin
  if v_uid is null then raise exception 'Connexion requise.' using errcode = 'P0001'; end if;
  select * into v_room from rooms where id = p_room_id for update;
  if not found then raise exception 'Room introuvable.' using errcode = 'P0001'; end if;
  if v_room.host_id <> v_uid then raise exception 'Seul le host démarre.' using errcode = 'P0001'; end if;
  if v_room.status <> 'lobby' then raise exception 'Déjà lancée.' using errcode = 'P0001'; end if;
  if array_length(v_room.player_ids, 1) < 2 then
    raise exception '2 joueurs minimum.' using errcode = 'P0001';
  end if;
  update rooms set status = 'playing', question_index = 0, updated_at = now() where id = p_room_id;
  return jsonb_build_object('started', true, 'players', array_length(v_room.player_ids, 1));
end $$;

create or replace function submit_party_answer(
  p_room_id text, p_answer text, p_elapsed_ms integer, p_lang text
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid text := auth.uid()::text;
  v_lang text := case when p_lang in ('en', 'ar') then p_lang else 'fr' end;
  v_room rooms%rowtype; v_me room_players%rowtype;
  v_answers jsonb; v_accepted jsonb; v_norm text; v_correct boolean := false;
  v_streak int; v_gained int := 0; v_score int; v_answered int; v_finished boolean;
  v_now bigint := now_ms(); v_nq int;
begin
  if v_uid is null then raise exception 'Connexion requise.' using errcode = 'P0001'; end if;
  if p_elapsed_ms is null or p_elapsed_ms < 700 then
    raise exception 'Réponse trop rapide.' using errcode = 'P0001';
  end if;
  if p_elapsed_ms > 600000 then raise exception 'Réponse périmée.' using errcode = 'P0001'; end if;
  select * into v_room from rooms where id = p_room_id;
  if not found then raise exception 'Room introuvable.' using errcode = 'P0001'; end if;
  if v_room.status <> 'playing' then raise exception 'Partie non lancée.' using errcode = 'P0001'; end if;
  if not (v_uid = any (v_room.player_ids)) then raise exception 'Pas dans cette room.' using errcode = 'P0001'; end if;
  v_nq := jsonb_array_length(v_room.questions);
  if v_room.question_index < 0 or v_room.question_index >= v_nq then
    raise exception 'Question terminée.' using errcode = 'P0001';
  end if;
  select * into v_me from room_players where room_id = p_room_id and uid = v_uid for update;
  if not found then raise exception 'Pas dans cette room.' using errcode = 'P0001'; end if;
  if v_me.last_question_index >= v_room.question_index then
    raise exception 'Déjà répondu.' using errcode = 'P0001';
  end if;
  select answers into v_answers from room_secrets where room_id = p_room_id;
  v_accepted := coalesce(v_answers->v_room.question_index->v_lang,
                         v_answers->v_room.question_index->'fr', '[]'::jsonb);
  v_norm := lower(btrim(coalesce(p_answer, '')));
  if v_norm <> '' then
    select exists (
      select 1 from jsonb_array_elements_text(v_accepted) a where lower(a) = v_norm
    ) into v_correct;
  end if;
  v_streak := v_me.streak + case when v_correct then 1 else 0 end;
  if v_correct then v_gained := 100 + case when v_streak >= 3 then 25 else 0 end; end if;
  v_score := v_me.score + v_gained;
  v_answered := v_me.answered + 1;
  v_finished := v_answered >= v_nq;
  update room_players set
    score = v_score, correct = v_me.correct + case when v_correct then 1 else 0 end,
    answered = v_answered, streak = case when v_correct then v_streak else 0 end,
    best_streak = greatest(v_me.best_streak, v_streak),
    last_question_index = v_room.question_index, finished = v_finished,
    finished_at = case when v_finished then v_now else 0 end, last_seen = v_now
  where room_id = p_room_id and uid = v_uid;
  if v_correct then
    update profiles set tokens = tokens + case when pass_active(auth.uid()) then 20 else 10 end
    where uid = auth.uid();
  end if;
  return jsonb_build_object('correct', v_correct, 'gained', v_gained, 'score', v_score, 'finished', v_finished);
end $$;

create or replace function advance_party(p_room_id text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid text := auth.uid()::text; v_room rooms%rowtype; v_next int; v_nq int;
begin
  if v_uid is null then raise exception 'Connexion requise.' using errcode = 'P0001'; end if;
  select * into v_room from rooms where id = p_room_id for update;
  if not found then raise exception 'Room introuvable.' using errcode = 'P0001'; end if;
  if v_room.host_id <> v_uid then raise exception 'Seul le host anime.' using errcode = 'P0001'; end if;
  if v_room.status <> 'playing' then raise exception 'Partie non lancée.' using errcode = 'P0001'; end if;
  v_nq := jsonb_array_length(v_room.questions);
  v_next := v_room.question_index + 1;
  if v_next >= v_nq then
    raise exception 'Dernière question : termine la partie.' using errcode = 'P0001';
  end if;
  update rooms set question_index = v_next, updated_at = now() where id = p_room_id;
  return jsonb_build_object('questionIndex', v_next, 'remaining', v_nq - 1 - v_next);
end $$;

create or replace function end_party(p_room_id text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid text := auth.uid()::text; v_room rooms%rowtype;
  v_top int; v_winners text[]; v_done text; v_winner text := null; v_draw boolean := false;
  r record;
begin
  if v_uid is null then raise exception 'Connexion requise.' using errcode = 'P0001'; end if;
  select * into v_room from rooms where id = p_room_id for update;
  if not found then raise exception 'Room introuvable.' using errcode = 'P0001'; end if;
  if v_room.host_id <> v_uid then raise exception 'Seul le host termine.' using errcode = 'P0001'; end if;
  if v_room.status <> 'playing' then raise exception 'Partie non lancée.' using errcode = 'P0001'; end if;
  select count(*) into v_top from room_players where room_id = p_room_id;
  if v_top = 0 then raise exception 'Aucun joueur.' using errcode = 'P0001'; end if;
  select max(score) into v_top from room_players where room_id = p_room_id;
  select array_agg(uid) into v_winners from room_players
  where room_id = p_room_id and score = v_top;
  if array_length(v_winners, 1) = 1 then
    v_winner := v_winners[1];
  else
    select uid into v_done from room_players
    where room_id = p_room_id and score = v_top and finished_at > 0
    order by finished_at asc limit 1;
    if found then v_winner := v_done; else v_draw := true; end if;
  end if;
  update rooms set status = 'finished', winner_uid = v_winner, is_draw = v_draw, updated_at = now()
  where id = p_room_id;
  for r in select uid, score from room_players where room_id = p_room_id loop
    perform bump_leaderboard(r.uid, r.score, v_winner is not null and r.uid = v_winner);
  end loop;
  return jsonb_build_object('winnerUid', v_winner, 'isDraw', v_draw, 'players', array_length(v_room.player_ids, 1));
end $$;

create or replace function touch_room_presence(p_room_id text, p_connected boolean)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid text := auth.uid()::text;
begin
  if v_uid is null then return jsonb_build_object('ok', false); end if;
  update room_players set connected = p_connected, last_seen = now_ms()
  where room_id = p_room_id and uid = v_uid;
  return jsonb_build_object('ok', true);
end $$;

-- ----------------------------------------------------------------------------
-- Social : amis, notes, signalements, tunnels.
-- ----------------------------------------------------------------------------

create or replace function add_friend(p_friend_uid text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid(); v_friend uuid; v_name text;
begin
  if v_uid is null then raise exception 'Connexion requise.' using errcode = 'P0001'; end if;
  begin v_friend := p_friend_uid::uuid;
  exception when others then raise exception 'Introuvable.' using errcode = 'P0001'; end;
  if v_friend = v_uid then raise exception 'Requête invalide.' using errcode = 'P0001'; end if;
  perform ensure_profile();
  if not exists (select 1 from profiles where uid = v_friend) then
    raise exception 'Introuvable.' using errcode = 'P0001';
  end if;
  update profiles set friend_ids = array(select distinct x from unnest(friend_ids || v_friend::text) x)
  where uid = v_uid;
  update profiles set friend_ids = array(select distinct x from unnest(friend_ids || v_uid::text) x)
  where uid = v_friend;
  v_name := profile_name(v_friend);
  return jsonb_build_object('displayName', v_name);
end $$;

create or replace function rate_tunnel(p_tunnel_id text, p_stars integer)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid text := auth.uid()::text; v_sum int; v_count int;
begin
  if v_uid is null then raise exception 'Connexion requise.' using errcode = 'P0001'; end if;
  if p_stars is null or p_stars < 1 or p_stars > 5 then
    raise exception 'Note entre 1 et 5.' using errcode = 'P0001';
  end if;
  if not exists (select 1 from tunnels where id = p_tunnel_id) then
    raise exception 'Introuvable.' using errcode = 'P0001';
  end if;
  insert into tunnel_ratings (tunnel_id, uid, stars) values (p_tunnel_id, v_uid, p_stars)
  on conflict (tunnel_id, uid) do update set stars = excluded.stars;
  select coalesce(sum(stars), 0), count(*) into v_sum, v_count
  from tunnel_ratings where tunnel_id = p_tunnel_id;
  update tunnels set rating_sum = v_sum, rating_count = v_count,
    rating_avg = case when v_count = 0 then 0 else v_sum::double precision / v_count end
  where id = p_tunnel_id;
  return jsonb_build_object('avg', (select rating_avg from tunnels where id = p_tunnel_id), 'count', v_count);
end $$;

create or replace function report_tunnel(p_tunnel_id text, p_reason text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid text := auth.uid()::text;
begin
  if v_uid is null then raise exception 'Connexion requise.' using errcode = 'P0001'; end if;
  if p_reason is null or btrim(p_reason) = '' then
    raise exception 'Motif requis.' using errcode = 'P0001';
  end if;
  insert into reports (tunnel_id, reporter_uid, reason) values (p_tunnel_id, v_uid, btrim(p_reason));
  return jsonb_build_object('ok', true);
end $$;

create or replace function publish_tunnel(
  p_theme text, p_questions jsonb, p_is_public boolean, p_lang text, p_image_url text
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid text := auth.uid()::text; v_id text;
  q jsonb;
begin
  if v_uid is null then raise exception 'Connexion requise.' using errcode = 'P0001'; end if;
  if p_theme is null or btrim(p_theme) = '' then
    raise exception 'Thème requis.' using errcode = 'P0001';
  end if;
  if p_questions is null or jsonb_typeof(p_questions) <> 'array' or jsonb_array_length(p_questions) = 0 then
    raise exception 'Questions requises.' using errcode = 'P0001';
  end if;
  for q in select * from jsonb_array_elements(p_questions) loop
    if q->>'prompt' is null or btrim(q->>'prompt') = ''
       or q->>'answer' is null or btrim(q->>'answer') = '' then
      raise exception 'Question invalide.' using errcode = 'P0001';
    end if;
  end loop;
  insert into tunnels (theme, questions, creator_id, is_public, lang, image_url)
  values (btrim(p_theme), p_questions, v_uid, coalesce(p_is_public, true),
          case when p_lang in ('en', 'ar') then p_lang else 'fr' end, p_image_url)
  returning id into v_id;
  return jsonb_build_object('id', v_id);
end $$;

-- ----------------------------------------------------------------------------
-- Droits d'exécution
-- ----------------------------------------------------------------------------

grant execute on function now_ms() to authenticated;
grant execute on function short_name(text) to authenticated;
grant execute on function profile_name(uuid) to authenticated;
grant execute on function ensure_profile() to authenticated;
grant execute on function pass_active(uuid) to authenticated;
grant execute on function bump_leaderboard(text, integer, boolean) to authenticated;
grant execute on function duel_bank() to authenticated;
grant execute on function fresh_duel_player(text) to authenticated;
grant execute on function assert_valid_questions(jsonb) to authenticated;
grant execute on function find_duel(text) to authenticated;
grant execute on function leave_queue() to authenticated;
grant execute on function submit_duel_answer(text, text, integer, text) to authenticated;
grant execute on function use_power(text, text) to authenticated;
grant execute on function claim_forfeit(text) to authenticated;
grant execute on function request_rematch(text) to authenticated;
grant execute on function touch_duel_presence(text, boolean) to authenticated;
grant execute on function create_party(text, jsonb, jsonb) to authenticated;
grant execute on function join_party(text) to authenticated;
grant execute on function leave_party(text) to authenticated;
grant execute on function start_party(text) to authenticated;
grant execute on function submit_party_answer(text, text, integer, text) to authenticated;
grant execute on function advance_party(text) to authenticated;
grant execute on function end_party(text) to authenticated;
grant execute on function touch_room_presence(text, boolean) to authenticated;
grant execute on function add_friend(text) to authenticated;
grant execute on function rate_tunnel(text, integer) to authenticated;
grant execute on function report_tunnel(text, text) to authenticated;
grant execute on function publish_tunnel(text, jsonb, boolean, text, text) to authenticated;
