-- Game records are writable only through validated RPCs, never direct table access.
create table if not exists public.hunters (
 id uuid primary key references auth.users(id) on delete cascade,
 name text not null check(char_length(name) between 2 and 12),
 photo text,
 updated_at timestamptz not null default now()
);
create unique index if not exists hunters_name_unique on public.hunters(lower(name));
create table if not exists public.hunts (
 id uuid primary key,
 hunter uuid not null references public.hunters(id) on delete cascade,
 score integer not null, duration real not null, total integer not null,
 combo integer not null, stage integer not null, counts integer[] not null,
 mode text not null, created_at timestamptz not null default now()
);
create index if not exists hunts_best on public.hunts(hunter,score desc,created_at desc);
create index if not exists hunts_day on public.hunts(created_at desc);
alter table public.hunters enable row level security;
alter table public.hunts enable row level security;
revoke all on public.hunters,public.hunts from anon,authenticated;

create or replace function public.hunter_name_available(p_name text) returns boolean
language sql stable security definer set search_path='' as $$
 select not exists(select 1 from public.hunters where lower(name)=lower(p_name) and id is distinct from auth.uid());
$$;

create or replace function public.save_hunt(p_id uuid,p_name text,p_photo text,p_score integer,p_duration real,p_total integer,p_combo integer,p_stage integer,p_counts integer[],p_mode text)
returns uuid language plpgsql security definer set search_path='' as $$
declare me uuid:=auth.uid(); previous_owner uuid;
begin
 if me is null then raise exception 'AUTH_REQUIRED'; end if;
 perform pg_advisory_xact_lock(hashtextextended(me::text,0));
 select hunter into previous_owner from public.hunts where id=p_id;
 if previous_owner=me then return me; end if;
 if previous_owner is not null then raise exception 'INVALID_RECORD'; end if;
 if p_name is null or char_length(p_name) not between 2 and 12 or p_name !~ '^[A-Za-z0-9가-힣ㄱ-ㅎㅏ-ㅣぁ-ゖァ-ヺー一-龯々]+$' then raise exception 'INVALID_NAME'; end if;
 if p_photo is not null and (octet_length(p_photo)>28000 or (p_photo<>'' and p_photo !~ '^data:image/webp;base64,[A-Za-z0-9+/=]+$')) then raise exception 'INVALID_PHOTO'; end if;
 if p_score is null or p_duration is null or p_total is null or p_combo is null or p_stage is null or p_counts is null or p_mode is null then raise exception 'INVALID_RECORD'; end if;
 if p_total not between 0 and 100000 or p_score<0 or p_score%10<>0 or p_score>(p_total/10)*550+((p_total%10)*(p_total%10+1)/2)*10 or p_score<p_total*10 or p_duration<0 or p_duration>86400 or p_duration::text in ('NaN','Infinity','-Infinity') or p_combo<0 or p_combo>p_total or p_stage not between 1 and 3 or p_mode not in ('cute','real') or cardinality(p_counts)<>3 or array_position(p_counts,null) is not null or p_counts[1]<0 or p_counts[2]<0 or p_counts[3]<0 or p_counts[1]+p_counts[2]+p_counts[3]<>p_total or p_counts[1]<>least(p_total,10) or p_counts[2]<>least(greatest(p_total-10,0),10) or p_counts[3]<>greatest(p_total-20,0) or p_stage<>(case when p_total<10 then 1 when p_total<20 then 2 else 3 end) then raise exception 'INVALID_RECORD'; end if;
 if exists(select 1 from public.hunts where hunter=me and created_at>now()-interval '3 seconds') then raise exception 'TRY_LATER'; end if;
 insert into public.hunters(id,name,photo) values(me,p_name,nullif(p_photo,''))
 on conflict(id) do update set name=excluded.name,photo=case when p_photo is null then hunters.photo else nullif(p_photo,'') end,updated_at=now();
 insert into public.hunts(id,hunter,score,duration,total,combo,stage,counts,mode) values(p_id,me,p_score,p_duration,p_total,p_combo,p_stage,p_counts,p_mode);
 return me;
end $$;

create or replace function public.hunt_leaderboard(p_daily boolean default false)
returns table(id uuid,name text,photo text,score integer,duration real,total integer,combo integer,stage integer,counts integer[],mode text,created_at timestamptz)
language sql stable security definer set search_path='' as $$
 with best as (
 select distinct on(r.hunter) r.* from public.hunts r
 where not p_daily or r.created_at >= (date_trunc('day',now() at time zone 'Asia/Seoul') at time zone 'Asia/Seoul')
 order by r.hunter,r.score desc,r.created_at desc,r.id desc)
 select h.id,h.name,h.photo,b.score,b.duration,b.total,b.combo,b.stage,b.counts,b.mode,b.created_at
 from best b join public.hunters h on h.id=b.hunter
 order by b.score desc,b.created_at desc,b.id desc limit 100;
$$;
revoke all on function public.save_hunt(uuid,text,text,integer,real,integer,integer,integer,integer[],text) from public,anon;
revoke all on function public.hunter_name_available(text) from public;
revoke all on function public.hunt_leaderboard(boolean) from public;
grant execute on function public.save_hunt(uuid,text,text,integer,real,integer,integer,integer,integer[],text) to authenticated;
grant execute on function public.hunter_name_available(text) to anon,authenticated;
grant execute on function public.hunt_leaderboard(boolean) to anon,authenticated;
