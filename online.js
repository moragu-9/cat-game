'use strict';
const Online=(()=>{
 const cfg=window.GAME_CONFIG,SESSION='cat-hunter-auth-v1';let session=null,inflight=null;
 try{session=JSON.parse(localStorage.getItem(SESSION));}catch{}
 const configured=()=>Boolean(cfg?.url&&cfg?.key);
 async function request(path,data,token){const res=await fetch(cfg.url+path,{method:'POST',headers:{apikey:cfg.key,'Content-Type':'application/json',...(token?{Authorization:`Bearer ${token}`}:{})},body:JSON.stringify(data),signal:AbortSignal.timeout(12000)});const value=await res.json();if(!res.ok){const err=Error(value.message||value.msg||value.error_description||'서버에 연결할 수 없어요.');err.status=res.status;throw err;}return value;}
 async function identity(){if(!configured())throw Error('온라인 랭킹 연결을 준비 중이에요.');if(session?.access_token&&session.expires_at>Date.now()/1000+90)return session;if(inflight)return inflight;inflight=(async()=>{const result=session?.refresh_token?await request('/auth/v1/token?grant_type=refresh_token',{refresh_token:session.refresh_token}):await request('/auth/v1/signup',{data:{game:'cat-hunter'}});session={...result,expires_at:result.expires_at||Date.now()/1000+result.expires_in};localStorage.setItem(SESSION,JSON.stringify(session));return session;})();try{return await inflight;}finally{inflight=null;}}
 async function rpc(name,args,auth=false){const s=auth?await identity():null;return request('/rest/v1/rpc/'+name,args,s?.access_token);}
 async function nameAvailable(name){await identity();return rpc('hunter_name_available',{p_name:name},true);}
 async function save(record,profile){const photo=profile.photo?.startsWith('data:image/webp;')?profile.photo:'';const unchanged=profile.syncedPhoto===photo;const id=await rpc('save_hunt',{p_id:record.id,p_name:profile.name,p_photo:unchanged?null:photo,p_score:record.score,p_duration:record.time,p_total:record.total,p_combo:record.best,p_stage:record.stage,p_counts:record.counts,p_mode:record.mode},true);profile.syncedPhoto=photo;return id;}
 function message(err){const s=err.message||'';if(s.includes('hunters_name_unique'))return '이미 사용 중인 닉네임이에요. 다른 이름으로 저장해 주세요.';if(s.includes('TRY_LATER'))return '잠시 후 다시 전송해 주세요.';if(s.includes('INVALID'))return '기록 형식을 확인할 수 없어요.';return '온라인 연결이 원활하지 않아요. 기록은 이 기기에 보관했어요.';}
 return {configured,identity,nameAvailable,save,message,leaderboard:daily=>rpc('hunt_leaderboard',{p_daily:daily}),id:()=>session?.user?.id};
})();
