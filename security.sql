-- Apply after schema.sql. No existing records are deleted by this migration.
begin;
alter table public.hunters add column if not exists hidden boolean not null default false;
alter table public.hunters add column if not exists moderated boolean not null default false;
alter table public.hunters add column if not exists deleted_at timestamptz;
create table if not exists public.hunt_sessions (
 id uuid primary key default gen_random_uuid(), owner uuid not null references auth.users(id) on delete cascade,
 mode text not null check(mode in ('cute','real')), started_at timestamptz not null default now(),
 consumed_at timestamptz
);
create index if not exists hunt_sessions_owner on public.hunt_sessions(owner,started_at desc);
create table if not exists public.hunt_quotas (
 bucket text not null, period timestamptz not null, uses integer not null default 1,
 primary key(bucket,period)
);
create table if not exists public.hunt_reports (
 reporter uuid not null references auth.users(id) on delete cascade,
 target uuid not null references public.hunters(id) on delete cascade,
 reason text not null check(reason in ('name','photo','score')),
 created_at timestamptz not null default now(), resolved boolean not null default false,
 primary key(reporter,target)
);
alter table public.hunt_sessions enable row level security;
alter table public.hunt_quotas enable row level security;
alter table public.hunt_reports enable row level security;
revoke all on public.hunt_sessions,public.hunt_quotas,public.hunt_reports from public,anon,authenticated;

-- Private helper: limits are server constants, never caller-supplied.
create or replace function public.hunt_quota(k text,cap integer,span text) returns void
language plpgsql security definer set search_path='' as $$
declare n integer;
begin
 insert into public.hunt_quotas(bucket,period) values(k,date_trunc(span,now()))
 on conflict(bucket,period) do update set uses=hunt_quotas.uses+1
 returning uses into n;
 if n>cap then raise exception 'TRY_LATER'; end if;
end $$;
revoke all on function public.hunt_quota(text,integer,text) from public,anon,authenticated;

create or replace function public.begin_hunt(p_mode text) returns uuid
language plpgsql security definer set search_path='' as $$
declare me uuid:=auth.uid(); result uuid;
begin
 if me is null then raise exception 'AUTH_REQUIRED'; end if;
 if p_mode is null or p_mode not in ('cute','real') then raise exception 'INVALID_MODE'; end if;
 if exists(select 1 from public.hunters where id=me and (moderated or deleted_at is not null)) then raise exception 'PROFILE_HIDDEN'; end if;
 perform public.hunt_quota('start-global',5000,'day');
 perform public.hunt_quota('start:'||me,10,'minute');
 perform public.hunt_quota('start:'||me,120,'day');
 insert into public.hunt_sessions(owner,mode) values(me,p_mode) returning id into result;
 return result;
end $$;

-- Recompute score and combo from a bounded event transcript. This does not prove physical touches.
create or replace function public.submit_hunt(p_id uuid,p_name text,p_photo text,p_duration real,p_events jsonb)
returns uuid language plpgsql security definer set search_path='' as $$
declare me uuid:=auth.uid(); s public.hunt_sessions; ev jsonb; ms integer; prev integer:=-1;
 hit integer; hits integer:=0; points integer:=0; combo integer:=0; best integer:=0; misses integer:=0;
 stage integer; counts integer[]; i integer:=0; window_start integer:=0; window_count integer:=0; pic bytea;
