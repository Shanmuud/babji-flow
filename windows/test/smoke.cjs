const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
module.exports = async ({ win, notch, avatar, avatarChanged, nativeRequest, pasteText, toggleDictation, loadModel, snapshot, folder, ai, insertionTestTargets }) => {
  fs.mkdirSync(folder,{recursive:true});
  const run = script => win.webContents.executeJavaScript(script);
  const waitFor = async script => { for(let i=0;i<80;i++){if(await run(script))return;await new Promise(resolve=>setTimeout(resolve,100));}throw new Error('Timed out: '+script); };
  const captureFresh = async () => { await win.webContents.capturePage(); await new Promise(r=>setTimeout(r,100)); return win.webContents.capturePage(); };
  const errors=[];win.webContents.on('console-message',({level,message})=>{if(level==='error'&&message!=='INFO: Created TensorFlow Lite XNNPACK delegate for CPU.')errors.push(message);});
  await waitFor('!!document.querySelector("h1")');
  await run(`document.querySelector('[data-page="Get started"]').click()`);
  await run(`window.babji.invoke('settings:save',{setupStep:0,appearance:'light'})`);
  await run(`document.querySelector('[data-page="Get started"]').click()`);
  assert.ok(await run('document.querySelector(".detected-system").textContent.includes("Windows")'));
  assert.ok(await run('!!document.querySelector("#bind-primary")'));
  fs.writeFileSync(path.join(folder,'setup-shortcut.png'),(await captureFresh()).toPNG());
  for(const theme of ['dark','light','system']){
    await run(`document.querySelector('.setup-sidebar ${theme==='system'?'.theme-auto':'.theme-toggle'}').click()`);
    await waitFor(`state.settings.appearance==='${theme}'`);
    if(theme!=='system')assert.equal(await run(`document.querySelector('.setup-sidebar .theme-toggle').getAttribute('aria-checked')`),String(theme==='dark'));
    assert.equal(await run(`document.querySelector('.welcome-shell img')===null`),true);
    assert.ok(await run(`parseFloat(getComputedStyle(document.querySelector('.setup-lead')).fontSize)>=17`));
    assert.ok(await run(`document.querySelector('.welcome-actions').getBoundingClientRect().top-document.querySelector('.welcome-content').getBoundingClientRect().bottom<30`));
    fs.writeFileSync(path.join(folder,'setup-'+theme+'.png'),(await captureFresh()).toPNG());
  }
  const nativeTheme=require('electron').nativeTheme, originalTheme=nativeTheme.themeSource;
  try { nativeTheme.themeSource='dark';await waitFor(`document.body.dataset.appearance==='dark'`);nativeTheme.themeSource='light';await waitFor(`document.body.dataset.appearance==='light'`); } finally { nativeTheme.themeSource=originalTheme; }
  await run(`document.querySelector('#welcome-next').click()`);await waitFor(`!!document.querySelector('#check-mic')`);
  fs.writeFileSync(path.join(folder,'setup-microphone.png'),(await captureFresh()).toPNG());
  await run(`document.querySelector('#welcome-next').click()`);await waitFor(`!!document.querySelector('#welcome-trial')`);
  fs.writeFileSync(path.join(folder,'get-started.png'),(await captureFresh()).toPNG());
  await run(`document.querySelector('#welcome-next').click()`);await waitFor(`!!document.querySelector('.ready-summary')`);
  await run(`document.querySelector('#welcome-next').click()`);await waitFor(`document.querySelector('h1').textContent==='Insights'`);
  assert.equal(snapshot().settings.setupVersion,3);
  await run(`document.querySelector('.topbar .theme-toggle').click()`);
  await waitFor(`state.settings.appearance===document.body.dataset.appearance`);
  assert.equal(snapshot().settings.appearance,await run(`document.body.dataset.appearance`));
  await run(`document.querySelector('.topbar .theme-auto').click()`);
  await waitFor(`state.settings.appearance==='system'`);
  await run(`document.querySelector('[data-page="Insights"]').click()`);
  assert.equal(await run('typeof require'),'undefined');
  await run(`document.querySelector('.playground').open=true;document.querySelector('#try-input').value='um hello new line see you tomorrow question mark';document.querySelector('#try-clean').click()`);
  await waitFor('document.querySelector("#try-output").textContent.includes("tomorrow?")');
  await run(`document.querySelector('[data-page="Dictionary"]').click();document.querySelector('#add-entry').click();document.querySelector('#entry-word').value='Babji';document.querySelector('#entry-value').value='bab gee';document.querySelector('#editor-form').requestSubmit()`);
  await waitFor('!document.querySelector("#editor").open');
  assert.ok(snapshot().dictionary.some(e=>e.word==='Babji'));
  await run(`document.querySelector('[data-page="Style"]').click();document.querySelector('[data-tone="formal"]').click()`);
  await waitFor('document.querySelector("[data-tone=formal]").getAttribute("aria-pressed")==="true"');
  await run(`document.querySelector('[data-page="Notetaker"]').click();document.querySelector('#import-note').click();document.querySelector('#note-title').value='Smoke test';document.querySelector('#note-text').value='Rishi will review the Windows build tomorrow.';document.querySelector('#editor-form').requestSubmit()`);
  await waitFor('!document.querySelector("#editor").open');assert.ok(snapshot().meetings.some(m=>m.title==='Smoke test'));
  await run(`document.querySelector('[data-page="Settings"]').click()`);
  const oldKeys=[snapshot().settings.dictationShortcut,snapshot().settings.fallbackShortcut];
  await run(`document.querySelector('#bind-primary').click()`);await waitFor(`document.querySelector('#bind-primary').classList.contains('capturing')`);
  await run(`const b=document.querySelector('#bind-primary');b.dispatchEvent(new KeyboardEvent('keydown',{key:'F8',code:'F8',ctrlKey:true,shiftKey:true,bubbles:true}));b.dispatchEvent(new KeyboardEvent('keyup',{key:'F8',code:'F8',bubbles:true}));`);
  await waitFor(`!document.querySelector('#bind-save').disabled`);await run(`document.querySelector('#bind-save').click()`);
  await waitFor(`document.querySelector('#binding-message').textContent.includes('Shortcut saved')`);
  assert.equal(snapshot().settings.dictationShortcut,'Control+Shift+F8');
  await run(`window.babji.invoke('shortcut:save',...${JSON.stringify(oldKeys)})`);
  assert.equal(await run('document.querySelector("#auto-paste").checked'),true);
  await ai.set('openai','test-key-not-real');assert.ok(ai.has('openai'));assert.ok(!fs.readFileSync(ai.file('openai')).includes(Buffer.from('test-key-not-real')));await ai.set('openai','');assert.ok(!ai.has('openai'));
  const target=await nativeRequest('capture');assert.ok(target.handle);
  await assert.rejects(nativeRequest('type',{handle:'0',text:'MUST NOT TYPE'}),/Focus changed|Test blocked input/);
  await assert.rejects(nativeRequest('paste',{handle:'0'}),/Focus changed|Test blocked input/);
  if(process.argv.includes('--insertion-smoke'))await require('./delivery-windows.cjs')({win,nativeRequest,pasteText,folder,insertionTestTargets});
  // Opt-in foreground test: a desktop in active use cannot guarantee stable focus.
  const desktopInput = process.argv.includes('--desktop-input');
  if (desktopInput) {
    await run(`document.querySelector('[data-page="Insights"]').click();document.querySelector('.playground').open=true;document.querySelector('#try-input').value='';document.querySelector('#try-input').focus()`);
    win.show();win.focus();await new Promise(resolve=>setTimeout(resolve,300));
    await new Promise((resolve,reject)=>require('node:child_process').execFile('powershell.exe',['-NoProfile','-File',path.join(__dirname,'focus-window.ps1'),'-WindowHandle',win.getNativeWindowHandle().readBigUInt64LE().toString(),'-ExpectedProcess',String(process.pid)],{windowsHide:true},error=>error?reject(error):resolve()));
    const ownTarget=await nativeRequest('capture');assert.equal(ownTarget.pid,process.pid,JSON.stringify({captured:ownTarget,expectedPID:process.pid}));
    await pasteText(ownTarget.handle,'Babji Windows\nSecond line ✓');
    await waitFor(`document.querySelector('#try-input').value==='Babji Windows\\nSecond line ✓'`);
  }
  // The overlay must animate from real level messages and must not activate itself.
  notch.show('recording', 'Listening to you', 'Test field · Esc cancels');
  assert.equal(notch.window.isFocusable(),false);
  assert.deepEqual(notch.window.getSize(),[72,72]);
  notch.manualPosition = true; const placed=notch.window.getPosition(); notch.refresh(); assert.deepEqual(notch.window.getPosition(),placed); notch.place(true);
  assert.notEqual((await nativeRequest('capture')).handle,notch.window.getNativeWindowHandle().readBigUInt64LE().toString());
  const meter = script => notch.window.webContents.executeJavaScript(script);
  for (let i=0; i<8; i++) { notch.level(.85); await new Promise(r=>setTimeout(r,30)); }
  assert.ok(await meter(`Number(document.querySelector('#talking-face').dataset.level) > .5`));
  assert.equal(await meter(`document.querySelector('.controls')===null`),true);
  const talking=await meter(`document.querySelector('#talking-face').toDataURL()`);
  const beforeMove=notch.window.getPosition();
  const realScreen=notch.screen;let fakeCursor={x:beforeMove[0]+20,y:beforeMove[1]+20};
  notch.screen={getCursorScreenPoint:()=>fakeCursor,getDisplayNearestPoint:p=>realScreen.getDisplayNearestPoint(p)};
  try{notch.drag('drag-start',fakeCursor);fakeCursor={x:beforeMove[0]+100,y:beforeMove[1]+80};notch.drag('drag-end',fakeCursor);}finally{notch.screen=realScreen;}
  assert.notDeepEqual(notch.window.getPosition(),beforeMove,'Native overlay must actually move in this regression test');
  assert.equal(notch.state.activity,'recording','Repositioning must not stop recording');
  notch.level(0);await new Promise(r=>setTimeout(r,600));
  const movedRest=await meter(`document.querySelector('#talking-face').toDataURL()`);
  for(let i=0;i<8;i++){notch.level(.85);await new Promise(r=>setTimeout(r,30));}
  assert.notEqual(await meter(`document.querySelector('#talking-face').toDataURL()`),movedRest,'Mouth must keep animating after a native window move');
  assert.equal(await meter(`(()=>{const source=document.querySelector('#face');const draw=mouthY=>{const canvas=document.createElement('canvas');canvas.width=canvas.height=192;new VoiceFace(canvas,source).draw(.8,{mouthY,custom:false});return canvas.toDataURL();};return draw(48)===draw(70);})()`),true,'Photo mouth calibration must not move the built-in mouth');
  fs.writeFileSync(path.join(folder,'notch-listening.png'),(await notch.window.webContents.capturePage()).toPNG());
  notch.level(0); await new Promise(r=>setTimeout(r,600));
  assert.ok(await meter(`Number(document.querySelector('#talking-face').dataset.level) < .02`));
  assert.notEqual(await meter(`document.querySelector('#talking-face').toDataURL()`),talking,'Mouth pixels must react to voice level');
  const imageFactory=require('electron').nativeImage;const rest=await meter(`document.querySelector('#talking-face').toDataURL()`);assert.deepEqual(imageFactory.createFromDataURL(talking).getBitmap().subarray(0,192*90*4),imageFactory.createFromDataURL(rest).getBitmap().subarray(0,192*90*4),'Talking must leave the upper face unchanged');
  const faceSource=await meter(`document.querySelector('#face').src`);for(const mode of ['processing','done','error']){notch.show(mode,mode);assert.deepEqual(notch.window.getSize(),[72,72]);assert.equal(await meter(`document.querySelector('#face').src`),faceSource);}
  const avatarFile = path.join(__dirname,'../assets/happy.png');
  avatar.import(avatarFile); avatarChanged();
  assert.ok(avatar.dataURL.startsWith('data:image/png;base64,'));
  assert.equal(new (require('../src/avatar.cjs').Avatar)(snapshot().dataPath,require('electron').nativeImage).dataURL,avatar.dataURL);
  assert.throws(()=>avatar.import(path.join(__dirname,'smoke.cjs')),/Choose a PNG/);
  await new Promise(r=>setTimeout(r,100));
  assert.equal(await meter(`document.querySelector('#face').classList.contains('custom')`),true);
  fs.writeFileSync(path.join(folder,'notch-custom-face.png'),(await notch.window.webContents.capturePage()).toPNG());
  avatar.reset(); avatarChanged(); notch.idle();
  if(process.argv.includes('--face-smoke')){
    const results=[];
    for(const [name,file] of [['babji',avatarFile],['portrait',path.join(folder,'portrait.jpg')],['astronaut',path.join(folder,'astronaut.png')]]){
      avatar.import(file);const rig=await run(`detectAvatarMouth(${JSON.stringify(avatar.dataURL)})`);avatar.setRig(rig);avatarChanged();
      assert.ok(avatar.rig.cx>0&&avatar.rig.cx<1&&avatar.rig.cy>0&&avatar.rig.cy<1);
      assert.deepEqual(new(require('../src/avatar.cjs').Avatar)(snapshot().dataPath,require('electron').nativeImage).rig,avatar.rig);
      fs.copyFileSync(avatar.file,path.join(folder,'face-'+name+'.png'));fs.writeFileSync(path.join(folder,'face-'+name+'-rig.json'),JSON.stringify(avatar.rig));
      notch.show('recording','Testing mouth');await new Promise(r=>setTimeout(r,200));
      notch.level(0);await new Promise(r=>setTimeout(r,400));const rest=await meter(`document.querySelector('#talking-face').toDataURL()`);
      for(let i=0;i<8;i++){notch.level(.8);await new Promise(r=>setTimeout(r,33));}
      assert.notEqual(await meter(`document.querySelector('#talking-face').toDataURL()`),rest,name+' must animate with detected mouth');
      fs.writeFileSync(path.join(folder,'source-'+name+'-talking.png'),Buffer.from((await meter(`document.querySelector('#talking-face').toDataURL()`)).split(',')[1],'base64'));
      fs.writeFileSync(path.join(folder,'source-'+name+'-rest.png'),Buffer.from(rest.split(',')[1],'base64'));
      fs.writeFileSync(path.join(folder,'detected-'+name+'.png'),(await notch.window.webContents.capturePage()).toPNG());results.push({name,rig:avatar.rig});
    }
    fs.writeFileSync(path.join(folder,'face-detection-results.json'),JSON.stringify(results,null,2));avatar.reset();avatarChanged();notch.idle();
    // Detect an off-center, tilted face, and reject an image with no face.
    const transformed=await run(`(async()=>{const img=new Image();img.src='../assets/happy.png';await img.decode();const c=document.createElement('canvas');c.width=c.height=512;const g=c.getContext('2d');g.fillStyle='#eee';g.fillRect(0,0,512,512);g.translate(200,220);g.rotate(.2);g.drawImage(img,-170,-170,340,340);return detectAvatarMouth(c.toDataURL());})()`);
    assert.ok(transformed.cx<.6&&transformed.width>.025);
    assert.equal(await run(`(async()=>{const c=document.createElement('canvas');c.width=c.height=192;try{await detectAvatarMouth(c.toDataURL());return false;}catch(e){return e.message.includes('No face');}})()`),true);
  }
  if (desktopInput && process.argv.includes('--audio-smoke')) {
    await require('./cross-app.cjs')({ win, notch, run, nativeRequest, toggleDictation, loadModel, snapshot, folder });
  }
  if (process.argv.includes('--shortcut-smoke')) {
    await require('./shortcut.cjs')({ notch, run, nativeRequest, loadModel, snapshot, folder });
  }
  await run(`document.querySelector('[data-page="Settings"]').click()`);
  assert.ok(await run(`!!document.querySelector('#microphone-device')`));
  if(process.argv.includes('--shortcut-smoke')||process.argv.includes('--audio-smoke')){
    await loadModel();
    if(!snapshot().records.some(r=>r.text)){
      const audioBytes=fs.readFileSync(path.join(folder,'jfk.f32'));const audio=new Float32Array(audioBytes.buffer.slice(audioBytes.byteOffset,audioBytes.byteOffset+audioBytes.byteLength));
      await run(`window.babji.invoke('capture:begin','dictation',{delivery:'insights'})`);await run(`window.babji.invoke('capture:ready')`);
      await run(`window.babji.invoke('capture:finish',new Float32Array(${JSON.stringify(Array.from(audio))}),'dictation')`);
    }

    await run(`document.querySelector('#refresh-mics').click()`);await waitFor(`document.querySelector('#microphone-device').options.length>1`);
    await run(`const select=document.querySelector('#microphone-device');select.selectedIndex=1;select.dispatchEvent(new Event('change'));`);
    await waitFor(`document.querySelector('#mic-message').textContent.includes('Input saved')`);
    assert.ok(snapshot().settings.microphoneId);
    await run(`document.querySelector('#check-mic').click()`);await waitFor(`document.querySelector('#mic-level').value>.01`);
    await run(`document.querySelector('[data-page="History"]').click()`);assert.equal(await run('micPreview===null'),true);
    assert.ok(snapshot().records.at(-1).text);assert.ok(snapshot().records.at(-1).raw);
    await run(`document.querySelector('#history-search').value='zzzz-no-result-zzzz';document.querySelector('#history-search').dispatchEvent(new Event('input'));`);
    assert.ok(await run(`document.querySelector('#history-results').textContent.includes('No dictations match')`));
    await run(`document.querySelector('#history-search').value='';document.querySelector('#history-search').dispatchEvent(new Event('input'));document.querySelector('[data-history-correct]').click();document.querySelector('#correction-heard').value='ree shee';document.querySelector('#correction-word').value='Rishi';document.querySelector('#editor-form').requestSubmit();`);
    await waitFor(`!document.querySelector('#editor').open`);
    assert.equal(await run(`window.babji.invoke('text:clean','ree shee','other')`),'Rishi');
    await run(`window.babji.invoke('settings:save',{microphoneId:''})`);
  }
  await run(`document.querySelector('[data-page="Settings"]').click();document.querySelector('#text-size').value='large';document.querySelector('#text-size').dispatchEvent(new Event('change'));`);
  await waitFor(`document.body.dataset.textSize==='large'`);
  await run(`document.querySelector('#density').value='compact';document.querySelector('#density').dispatchEvent(new Event('change'));`);await waitFor(`document.body.dataset.density==='compact'`);
  await run(`document.querySelector('#reduced-motion').click()`);await waitFor(`document.body.classList.contains('reduced-motion')`);
  fs.writeFileSync(path.join(folder,'reading-preferences.png'),(await captureFresh()).toPNG());
  const originalSize=win.getSize();
  win.setSize(980,640);await new Promise(r=>setTimeout(r,200));
  for(const screen of ['Settings','Style','History','Insights']){
    await run(`document.querySelector('[data-page="${screen}"]').click()`);
    assert.ok(await run(`document.querySelector('main').scrollWidth<=document.querySelector('main').clientWidth+1`),`${screen} must fit with large text at minimum window size`);
  }
  fs.writeFileSync(path.join(folder,'compact-window.png'),(await captureFresh()).toPNG());
  win.setSize(...originalSize);await new Promise(r=>setTimeout(r,200));
  notch.show('recording','Listening');for(let i=0;i<5;i++){notch.level(.9);await new Promise(r=>setTimeout(r,35));}
  const stillFace=await meter(`document.querySelector('#talking-face').toDataURL()`);notch.level(0);await new Promise(r=>setTimeout(r,600));assert.equal(await meter(`document.querySelector('#talking-face').toDataURL()`),stillFace,'Reduced motion keeps the face still');
  await run(`window.babji.invoke('settings:save',{textSize:'normal',density:'comfortable',reducedMotion:false})`);notch.idle();
  for(const name of ['Insights','History','Dictionary','Style','Notetaker','Settings']){
    await run(`document.querySelector('[data-page="${name}"]').click()`);
    await new Promise(resolve=>setTimeout(resolve,120));
    await run(`window.babji.invoke('settings:save',{appearance:'dark'})`);
    fs.writeFileSync(path.join(folder,`${name.toLowerCase()}-dark.png`),(await captureFresh()).toPNG());
    await run(`window.babji.invoke('settings:save',{appearance:'light'})`);
    const screenshot=await captureFresh();fs.writeFileSync(path.join(folder,`${name.toLowerCase()}.png`),screenshot.toPNG());
    assert.equal(await run('document.documentElement.scrollWidth <= innerWidth'),true);
  }
  const preview=new (require('electron').BrowserWindow)({width:1100,height:1050,show:false,webPreferences:{sandbox:true,contextIsolation:true,nodeIntegration:false}});
  try {
    await preview.loadFile(path.join(__dirname,'../../docs/download/index.html'));
    assert.equal(await preview.webContents.executeJavaScript(`document.querySelector('.recommended').id`),'windows');
    fs.writeFileSync(path.join(folder,'download-desktop.png'),(await preview.webContents.capturePage()).toPNG());
    preview.setSize(390,844);await new Promise(r=>setTimeout(r,150));
    assert.ok(await preview.webContents.executeJavaScript('document.documentElement.scrollWidth <= innerWidth'));
    fs.writeFileSync(path.join(folder,'download-mobile.png'),(await preview.webContents.capturePage()).toPNG());
  } finally { preview.destroy(); }
  assert.deepEqual(errors,[]);
  fs.writeFileSync(path.join(folder,'smoke-results.json'),JSON.stringify({passed:true,screens:6,dictionary:true,styles:true,notes:true,encryptedKeys:true,nativeHelper:true,nativePaste:desktopInput?'passed':'separate --desktop-input test',focusGuard:true,rendererIsolation:true,voiceNotch:true,notchNonFocusable:true,customAvatarPersists:true},null,2));
  console.log('SMOKE PASSED: six screens, CRUD, styles, encrypted keys, native helper, focus guard, voice notch, custom avatar persistence.');
};
