const FUNCTIONS_CONFIG = JSON.parse(Deno.env.get("SUPABASE_INTERNAL_FUNCTIONS_CONFIG") || "{}");
const FUNCTIONS_PATH = Deno.env.get("SUPABASE_INTERNAL_FUNCTIONS_PATH") || "";

const envVarsObj = Deno.env.toObject();
const envVars = Object.keys(envVarsObj).map((k) => [k, envVarsObj[k]]);

Deno.serve(async (req: Request) => {
  const url = new URL(req.url);
  const pathParts = url.pathname.split("/").filter(Boolean);
  const functionName = pathParts[0];

  if (!functionName || !FUNCTIONS_CONFIG[functionName]) {
    return new Response(JSON.stringify({ error: "Function not found" }), {
      status: 404,
      headers: { "Content-Type": "application/json" },
    });
  }

  const config = FUNCTIONS_CONFIG[functionName];
  const servicePath = `${FUNCTIONS_PATH}/${config.entrypointPath}`.replace(/\/index\.ts$/, "");

  try {
    const worker = await EdgeRuntime.userWorkers.create({
      servicePath,
      memoryLimitMb: 150,
      workerTimeoutMs: 300 * 1000,
      noModuleCache: false,
      envVars,
      forceCreate: false,
    });

    const newUrl = new URL(req.url);
    newUrl.pathname = "/" + pathParts.slice(1).join("/");

    const newReq = new Request(newUrl.toString(), req);
    EdgeRuntime.applySupabaseTag(req, newReq);

    return await worker.fetch(newReq);
  } catch (e) {
    console.error(`Error serving ${functionName}:`, e);
    return new Response(JSON.stringify({ error: e.message }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
});
