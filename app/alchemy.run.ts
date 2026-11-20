// Deploys the prebuilt app in DIST_DIR (from scripts/build.sh, checked by
// scripts/validate-dist.sh) to the Cloudflare account in CLOUDFLARE_ACCOUNT_ID.
// Nothing here builds or runs the app's code: the Worker is uploaded as-is with noBundle.
//
// Env: STAGE (pr-<n> or prod), DIST_DIR (absolute), ALCHEMY_TELEMETRY_DISABLED,
//      CLOUDFLARE_API_TOKEN, CLOUDFLARE_ACCOUNT_ID, ALCHEMY_STATE_TOKEN, ALCHEMY_PASSWORD
// Run: bun ./alchemy.run.ts             deploy or update the stage
//      bun ./alchemy.run.ts --destroy   remove the stage
import { existsSync, lstatSync } from "node:fs";
import { isAbsolute, join } from "node:path";

function fail(message: string): never {
  console.error(`alchemy.run.ts: ${message}`);
  process.exit(1);
}

// Checked before Alchemy is imported, so nothing of it runs with bad input
const STAGE = process.env.STAGE ?? "";
if (!/^(pr-[0-9]{1,6}|prod)$/.test(STAGE)) fail("STAGE must match ^(pr-[0-9]{1,6}|prod)$");

const DIST_DIR = process.env.DIST_DIR ?? "";
if (!isAbsolute(DIST_DIR)) fail("DIST_DIR must be an absolute path");
for (const [path, kind] of [
  [DIST_DIR, "dir"],
  [join(DIST_DIR, "worker.js"), "file"],
  [join(DIST_DIR, "assets"), "dir"],
  [join(DIST_DIR, "migrations"), "dir"],
] as const) {
  if (!existsSync(path)) fail(`missing ${kind} in DIST_DIR`);
  const st = lstatSync(path);
  if (kind === "dir" ? !st.isDirectory() : !st.isFile()) fail(`not a plain ${kind} in DIST_DIR`);
}

if (process.env.ALCHEMY_TELEMETRY_DISABLED !== "1") fail("ALCHEMY_TELEMETRY_DISABLED must be 1");
for (const name of ["CLOUDFLARE_API_TOKEN", "CLOUDFLARE_ACCOUNT_ID", "ALCHEMY_STATE_TOKEN", "ALCHEMY_PASSWORD"]) {
  if (!process.env[name]) fail(`${name} is not set`);
}

const { default: alchemy } = await import("alchemy");
const { Assets, D1Database, Worker } = await import("alchemy/cloudflare");
const { CloudflareStateStore } = await import("alchemy/state");

const app = await alchemy("spike2-app", {
  stage: STAGE,
  password: process.env.ALCHEMY_PASSWORD,
  stateStore: (scope) => new CloudflareStateStore(scope, { scriptName: "spike2-state" }),
});

const db = await D1Database("db", {
  name: `spike2-db-${STAGE}`,
  migrationsDir: join(DIST_DIR, "migrations"),
});

const assets = await Assets({ path: join(DIST_DIR, "assets") });

const worker = await Worker("worker", {
  name: `spike2-app-${STAGE}`,
  entrypoint: join(DIST_DIR, "worker.js"),
  noBundle: true,
  // Without rules, noBundle uploads every .js, .mjs, .wasm and .js.map under DIST_DIR
  rules: [{ globs: ["worker.js"] }],
  sourceMap: false,
  compatibilityDate: "2026-10-01",
  url: true,
  assets: { run_worker_first: true },
  bindings: {
    DB: db,
    ASSETS: assets,
    STAGE,
  },
});

console.log(`worker: ${worker.name}`);
console.log(`url: ${worker.url ?? "none"}`);

await app.finalize();
