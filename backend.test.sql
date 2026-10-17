-- Transactional integration tests: every test row is rolled back.
begin;
insert into auth.users(id) values('00000000-0000-4000-8000-000000000001'),('00000000-0000-4000-8000-000000000002');
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',true);
select public.save_hunt('10000000-0000-4000-8000-000000000001','검증냥A','',550,20,10,10,2,array[10,0,0],'cute');
select public.save_hunt('10000000-0000-4000-8000-000000000001','검증냥A','',550,20,10,10,2,array[10,0,0],'cute');
do $$ begin
 if (select count(*) from public.hunts where id='10000000-0000-4000-8000-000000000001')<>1 then raise exception 'Idempotency failed'; end if;
 if not public.hunter_name_available('검증냥A') then raise exception 'Own nickname rejected'; end if;
 if (select count(*) from public.hunt_leaderboard(false) where name='검증냥A')<>1 then raise exception 'Ranking missing'; end if;
 if (select count(*) from public.hunt_leaderboard(true) where name='검증냥A')<>1 then raise exception 'Daily ranking missing'; end if;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000002',true);
do $$ begin
 if public.hunter_name_available('검증냥a') then raise exception 'Nickname collision allowed'; end if;
 begin
 perform public.save_hunt('10000000-0000-4000-8000-000000000001','검증냥B','',550,20,10,10,2,array[10,0,0],'cute');
 raise exception 'Ownership bypass';
 exception when others then if SQLERRM<>'INVALID_RECORD' then raise; end if; end;
 begin
 perform public.save_hunt('10000000-0000-4000-8000-000000000002','검증냥B','',999999,20,10,10,2,array[10,0,0],'cute');
 raise exception 'Invalid score accepted';
 exception when others then if SQLERRM<>'INVALID_RECORD' then raise; end if; end;
 if has_table_privilege('anon','public.hunts','SELECT') or has_table_privilege('authenticated','public.hunts','INSERT') then raise exception 'Direct table access exposed'; end if;
end $$;
rollback;
select 'PASS: save, duplicate retry, ownership, nickname, daily ranking, validation, table access' as result;
