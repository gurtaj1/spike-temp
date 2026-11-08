Bun.serve({
  port: 3000,
  routes: {
    "/": {
      GET: () => new Response("hello from a"),
    },
  },
});

console.log("Listening on http://127.0.0.1:3000/");
