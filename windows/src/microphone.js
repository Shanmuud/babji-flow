'use strict';
let micPreview=null, micGeneration=0;
function microphoneConstraints(settings){return {channelCount:1,echoCancellation:true,noiseSuppression:true,...(settings.microphoneId?{deviceId:{exact:settings.microphoneId}}:{})};}
async function stopMicPreview(){micGeneration++;const old=micPreview;micPreview=null;if(old){cancelAnimationFrame(old.frame);old.stream.getTracks().forEach(t=>t.stop());await old.context.close();}const b=document.querySelector('#check-mic');if(b)b.textContent='Test microphone';const meter=document.querySelector('#mic-level');if(meter)meter.value=0;}
function microphoneHTML(){return '<section class="microphone-panel"><h3>Microphone</h3><p class="muted">Choose your input for dictation and meetings.</p><label class="field">Input device<select id="microphone-device"><option value="">System default</option></select></label><div class="actions"><button id="refresh-mics" class="secondary">Find microphones</button><button id="check-mic" class="secondary">Test microphone</button></div><div class="mic-meter"><meter id="mic-level" min="0" max="1" value="0" aria-label="Microphone input level"></meter><span id="mic-reading">Input level</span></div><p id="mic-message" class="model-message" role="status">Testing listens locally. No audio is saved.</p></section>';}
function mountMicrophone(settings){
 const select=document.querySelector('#microphone-device'),message=document.querySelector('#mic-message');if(!select)return;
 const report=e=>{message.textContent=e.name==='NotFoundError'||e.name==='OverconstrainedError'?'Selected microphone is unavailable. Connect it or choose System default.':e.message;};
 const populate=async()=>{const devices=(await navigator.mediaDevices.enumerateDevices()).filter(d=>d.kind==='audioinput');select.replaceChildren(new Option('System default',''));for(const [i,d] of devices.entries())if(d.deviceId&&d.deviceId!=='default')select.add(new Option(d.label||'Microphone '+(i+1),d.deviceId));if(settings.microphoneId&&!devices.some(d=>d.deviceId===settings.microphoneId))select.add(new Option('Saved microphone (disconnected)',settings.microphoneId));select.value=settings.microphoneId||'';};
 populate().catch(report);
 document.querySelector('#refresh-mics').onclick=async()=>{let stream;try{if(recording||starting||finishing)throw new Error('Finish recording before changing microphones.');stream=await navigator.mediaDevices.getUserMedia({audio:true});await populate();message.textContent='Microphones refreshed. Choose an input and test its level.';}catch(e){report(e);}finally{stream?.getTracks().forEach(t=>t.stop());}};
 select.onchange=async()=>{try{if(recording||starting||finishing)throw new Error('Finish recording before changing microphones.');await stopMicPreview();const next=await window.babji.invoke('settings:save',{microphoneId:select.value});settings=next.settings;message.textContent='Input saved for dictation and meetings.';}catch(e){select.value=settings.microphoneId||'';report(e);}};
 document.querySelector('#check-mic').onclick=async()=>{
  if(micPreview){await stopMicPreview();message.textContent='Microphone test stopped.';return;}
  let stream,context;try{
   if(recording||starting||finishing)throw new Error('Finish recording before testing the microphone.');
   const generation=++micGeneration;stream=await navigator.mediaDevices.getUserMedia({audio:microphoneConstraints(settings)});
   if(generation!==micGeneration||!select.isConnected){stream.getTracks().forEach(t=>t.stop());return;}
   context=new AudioContext();const analyser=context.createAnalyser();analyser.fftSize=1024;context.createMediaStreamSource(stream).connect(analyser);await context.resume();
   if(generation!==micGeneration||!select.isConnected){stream.getTracks().forEach(t=>t.stop());await context.close();return;}
   const preview={stream,context,frame:0};micPreview=preview;const samples=new Float32Array(analyser.fftSize);let peak=0;
   const tick=()=>{if(micPreview!==preview)return;analyser.getFloatTimeDomainData(samples);let energy=0;for(const sample of samples)energy+=sample*sample;const rms=Math.sqrt(energy/samples.length);peak=Math.max(peak,rms);document.querySelector('#mic-level').value=Math.min(1,rms*6);document.querySelector('#mic-reading').textContent=rms>.003?Math.round(20*Math.log10(rms))+' dBFS':'Quiet';preview.frame=requestAnimationFrame(tick);};tick();
   document.querySelector('#check-mic').textContent='Stop test';message.textContent='Listening to '+(stream.getAudioTracks()[0].label||'your microphone')+'. Speak to check the meter. Nothing is saved.';await populate();
  }catch(e){stream?.getTracks().forEach(t=>t.stop());if(context&&context.state!=='closed')await context.close();micPreview=null;report(e);}
 };
}
window.addEventListener('pagehide',()=>stopMicPreview());

 document.addEventListener('visibilitychange',()=>{if(document.hidden)stopMicPreview();});
