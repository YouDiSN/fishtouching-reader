'use strict';
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '..');
fs.copyFileSync(path.join(root, 'package-lock.json'), path.join(root, 'dist', 'FishTouching Reader-win32-x64', 'resources', 'app', 'package-lock.json'));
