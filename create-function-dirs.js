const fs = require('fs');
const path = require('path');

const dirs = [
  'functions',
  'functions/upload-media',
  'functions/upload-media/src'
];

dirs.forEach(dir => {
  const fullPath = path.join(__dirname, dir);
  if (!fs.existsSync(fullPath)) {
    fs.mkdirSync(fullPath, { recursive: true });
    console.log(`Created: ${dir}`);
  }
});

console.log('All function directories created');
