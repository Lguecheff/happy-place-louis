import { useQuery, useQueryClient } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { nextDigestLabel, type DigestSendResult, type LastDigest } from "@/lib/weekly-digest";
import { WeeklyDigestCard } from "./WeeklyDigestCard";

const LAST_DIGEST_KEY = ["weekly_digests", "last"] as const;

/** Dernier envoi, sans la colonne payload (non lisible côté app). */
async function fetchLastDigest(): Promise<LastDigest | null> {
  const { data, error } = await supabase
    .from("weekly_digests")
    .select("created_at, mode, recipients_count, status, sent_by_name")
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle();
  if (error) throw error;
  return data as LastDigest | null;
}

async function countRecipients() {
  const { data, error } = await supabase.rpc("weekly_digest_recipients_count");
  if (error) throw error;
  return data ?? 0;
}

async function sendDigest(): Promise<DigestSendResult> {
  const { data, error } = await supabase.rpc("send_weekly_digest");
  // Messages de la base (refus, envoi trop rapproché) affichés tels quels ; sinon message générique.
  if (error) throw new Error(error.code === "P0001" || error.code === "42501" ? error.message : "");
  const row = Array.isArray(data) ? data[0] : data;
  return { recipients: row?.recipients ?? 0, transmitted: !!row?.transmitted };
}

/** Carte « Résumé hebdomadaire » de /manage, branchée sur la base. Admins seulement. */
export function WeeklyDigestPanel() {
  const qc = useQueryClient();
  const last = useQuery({ queryKey: LAST_DIGEST_KEY, queryFn: fetchLastDigest, retry: false });

  return (
    <WeeklyDigestCard
      nextLabel={nextDigestLabel()}
      last={last.data ?? null}
      lastUnavailable={last.isError}
      loadCount={countRecipients}
      send={async () => {
        try {
          return await sendDigest();
        } finally {
          await qc.invalidateQueries({ queryKey: LAST_DIGEST_KEY });
        }
      }}
    />
  );
}
