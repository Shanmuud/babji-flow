const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const {execFile}=require('node:child_process');
const pause=ms=>new Promise(r=>setTimeout(r,ms));
module.exports=async({notch,run,loadModel,snapshot,folder})=>{
  await loadModel();assert.equal(snapshot().shortcuts.primary,true,'Shortcut must be owned by this test instance before sending keys');
  const original={shortcutMode:snapshot().settings.shortcutMode,autoPaste:snapshot().settings.autoPaste,soundCues:snapshot().settings.soundCues};
  const originalKeys=[snapshot().settings.dictationShortcut,snapshot().settings.fallbackShortcut];
  const press=(holdMs=0,virtualKey=32)=>new Promise((resolve,reject)=>execFile('powershell.exe',['-NoProfile','-File',path.join(__dirname,'send-shortcut.ps1'),'-HoldMs',String(holdMs),'-VirtualKey',String(virtualKey)],{windowsHide:true},error=>error?reject(error):resolve()));
  const until=async predicate=>{for(let i=0;i<400;i++){if(predicate())return;await pause(100);}throw new Error('Shortcut test timed out: '+snapshot().activity);};
  try{
    // Test global key delivery without ever inserting fixture text into the user's active app.
    await run(`window.babji.invoke('settings:save',{autoPaste:false,soundCues:false,shortcutMode:'toggle'})`);
    const previous=snapshot().records.length;
    await press();await until(()=>snapshot().activity==='recording');
    let maxLevel=0;
    for(let i=0;i<12;i++){await pause(300);maxLevel=Math.max(maxLevel,await notch.window.webContents.executeJavaScript(`Number(document.querySelector('#talking-face').dataset.level)`));}
    assert.ok(maxLevel>.1,'Notch did not receive real fake-microphone levels');
    fs.writeFileSync(path.join(folder,'notch-live-audio.png'),(await notch.window.webContents.capturePage()).toPNG());
    await pause(8000);await press();await until(()=>snapshot().activity==='idle'&&snapshot().records.length>previous);
    assert.match(snapshot().lastResult,/country/i);assert.equal(snapshot().lastDelivery.status,'saved');
    const events=JSON.parse(fs.readFileSync(path.join(snapshot().dataPath,'dictation-diagnostics.json'),'utf8'));
    assert.ok(events.filter(e=>e.event==='trigger'&&e.source==='Ctrl + Shift + Space').length>=2);
    await run(`window.babji.invoke('settings:save',{shortcutMode:'hold'})`);
    await run(`window.babji.invoke('shortcut:save','Control+Shift+F9','')`);
    const beforeHold=snapshot().records.length;
    const held=press(2200,120); await until(()=>snapshot().activity==='recording'); await held;
    await until(()=>snapshot().activity==='idle' && snapshot().records.length>beforeHold);
    assert.ok(snapshot().records.at(-1).seconds>.5 && snapshot().records.at(-1).seconds<4,'Hold release must stop without a second press');
    fs.writeFileSync(path.join(folder,'shortcut-results.json'),JSON.stringify({passed:true,holdReleaseStops:true,actualWindowsShortcut:true,startedAndStopped:true,realAudioMeter:true,transcription:true,autoPasteDisabledForTest:true},null,2));
    console.log('SHORTCUT PASSED: actual Windows Ctrl+Shift+Space starts/stops, fake microphone drives notch and transcription. Auto-paste disabled to protect active user documents.');
  }finally{await run(`window.babji.invoke('shortcut:save',...${JSON.stringify(originalKeys)})`);await run(`window.babji.invoke('settings:save',${JSON.stringify(original)})`);}
};
