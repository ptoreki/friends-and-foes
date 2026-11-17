// Every string the add-on uses (L.SOMETHING in the code) is defined in Locale.lua. A missing one
// would show its key ("PROF_ENEMY") in game instead of text, because Locale.lua falls back to the
// key so nothing ever breaks - which is also why a mistake there is easy to miss.
// Also lists strings defined but never used (a warning, not a failure).
const fs = require("fs");
const path = require("path");

const dir = process.argv[2];
const files = fs.readdirSync(dir).filter((f) => f.endsWith(".lua"));
const locale = fs.readFileSync(path.join(dir, "Locale.lua"), "utf8");

const defined = new Set();
for (const m of locale.matchAll(/^L\.([A-Za-z0-9_]+)\s*=/gm)) defined.add(m[1]);

const used = new Map(); // key -> "File.lua:line"
for (const f of files) {
  if (f === "Locale.lua") continue;
  const lines = fs.readFileSync(path.join(dir, f), "utf8").split("\n");
  lines.forEach((line, i) => {
    const code = line.replace(/--.*$/, ""); // (not in comments)
    for (const m of code.matchAll(/\bL\.([A-Z][A-Za-z0-9_]*)\b/g)) {
      if (!used.has(m[1])) used.set(m[1], `${f}:${i + 1}`);
    }
  });
}
// strings looked up by building their name (L["GROUP_" .. reason], L[reason]) are reasons
// passed around as Locale keys: those are checked where they're defined
const missing = [...used.keys()].filter((k) => !defined.has(k));
for (const k of missing) console.log(`MISSING  L.${k}  (used at ${used.get(k)})`);
const unused = [...defined].filter((k) => !used.has(k) && !locale.includes(`L.${k}]`) && !locale.includes(`[L.${k}]`));
if (unused.length) console.log(`(${unused.length} strings defined but not used by name; may be looked up by key)`);
if (missing.length) {
  console.log(`${missing.length} missing strings`);
  process.exit(1);
}
console.log(`strings: ${used.size} used, all defined`);
