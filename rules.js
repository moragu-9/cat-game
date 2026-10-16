(function(root){
const names=['콩벌레','지렁이','파리','지네'];
function create(){return {score:0,combo:0,best:0,miss:0,stage:1,caught:0,total:0,counts:[0,0,0,0],ended:false};}
function hit(s,type){if(s.ended)return 0;const points=(s.combo%10+1)*10;s.combo++;s.best=Math.max(s.best,s.combo);s.score+=points;s.miss=0;s.caught++;s.total++;s.counts[type]++;if(s.stage<3&&s.caught===10){s.stage++;s.caught=0;}return points;}
function miss(s){if(s.ended)return;s.combo=0;s.miss++;s.ended=s.miss>=5;}
const api={create,hit,miss,names};if(typeof module!=='undefined')module.exports=api;else root.Rules=api;
})(globalThis);
