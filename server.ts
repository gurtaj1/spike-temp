Bun.serve({
  port: 3001,
  routes: {
    "/": {
      GET: () => new Response("hello from b"),
    },
  },
});
