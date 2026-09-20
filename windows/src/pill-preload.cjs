const { contextBridge, ipcRenderer } = require('electron');
contextBridge.exposeInMainWorld('notch', {
  onState: callback => ipcRenderer.on('pill', (_, state) => callback(state)),
  onLevel: callback => ipcRenderer.on('pill:level', (_, level) => callback(level)),
  action: (action,point) => { if (['toggle', 'open', 'drag-start','drag-move','drag-end','drag-cancel'].includes(action)) ipcRenderer.send('pill:action', action,point); }
});
