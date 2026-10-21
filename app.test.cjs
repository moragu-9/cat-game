const vm=require('node:vm'),fs=require('node:fs'),assert=require('node:assert/strict');
class Element{constructor(){this.handlers={};this.classList={toggle(){},add(){},remove(){}};this.value='';this.textContent='';this.files=[];}addEventListener(k,f){this.handlers[k]=f;}setAttribute(){}append(){}replaceChildren(){}close(){}showModal(){}setPointerCapture(){}getBoundingClientRect(){return {left:0,top:0};}getContext(){return {setTransform(){}};}}
const elements=new Map(),get=id=>{if(!elements.has(id))elements.set(id,new Element());return elements.get(id);};
let now=0;const doc={hidden:false,handlers:{},body:new Element(),getElementById:get,querySelector:()=>({value:'cute'}),querySelectorAll:()=>[],createElement:()=>new Element(),addEventListener(k,f){this.handlers[k]=f;}};
const sandbox={document:doc,window:{addEventListener(){},scrollTo(){}},innerWidth:820,innerHeight:1180,devicePixelRatio:1,performance:{now:()=>now},localStorage:{getItem:()=>null,setItem(){}},crypto:require('node:crypto').webcrypto,Intl,Date,Math,console,setTimeout,clearTimeout,requestAnimationFrame(){},Rules:require('./rules.js'),Online:{configured:()=>false,begin:async()=> 'server-run'},Art:{ready:Promise.resolve(),backdrop(){},target(){},effects(){},burst:(x,y,points)=>({x,y,points,life:1.05})}};
vm.createContext(sandbox);vm.runInContext(fs.readFileSync(__dirname+'/app.js','utf8'),sandbox);
const run=code=>vm.runInContext(code,sandbox);
(async()=>{
await run('start()');assert.equal(run('onlineRun'),false);assert.equal(run('bugs.length'),6);
const tap=(x,y,stamp=now)=>get('field').handlers.pointerdown({preventDefault(){},pointerType:'touch',timeStamp:stamp,clientX:x,clientY:y,width:20,height:20});
const ready=()=>{run('heldPointers.clear()');for(let i=0;i<50;i++){now+=50;run('frame('+now+')');}now+=100;};
tap(5,200);assert.equal(run('state.caught'),0);
run('heldPointers.add(1)');for(let i=0;i<50;i++){now+=50;run('frame('+now+')');}assert.ok(run('transition')>0);ready();
run('bugs.forEach((b,i)=>{b.x=300+i*90;b.y=500})');tap(5,200,1);tap(5,200);assert.equal(run('state.miss'),0);assert.equal(run('events.length'),0);
tap(300,500);assert.equal(run('state.caught'),1);assert.equal(run('state.score'),0);assert.equal(run('effects.at(-1).points'),0);
run('finish()');await get('save').onclick();assert.equal(run('db.records.length'),0);
await run('start()');ready();for(let i=0;i<3;i++){const b=run('bugs[0]');tap(b.x,b.y);}await new Promise(setImmediate);
assert.equal(run('state.stage'),3);assert.equal(run('state.score'),0);assert.equal(run('state.total'),0);assert.equal(run('events.length'),0);assert.equal(run('elapsed'),0);assert.equal(run('runId'),'server-run');assert.equal(run('bugs.length'),6);assert.ok(run('bugs.every(b=>b.type===2)'));
ready();run('bugs.forEach((b,i)=>{b.x=300+i*90;b.y=500})');tap(5,200);assert.equal(run('state.miss'),1);
tap(230,500);assert.equal(run('state.score'),10,'expanded hit radius accepts near-edge paw');assert.equal(run('state.miss'),0);assert.equal(run('state.total'),1);
run('bugs[0].x=300;bugs[1].x=340;bugs[0].y=bugs[1].y=500');tap(301,500);assert.equal(run('bugs[1].x'),340,'nearest prey only');assert.equal(run('state.total'),2);
run('pause()');tap(5,200);assert.equal(run('events.length'),3);get('resume').onclick({stopPropagation(){}});tap(5,200);assert.equal(run('events.length'),3);now+=400;tap(5,200);assert.equal(run('events.length'),4);
await run('Online.begin=async()=>{throw Error("offline")};start()');ready();for(let i=0;i<3;i++){const b=run('bugs[0]');tap(b.x,b.y);}await new Promise(setImmediate);assert.equal(run('onlineRun'),false);assert.equal(run('playing'),true);
console.log('PASS: tutorial no-save and no-events, 3 hits reset into main, six spiders, enlarged nearest hit, input guards, offline fallback');
})();
