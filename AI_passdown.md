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
