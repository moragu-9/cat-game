begin;
insert into auth.users(id) values('00000000-0000-4000-8000-000000000001'),('00000000-0000-4000-8000-000000000002');
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',true);
select set_config('test.run',public.begin_hunt('cute')::text,true);
update public.hunt_sessions set started_at=now()-interval '30 seconds' where id=current_setting('test.run')::uuid;
set local role authenticated;
select public.submit_hunt_v4(current_setting('test.run')::uuid,'검증냥A','',20,'[[1000,1],[2000,1],[3000,0],[4000,1]]');
select public.submit_hunt_v4(current_setting('test.run')::uuid,'검증냥A','',20,'[]');
reset role;
do $$ begin
 if (select score from public.hunts where id=current_setting('test.run')::uuid)<>40 then raise exception 'Score replay failed'; end if;
 if (select combo from public.hunts where id=current_setting('test.run')::uuid)<>2 then raise exception 'Combo replay failed'; end if;
 if (select count(*) from public.hunts where id=current_setting('test.run')::uuid)<>1 then raise exception 'Idempotency failed'; end if;
end $$;

do $$ begin
 if not exists(select 1 from public.hunts where id=current_setting('test.run')::uuid and stage=3 and total=3 and counts=array[0,0,3] and score=40) then raise exception 'Main hunt totals invalid'; end if;
 if has_function_privilege('anon','public.submit_hunt_v4(uuid,text,text,real,jsonb)','EXECUTE') then raise exception 'Anonymous access'; end if;
end $$;
rollback;
select 'PASS: v4 main-only score, spider counts, idempotency, authenticated access; test data rolled back' as result;
