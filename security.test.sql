begin;
insert into auth.users(id) values('00000000-0000-4000-8000-000000000001'),('00000000-0000-4000-8000-000000000002');
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',true);
select set_config('test.run',public.begin_hunt('cute')::text,true);
update public.hunt_sessions set started_at=now()-interval '30 seconds' where id=current_setting('test.run')::uuid;
set local role authenticated;
select public.submit_hunt(current_setting('test.run')::uuid,'검증냥A','',20,'[[1000,1],[2000,1],[3000,0],[4000,1]]');
select public.submit_hunt(current_setting('test.run')::uuid,'검증냥A','',20,'[]');
reset role;
do $$ begin
 if (select score from public.hunts where id=current_setting('test.run')::uuid)<>40 then raise exception 'Score replay failed'; end if;
 if (select combo from public.hunts where id=current_setting('test.run')::uuid)<>2 then raise exception 'Combo replay failed'; end if;
 if (select count(*) from public.hunts where id=current_setting('test.run')::uuid)<>1 then raise exception 'Idempotency failed'; end if;
end $$;
set local role authenticated;
select public.manage_hunter('hide');
do $$ begin if exists(select 1 from public.hunt_leaderboard(false) where id=auth.uid()) then raise exception 'Hidden record leaked'; end if; end $$;
select public.manage_hunter('show');
select public.manage_hunter('delete');
do $$ begin
 if exists(select 1 from public.hunt_leaderboard(false) where id=auth.uid()) then raise exception 'Deleted record leaked'; end if;
 begin perform public.begin_hunt('cute'); raise exception 'Deletion bypass'; exception when others then if SQLERRM<>'PROFILE_HIDDEN' then raise; end if; end;
end $$;
select public.manage_hunter('restore');
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000002',true);
set local role authenticated;
do $$ begin
 begin perform public.submit_hunt(current_setting('test.run')::uuid,'검증냥B','',20,'[]'); raise exception 'Ownership bypass'; exception when others then if SQLERRM<>'SESSION_REQUIRED' then raise; end if; end;
 if has_function_privilege('authenticated','public.save_hunt(uuid,text,text,integer,real,integer,integer,integer,integer[],text)','EXECUTE') then raise exception 'Legacy bypass'; end if;
 if has_table_privilege('authenticated','public.hunt_sessions','SELECT') or has_table_privilege('anon','public.hunts','SELECT') or has_function_privilege('authenticated','public.hunt_quota(text,integer,text)','EXECUTE') then raise exception 'Privilege leak'; end if;
end $$;
select public.report_hunter('00000000-0000-4000-8000-000000000001','score');
select public.report_hunter('00000000-0000-4000-8000-000000000001','score');
select set_config('test.bad',public.begin_hunt('real')::text,true);
reset role;
update public.hunt_sessions set started_at=now()-interval '30 seconds' where id=current_setting('test.bad')::uuid;
set local role authenticated;
do $$ begin
 begin perform public.submit_hunt(current_setting('test.bad')::uuid,'검증냥B','',100,'[]'); raise exception 'Impossible time accepted'; exception when others then if SQLERRM<>'INVALID_TIME' then raise; end if; end;
 begin perform public.submit_hunt(current_setting('test.bad')::uuid,'검증냥B','',0,'[[0,null]]'); raise exception 'Null event accepted'; exception when others then if SQLERRM<>'INVALID_EVENTS' then raise; end if; end;
 begin perform public.submit_hunt(current_setting('test.bad')::uuid,'검증냥B','',10,(select jsonb_agg(jsonb_build_array(i*100,case when i=101 then 1 else 0 end)) from generate_series(0,101) i)); raise exception 'Post-end event accepted'; exception when others then if SQLERRM<>'INVALID_EVENTS' then raise; end if; end;
 begin perform public.submit_hunt(current_setting('test.bad')::uuid,'검증냥B','data:image/webp;base64,AAAA',0,'[]'); raise exception 'Invalid photo accepted'; exception when others then if SQLERRM<>'INVALID_PHOTO' then raise; end if; end;
end $$;
reset role;
do $$ begin
 if (select count(*) from public.hunt_reports where reporter='00000000-0000-4000-8000-000000000002')<>1 then raise exception 'Duplicate report'; end if;
 begin
 update public.hunts set counts='[0:2]={3,0,0}'::integer[] where id=current_setting('test.run')::uuid;
 raise exception 'Array lower-bound bypass'; exception when check_violation then null; end;
 perform public.hunt_quota('test-rate',1,'day');
 begin perform public.hunt_quota('test-rate',1,'day'); raise exception 'Quota bypass'; exception when others then if SQLERRM<>'TRY_LATER' then raise; end if; end;
end $$;
-- Moderation cannot be undone by profile visibility controls.
update public.hunters set moderated=true where id='00000000-0000-4000-8000-000000000001';
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',true);
set local role authenticated;
select public.manage_hunter('show');
do $$ begin if exists(select 1 from public.hunt_leaderboard(false) where id=auth.uid()) then raise exception 'Moderation bypass'; end if; end $$;
reset role;
-- Cleanup preserves all-time best and removes old inferior records.
update public.hunts set created_at=now()-interval '40 days' where id=current_setting('test.run')::uuid;
insert into public.hunts(id,hunter,score,duration,total,combo,stage,counts,mode,created_at) values('10000000-0000-4000-8000-000000000009','00000000-0000-4000-8000-000000000001',10,20,1,1,1,array[1,0,0],'cute',now()-interval '40 days');
select public.cleanup_hunts();
do $$ begin
 if not exists(select 1 from public.hunts where id=current_setting('test.run')::uuid) then raise exception 'Best removed'; end if;
 if exists(select 1 from public.hunts where id='10000000-0000-4000-8000-000000000009') then raise exception 'Old inferior kept'; end if;
end $$;
rollback;
select 'PASS: role permissions, replay, idempotency, ownership, timing, malformed events/photo/arrays, quotas, reports, privacy, moderation and retention; all test data rolled back' as result;
