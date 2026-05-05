export default {
  async fetch(request, env, ctx) {
    if (request.method !== "POST")
      return new Response("Method Not Allowed", { status: 405 });

    const appToken = request.headers.get("X-App-Token");
    if (appToken !== env.APP_SECRET)
      return new Response("Forbidden", { status: 403 });

    const ip = request.headers.get("CF-Connecting-IP") ?? "unknown";
    const endpointType = request.headers.get("X-Endpoint") ?? "personality";
    const isLife = endpointType === "life-analysis";
    const rateLimitKey = `rl:${ip}:${endpointType}`;
    const windowSeconds = isLife ? 86400 : 3600;
    const maxRequests   = isLife ? 15 : 100;

    const current = parseInt(await env.RATE_LIMIT_KV.get(rateLimitKey) ?? "0");
    if (current >= maxRequests)
      return new Response("Rate limit exceeded", { status: 429 });

    ctx.waitUntil(
      env.RATE_LIMIT_KV.put(rateLimitKey, String(current + 1), { expirationTtl: windowSeconds })
    );

    const body = await request.text();
    const resp = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-api-key": env.ANTHROPIC_API_KEY,
        "anthropic-version": "2023-06-01",
      },
      body,
    });

    return new Response(resp.body, {
      status: resp.status,
      headers: { "Content-Type": "application/json" },
    });
  },
};
