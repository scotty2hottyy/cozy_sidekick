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

## Next
1. Complete the provider/settings manual test checklist above.
2. Manually validate personality persistence across a full app restart and confirm chat requests use the selected prompt.
3. Manually validate issue #2 on physical iPhone and Android devices.
4. Continue with chat-history work without moving provider behavior into chat widgets.
