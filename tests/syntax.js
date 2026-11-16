const fs = require('fs'), path = require('path'), lp = require('luaparse');
const dir = process.argv[2]; let bad = 0;
// every .lua file, including the bundled libraries in Libs/
function walk(d) {
  for (const e of fs.readdirSync(d, { withFileTypes: true })) {
    const p = path.join(d, e.name);
    if (e.isDirectory()) walk(p);
    else if (e.name.endsWith('.lua')) {
      const name = path.relative(dir, p).replace(/\\/g, '/');
      try { lp.parse(fs.readFileSync(p, 'utf8'), { luaVersion: '5.1' }); console.log('OK  ', name); }
      catch (err) { bad++; console.log('FAIL', name, err.message); }
    }
  }
}
walk(dir);
process.exit(bad);
