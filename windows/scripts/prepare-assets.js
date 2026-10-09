'use strict';
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '../..');
const target = path.join(root, 'windows/assets');
fs.mkdirSync(target, { recursive: true });
let index = fs.readFileSync(path.join(root, 'Resources/index.html'), 'utf8');
index = index.replaceAll('选择 Dock 图标', '选择任务栏图标')
  .replaceAll('设置 (⌘,)', '设置 (Ctrl+,)')
  .replaceAll('旧书会在保存时迁移。', 'Windows 书库会单独保存在本机。');
fs.writeFileSync(path.join(target, 'index.html'), index);
let settings = fs.readFileSync(path.join(root, 'Resources/settings.html'), 'utf8');
settings = settings.replaceAll('Command-Tab', 'Alt+Tab').replaceAll('Dock', '任务栏');
fs.writeFileSync(path.join(target, 'settings.html'), settings);
