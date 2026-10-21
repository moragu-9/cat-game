const assert=require('node:assert/strict'),R=require('./rules.js');
let s=R.create();for(let i=0;i<150;i++)R.miss(s);assert.equal(s.ended,false);assert.equal(s.miss,0);
for(let i=0;i<2;i++){assert.equal(R.hit(s,0),0);assert.equal(s.stage,1);}
assert.equal(R.hit(s,0),0);assert.equal(s.stage,3);assert.equal(s.total,0);assert.equal(s.score,0);assert.deepEqual(s.counts,[0,0,0]);
assert.deepEqual(Array.from({length:11},()=>R.hit(s,2)),[10,20,30,40,50,60,70,80,90,100,10]);assert.equal(s.total,11);R.miss(s);assert.equal(R.hit(s,2),10);assert.equal(s.miss,1);assert.equal(s.best,11);assert.deepEqual(s.counts,[0,0,12]);
for(let i=0;i<98;i++)R.miss(s);assert.equal(s.ended,false);R.miss(s);assert.equal(s.ended,true);assert.equal(R.hit(s,2),0);
s=R.create();for(let i=0;i<3;i++)R.hit(s,0);for(let i=0;i<99;i++){R.miss(s);R.hit(s,2);}assert.equal(s.miss,99);assert.equal(s.ended,false);R.miss(s);assert.equal(s.ended,true);
console.log('PASS: cumulative misses survive catches; 3-catch unscored tutorial, no tutorial penalty, direct spider hunt, scoring and 100-miss boundary');
const rows=Array.from({length:105},(_,i)=>({profile:String(i),score:100,createdAt:i+1,day:'2026-10-17'}));rows.push({profile:'104',score:100,createdAt:200,day:'2026-10-17'});const board=R.leaderboard(rows);assert.equal(board.length,100);assert.equal(board[0].profile,'104');assert.equal(board[0].createdAt,200);assert.equal(board[99].profile,'5');assert.equal(R.leaderboard(rows,'2026-10-16').length,0);console.log('PASS: stage species, 100-row cutoff, latest tie-break, per-profile best, daily filter');
