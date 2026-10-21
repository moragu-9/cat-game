(function(root){
const names=['나비','물고기','거미'];
function create(){return {score:0,combo:0,best:0,miss:0,stage:1,caught:0,total:0,counts:[0,0,0],ended:false};}
function hit(s,type){if(s.ended)return 0;if(s.stage===1){s.caught++;if(s.caught===3){s.stage=3;s.caught=0;}return 0;}const points=(s.combo%10+1)*10;s.combo++;s.best=Math.max(s.best,s.combo);s.score+=points;s.miss=0;s.caught++;s.total++;s.counts[type]++;return points;}
function miss(s){if(s.ended||s.stage===1)return;s.combo=0;s.miss++;s.ended=s.miss>=100;}
function leaderboard(records,day){const best=new Map();records.forEach((r,i)=>{if(day&&r.day!==day)return;const c={...r,stamp:r.createdAt||i};const old=best.get(r.profile);if(!old||c.score>old.score||(c.score===old.score&&c.stamp>old.stamp))best.set(r.profile,c);});return [...best.values()].sort((a,b)=>b.score-a.score||b.stamp-a.stamp).slice(0,100);}
const api={create,hit,miss,names,leaderboard};if(typeof module!=='undefined')module.exports=api;else root.Rules=api;
})(globalThis);
