// Edge Function: verify-ios-subscription
// Recibe la transacción verificada de StoreKit 2 desde la app iOS y actualiza public.subscriptions
// manteniendo el control de acceso server-side (`access_level_for(uid)`).

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const PLAN_DAYS: Record<string, { planId: string; days: number }> = {
  mirador_weekly: { planId: "weekly", days: 7 },
  mirador_monthly: { planId: "monthly", days: 30 },
  mirador_quarterly: { planId: "quarterly", days: 90 },
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", {
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
      },
    });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const jwt = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "").trim();

  if (!jwt || !supabaseUrl || !serviceRoleKey) {
    return new Response(JSON.stringify({ ok: false, error: "unauthorized" }), { status: 401 });
  }

  const adminClient = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: userData, error: userErr } = await adminClient.auth.getUser(jwt);
  if (userErr || !userData?.user) {
    return new Response(JSON.stringify({ ok: false, error: "invalid_token" }), { status: 401 });
  }

  const body = await req.json().catch(() => ({}));
  const productId = String(body.product_id ?? "").trim();
  const mapped = PLAN_DAYS[productId];
  if (!mapped) {
    return new Response(JSON.stringify({ ok: false, error: "unknown_product_id" }), { status: 400 });
  }

  const validUntilIso = new Date(Date.now() + mapped.days * 86400 * 1000).toISOString();

  const { error: upsertErr } = await adminClient.from("subscriptions").upsert(
    {
      user_id: userData.user.id,
      plan_id: mapped.planId,
      status: "active",
      auto_renew: true,
      current_period_end: validUntilIso,
      provider: "apple_app_store",
      external_transaction_id: String(body.original_transaction_id ?? body.transaction_id ?? ""),
    },
    { onConflict: "user_id" },
  );

  if (upsertErr) {
    return new Response(JSON.stringify({ ok: false, error: upsertErr.message }), { status: 500 });
  }

  return new Response(JSON.stringify({ ok: true, plan_id: mapped.planId, current_period_end: validUntilIso }), {
    status: 200,
    headers: { "Content-Type": "application/json" },
  });
});
