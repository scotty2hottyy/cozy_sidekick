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

## Current Work
### Issue #2 - Create basic chat UI
Branch: `2-create-basic-chat-ui`

UI reference projects:
- `scotty2hottyy/teddy-chat` for the more polished chat presentation.
- `scotty2hottyy/chat_beta` for the settings/menu structure.

Important UI requirement:
- Do not reproduce the bottom gap seen in the older chat UI. The composer/background should visually continue to the bottom edge while still respecting the iPhone safe area.

Issue #2 remains intentionally simple:
- text chat only
- local placeholder assistant reply
- no real AI provider yet
- no history persistence yet
- no personality behavior yet

## Next
For issue #2:
1. Replace Flutter counter UI.
2. Build chat screen, message bubbles, and composer.
3. Reuse/adapt the polished UI patterns rather than copying provider/history code.
4. Add/update widget tests.
5. Run `flutter analyze` and `flutter test`.
6. Update this file before opening the PR.
