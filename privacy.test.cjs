const vm=require('node:vm'),fs=require('node:fs'),assert=require('node:assert/strict');
const elements=new Map(),get=id=>{if(!elements.has(id))elements.set(id,{value:'score',showModal(){},close(){}});return elements.get(id);};
let profile=null,managed=[],reports=[],allow=false,fail=false,draws=0;
const box={document:{getElementById:get},localStorage:{getItem:()=>null,setItem(){},removeItem(){}},Online:{mine:async()=>profile,manage:async action=>{if(fail)throw Error();managed.push(action);},report:async(id,reason)=>reports.push([id,reason]),message:()=> 'error'},Date,JSON,Set,confirm:()=>allow,db:{records:[{pending:true}],profiles:[{syncedPhoto:'old'}]},persist(){},showRank:async()=>{draws++;}};
vm.createContext(box);vm.runInContext(fs.readFileSync(__dirname+'/privacy.js','utf8'),box);
(async()=>{
 await get('manage-open').onclick();assert.equal(get('my-delete').disabled,true);
 profile={hidden:false,moderated:false,deleted_at:null};await get('manage-open').onclick();assert.equal(get('my-hide').disabled,false);
 await get('my-delete').onclick();assert.equal(managed.length,0,'cancel must not send deletion');
 allow=true;fail=true;await get('my-delete').onclick();assert.equal(box.db.records[0].pending,true,'failed delete must preserve pending uploads');
 fail=false;await get('my-delete').onclick();assert.deepEqual(managed,['delete']);assert.equal(box.db.records[0].pending,false);assert.equal(box.db.profiles[0].syncedPhoto,undefined);
 vm.runInContext("openReport('target','냥냥')",box);await get('report-send').onclick();assert.deepEqual(reports,[['target','score']]);assert.equal(vm.runInContext("blocked.includes('target')",box),true);
 await get('unblock').onclick();assert.equal(vm.runInContext('blocked.length',box),0);
 console.log('PASS: no-profile controls, deletion confirmation/cancel/failure, pending-upload stop, report and local unblock');
})();
