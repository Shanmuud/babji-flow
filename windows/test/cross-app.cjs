const fs = require('node:fs');
const path = require('node:path');
const { spawn } = require('node:child_process');
const assert = require('node:assert/strict');
const pause = ms => new Promise(r=>setTimeout(r,ms));
module.exports = async ({ win, notch, run, nativeRequest, toggleDictation, loadModel, snapshot, folder }) => {
  await loadModel();
  const output = path.join(folder, 'external-' + Date.now() + '.txt');
  const child = spawn('powershell.exe', ['-NoProfile','-STA','-File',path.join(__dirname,'paste-target.ps1'),'-OutputFile',output], { windowsHide:true, stdio:'ignore' });
  try {
    for(let i=0;i<100&&!fs.existsSync(output+'.ready');i++)await pause(100);
    assert.ok(fs.existsSync(output+'.ready'),'Disposable text window did not start');
    const expected = fs.readFileSync(output+'.ready','utf8');
    const focusTestField = async () => {
      fs.writeFileSync(output+'.focus','focus');
      for(let i=0;i<30;i++){ if ((await nativeRequest('capture')).handle===expected)return; await pause(100); }
      throw new Error('Could not focus our disposable test field; no insertion attempted');
    };
    await focusTestField();
    assert.equal((await nativeRequest('capture')).handle,expected,'Refusing to test against an unrelated window');
    const recordsBefore=snapshot().records.length;
    // Actual Windows shortcut; all audio comes from the fake microphone.
    assert.equal(snapshot().shortcuts.primary,true);
    fs.writeFileSync(output+'.shortcut','press');
    for(let i=0;i<100&&snapshot().activity!=='recording';i++)await pause(100);
    assert.equal(snapshot().activity,'recording');
    assert.equal((await nativeRequest('capture')).handle,expected);
    await pause(11500);
    await focusTestField();
    assert.equal((await nativeRequest('capture')).handle,expected);
    await notch.window.webContents.executeJavaScript(`document.querySelector('#toggle').click()`);
    for(let i=0;i<300&&(snapshot().activity!=='idle'||snapshot().records.length===recordsBefore);i++)await pause(100);
    assert.equal(snapshot().lastDelivery.status,'inserted');
    assert.match(fs.readFileSync(output,'utf8'),/country/i);
    // Exercise the app-button path that originally silently saved only in Insights.
    win.show();win.focus();await pause(200);
    await run(`window.babji.invoke('capture:begin','dictation',{delivery:'external'})`);
    await pause(300);assert.equal(win.isVisible(),false);
    await focusTestField();
    assert.equal((await nativeRequest('capture')).handle,expected);
    await run(`window.babji.invoke('capture:ready')`);
    const buffer=fs.readFileSync(path.join(folder,'jfk.f32'));
    const samples=new Float32Array(buffer.buffer.slice(buffer.byteOffset,buffer.byteOffset+buffer.byteLength));
    await run(`window.babji.invoke('capture:finish',new Float32Array(${JSON.stringify(Array.from(samples))}),'dictation')`);
    assert.equal(snapshot().lastDelivery.status,'inserted');
    assert.equal((fs.readFileSync(output,'utf8').match(/country/gi)||[]).length,4);
    fs.writeFileSync(path.join(folder,'cross-app-results.json'),JSON.stringify({passed:true,shortcutToExternalApp:true,buttonToExternalApp:true,notchStop:true,notchPreservesFocus:true},null,2));
    console.log('CROSS-APP PASSED: fake microphone → external Windows text field; app button hides and pastes; notch stop preserves focus.');
  } finally { child.kill();win.show();win.focus(); }
};
