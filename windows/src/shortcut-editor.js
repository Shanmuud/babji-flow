'use strict';
let activeKeyRecorder;
async function stopKeyRecorder() {
  if (!activeKeyRecorder) return;
  const recorder = activeKeyRecorder; activeKeyRecorder = null;
  recorder.button.onkeydown = recorder.button.onkeyup = null;
  recorder.button.classList.remove('capturing');
  await window.babji.invoke('shortcut:capture', false);
  recorder.refresh();
}
window.babji.on('shortcut-capture-ended', () => { if (activeKeyRecorder) stopKeyRecorder(); });
function shortcutEditorHTML(settings, compact = false) {
  const label = value => value ? Keybinding.parse(value).label : 'Not set';
  return `<section class="shortcut-editor" aria-label="Keyboard shortcuts"><div class="binding-row"><div><strong>Dictation shortcut</strong><small>Works in any app</small></div><button type="button" class="binding-key" id="bind-primary" aria-label="Record dictation shortcut">${label(settings.dictationShortcut)}</button></div>${compact ? '' : `<div class="binding-row"><div><strong>Backup shortcut</strong><small>Optional second shortcut</small></div><button type="button" class="binding-key" id="bind-fallback" aria-label="Record backup shortcut">${label(settings.fallbackShortcut)}</button></div><button type="button" id="bind-clear" class="quiet">Remove backup</button>`}<p class="binding-help">Click a shortcut, then press your keys. Use Ctrl, Alt or Win with a letter, number or Space, or an F-key on its own. Esc cancels.</p><p id="binding-message" role="status" aria-live="polite"></p><div class="binding-actions"><button type="button" class="quiet" id="bind-reset">Restore defaults</button><button type="button" class="secondary" id="bind-cancel" hidden>Cancel recording</button><button type="button" class="primary" id="bind-save" disabled>Save shortcut</button></div></section>`;
}
function mountShortcutEditor(settings, onSaved) {
  let primary = settings.dictationShortcut, fallback = settings.fallbackShortcut;
  const message = document.querySelector('#binding-message'), save = document.querySelector('#bind-save');
  const refresh = () => {
    const a = document.querySelector('#bind-primary'), b = document.querySelector('#bind-fallback');
    if (!a) return;
    a.textContent = Keybinding.parse(primary).label;
    if (b) b.textContent = fallback ? Keybinding.parse(fallback).label : 'Not set';
    save.disabled = !!activeKeyRecorder || primary === settings.dictationShortcut && fallback === settings.fallbackShortcut;
    document.querySelector('#bind-cancel').hidden = !activeKeyRecorder;
  };
  for (const [id, kind] of [['#bind-primary', 'primary'], ['#bind-fallback', 'fallback']]) {
    const button = document.querySelector(id); if (!button) continue;
    button.onclick = async () => {
      try {
        await stopKeyRecorder(); await window.babji.invoke('shortcut:capture', true);
        activeKeyRecorder = { button, refresh }; let captured = false;
        refresh(); button.classList.add('capturing'); button.textContent = 'Press your shortcut…'; button.focus();
        message.textContent = 'Listening for keys. Dictation is paused while you choose.';
        button.onkeydown = event => {
          event.preventDefault(); event.stopPropagation();
          if (event.key === 'Escape') { stopKeyRecorder(); message.textContent = 'Recording cancelled.'; return; }
          if (event.repeat) return;
          try {
            const binding = Keybinding.fromEvent(event); if (!binding) return;
            if (kind === 'primary') primary = binding.accelerator; else fallback = binding.accelerator;
            button.textContent = binding.label; captured = true;
            message.textContent = 'Release the keys, then save to check availability.';
          } catch (error) { message.textContent = error.message; }
        };
        button.onkeyup = () => { if (captured) stopKeyRecorder(); };
      } catch (error) { message.textContent = error.message; }
    };
  }
  document.querySelector('#bind-cancel').onclick = () => stopKeyRecorder();
  document.querySelector('#bind-reset').onclick = async () => { await stopKeyRecorder(); primary = 'Control+Shift+Space'; fallback = 'Control+Alt+Space'; refresh(); message.textContent = 'Save to restore the default shortcuts.'; };
  const clear = document.querySelector('#bind-clear'); if (clear) clear.onclick = async () => { await stopKeyRecorder(); fallback = ''; refresh(); };
  save.onclick = async () => {
    save.disabled = true;
    try { await stopKeyRecorder(); const next = await window.babji.invoke('shortcut:save', primary, fallback); settings = next.settings; message.textContent = 'Shortcut saved. Ready in every app.'; onSaved(next); }
    catch (error) { message.textContent = error.message.replace(/^Error invoking remote method '[^']+': Error: /, ''); }
    finally { refresh(); }
  };
}
