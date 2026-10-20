'use strict';
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '../..');
const target = path.join(root, 'windows/assets');
fs.mkdirSync(target, { recursive: true });
let index = fs.readFileSync(path.join(root, 'Resources/index.html'), 'utf8');
index = index.replaceAll('Command-Tab', 'Alt+Tab').replaceAll('Dock','任务栏').replaceAll('选择 Dock 图标', '选择任务栏图标')
  .replaceAll('设置 (⌘,)', '设置 (Ctrl+,)')
  .replaceAll('旧书会在保存时迁移。', 'Windows 书库会单独保存在本机。');
fs.writeFileSync(path.join(target, 'index.html'), index);
for (const name of ['settings.js', 'settings.css', 'reader-appearance.js', 'reader-appearance.css', 'web-plugins.js', 'community-plugins.json', 'fanqie-font-map.json']) fs.copyFileSync(path.join(root, 'Resources', name), path.join(target, name));
