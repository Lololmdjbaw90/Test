// Copies the server code (netlify/functions and netlify/lib) into functions/,
// so Firebase runs exactly what Netlify runs. firebase.json runs this before
// every functions deploy; the copy isn't kept in git (functions/.gitignore).
import { cpSync, rmSync } from "node:fs";

const root = new URL("../", import.meta.url);
const target = new URL("functions/netlify/", root);
rmSync(target, { recursive: true, force: true });
for (const part of ["functions", "lib"]) {
  cpSync(new URL(`netlify/${part}/`, root), new URL(`${part}/`, target), { recursive: true });
}
console.log("Copied netlify/functions and netlify/lib into functions/netlify/.");
