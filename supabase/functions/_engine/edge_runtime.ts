/** Injected by the Supabase Edge runtime. Its shipped `edge-runtime.d.ts`
 * doesn't register ambient types under `deno check`, so the one API the
 * engine uses is declared here; import this module for its side effect
 * wherever `EdgeRuntime` is referenced. `waitUntil` keeps the worker alive
 * until the promise settles, so a post-response notify isn't dropped; on a
 * platform without `EdgeRuntime` the call throws loudly (deliberately
 * unguarded). */
declare global {
  namespace EdgeRuntime {
    function waitUntil<T>(promise: Promise<T>): Promise<T>;
  }
}

export {};
