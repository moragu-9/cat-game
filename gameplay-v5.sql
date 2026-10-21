-- Apply after gameplay-v4.sql. Cumulative 100 misses; older submissions retain their versioned validation.
begin;
create or replace function public.submit_hunt_v5(p_id uuid,p_name text,p_photo text,p_duration real,p_events jsonb)
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
  if hit=1 then points:=points+(combo%10+1)*10; combo:=combo+1; best:=greatest(best,combo); hits:=hits+1;
  else combo:=0; misses:=misses+1; end if;
 end loop;
 if i>p_duration*20+10 then raise exception 'INVALID_SPEED'; end if;
 stage:=3;
 counts:=array[0,0,hits];
 perform public.hunt_quota('save-global',5000,'day');
 perform public.hunt_quota('save:'||me,6,'minute');
 perform public.hunt_quota('save:'||me,100,'day');
 insert into public.hunters(id,name,photo) values(me,p_name,nullif(p_photo,''))
 on conflict(id) do update set name=excluded.name,photo=case when p_photo is null then hunters.photo else nullif(p_photo,'') end,updated_at=now();
 insert into public.hunts(id,hunter,score,duration,total,combo,stage,counts,mode) values(p_id,me,points,p_duration,hits,best,stage,counts,s.mode);
 update public.hunt_sessions set consumed_at=now() where id=p_id;
 return me;
end $$;


revoke all on function public.submit_hunt_v5(uuid,text,text,real,jsonb) from public,anon;
grant execute on function public.submit_hunt_v5(uuid,text,text,real,jsonb) to authenticated;
commit;
