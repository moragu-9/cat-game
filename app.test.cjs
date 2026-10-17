const vm=require('node:vm'),fs=require('node:fs'),assert=require('node:assert/strict');
class Element{constructor(){this.handlers={};this.classList={toggle(){},add(){},remove(){}};this.value='';this.textContent='';this.files=[];}addEventListener(k,f){this.handlers[k]=f;}setAttribute(){}append(){}replaceChildren(){}close(){}showModal(){}setPointerCapture(){}getBoundingClientRect(){return {left:0,top:0};}getContext(){return {setTransform(){}};}}
const elements=new Map(),get=id=>{if(!elements.has(id))elements.set(id,new Element());return elements.get(id);};
let now=0;const doc={hidden:false,handlers:{},body:new Element(),getElementById:get,querySelector:()=>({value:'cute'}),querySelectorAll:()=>[],createElement:()=>new Element(),addEventListener(k,f){this.handlers[k]=f;}};
const sandbox={document:doc,window:{addEventListener(){},scrollTo(){}},innerWidth:820,innerHeight:1180,devicePixelRatio:1,performance:{now:()=>now},localStorage:{getItem:()=>null,setItem(){}},crypto:require('node:crypto').webcrypto,Intl,Date,Math,console,setTimeout,clearTimeout,requestAnimationFrame(){},Rules:require('./rules.js'),Online:{configured:()=>false},Art:{ready:Promise.resolve(),backdrop(){},target(){},effects(){},burst:(x,y,points)=>({x,y,points,life:1.05})}};
vm.createContext(sandbox);vm.runInContext(fs.readFileSync(__dirname+'/app.js','utf8'),sandbox);
const run=code=>vm.runInContext(code,sandbox);
(async()=>{
await run('start({preventDefault(){},stopPropagation(){}})');
const tap=(x,y,stamp=now)=>get('field').handlers.pointerdown({preventDefault(){},pointerType:'touch',timeStamp:stamp,clientX:x,clientY:y});
tap(5,200);assert.equal(run('state.miss'),0,'start gesture must not count');
run('heldPointers.add(1)');for(let i=0;i<50;i++){now+=50;run(`frame(${now})`);}assert.ok(run('transition')>0,'held finger blocks start');
run('heldPointers.clear()');for(let i=0;i<50;i++){now+=50;run(`frame(${now})`);}now+=100;
tap(5,200,1);assert.equal(run('state.miss'),0,'stale event ignored');
tap(5,200);assert.equal(run('state.miss'),1);
let target=run('bugs[0]');tap(target.x,target.y);assert.equal(run('state.score'),10);assert.equal(run('state.miss'),0);assert.equal(run('effects.at(-1).points'),10);
run('pause()');tap(5,200);assert.equal(run('state.miss'),0,'paused touches ignored');
get('resume').onclick({stopPropagation(){}});tap(5,200);assert.equal(run('state.miss'),0,'resume gesture ignored');now+=400;tap(5,200);assert.equal(run('state.miss'),1);
console.log('PASS: start gesture, held touch, stale event, first valid hit/miss, burst, pause/resume guards');
})();
