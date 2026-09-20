'use strict';
let setupMicReady=false;
function renderWelcome({state,escape,on,invoke,go,loadModel,startTrial}) {
 const step=Math.min(state.settings.setupStep||0,3),label=Keybinding.parse(state.settings.dictationShortcut).label;
 const titles=['Make it your shortcut','Prepare your voice','Try your first dictation','Your everyday workflow'];
 const subtitles=['Choose keys that feel natural. You can change these anytime in Settings.','Speech recognition runs on this computer. Prepare the model and check microphone access.','Record a sentence here before using Babji in another app.','Click a text field in another app, use your shortcut, and speak.'];
 const contents=[
 shortcutEditorHTML(state.settings,true)+'<label class="field">How the shortcut works<select id="welcome-mode"><option value="hold" '+(state.settings.shortcutMode==='hold'?'selected':'')+'>Hold to talk, release to finish</option><option value="toggle" '+(state.settings.shortcutMode==='toggle'?'selected':'')+'>Press to start, press again to finish</option></select></label>',
 '<div class="setup-task"><div><h3>Local speech model</h3><p id="home-model-message" class="model-message">'+escape(state.model.message)+'</p><small>The first download needs an internet connection.</small></div><button id="home-load" class="secondary">Load model</button></div>'+microphoneHTML(),
 '<div class="practice-prompt"><small>TRY SAYING</small><p>Hello Babji, this is my first dictation.</p></div><button id="welcome-trial" class="primary">Start practice</button><p class="setup-fine">Use Stop recording below when finished. This practice stays in Babji.</p><div class="trial-result" aria-live="polite">'+escape(state.settings.onboardingTrialDone?state.lastResult:'Your transcript will appear here.')+'</div>',
 (state.model.status!=='ready'?'<p class="setup-note">Speech model setup is still pending. Load it from Insights before your first dictation.</p>':'')+'<div class="ready-summary"><small>YOUR DICTATION SHORTCUT</small><strong>'+escape(label)+'</strong><p>'+ (state.settings.shortcutMode==='hold'?'Hold while speaking. Release to transcribe.':'Press once to start. Press again to transcribe.')+'</p></div><div class="setup-task"><div><h3>Your words stay within reach</h3><p class="muted">Find your latest transcript in Insights. If insertion fails, copy it from there.</p></div></div><p class="setup-fine">Move the floating face by dragging it. Double-click it to start or stop. Right-click to open Babji.</p>'
 ];
 document.querySelector('#main').innerHTML='<section class="welcome-shell"><aside class="setup-sidebar"><div class="wordmark">Babji Flow</div><div class="detected-system">Windows desktop</div>'+themeControlHTML()+'<ol class="setup-progress">'+['Shortcut','Microphone','Practice','Start using Babji'].map((t,i)=>'<li class="'+(i===step?'current':i<step?'done':'')+'"><span>'+(i+1)+'</span>'+t+'</li>').join('')+'</ol></aside><div class="welcome-story"><div class="welcome-content"><span class="chapter">GET STARTED / '+(step+1)+' OF 4</span><h1>'+titles[step]+'</h1><p class="setup-lead">'+subtitles[step]+'</p>'+contents[step]+'</div><div class="welcome-actions"><button id="welcome-back" class="quiet" '+(step===0?'hidden':'')+'>Back</button><button id="skip-setup" class="quiet">Set up later</button><button id="welcome-next" class="primary">'+(step===3?'Open workspace':'Continue')+'</button></div></div></section>';
 mountThemeControls(document.querySelector('.setup-sidebar'),async appearance=>{await invoke('settings:save',{appearance});});syncThemeControls(state.settings.appearance||'system');
 const change=async patch=>{await invoke('settings:save',patch);go('Get started');};
 const complete=async()=>{await invoke('settings:save',{onboardingDismissed:true,setupVersion:3});go('Insights');};
 on('#welcome-next','click',async()=>{if(document.querySelector('#bind-save')&&!document.querySelector('#bind-save').disabled)throw new Error('Save your new shortcut before continuing.');if(step<3)await change({setupStep:step+1});else await complete();});
 on('#skip-setup','click',complete);on('#welcome-back','click',()=>change({setupStep:Math.max(0,step-1)}));
 if(step===0)mountShortcutEditor(state.settings,next=>{state.settings=next.settings;});
 on('#welcome-mode','change',()=>invoke('settings:save',{shortcutMode:document.querySelector('#welcome-mode').value}));
 on('#home-load','click',loadModel);on('#welcome-trial','click',startTrial);
 if(step===1)mountMicrophone(state.settings);
 document.body.dataset.setupStep=String(step);
}
