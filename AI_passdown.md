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
- Self-hosted LLM through `teddy_chat.sonniersolution.com`

The personality/system instructions live in the app rather than on the server.

## Current Architecture Decisions
- `ChatMessage` is the shared message model.
- Personality configuration will be stored in the app.
- Provider-specific implementations will sit behind a common provider interface.
- Chat history will be stored locally.
- API credentials must not be hard-coded into the repository.

## Completed
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
1. Manually validate issue #2 on physical iPhone and Android devices.
2. Keep settings rows as placeholders until their dedicated issues are implemented.
3. Continue with provider, persistence, and personality issues without moving that behavior into the chat widgets.
