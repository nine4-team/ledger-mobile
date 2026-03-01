const WORKER_URL = process.env.EXPO_PUBLIC_AI_WORKER_URL ?? 'https://ledger-ai.team-1d4.workers.dev';

export type ItemStub = {
  id: string;
  name: string;
  notes?: string | null;
};

export type AiMatchResult = {
  itemId: string;
  phrase: string;
};

export type AiSearchResult = {
  matches: AiMatchResult[];
  unmatched: string[];
};

export async function searchItemsByDescription(
  description: string,
  items: ItemStub[],
): Promise<AiSearchResult> {
  const response = await fetch(WORKER_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ description, items }),
  });

  if (!response.ok) {
    throw new Error(`AI search failed: ${response.status}`);
  }

  const data = await response.json() as AiSearchResult;

  if (!Array.isArray(data.matches) || !Array.isArray(data.unmatched)) {
    throw new Error('Unexpected response format from AI');
  }

  return data;
}
