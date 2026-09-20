const {test}=require('node:test'),assert=require('node:assert/strict'),vm=require('node:vm'),fs=require('node:fs');
test('renderer records only on deliberate double-click, never drag release',()=>{
 const actions=[],button={setPointerCapture(){},hasPointerCapture(){return true},releasePointerCapture(){}},nodes={'face-button':button,'talking-face':{},face:{}};let now=1000;
 const context={document:{getElementById:id=>nodes[id]},matchMedia:()=>({matches:false}),VoiceFace:class{},window:{notch:{onState(){},onLevel(){},action:(...a)=>actions.push(a)}},setInterval(){},performance:{now:()=>now},Math};vm.runInNewContext(fs.readFileSync(require.resolve('../src/pill.js'),'utf8'),context);
 const event=(x,y)=>({button:0,pointerId:1,screenX:x,screenY:y,currentTarget:button,preventDefault(){}});
 button.onpointerdown(event(10,10));button.onpointermove(event(60,60));button.onpointerup(event(60,60));button.ondblclick(event(60,60));assert.equal(actions.some(a=>a[0]==='toggle'),false);
 now=2000;button.onpointerdown(event(60,60));button.onpointerup(event(60,60));assert.equal(actions.some(a=>a[0]==='toggle'),false);button.ondblclick(event(60,60));assert.equal(actions.filter(a=>a[0]==='toggle').length,1);
});
