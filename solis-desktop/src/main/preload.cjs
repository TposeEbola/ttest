'use strict';

const { contextBridge, ipcRenderer } = require('electron');
// This is the whole renderer capability surface: no Node, shell, files, or raw IPC.
contextBridge.exposeInMainWorld('solis', Object.freeze({
  getStatus: () => ipcRenderer.invoke('solis:status'),
  sendMessage: (message) => ipcRenderer.invoke('solis:message', message),
  getDiagnostics: () => ipcRenderer.invoke('solis:diagnostics'),
  requestMicrophone: () => ipcRenderer.invoke('solis:microphone'),
  startListening: () => ipcRenderer.invoke('solis:listen'),
  stopListening: () => ipcRenderer.invoke('solis:stop-listening'),
  speak: (text) => ipcRenderer.invoke('solis:speak', text),
  stopSpeaking: () => ipcRenderer.invoke('solis:stop-speaking'),
  getSettings: () => ipcRenderer.invoke('solis:settings'),
  saveSettings: (settings) => ipcRenderer.invoke('solis:save-settings', settings),
  testConnection: () => ipcRenderer.invoke('solis:test-connection'),
}));
