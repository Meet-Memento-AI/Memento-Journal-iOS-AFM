alter table "public"."entries" add column if not exists "is_archived" boolean default false;

alter table "public"."entries" add column if not exists "tags" text[] default '{}'::text[];

alter table "public"."entries" add column if not exists "title" text;

alter table "public"."entries" alter column "created_at" set not null;

alter table "public"."entries" alter column "updated_at" set not null;

alter table "public"."entries" drop constraint if exists "text_not_empty";

alter table "public"."entries" add constraint "text_not_empty" CHECK ((char_length(text) > 0)) not valid;

alter table "public"."entries" validate constraint "text_not_empty";

set check_function_bodies = off;

CREATE OR REPLACE FUNCTION public.delete_user()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  DECLARE
    current_user_id uuid;
  BEGIN
    -- SAFETY: Get only the authenticated user's ID
    current_user_id := auth.uid();

    -- SAFETY: Verify user is authenticated
    IF current_user_id IS NULL THEN
      RAISE EXCEPTION 'Not authenticated. Cannot delete account.';
    END IF;

    -- Transaction: All-or-nothing deletion
    BEGIN
      -- Step 1: Delete all journal entries for this user
      DELETE FROM public.entries WHERE user_id = current_user_id;

      -- Step 2: Delete the user from auth.users
      -- This also deletes user_metadata automatically
      DELETE FROM auth.users WHERE id = current_user_id;

      -- Log success
      RAISE NOTICE 'User % deleted successfully', current_user_id;

    EXCEPTION
      WHEN OTHERS THEN
        -- Transaction auto-rolls back on error
        RAISE EXCEPTION 'Failed to delete user: %', SQLERRM;
    END;
  END;
  $function$
;

CREATE OR REPLACE FUNCTION public.get_user_entry_count()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  DECLARE
    current_user_id uuid;
    entry_count integer;
  BEGIN
    current_user_id := auth.uid();

    IF current_user_id IS NULL THEN
      RAISE EXCEPTION 'Not authenticated';
    END IF;

    SELECT COUNT(*)::integer INTO entry_count
    FROM public.entries
    WHERE user_id = current_user_id;

    RETURN entry_count;
  END;
  $function$
;

CREATE OR REPLACE FUNCTION public.get_user_entry_stats()
 RETURNS TABLE(total_entries integer, entries_this_week integer, entries_this_month integer, first_entry_date timestamp with time zone, last_entry_date timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  DECLARE
    current_user_id uuid;
  BEGIN
    current_user_id := auth.uid();

    IF current_user_id IS NULL THEN
      RAISE EXCEPTION 'Not authenticated';
    END IF;

    RETURN QUERY
    SELECT
      COUNT(*)::integer AS total_entries,
      COUNT(*) FILTER (WHERE created_at >= NOW() - INTERVAL '7 
  days')::integer AS entries_this_week,
      COUNT(*) FILTER (WHERE created_at >= NOW() - INTERVAL '30 
  days')::integer AS entries_this_month,
      MIN(created_at) AS first_entry_date,
      MAX(created_at) AS last_entry_date
    FROM public.entries
    WHERE user_id = current_user_id;
  END;
  $function$
;

CREATE OR REPLACE FUNCTION public.update_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.update_updated_at_column()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
  BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
  END;
  $function$
;

drop policy if exists "Users can create own entries" on "public"."entries";
create policy "Users can create own entries"
on "public"."entries"
as permissive
for insert
to public
with check ((auth.uid() = user_id));


drop policy if exists "Users can create their own entries" on "public"."entries";
create policy "Users can create their own entries"
on "public"."entries"
as permissive
for insert
to public
with check ((auth.uid() = user_id));


drop policy if exists "Users can delete their own entries" on "public"."entries";
create policy "Users can delete their own entries"
on "public"."entries"
as permissive
for delete
to public
using ((auth.uid() = user_id));


drop policy if exists "Users can update their own entries" on "public"."entries";
create policy "Users can update their own entries"
on "public"."entries"
as permissive
for update
to public
using ((auth.uid() = user_id))
with check ((auth.uid() = user_id));


drop policy if exists "Users can view their own entries" on "public"."entries";
create policy "Users can view their own entries"
on "public"."entries"
as permissive
for select
to public
using ((auth.uid() = user_id));


drop trigger if exists entries_updated_at on public.entries;
CREATE TRIGGER entries_updated_at BEFORE UPDATE ON public.entries FOR EACH ROW EXECUTE FUNCTION update_updated_at();

drop trigger if exists update_entries_updated_at on public.entries;
CREATE TRIGGER update_entries_updated_at BEFORE UPDATE ON public.entries FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();


