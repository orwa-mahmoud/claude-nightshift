import fs from "node:fs";
import path from "node:path";

const roots = ["locales", "i18n", "translations", "lang"];
let dir = "";
for (const candidate of roots) {
  if (
    fs.existsSync(candidate) &&
    fs.readdirSync(candidate).some((name) => name.endsWith(".json"))
  ) {
    dir = candidate;
    break;
  }
}
if (!dir) {
  console.error("check-locale-parity: no locale JSON directory");
  process.exit(78);
}
const files = fs
  .readdirSync(dir)
  .filter((name) => name.endsWith(".json"))
  .sort();
if (files.length < 2) {
  console.error("check-locale-parity: need at least two locale files");
  process.exit(78);
}
const keySets = Object.fromEntries(
  files.map((file) => {
    const data = JSON.parse(fs.readFileSync(path.join(dir, file), "utf8"));
    return [file, new Set(Object.keys(data))];
  })
);
const union = new Set();
for (const keys of Object.values(keySets)) {
  for (const key of keys) {
    union.add(key);
  }
}
let drift = 0;
for (const file of files) {
  for (const key of union) {
    if (!keySets[file].has(key)) {
      console.log(`missing ${key} in ${dir}/${file}`);
      drift += 1;
    }
  }
}
if (drift > 0) {
  process.exit(1);
}
console.log("locale keys aligned");
