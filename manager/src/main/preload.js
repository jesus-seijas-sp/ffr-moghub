const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('api', {
  gameInfo: () => ipcRenderer.invoke('game:info'),
  pickGame: () => ipcRenderer.invoke('game:pick'),
  scanMods: () => ipcRenderer.invoke('mods:scan'),
  modUpdates: () => ipcRenderer.invoke('mods:updates'),
  setEnabled: (id, on) => ipcRenderer.invoke('mods:setEnabled', id, on),
  catalogStatus: (force) => ipcRenderer.invoke('catalog:status', force),
  install: (id) => ipcRenderer.invoke('catalog:install', id),
  uninstall: (id) => ipcRenderer.invoke('catalog:uninstall', id),
  onProgress: (fn) => ipcRenderer.on('progress', (_e, msg) => fn(msg)),
  openUrl: (url) => ipcRenderer.invoke('open:url', url),
  openFolder: (rel) => ipcRenderer.invoke('open:folder', rel),
});
