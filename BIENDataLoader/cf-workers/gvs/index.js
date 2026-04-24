export default {
  async fetch(request, env) {
    if (request.method === "OPTIONS") {
      return new Response(null, {
        status: 204,
        headers: {
          "Access-Control-Allow-Origin": "*",
          "Access-Control-Allow-Methods": "POST, OPTIONS",
          "Access-Control-Allow-Headers": "Content-Type, Accept"
        }
      });
    }
    if (request.method !== "POST") {
      return new Response("POST required", {
        status: 405,
        headers: { "Access-Control-Allow-Origin": "*" }
      });
    }
    const body = await request.arrayBuffer();
    let upstreamResp, upstreamBody;
    try {
      upstreamResp = await fetch("https://gvsapi.xyz/gvs_api.php", {
        method: "POST",
        headers: {
          "Content-Type": request.headers.get("Content-Type") || "application/json",
          "Accept": request.headers.get("Accept") || "application/json"
        },
        body
      });
      upstreamBody = await upstreamResp.arrayBuffer();
    } catch (err) {
      return new Response(JSON.stringify({ error: "Upstream unreachable", detail: err.message }), {
        status: 502,
        headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" }
      });
    }
    return new Response(upstreamBody, {
      status: upstreamResp.status,
      headers: {
        "Content-Type": upstreamResp.headers.get("Content-Type") || "application/json",
        "Access-Control-Allow-Origin": "*"
      }
    });
  }
};
