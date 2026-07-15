-- Migration: pin search_path on remaining SECURITY DEFINER functions (spec-004 R4).
--
-- Without an explicit search_path, a SECURITY DEFINER function resolves
-- unqualified object references using the CALLER's search_path — a classic
-- privilege-escalation vector (a caller could create a same-named object in a
-- schema ahead of `public` in their search_path to have it silently substituted
-- with the function's elevated privileges). `delete_user`, `get_user_entry_count`,
-- `get_user_entry_stats`, and `prune_rate_limits` already pin it; these ten did not.
--
-- ALTER FUNCTION ... SET search_path only changes the function's configuration,
-- not its body — zero behavior change, just closes the hijacking vector.

ALTER FUNCTION public.calculate_writing_streak(uuid) SET search_path = public;
ALTER FUNCTION public.cleanup_expired_insights() SET search_path = public;
ALTER FUNCTION public.get_cached_insight(uuid, text, timestamp with time zone, timestamp with time zone) SET search_path = public;
ALTER FUNCTION public.get_entries_by_date_range(uuid, timestamp with time zone, timestamp with time zone) SET search_path = public;
ALTER FUNCTION public.get_entries_by_themes(uuid, text[], integer) SET search_path = public;
ALTER FUNCTION public.invalidate_insights(uuid, text) SET search_path = public;
ALTER FUNCTION public.recalculate_user_stats(uuid) SET search_path = public;
ALTER FUNCTION public.save_insight_cache(uuid, text, jsonb, integer, timestamp with time zone, timestamp with time zone, integer) SET search_path = public;
ALTER FUNCTION public.search_entries(uuid, text, integer) SET search_path = public;
ALTER FUNCTION public.update_period_counts(uuid) SET search_path = public;
