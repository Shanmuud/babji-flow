(function (root) {
  const modifiers = ['Control', 'Alt', 'Shift', 'Super'];
  function parse(value) {
    if (typeof value !== 'string' || value.length > 80) throw new Error('Choose a valid keyboard shortcut.');
    const parts = value.split('+').map(p => p.trim()).filter(Boolean);
    const key = parts.pop();
    if (!key || parts.some(p => !modifiers.includes(p)) || new Set(parts).size !== parts.length) throw new Error('Use Ctrl, Alt, Shift or Win with a letter, number, Space, or F-key.');
    let virtualKey;
    if (/^[A-Z0-9]$/.test(key)) virtualKey = key.charCodeAt(0);
    else if (key === 'Space') virtualKey = 32;
    else if (/^F([1-9]|1[0-9]|2[0-4])$/.test(key)) virtualKey = 111 + Number(key.slice(1));
    else throw new Error('Choose a letter, number, Space, or F1–F24.');
    if (!/^F\d+$/.test(key) && !parts.some(p => ['Control', 'Alt', 'Super'].includes(p))) throw new Error('Include Ctrl, Alt or Win so normal typing stays available. A function key can be used alone.');
    const accelerator = [...modifiers.filter(p => parts.includes(p)), key].join('+');
    if (['Alt+F4', 'Super+L'].includes(accelerator)) throw new Error('That combination is reserved by Windows. Choose another.');
    return { accelerator, virtualKey, label: accelerator.replace('Control', 'Ctrl').replace('Super', 'Win').split('+').join(' + ') };
  }
  function fromEvent(event) {
    let key = event.code === 'Space' ? 'Space' : /^F\d+$/.test(event.key) ? event.key : /^[a-z0-9]$/i.test(event.key) ? event.key.toUpperCase() : /^Digit\d$/.test(event.code) ? event.code.slice(-1) : null;
    if (!key) return null;
    return parse([event.ctrlKey && 'Control', event.altKey && 'Alt', event.shiftKey && 'Shift', event.metaKey && 'Super', key].filter(Boolean).join('+'));
  }
  const api = { parse, fromEvent };
  if (typeof module !== 'undefined') module.exports = api;
  else root.Keybinding = api;
})(globalThis);
