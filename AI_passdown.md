# AI Passdown

## Purpose
Shared handoff notes for teammates and AI tools working on Cozy Sidekick. Update this file after completing or materially changing a task so the next person can quickly understand the current state.

## Project
- Flutter app targeting iOS and Android.
- Repository: `scotty2hottyy/cozy_sidekick`
- Development workflow: one GitHub issue per branch, test before merge, then merge to `main`.

## Product Direction
Cozy Sidekick is a generic configurable AI chat app.

Planned AI providers:
- OpenRouter
- OpenAI
- xAI / Grok
- User-configurable custom HTTP(S) chat server

The personality/system instructions live in the app rather than on the server.

## Current Architecture Decisions
- `ChatMessage` is the shared message model.
- Personality configuration will be stored in the app.
- Provider-specific implementations will sit behind a common provider interface.
- Chat history will be stored locally.
- API credentials must not be hard-coded into the repository.

## Completed
### Issue #9 - OpenAI provider

- `OpenAiProvider` (registered in `main.dart` since #30) now defaults to `gpt-6-luna`, OpenAI's most efficient current model ($0.10 input / $0.50 output per 1M tokens). The model ID lives only in its constructor so #27 can make it configurable.
- It uses Chat Completions (`https://api.openai.com/v1/chat/completions`) through the shared `OpenAiCompatibleProvider`, like OpenRouter and xAI.
- Added `test/ai/openai_provider_test.dart` for the URL, Bearer header, model, ordered messages, reply parsing, the OpenAI-only key slot, malformed replies, and 401s.
- OpenAI has no free tier, so the account needs credit. If Test Connection says "Authentication failed" but the key is right, the OpenAI project may not allow the model (HTTP 403 `model_not_found`). Allow `gpt-6-luna` under Settings → Project → Limits.
- Validation: `flutter analyze` passes; `flutter test` passes (78 tests). Test Connection and a real chat reply worked in the iOS Simulator with a real key.

### Issue #16 - Single local chat history

- Added an injectable `ChatHistoryStore` and `FileChatHistoryStore`, using the application documents directory and `chat_history.json` with existing `ChatMessage` JSON serialization.
- Stores the newest 500 messages; missing or invalid history loads as empty.
- `ChatService` saves before provider requests and after successful replies. Only the newest 20 conversation messages are sent to providers; the system prompt is unchanged.
- `ChatScreen` restores history with an initial spinner and offers a confirmed Clear chat action under Settings → Chat History. Sending/clearing is disabled while loading or busy to avoid conflicting updates.
- Added file-store, service, and widget coverage using temporary directories and fake stores. Physical-device close/reopen verification remains pending.
- Validation: `flutter analyze` passes; `flutter test` passes (50 tests).


### Issues #7, #8, #11, #12, #13, and #14 - Providers and settings

Implemented:
- A shared `AiProvider` interface, provider types, typed provider errors, and a reusable JSON HTTP helper.
- A reusable OpenAI-compatible provider plus registered OpenRouter, OpenAI, and xAI/Grok implementations. OpenRouter defaults to `openrouter/free`.
- A custom server provider that reads a user-configured HTTP(S) base URL and posts ordered system/user/assistant messages to `{baseUrl}/chat`.
- `ChatService` resolves the selected provider for every message, so `ChatScreen` remains provider-neutral and provider changes take effect without restarting.
- `flutter_secure_storage` credential persistence with a distinct slot per provider, trimming, empty-value rejection, replacement/deletion, and an in-memory test implementation. Stored secrets are never displayed or logged.
- `shared_preferences` persistence for the selected text-chat provider and custom server base URL. A fresh install defaults to OpenRouter; the custom server URL is validated but is not hard-coded.
- Functional AI Settings and API Credentials screens linked from Settings. Credentials can be saved, replaced, or deleted, and custom server configuration has separate URL and secure token fields.
- Test Connection actions for every provider, with visible success and clean credential, rate-limit, network, configuration, availability, and malformed-response failures.
- Provider failures are surfaced in chat with safe user-facing messages that do not include credentials or request headers.

Automated coverage:
- HTTP success/error translation and network failures.
- Secure credential save/read/replace/delete, per-provider separation, trimming, and empty-value rejection.
- Provider selection and custom URL persistence.
- OpenRouter and custom server URLs, headers, ordered bodies, parsing, missing credentials, authentication failures, and malformed responses using mock HTTP clients only.
- Selected-provider chat routing, connection-test results, settings navigation, provider selection, URL/credential saving, and visible connection success.

Validation:
- `flutter analyze` passes with no issues.
- `flutter test` passes (33 tests).

Remaining manual testing:
- Save settings, fully restart the app, and confirm provider, URL, and credentials persist.
- Test OpenRouter with a real user-entered key.
- Configure `https://chatserver.sonniersolution.com` with a privately supplied token; test connection and a real chat round trip.
- Confirm bad-token behavior on the live custom server.
- Validate the complete flow on physical iPhone and Android devices.

### Issue #3 - Create message data model
File: `lib/models/chat_message.dart`

Implemented:
- `MessageRole.user`
- `MessageRole.assistant`
- Immutable `ChatMessage`
- `ChatMessage.user()`
- `ChatMessage.assistant()`
- `isUser`
- JSON serialization/deserialization
- UTC ISO-8601 persistence for `createdAt`
- Value equality, `hashCode`, and `toString`

Tests cover JSON round trips, roles, timestamps, invalid input, and equality.

### Issues #4, #5, and #6 - Personality configuration, persistence, and chat integration
Files: `lib/models/personality.dart`, `lib/screens/personality_screen.dart`, `lib/services/personality_service.dart`

Implemented:
- `Personality` model with an ID, name, system prompt, and default flag.
- Personality screen reachable from Settings, with controls to add, edit, choose a default, and remove non-default personalities.
- `PersonalityService` stores the serialized personality list and active personality ID in `shared_preferences`, loads saved state at app startup, and seeds the built-in personalities on a fresh install.
- `ChatService` loads the active personality for each reply and passes its system prompt to the selected provider.
- Unit and widget coverage checks personality persistence, active-personality chat prompts, and personality editing from Settings.

Validation: `flutter test` passes (37 tests), and `flutter analyze` reports no issues. Personality persistence across a full app restart and a real-provider chat round trip still need manual confirmation.

### Combined personality and chat-history integration
- `ChatService` persists the full conversation while sending only the newest 20 messages to the selected provider with the active personality's system prompt.
- History restore, clear-chat, busy-state protection, storage error handling, and personality editing remain available together.
- Settings routes to both the functional Personality and Chat History screens.
- Validation after merging the features: `flutter analyze` passes and `flutter test` passes (54 tests).

### Issue #2 - Create basic chat UI
Branch: `2-create-basic-chat-ui`

Implemented:
- Polished responsive chat screen with header, empty state, message bubbles, typing indicator, and bottom-edge composer.
- Local placeholder replies through `ChatService` (`You said: ...`); no provider integration or persistence.
- Settings button and navigable generic settings shell with placeholders for providers, credentials, personality, voice, appearance, history, and app information.
- Speech-to-text composer input with partial results, stop-listening support, user-facing unavailable/permission/error states, and platform permissions.
- Widget tests for chat, settings navigation, partial speech results, stopping speech, and denied permissions, plus unit tests for the placeholder chat service.

Validation:
- `flutter analyze` passes with no issues.
- `flutter test` passes (14 tests).
- Physical iPhone and Android checks are still needed for permission prompts, speech recognition, keyboard/rotation behavior, and the home-indicator/navigation-bar background.

### Chat-history settings navigation
- Moved Clear chat from the chat header menu to Settings → Chat History, retaining the delete confirmation and persistence behavior.
- Settings is disabled during history loading, sending, or clearing to preserve the existing operation guard. Updated the widget test to cover the settings path, cancel, deletion, and returning to chat.

## Next
1. Complete the provider/settings manual test checklist above.
2. Manually validate personality persistence across a full app restart and confirm chat requests use the selected prompt.
3. Manually verify chat history survives a physical-device close/reopen cycle and clear-chat persists.
4. Manually validate issue #2 on physical iPhone and Android devices.

### Five personality presets
- Added Cozy, Curious, Adventure, Planner, and Captain Quip as constant `Personality.presets`.
- The horizontal Start from a preset chips open the existing editable name/system-instructions dialog. Only Save creates a personality; Cancel leaves stored personalities and the active selection untouched.
- Adapted the proposed trait/description design to the existing name/systemPrompt model; no storage migration or changes to existing user personalities/defaults.
- Added model validation and widget coverage for all five chips, editing, cancel, and explicit save.

### Preset layout cleanup
- Cozy remains the seeded large card; top preset chips are Curious, Adventure, Planner, and Captain Quip. Removed the Cozy chip and legacy unmodified Curious Guide seed, including saved copies on initialization. Customized Curious entries are preserved. Removed active legacy entries fall back to a remaining default.

### Active personality versus startup default
- Preset ChoiceChips switch immediately for this session without saving a new personality; saved cards offer Use now and indicate Active now. Customize preset retains the editable draft / explicit Save flow.
- The persisted isDefault flag now controls startup only. Use when app opens sets it; changing it does not switch the current chat. New service instances start with the default, not the previous session selection.
- Existing default flags are preserved; the old active_id key is used only as a migration fallback, then removed. Deleting an active saved personality falls back to the startup default.

### Direct startup-default selection
- Added a Startup default dropdown listing presets and saved personalities independently of current selection. Selecting it persists the default without changing the current personality; choosing a preset directly still changes only the current session. Presets saved as defaults remain chips, avoiding duplicate large cards.

- Preset customization saved with its original name now receives a Custom suffix (for example CuriousCustom). User-entered names remain unchanged.

### Issue #40 - Model-access errors
- `postJson` now reads the body of 403 and 404 responses. OpenAI's `model_not_found` (the project's model allowlist blocks the model, or the model ID is unknown) raises the new `ModelNotAvailableException` instead of `InvalidApiKeyException` or `BadResponseException('HTTP 404')`. Every other 401/403 is still a key error, and other bodies keep their old mapping.
- Chat shows "This model isn't available for your account. Check the model or your provider's settings." with a Settings action. Test Connection shows "The credential was accepted, but the model isn't available for this account."
- A new `AiProviderException` subtype must also be caught in `ProviderConnectionService.testConnection`. The compiler only flags the `friendlyMessage` and `needsSettings` switches.
- Validation: `flutter analyze` passes; `flutter test` passes (82 tests).

