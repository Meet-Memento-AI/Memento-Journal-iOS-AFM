// _shared/utils.ts
//
// Common utility functions shared across edge functions
//

/**
 * Parse an integer from environment variable with fallback and optional max.
 */
export function envInt(key: string, fallback: number, max?: number): number {
  const n = Number.parseInt(Deno.env.get(key) ?? String(fallback), 10);
  if (!Number.isFinite(n) || n <= 0) return fallback;
  return max === undefined ? n : Math.min(n, max);
}

/**
 * Parse a float from environment variable with fallback.
 */
export function envFloat(key: string, fallback: number): number {
  const n = Number.parseFloat(Deno.env.get(key) ?? String(fallback));
  return Number.isFinite(n) ? n : fallback;
}

/**
 * Locale-aware string comparison for sorting.
 */
export function localeCompare(a: string, b: string): number {
  return a.localeCompare(b);
}
