// Drives the actual packaged EXE through its temporary localhost debugging port.
// Uses a fake microphone and an isolated test profile; no room audio is recorded.
const fs=require('node:fs'),path=require('node:path'),{spawn}=require('node:child_process'),assert=require('node:assert/strict');
const folder=path.join(__dirname,'../test-artifacts');
const pause=ms=>new Promise(r=>setTimeout(r,ms));
(async()=>{
  const server=require('node:net').createServer();await new Promise(r=>server.listen(0,'127.0.0.1',r));const port=server.address().port;await new Promise(r=>server.close(r));
  const testFace=process.env.BABJI_TEST_FACE;
  if(testFace&&!['babji','portrait','astronaut'].includes(testFace))throw new Error('Unknown test face');
  const profile=path.join(folder,testFace?'packaged-face-'+testFace:'packaged-profile');
  if(testFace){fs.mkdirSync(profile,{recursive:true});fs.copyFileSync(path.join(folder,'face-'+testFace+'.png'),path.join(profile,'avatar.png'));fs.copyFileSync(path.join(folder,'face-'+testFace+'-rig.json'),path.join(profile,'avatar-rig.json'));}
  const childEnv={...process.env,BABJI_TEST_PROFILE:profile};delete childEnv.ELECTRON_RUN_AS_NODE;
  const child=spawn(path.join(__dirname,'../release/win-unpacked/Babji Flow.exe'),[`--remote-debugging-port=${port}`,'--remote-debugging-address=127.0.0.1','--use-fake-device-for-media-stream',`--use-file-for-fake-audio-capture=${path.join(folder,'jfk.wav')}%noloop`],{env:childEnv,windowsHide:true,stdio:['ignore','pipe','pipe']});
  let logs='';child.stdout.on('data',b=>logs+=b);child.stderr.on('data',b=>logs+=b);child.on('exit',code=>{if(code)console.error('Packaged app exited',code,logs);});
  let ws,pillWS,sequence=0;const jobs=new Map();
  try{
    let page;
    for(let i=0;i<100;i++){try{const list=await(await fetch(`http://127.0.0.1:${port}/json/list`)).json();page=list.find(x=>x.url.endsWith('/index.html'));if(page)break;}catch{}await pause(200);}
    assert.ok(page,'Packaged window did not start: '+logs);ws=new WebSocket(page.webSocketDebuggerUrl);await new Promise((r,j)=>{ws.onopen=r;ws.onerror=j;});
    ws.onmessage=event=>{const m=JSON.parse(event.data);if(jobs.has(m.id)){const{resolve,reject}=jobs.get(m.id);jobs.delete(m.id);m.error?reject(new Error(m.error.message)):resolve(m.result);}};
    const cdp=(method,params={})=>new Promise((resolve,reject)=>{const id=++sequence;jobs.set(id,{resolve,reject});ws.send(JSON.stringify({id,method,params}));});
    const run=async expression=>{const r=await cdp('Runtime.evaluate',{expression,awaitPromise:true,returnByValue:true,userGesture:true});if(r.exceptionDetails)throw new Error(r.exceptionDetails.exception?.description||r.exceptionDetails.text);return r.result.value;};
    const until=async expression=>{for(let i=0;i<180;i++){if(await run(expression))return;await pause(500);}throw new Error('Timed out: '+expression);};
    const pillPage=(await(await fetch(`http://127.0.0.1:${port}/json/list`)).json()).find(p=>p.url.endsWith('/pill.html'));
    assert.ok(pillPage);pillWS=new WebSocket(pillPage.webSocketDebuggerUrl);await new Promise((r,j)=>{pillWS.onopen=r;pillWS.onerror=j;});
    let pillSequence=0;const pillJobs=new Map();pillWS.onmessage=e=>{const m=JSON.parse(e.data),job=pillJobs.get(m.id);if(job){pillJobs.delete(m.id);m.error?job.reject(new Error(m.error.message)):job.resolve(m.result);}};
    const pillRun=expression=>new Promise((resolve,reject)=>{const id=++pillSequence;pillJobs.set(id,{resolve:r=>r.exceptionDetails?reject(new Error(r.exceptionDetails.text)):resolve(r.result.value),reject});pillWS.send(JSON.stringify({id,method:'Runtime.evaluate',params:{expression,returnByValue:true}}));});
    await until(`!!window.babji && !!document.querySelector('h1')`);
    await until(`window.babji.invoke('state:get').then(s=>s.model.status==='ready')`);
    const detected=await run(`window.babji.invoke('state:get').then(s=>detectAvatarMouth(s.customAvatar||'../assets/happy.png'))`);
    assert.ok(detected.width>.025,'Bundled detector/model must load inside the packaged app');
    await run(`window.babji.invoke('settings:save',{autoPaste:false,soundCues:false,setupStep:2,reducedMotion:false})`);
    await run(`document.querySelector('[data-page="Get started"]').click();document.querySelector('#welcome-trial').click()`);
    await until(`document.querySelector('#capture-label').textContent==='Listening to you'`);
    await until(`Array.from(document.querySelectorAll('.input-wave i')).some(b=>parseFloat(b.style.height)>5)`);
    const speakingFace=await run(`document.querySelector('#capture-face-canvas').toDataURL()`);
    for(let i=0;i<30&&!(await pillRun(`Number(document.querySelector('#talking-face').dataset.level)>.1`));i++)await pause(100);
    assert.ok(await pillRun(`Number(document.querySelector('#talking-face').dataset.level)>.1`),'Real microphone path must reach the floating overlay');
    const speakingPill=await pillRun(`document.querySelector('#talking-face').toDataURL()`);
    await run(`window.babji.invoke('settings:save',{reducedMotion:true})`);await pause(200);
    const stillFace=await run(`document.querySelector('#capture-face-canvas').toDataURL()`);
    assert.notEqual(speakingFace,stillFace,'Dashboard face must visibly respond to microphone levels');
    const stillPill=await pillRun(`document.querySelector('#talking-face').toDataURL()`);
    assert.notEqual(speakingPill,stillPill,'Floating face must change pixels from actual audio IPC, not injected levels');
    fs.writeFileSync(path.join(folder,'verified-'+(testFace||'default')+'-talking.png'),Buffer.from(speakingPill.split(',')[1],'base64'));
    fs.writeFileSync(path.join(folder,'verified-'+(testFace||'default')+'-rest.png'),Buffer.from(stillPill.split(',')[1],'base64'));
    await run(`window.babji.invoke('settings:save',{reducedMotion:false})`);
    if(testFace){
      await pause(250);assert.ok(await pillRun(`Number(document.querySelector('#talking-face').dataset.level)>.01`));
      assert.notEqual(await pillRun(`document.querySelector('#talking-face').toDataURL()`),stillPill,'Animation must resume after Reduced motion is disabled');
      await run(`document.querySelector('#cancel-record').click()`);await until(`window.babji.invoke('state:get').then(s=>s.activity==='idle')`);
      console.log('PACKAGED FACE PASSED: '+testFace+' microphone -> overlay IPC -> detected mouth; motion toggle and cancellation.');
      await cdp('Browser.close').catch(()=>{});return;
    }
    await pause(12500);
    await run(`document.querySelector('#record-button').click()`);
    await until(`window.babji.invoke('state:get').then(s=>s.activity==='idle' && !!s.lastResult)`);
    const state=await run(`window.babji.invoke('state:get')`);
    assert.match(state.lastResult,/country/i);assert.ok(state.records.at(-1).seconds>=10);
    assert.equal(state.lastDelivery.status,'saved');
    assert.equal(state.records.at(-1).text,state.lastResult);assert.equal(state.records.at(-1).raw,state.lastRaw);
    await run(`document.querySelector('[data-page="History"]').click();document.querySelector('#history-search').value='country';document.querySelector('#history-search').dispatchEvent(new Event('input'));`);
    assert.ok(await run(`document.querySelector('#history-results').textContent.toLowerCase().includes('country')`));
    await run(`document.querySelector('[data-history-correct]').click();document.querySelector('#correction-heard').value='ree shee';document.querySelector('#correction-word').value='Rishi';document.querySelector('#editor-form').requestSubmit();`);
    await until(`!document.querySelector('#editor').open`);
    assert.equal(await run(`window.babji.invoke('text:clean','ree shee','other')`),'Rishi');
    await run(`document.querySelector('[data-page="Settings"]').click();document.querySelector('#check-mic').click()`);
    await until(`document.querySelector('#mic-level').value>.01`);
    await run(`document.querySelector('#check-mic').click()`);
    await until(`document.querySelector('#check-mic').textContent==='Test microphone'`);

    await run(`document.querySelector('[data-page="Insights"]').click()`);
    assert.ok(await run(`!!document.querySelector('#copy-raw')`));
    // Meeting persistence, audio export, and silence behavior use the same IPC boundary.
    await run(`document.querySelector('[data-page="Notetaker"]').click()`);
    await run(`window.babji.invoke('capture:begin','meeting')`);
    await run(`window.babji.invoke('capture:ready')`);
    const bytes=fs.readFileSync(path.join(folder,'jfk.f32'));const samples=new Float32Array(bytes.buffer.slice(bytes.byteOffset,bytes.byteOffset+bytes.byteLength));
    const meeting=await run(`window.babji.invoke('capture:finish',new Float32Array(${JSON.stringify(Array.from(samples))}),'meeting',{systemAudio:false})`);
    assert.ok(meeting.meeting);assert.match(meeting.text,/country/i);
    assert.ok(fs.existsSync(path.join(folder,'packaged-profile','recordings',meeting.meeting+'.wav')));
    const screenshot=await cdp('Page.captureScreenshot',{format:'png'});fs.writeFileSync(path.join(folder,'packaged-running.png'),Buffer.from(screenshot.data,'base64'));
    fs.writeFileSync(path.join(folder,'packaged-results.json'),JSON.stringify({passed:true,onboardingTrial:true,rawTranscriptComparison:true,localModel:true,fakeMicrophone:true,audioWorklet:true,dictation:state.lastResult,meetingAudioSaved:true},null,2));
    console.log('PACKAGED PASSED: local speech engine, fake microphone → AudioWorklet → transcription → cleanup → saved stats; meeting audio and transcript persistence.');
    await cdp('Browser.close').catch(()=>{});
  }finally{ws?.close();pillWS?.close();child.kill();}
})().catch(error=>{console.error(error);process.exitCode=1;});