begin
 if me is null then raise exception 'AUTH_REQUIRED'; end if;
 perform pg_advisory_xact_lock(hashtextextended(me::text,0));
 select * into s from public.hunt_sessions where id=p_id and owner=me for update;
 if not found then raise exception 'SESSION_REQUIRED'; end if;
 if s.consumed_at is not null then return me; end if;
 if s.started_at<now()-interval '24 hours' then raise exception 'SESSION_EXPIRED'; end if;
 if exists(select 1 from public.hunters where id=me and (moderated or deleted_at is not null)) then raise exception 'PROFILE_HIDDEN'; end if;
 if p_name is null or char_length(p_name) not between 2 and 12 or p_name !~ '^[A-Za-z0-9가-힣ㄱ-ㅎㅏ-ㅣぁ-ゖァ-ヺー一-龯々]+$' then raise exception 'INVALID_NAME'; end if;
 if p_photo is not null and p_photo<>'' then
  if octet_length(p_photo)>28000 or p_photo !~ '^data:image/webp;base64,[A-Za-z0-9+/]+={0,2}$' then raise exception 'INVALID_PHOTO'; end if;
  begin pic:=decode(substr(p_photo,24),'base64'); exception when others then raise exception 'INVALID_PHOTO'; end;
  if octet_length(pic)>20480 or substring(pic from 1 for 4)<>decode('52494646','hex') or substring(pic from 9 for 4)<>decode('57454250','hex') then raise exception 'INVALID_PHOTO'; end if;
 end if;
 if p_duration is null or p_duration<0 or p_duration>21600 or p_duration::text in ('NaN','Infinity','-Infinity') or p_duration>extract(epoch from now()-s.started_at)+2 then raise exception 'INVALID_TIME'; end if;
 if p_events is null or jsonb_typeof(p_events)<>'array' or octet_length(p_events::text)>300000 then raise exception 'INVALID_EVENTS'; end if;
 if jsonb_array_length(p_events)>12000 then raise exception 'INVALID_EVENTS'; end if;
 for ev in select value from jsonb_array_elements(p_events) loop
  if jsonb_typeof(ev)<>'array' then raise exception 'INVALID_EVENTS'; end if;
  if jsonb_array_length(ev)<>2 or jsonb_typeof(ev->0)<>'number' or jsonb_typeof(ev->1)<>'number' or (ev->>0)!~ '^[0-9]{1,8}$' or (ev->>1) not in ('0','1') then raise exception 'INVALID_EVENTS'; end if;
  ms:=(ev->>0)::integer; hit:=(ev->>1)::integer;
  if ms<prev or ms>p_duration*1000+100 or misses>=100 then raise exception 'INVALID_EVENTS'; end if;
  if ms-window_start>=1000 then window_start:=ms; window_count:=0; end if;
  window_count:=window_count+1;
  if window_count>30 then raise exception 'INVALID_SPEED'; end if;
  prev:=ms; i:=i+1;
  if hit=1 then points:=points+(combo%10+1)*10; combo:=combo+1; best:=greatest(best,combo); hits:=hits+1; misses:=0;
  else combo:=0; misses:=misses+1; end if;
 end loop;
 if i>p_duration*20+10 then raise exception 'INVALID_SPEED'; end if;
 stage:=case when hits<10 then 1 when hits<20 then 2 else 3 end;
 counts:=array[least(hits,10),least(greatest(hits-10,0),10),greatest(hits-20,0)];
 perform public.hunt_quota('save-global',5000,'day');
 perform public.hunt_quota('save:'||me,6,'minute');
 perform public.hunt_quota('save:'||me,100,'day');
 insert into public.hunters(id,name,photo) values(me,p_name,nullif(p_photo,''))
 on conflict(id) do update set name=excluded.name,photo=case when p_photo is null then hunters.photo else nullif(p_photo,'') end,updated_at=now();
 insert into public.hunts(id,hunter,score,duration,total,combo,stage,counts,mode) values(p_id,me,points,p_duration,hits,best,stage,counts,s.mode);
 update public.hunt_sessions set consumed_at=now() where id=p_id;
 return me;
end $$;

-- Old clients cannot bypass the verified submission path.
create or replace function public.save_hunt(p_id uuid,p_name text,p_photo text,p_score integer,p_duration real,p_total integer,p_combo integer,p_stage integer,p_counts integer[],p_mode text)
returns uuid language plpgsql set search_path='' as $$ begin raise exception 'UPDATE_REQUIRED'; end $$;
revoke all on function public.save_hunt(uuid,text,text,integer,real,integer,integer,integer,integer[],text) from public,anon,authenticated;

-- NOT VALID preserves legacy rows; all future inserts/updates must satisfy checks.
do $$ begin
 if not exists(select 1 from pg_constraint where conname='hunt_record_shape' and conrelid='public.hunts'::regclass) then
 alter table public.hunts add constraint hunt_record_shape check (
  (array_ndims(counts)=1 and array_lower(counts,1)=1 and array_upper(counts,1)=3
   and array_position(counts,null) is null and total between 0 and 12000
   and counts=array[least(total,10),least(greatest(total-10,0),10),greatest(total-20,0)]
   and stage=case when total<10 then 1 when total<20 then 2 else 3 end
   and score between total*10 and (total/10)*550+((total%10)*(total%10+1)/2)*10
   and score%10=0 and combo between 0 and total and duration>=0 and duration<=21600
   and duration::text not in ('NaN','Infinity','-Infinity') and mode in ('cute','real')) is true
 ) not valid;
 end if;
end $$;

