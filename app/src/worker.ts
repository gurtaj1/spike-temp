// Spike 2 test app: a D1 counter at /api/count, and static files from Workers Assets.
// Every response gets X-Robots-Tag: noindex unless the STAGE binding is "prod".
import { Hono } from "hono";

// The few Cloudflare runtime types used here, so the app needs no types package
interface D1Database {
  prepare(sql: string): { first<T>(): Promise<T | null> };
}
interface Fetcher {
  fetch(request: Request): Promise<Response>;
}
type Bindings = {
  DB: D1Database;
  ASSETS: Fetcher;
  STAGE: string;
};

const app = new Hono<{ Bindings: Bindings }>();

app.use("*", async (c, next) => {
  await next();
  if (c.env.STAGE !== "prod") {
    // Responses from ASSETS have immutable headers, so copy before setting
    c.res = new Response(c.res.body, c.res);
    c.res.headers.set("X-Robots-Tag", "noindex");
  }
});

app.get("/api/count", async (c) => {
  const row = await c.env.DB.prepare(
    "UPDATE counter SET value = value + 1 WHERE id = 1 RETURNING value",
  ).first<{ value: number }>();
  if (!row) return c.json({ error: "no counter row" }, 500);
  return c.json({ count: row.value });
});

app.all("*", (c) => c.env.ASSETS.fetch(c.req.raw));

export default app;
