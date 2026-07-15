# Supabase Edge Functions

This directory contains all Supabase Edge Functions for the MeetMemento app.

## Directory Structure

```
functions/
├── _shared/                      # Shared utilities across functions
│   ├── cors.ts                   # CORS headers
│   ├── auth.ts                   # Authentication helpers
│   └── types.ts                  # Shared TypeScript types
│
└── generate-follow-up/           # Follow-up question generation
    ├── index.ts                  # Main entry point (required)
    ├── tfidf.ts                  # TF-IDF algorithm implementation
    ├── question-bank.ts          # Curated questions database
    ├── precompute.ts             # Pre-compute question vectors
    └── types.ts                  # Function-specific types
```

## Getting Started

### Prerequisites

1. Install Supabase CLI:
   ```bash
   brew install supabase/tap/supabase
   ```

2. Link to your Supabase project:
   ```bash
   cd /path/to/MeetMemento
   supabase link --project-ref YOUR_PROJECT_ID
   ```

### Local Development

1. Start local Supabase (optional but recommended):
   ```bash
   supabase start
   ```

2. Serve function locally:
   ```bash
   supabase functions serve generate-follow-up
   ```

3. Test with curl:
   ```bash
   curl -i --location --request POST \
     'http://localhost:54321/functions/v1/generate-follow-up' \
     --header 'Authorization: Bearer YOUR_ANON_KEY' \
     --header 'Content-Type: application/json'
   ```

### Deployment

Deploy to production:
```bash
supabase functions deploy generate-follow-up
```

Deploy all functions:
```bash
supabase functions deploy
```

### Environment Variables

For local development, create `.env.local` in the project root:
```
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_ANON_KEY=your-anon-key
```

For production, use Supabase secrets:
```bash
supabase secrets set MY_SECRET=value
```

## Creating New Functions

1. Create new function:
   ```bash
   supabase functions new function-name
   ```

2. Edit `functions/function-name/index.ts`

3. Test locally:
   ```bash
   supabase functions serve function-name
   ```

4. Deploy:
   ```bash
   supabase functions deploy function-name
   ```

## Calling Functions from Swift

```swift
let response = try await supabase.functions.invoke(
    "generate-follow-up",
    options: FunctionInvokeOptions(
        headers: ["Authorization": "Bearer \(token)"],
        body: [:]
    )
)
```

## Shared Utilities

Functions in `_shared/` are not deployable - they're imported by other functions:

```typescript
// In your function's index.ts
import { corsHeaders } from '../_shared/cors.ts'
import { requireAuth } from '../_shared/auth.ts'

const auth = await requireAuth(req, corsHeaders, { missing: 'AUTH_REQUIRED', invalid: 'AUTH_FAILED' });
if (auth instanceof Response) return auth;
const { user, supabase } = auth;
```

## Debugging

View function logs in Supabase Dashboard:
1. Go to Edge Functions
2. Click function name
3. Click "Logs" tab

Or use CLI:
```bash
supabase functions logs generate-follow-up
```

## TypeScript Support

Edge functions run on Deno, which uses ES modules:
- Always include `.ts` extension in imports
- Use `https://` URLs for external dependencies
- Relative imports for local modules

```typescript
// ✅ Correct
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { computeTFIDF } from './tfidf.ts'

// ❌ Wrong
import { computeTFIDF } from './tfidf'
```

## Resources

- [Supabase Edge Functions Docs](https://supabase.com/docs/guides/functions)
- [Deno Documentation](https://deno.land/manual)
- [TypeScript Handbook](https://www.typescriptlang.org/docs/)
