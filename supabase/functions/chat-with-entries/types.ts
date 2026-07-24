// types.ts
// Type definitions for chat-with-entries Edge Function
// Matches InsightsService.ChatRequest and AIOutputContent response format

export interface JournalEntryPayload {
  date: string;
  title: string;
  content: string;
  word_count: number;
}

export interface ChatMessagePayload {
  content: string;
  isFromUser: string; // "true" | "false" - JSON serialization from Swift Bool
}

/** Personalization from onboarding: LearnAboutYourselfView + YourGoalsView */
export interface SystemPromptContext {
  onboardingSelfReflection?: string;
  selectedGoals?: string[];
}

export interface ChatWithEntriesRequest {
  messages: ChatMessagePayload[];
  entries: JournalEntryPayload[];
  systemPromptContext?: SystemPromptContext;
}

/** Response structure matching AIOutputContent (heading1, heading2, body, citations) */
export interface ChatResponse {
  heading1?: string;
  heading2?: string;
  body: string;
  citations?: { id: string; entry_id: string; entry_title: string; entry_date: string; excerpt: string }[];
}

export interface ErrorResponse {
  error: string;
  code?: string;
  debug?: unknown;
}
