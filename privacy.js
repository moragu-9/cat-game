'use strict';
let blocked=[],viewHidden=false;
try{const value=JSON.parse(localStorage.getItem('cat-blocked-v1'));if(Array.isArray(value))blocked=value.slice(0,500);}catch{}
let reportTarget=null;
function openReport(id,name){reportTarget=id;document.getElementById('report-name').textContent=name;document.getElementById('report-status').textContent='';document.getElementById('report-dialog').showModal();}
document.getElementById('report-close').onclick=()=>document.getElementById('report-dialog').close();
document.getElementById('report-send').onclick=async()=>{const b=document.getElementById('report-send');b.disabled=true;try{await Online.report(reportTarget,document.getElementById('report-reason').value);blocked=[...new Set([...blocked,reportTarget])].slice(-500);try{localStorage.setItem('cat-blocked-v1',JSON.stringify(blocked));}catch{}document.getElementById('report-dialog').close();await showRank();document.getElementById('rank-status').textContent='신고를 접수했어요. 운영자가 검토하며, 이 기기에서는 해당 사냥꾼을 숨겼어요.';}catch(err){document.getElementById('report-status').textContent=Online.message(err);}finally{b.disabled=false;}};
document.getElementById('unblock').onclick=()=>{viewHidden=!viewHidden;localOnly=false;showRank();};
function restoreHunter(id){blocked=blocked.filter(value=>value!==id);try{localStorage.setItem('cat-blocked-v1',JSON.stringify(blocked));}catch{}showRank();}
async function refreshMine(){const p=await Online.mine();document.getElementById('manage-status').textContent=!p?'아직 저장한 온라인 정보가 없어요.':p.moderated?'운영자 검토로 비공개 상태예요.':p.deleted_at?'삭제 대기 중이에요. 7일 안에 취소할 수 있어요.':p.hidden?'랭킹에서 숨김 상태예요.':'랭킹에 공개 중이에요.';document.getElementById('my-hide').disabled=!p||p.hidden||!!p.deleted_at;document.getElementById('my-show').disabled=!p||!p.hidden||!!p.deleted_at||p.moderated;document.getElementById('my-delete').disabled=!p||!!p.deleted_at;document.getElementById('my-restore').disabled=!p||!p.deleted_at||Date.now()-Date.parse(p.deleted_at)>=7*86400000;}
document.getElementById('manage-open').onclick=async()=>{document.getElementById('manage-dialog').showModal();document.getElementById('manage-status').textContent='내 정보를 확인하고 있어요…';try{await refreshMine();}catch(err){document.getElementById('manage-status').textContent=Online.message(err);}};
document.getElementById('manage-close').onclick=()=>document.getElementById('manage-dialog').close();
for(const [id,action]of [['my-hide','hide'],['my-show','show'],['my-delete','delete'],['my-restore','restore']])document.getElementById(id).onclick=async()=>{
 if(action==='delete'&&!confirm('온라인 닉네임·사진·기록을 삭제할까요? 지금 비공개로 바꾸고 7일 후 삭제합니다. 삭제 전까지 취소할 수 있어요. 이 기기의 기록은 유지됩니다.'))return;
 const buttons=['my-hide','my-show','my-delete','my-restore'].map(x=>document.getElementById(x));buttons.forEach(b=>b.disabled=true);
 try{await Online.manage(action);if(action==='delete'){db.records.forEach(r=>r.pending=false);db.profiles.forEach(p=>{delete p.syncedPhoto;});persist();}await refreshMine();await showRank();}catch(err){document.getElementById('manage-status').textContent=Online.message(err);buttons.forEach(b=>b.disabled=false);}
};
