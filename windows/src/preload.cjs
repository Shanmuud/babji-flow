const { contextBridge, ipcRenderer } = require('electron');
const channels = new Set(['state:get','shortcut:capture','shortcut:save','settings:save','key:save','model:load','dictionary:learn','dictionary:save','snippet:save','entry:delete','text:clean','text:copy','text:rewrite','capture:begin','capture:ready','capture:failed','capture:cancel','capture:finish','meeting:import','meeting:update','meeting:summarize','meeting:chat','meeting:delete','meeting:export','data:open','avatar:choose','avatar:reset']);
contextBridge.exposeInMainWorld('babji', {
  audioLevel: level => { if (typeof level === 'number' && Number.isFinite(level)) ipcRenderer.send('capture:level', Math.max(0, Math.min(1, level))); },
  invoke: (channel, ...args) => { if (!channels.has(channel)) throw new Error('Unknown action'); return ipcRenderer.invoke(channel, ...args); },
  on: (channel, callback) => { if (!['state','model','activity','capture-control','notice','shortcut-capture-ended'].includes(channel)) throw new Error('Unknown event'); const listener = (_, value) => callback(value); ipcRenderer.on(channel, listener); return () => ipcRenderer.removeListener(channel, listener); }
});
