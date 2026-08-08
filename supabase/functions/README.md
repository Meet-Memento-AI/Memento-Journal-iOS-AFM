# Supabase Edge Functions

The MeetMemento app is **on-device first** (Apple Foundation Models: chat,
summarization, and journal-entry embeddings/retrieval all run locally — see
`MeetMemento/Services/Intelligence/`). Journals are stored encrypted on device
with no server copy. As a result only **two** edge functions remain, and they
are the only ones the app actually calls.

## Live functions

| Function | Called from | Purpose |
|---|---|---|
| `chat-feedback` | `MeetMemento/Services/ChatService.swift` (`submitFeedback` / `fetchFeedback`) | Records thumbs-up/down on AI replies for quality signal. |
| `generate-insights` | `MeetMemento/Services/InsightsService.swift` | Produces the monthly Insights summary. |

`_shared/` holds cross-function helpers (CORS, auth, rate limiting) and is not
independently deployable.

## Retired functions

The server-side RAG chat stack was decommissioned when chat moved on-device.
`chat`, `chat-with-entries`, `summarize-chat`, `sync-embedding`, and
`new-user-insights` were removed from the repo. Any copies still deployed to a
live project should be undeployed manually with `supabase functions delete <name>`
— deleting them here does not undeploy them.

## Local development

```bash
brew install supabase/tap/supabase
supabase link --project-ref YOUR_PROJECT_ID
supabase functions serve chat-feedback   # or generate-insights
```

## Deployment

Deployment is automated by `.github/workflows/deploy-dev-staging.yml` (dev/staging)
and `.github/workflows/deploy-prod.yml` (production), which enumerate every
non-`_shared` function directory with an `index.ts`. To deploy manually:

```bash
supabase functions deploy chat-feedback
supabase functions deploy generate-insights
```

## Tests

Deno tests run in `.github/workflows/ios-tests.yml` (job `deno-functions`) and
gate production in `deploy-prod.yml`:
- `deno check` compile-gates the two live functions.
- `_shared/rate_limit_test.ts` and `_shared/auth_test.ts` cover the shared middleware.
- Per-function `lib_test.ts` covers extractable pure helpers.

## Shared utilities

```typescript
import { corsHeaders } from '../_shared/cors.ts'
import { requireAuth } from '../_shared/auth.ts'

const auth = await requireAuth(req, corsHeaders, { missing: 'AUTH_REQUIRED', invalid: 'AUTH_FAILED' });
if (auth instanceof Response) return auth;
const { user, supabase } = auth;
```

## Resources

- [Supabase Edge Functions Docs](https://supabase.com/docs/guides/functions)
- [Deno Documentation](https://deno.land/manual)
