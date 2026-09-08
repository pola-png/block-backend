const fs = require('fs');
const path = require('path');

const dir = 'app/api/presigned-url';
const fullPath = path.join(__dirname, dir);
if (!fs.existsSync(fullPath)) {
  fs.mkdirSync(fullPath, { recursive: true });
  console.log(`Created: ${dir}`);
}
