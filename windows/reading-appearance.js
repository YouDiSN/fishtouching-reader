'use strict';
const { execFile } = require('node:child_process');
const path = require('node:path');
let cachedFonts;
function systemFonts() {
  if (cachedFonts) return cachedFonts;
  if (process.platform !== 'win32') return Promise.reject(new Error('请在 Windows 应用中读取系统字体。'));
  // Fixed command only: neither font names nor renderer input enter the shell.
  const command = "[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false); Add-Type -AssemblyName System.Drawing; $fonts = New-Object System.Drawing.Text.InstalledFontCollection; try { @($fonts.Families | ForEach-Object { $_.Name } | Sort-Object -Unique) | ConvertTo-Json -Compress } finally { $fonts.Dispose() }";
  cachedFonts = new Promise((resolve, reject) => {
    execFile(path.join(process.env.SystemRoot || 'C:\\Windows', 'System32', 'WindowsPowerShell', 'v1.0', 'powershell.exe'),
      ['-NoLogo', '-NoProfile', '-NonInteractive', '-Command', command],
      { encoding:'utf8', windowsHide:true, timeout:15000, maxBuffer:2*1024*1024 }, (error, stdout) => {
        if(error) { reject(new Error('读取系统字体失败，请重新展开字体列表重试。')); return; }
        try {
          const value=JSON.parse(stdout.replace(/^\uFEFF/,''));
          const names=Array.isArray(value)?value:[value];
          resolve([...new Set(names.filter(x=>typeof x==='string'&&x.length>0&&x.length<=200&&!x.startsWith('@')))].sort());
        } catch { reject(new Error('系统字体列表无法解析，请重试。')); }
      });
  }).catch(error=>{cachedFonts=null;throw error;});
  return cachedFonts;
}
module.exports={systemFonts};