### Issue #37 - Markdown and math in replies
- Assistant replies render Markdown and LaTeX through `FormattedReply` (`lib/widgets/formatted_reply.dart`), which wraps `gpt_markdown`. The package is pinned to 1.3.0 because that release rewrote its parser, so upgrade on purpose and re-run the tests. User messages stay plain `Text`.
- Settings → Appearance (`AppearanceScreen`) has Format replies (on), Show math (on) and Dollar-sign math (off). They're saved as `chat.format_replies`, `chat.show_math` and `chat.dollar_math`, and load together as a `MessageFormatting` from `AppSettingsStore.loadMessageFormatting()`.
- `ChatScreen._loadChatSettings()` runs at startup and whenever the user comes back from Settings. #34's Show reasoning setting should load there too.
- Dollar-sign math uses our own `convertDollarMath`, not gpt_markdown's `useDollarSignsForLatex`. That option also rewrites `$` inside code, so `echo "$HOME $PATH"` showed as `echo "\(HOME \)PATH"`. Ours skips code and follows Pandoc's rules, so "$5 and $10" stays text.
- Math is drawn by our own `latexBuilder`. Invalid LaTeX shows its source in the normal text color (gpt_markdown's default turns it red in debug builds). `align`, `gather` and `equation` are mapped to environments flutter_math_fork can draw. Long inline equations wrap after `+` and `=`. `flutter_math_fork` is a regular dependency because `lib/` imports it.
- Long-pressing a reply offers Copy, which copies the original Markdown and LaTeX.
- While math is shown, `ChatService` adds `ChatService.mathInstruction` to the system prompt so models use `\( \)` and `\[ \]`.
- Links are styled but don't open yet. That needs `url_launcher`.
- Validation: `flutter analyze` passes; `flutter test` passes (111 tests). Checked in the iOS Simulator (iPhone 17 Pro) with sample replies loaded into the chat history. Landscape is covered by widget tests only.

### Issue #34 - Show model reasoning
- Providers return an `AiReply` (`text` plus an optional `reasoning`) instead of a `String`. New providers and test fakes must return one too.
- `OpenAiCompatibleProvider.parseReply` takes reasoning from the first of these that isn't blank: `message.reasoning` (OpenRouter, Ollama, vLLM), `message.reasoning_content` (xAI, llama.cpp, DeepSeek-style), or the content before its last `</think>`, which is then removed from the answer. A reply that's only reasoning is still a `BadResponseException`. `CustomServerProvider` reads an optional `reasoning` string next to `message`. OpenAI's Chat Completions never returns reasoning.
- `ChatMessage.reasoning` is saved in `chat_history.json` only when there is some, so older history still loads. It's saved even while Show reasoning is off. Requests never include it, because both providers send only `message.text`.
- Settings → AI Settings has Show reasoning (`chat.show_reasoning`, off by default). `ChatScreen._loadChatSettings()` loads it with the formatting switches, so it applies when the user comes back from Settings.
- `MessageBubble` shows a collapsed Reasoning row (`Key('reasoningToggle')`) above replies that have reasoning. `ChatScreen` remembers which replies are open, so they stay open while new messages arrive. The chat list is reversed, so opening long reasoning scrolls just enough to keep its row on screen, and closing puts the row back where it was.
- Validation: `flutter analyze` passes; `flutter test` passes (135 tests). Checked in the iOS Simulator (iPhone 17 Pro) with sample replies loaded into the chat history. Not checked yet: a real OpenRouter reply with reasoning.