create or replace function public.report_hunter(p_target uuid,p_reason text) returns void
language plpgsql security definer set search_path='' as $$
declare me uuid:=auth.uid();
begin
 if me is null then raise exception 'AUTH_REQUIRED'; end if;
 if p_reason is null or p_reason not in ('name','photo','score') or p_target=me or not exists(select 1 from public.hunters where id=p_target and not hidden and not moderated and deleted_at is null) then raise exception 'INVALID_REPORT'; end if;
 if exists(select 1 from public.hunt_reports where reporter=me and target=p_target) then return; end if;
 perform public.hunt_quota('report-global',500,'day');
 perform public.hunt_quota('report:'||me,5,'day');
 insert into public.hunt_reports(reporter,target,reason) values(me,p_target,p_reason) on conflict do nothing;
end $$;

create or replace function public.my_hunter() returns jsonb
language sql stable security definer set search_path='' as $$
 select jsonb_build_object('hidden',hidden,'deleted_at',deleted_at,'moderated',moderated) from public.hunters where id=auth.uid();
$$;
create or replace function public.manage_hunter(p_action text) returns void
language plpgsql security definer set search_path='' as $$
declare me uuid:=auth.uid();
begin
 if me is null then raise exception 'AUTH_REQUIRED'; end if;
 if p_action is null or p_action not in ('hide','show','delete','restore') then raise exception 'INVALID_ACTION'; end if;
 perform pg_advisory_xact_lock(hashtextextended(me::text,0));
 perform public.hunt_quota('manage:'||me,10,'minute');
 if p_action='hide' then update public.hunters set hidden=true where id=me;
 elsif p_action='show' then update public.hunters set hidden=false where id=me and deleted_at is null;
 elsif p_action='delete' then update public.hunters set hidden=true,deleted_at=coalesce(deleted_at,now()) where id=me;
 elsif p_action='restore' then update public.hunters set deleted_at=null,hidden=false where id=me and deleted_at>now()-interval '7 days';
 end if;
end $$;

create or replace function public.hunt_leaderboard(p_daily boolean default false)
returns table(id uuid,name text,photo text,score integer,duration real,total integer,combo integer,stage integer,counts integer[],mode text,created_at timestamptz)
language sql stable security definer set search_path='' set statement_timeout='3s' as $$
 with best as (
 select distinct on(r.hunter) r.* from public.hunts r
 join public.hunters h on h.id=r.hunter and not h.hidden and not h.moderated and h.deleted_at is null
 where not p_daily or r.created_at >= (date_trunc('day',now() at time zone 'Asia/Seoul') at time zone 'Asia/Seoul')
 order by r.hunter,r.score desc,r.created_at desc,r.id desc)
 select h.id,h.name,h.photo,b.score,b.duration,b.total,b.combo,b.stage,b.counts,b.mode,b.created_at
 from best b join public.hunters h on h.id=b.hunter order by b.score desc,b.created_at desc,b.id desc limit 100;
$$;
create or replace function public.hunter_name_available(p_name text) returns boolean
language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
 if p_name is null or char_length(p_name) not between 2 and 12 then raise exception 'INVALID_NAME'; end if;
 perform public.hunt_quota('name:'||auth.uid(),20,'minute');
 return not exists(select 1 from public.hunters where lower(name)=lower(p_name) and id is distinct from auth.uid());
end $$;
revoke all on function public.hunter_name_available(text) from public,anon;
revoke all on function public.begin_hunt(text),public.submit_hunt(uuid,text,text,real,jsonb),public.report_hunter(uuid,text),public.my_hunter(),public.manage_hunter(text) from public,anon,authenticated;
grant execute on function public.begin_hunt(text),public.submit_hunt(uuid,text,text,real,jsonb),public.report_hunter(uuid,text),public.my_hunter(),public.manage_hunter(text),public.hunter_name_available(text) to authenticated;

-- Only the database operator may run cleanup or moderate reports.
create or replace function public.cleanup_hunts() returns void
language plpgsql security definer set search_path='' as $$
begin
 delete from public.hunters where deleted_at<now()-interval '7 days';
 delete from public.hunt_sessions where started_at<now()-interval '2 days';
 delete from public.hunt_quotas where period<now()-interval '2 days';
 delete from public.hunt_reports where resolved and created_at<now()-interval '90 days';
 with keep as (select distinct on(hunter) id from public.hunts order by hunter,score desc,created_at desc,id desc)
 delete from public.hunts h where h.created_at<now()-interval '30 days' and not exists(select 1 from keep k where k.id=h.id);
end $$;
revoke all on function public.cleanup_hunts() from public,anon,authenticated;
commit;
