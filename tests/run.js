const fs = require('fs'), path = require('path');
const { lua, lauxlib, lualib, to_luastring } = require('fengari');

const addonDir = process.argv[2];
const here = __dirname;
const toc = fs.readFileSync(path.join(addonDir, 'FriendsAndFoes.toc'), 'utf8');
// toc entries in load order; an .xml entry loads its <Script file="..."/> files, like the game
const files = [];
for (const entry of toc.split(/\r?\n/).map(s => s.trim()).filter(s => s && !s.startsWith('#'))) {
  const rel = entry.replace(/\\/g, '/');
  if (rel.endsWith('.xml')) {
    const xml = fs.readFileSync(path.join(addonDir, rel), 'utf8');
    for (const m of xml.matchAll(/<Script\s+file="([^"]+)"/g)) {
      files.push(path.posix.join(path.posix.dirname(rel), m[1].replace(/\\/g, '/')));
    }
  } else {
    files.push(rel);
  }
}

const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);

function run(code, name) {
  if (lauxlib.luaL_loadbuffer(L, to_luastring(code), null, to_luastring('@' + name)) !== lua.LUA_OK ||
      lua.lua_pcall(L, 0, 0, 0) !== lua.LUA_OK) {
    console.error('LUA ERROR:', lua.lua_tojsstring(L, -1));
    process.exit(2);
  }
}

run(fs.readFileSync(path.join(here, 'mock.lua'), 'utf8'), 'mock.lua');
lua.lua_newtable(L);
files.forEach((f, i) => {
  lua.lua_newtable(L);
  lua.lua_pushstring(L, to_luastring(f)); lua.lua_setfield(L, -2, to_luastring('name'));
  lua.lua_pushstring(L, to_luastring(fs.readFileSync(path.join(addonDir, f), 'utf8'))); lua.lua_setfield(L, -2, to_luastring('src'));
  lua.lua_rawseti(L, -2, i + 1);
});
lua.lua_setglobal(L, to_luastring('ADDON_FILES'));
run('RESULTS = {}', 'init');
run(fs.readFileSync(path.join(here, 'test.lua'), 'utf8'), 'test.lua');

lua.lua_getglobal(L, to_luastring('RESULTS'));
const n = lua.lua_rawlen(L, -1);
let failed = false;
for (let i = 1; i <= n; i++) {
  lua.lua_rawgeti(L, -1, i);
  const s = lua.lua_tojsstring(L, -1);
  if (s.startsWith('FAIL')) failed = true;
  console.log(s);
  lua.lua_pop(L, 1);
}
process.exit(failed ? 1 : 0);
