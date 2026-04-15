// _shared/types.ts
//
// Shared TypeScript types used across multiple edge functions
//
// Purpose:
// - Define common database table interfaces
// - Define common response formats
// - Ensure consistency across functions

/**
 * Common user type from Supabase auth.
 */
export interface User {
  id: string;
  email?: string;
  user_metadata?: Record<string, unknown>;
}

/**
 * Standard error response format.
 */
export interface ErrorResponse {
  error: string;
  details?: string;
  code?: string;
}

/**
 * Standard success response wrapper.
 */
export interface SuccessResponse<T> {
  data: T;
  metadata?: {
    timestamp: string;
    [key: string]: unknown;
  };
}

// Note: Function-specific types should be in their own types.ts files
// Only put truly shared types here
