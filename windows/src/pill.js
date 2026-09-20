const $=id=>document.getElementById(id);
let activity='idle',targetLevel=0,currentLevel=0,receivedAt=0,previousFrame=0,mouthY=70,reduceMotion=false,rig=null;
const systemMotion=matchMedia('(prefers-reduced-motion: reduce)'),facePainter=new VoiceFace($('talking-face'),$('face'));
window.notch.onState(state=>{activity=state.activity;document.body.dataset.activity=activity;mouthY=state.mouthY||70;rig=state.rig||null;reduceMotion=!!state.reducedMotion;const src=state.avatar||'../assets/happy.png';if($('face').getAttribute('src')!==src)$('face').src=src;$('face').classList.toggle('custom',!!state.avatar);$('face-button').title=(reduceMotion||systemMotion.matches?'Mouth animation paused by Reduced motion. ':state.label+'. ')+'. Double-click to start or stop. Drag to move. Right-click to open Babji.';if(activity!=='recording'){targetLevel=0;currentLevel=0;}});
window.notch.onLevel(level=>{targetLevel=level;receivedAt=performance.now();});
setInterval(()=>{const time=performance.now(),elapsed=previousFrame?time-previousFrame:33;previousFrame=time;const desired=activity==='recording'&&time-receivedAt<250?targetLevel:0;currentLevel+=(desired-currentLevel)*(1-Math.exp(-elapsed/(desired>currentLevel?65:110)));$('talking-face').dataset.level=currentLevel.toFixed(3);facePainter.draw(currentLevel,{mouthY,rig,reduced:reduceMotion||systemMotion.matches,custom:$('face').classList.contains('custom')});},33);
$('face-button').ondragstart=e=>e.preventDefault();
let dragPointer=null,lastPoint,pressPoint,dragged=false,lastDragAt=-Infinity;
$('face-button').onpointerdown=e=>{if(e.button!==0||dragPointer!==null)return;e.preventDefault();dragPointer=e.pointerId;dragged=false;pressPoint=lastPoint={x:e.screenX,y:e.screenY};e.currentTarget.setPointerCapture(e.pointerId);window.notch.action('drag-start',lastPoint);};
$('face-button').onpointermove=e=>{if(e.pointerId!==dragPointer)return;lastPoint={x:e.screenX,y:e.screenY};if(Math.hypot(lastPoint.x-pressPoint.x,lastPoint.y-pressPoint.y)>4)dragged=true;window.notch.action('drag-move',lastPoint);};
function endDrag(e,cancelled=false){if(e.pointerId!==dragPointer)return;dragPointer=null;lastPoint={x:e.screenX,y:e.screenY};if(dragged||cancelled||Math.hypot(lastPoint.x-pressPoint.x,lastPoint.y-pressPoint.y)>4)lastDragAt=performance.now();window.notch.action(cancelled?'drag-cancel':'drag-end',lastPoint);if(e.currentTarget.hasPointerCapture(e.pointerId))e.currentTarget.releasePointerCapture(e.pointerId);}
$('face-button').onpointerup=e=>endDrag(e);
$('face-button').onpointercancel=e=>endDrag(e,true);
$('face-button').onlostpointercapture=e=>{if(e.pointerId!==dragPointer)return;dragPointer=null;window.notch.action('drag-cancel',lastPoint);};
$('face-button').ondblclick=e=>{e.preventDefault();if(performance.now()-lastDragAt>600)window.notch.action('toggle');};
$('face-button').oncontextmenu=e=>{e.preventDefault();window.notch.action('open');};
$('face-button').onkeydown=e=>{if(e.key==='Enter'||e.key===' '){e.preventDefault();window.notch.action('toggle');}};
