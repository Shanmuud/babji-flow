'use strict';
function themeControlHTML(){
  return '<div class="theme-control"><span class="theme-label">Light</span><button type="button" class="theme-toggle" role="switch" aria-label="Dark mode" aria-checked="false"><span class="theme-thumb" aria-hidden="true"></span></button><span class="theme-label">Dark</span><button type="button" class="theme-auto" data-theme="system" aria-label="Follow Windows appearance" aria-pressed="false" title="Follow Windows appearance">Auto</button></div>';
}
function syncThemeControls(choice){
  const dark=document.body.dataset.appearance==='dark';
  document.querySelectorAll('.theme-control').forEach(control=>{
    control.querySelector('.theme-toggle').setAttribute('aria-checked',String(dark));
    control.querySelector('.theme-auto').setAttribute('aria-pressed',String(choice==='system'));
    control.dataset.mode=dark?'dark':'light';
  });
}
function mountThemeControls(root,save){
  root.querySelectorAll('.theme-control').forEach(control=>{
    let pending=false;
    const update=async choice=>{
      if(pending)return;
      pending=true;
      try{await save(choice);}catch(error){notice(error.message);}finally{pending=false;}
    };
    control.querySelector('.theme-toggle').onclick=()=>update(document.body.dataset.appearance==='dark'?'light':'dark');
    control.querySelector('.theme-auto').onclick=()=>update('system');
  });
}
