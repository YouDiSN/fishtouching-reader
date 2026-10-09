'use strict';
const { contextBridge, ipcRenderer } = require('electron');
contextBridge.exposeInMainWorld('webkit', { messageHandlers: {
  app: { postMessage: data => ipcRenderer.send('app-action', data) },
  settings: { postMessage: data => ipcRenderer.send('settings-action', data) }
} });
contextBridge.exposeInMainWorld('readerNative', {
  onPdf: callback => ipcRenderer.on('pdf-document', (_event, data) => callback(data)),
  onClear: callback => ipcRenderer.on('pdf-clear', callback),
  pdfReady: () => ipcRenderer.send('pdf-ready'),
  pdfCount: count => ipcRenderer.send('pdf-count', count),
  pdfProgress: data => ipcRenderer.send('pdf-progress', data),
  pdfBack: () => ipcRenderer.send('pdf-back'),
  pdfSecure: () => ipcRenderer.send('pdf-secure')
});
