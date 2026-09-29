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
- GroqCloud
- User-configurable custom HTTP(S) chat server

The personality/system instructions live in the app rather than on the server.

## Current Architecture Decisions
- `ChatMessage` is the shared message model.
- Personality configuration will be stored in the app.
- Provider-specific implementations will sit behind a common provider interface.
- Chat history will be stored locally.
- API credentials must not be hard-coded into the repository.

## Completed
### Issue #18 - iOS configuration

- Runner uses `com.sonniersolution.cozysidekick` for Debug, Release, and Profile; RunnerTests uses `com.sonniersolution.cozysidekick.RunnerTests`.
- The minimum iOS version remains 15.0, and `ios/Podfile` explicitly declares `platform :ios, '15.0'`.
- The visible app name remains Cozy Sidekick. Microphone and speech-recognition usage descriptions remain in Info.plist because speech-to-text is implemented.
- Validation: `flutter pub get`, `flutter analyze`, `flutter test` (170 tests), and `flutter build ios --no-codesign` pass. The built app reports the expected bundle ID, display name, and iOS 15.0 minimum.
- Physical iPhone execution was validated previously. After this configuration change, run a final device smoke test: chat, restart, and confirm the key, provider choice, personality, and chat history persist.

### Issue #10 - GroqCloud provider

- `GroqProvider` reuses `OpenAiCompatibleProvider` with `https://api.groq.com/openai/v1` (`/chat/completions`) and the text model `openai/gpt-oss-20b`. This matches the proven Teddy Chat Groq setup for text chat without copying its separate provider architecture.
- `main.dart` registers it as `AiProviderType.groq`. AI Settings shows Groq, and API Credentials uses the existing secure `api_key.groq` slot and Test Connection path.
- `test/ai/groq_provider_test.dart` uses mock HTTP to cover the endpoint, Bearer key, model, ordered system and conversation messages, first-choice reply parsing, streaming replies, missing-key behavior, and the existing connection-test service. Settings and key-store tests cover Groq selection and credential handling.
- A manual Test Connection and chat reply with an existing Groq API key are still required.

### Issue #9 - OpenAI provider

- `OpenAiProvider` (registered in `main.dart` since #30) now defaults to `gpt-6-luna`, OpenAI's most efficient current model ($0.10 input / $0.50 output per 1M tokens). Since #27 the default lives in `AiProviderType.openAi.defaultModel`, and AI Settings can pick another model.
- It uses Chat Completions (`https://api.openai.com/v1/chat/completions`) through the shared `OpenAiCompatibleProvider`, like OpenRouter and Groq.
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
- A reusable OpenAI-compatible provider plus registered OpenRouter, OpenAI, and Groq implementations. OpenRouter defaults to `openrouter/free`.
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
- `OpenAiCompatibleProvider.parseReply` takes reasoning from the first of these that isn't blank: `message.reasoning` (OpenRouter, Ollama, vLLM), `message.reasoning_content` (llama.cpp, DeepSeek-style), or the content before its last `</think>`, which is then removed from the answer. A reply that's only reasoning is still a `BadResponseException`. `CustomServerProvider` reads an optional `reasoning` string next to `message`. OpenAI's Chat Completions never returns reasoning.
- `ChatMessage.reasoning` is saved in `chat_history.json` only when there is some, so older history still loads. It's saved even while Show reasoning is off. Requests never include it, because both providers send only `message.text`.
- Settings → AI Settings has Show reasoning (`chat.show_reasoning`, off by default). `ChatScreen._loadChatSettings()` loads it with the formatting switches, so it applies when the user comes back from Settings.
- `MessageBubble` shows a collapsed Reasoning row (`Key('reasoningToggle')`) above replies that have reasoning. `ChatScreen` remembers which replies are open, so they stay open while new messages arrive. The chat list is reversed, so opening long reasoning scrolls just enough to keep its row on screen, and closing puts the row back where it was.
- Validation: `flutter analyze` passes; `flutter test` passes (135 tests). Checked in the iOS Simulator (iPhone 17 Pro) with sample replies loaded into the chat history. Not checked yet: a real OpenRouter reply with reasoning.

### Issue #45 - Stream replies as they arrive
- `AiProvider` has `streamChat` next to `sendChat`. Each event is the whole reply so far, and the last one is the finished reply. New providers and test fakes need both. `CustomServerProvider.streamChat` sends one event, because `/chat` returns one JSON reply. Test Connection still uses `sendChat`.
- `OpenAiCompatibleProvider.streamChat` sends `"stream": true` through `postEventStream` in `http_helper.dart`. It skips keep-alive comments like `: OPENROUTER PROCESSING`, decodes each event's `data:` as JSON, and stops at `[DONE]`. Errors before the stream use the same status checks as `postJson`. The 60-second timeout is the longest wait between two lines. A dropped connection is a `NetworkException` (http passes some mid-reply drops on as a `SocketException`), an error piece is a `ProviderUnavailableException`, and a stream with no answer is a `BadResponseException`.
- Streamed reasoning comes from `delta.reasoning`, `delta.reasoning_details` (the `text` of `reasoning.text` entries and the `summary` of `reasoning.summary` entries) or `delta.reasoning_content`. Each has its own buffer, because OpenRouter can send the same text in two of them. Until a `<think>` at the start of the content closes, the rest is reasoning so far. The finished reply is what `parseReply` returns for the same text.
- `ChatService.streamReply` yields the reply so far as assistant messages that share one `createdAt`, and saves once, at the end. `getReply` is `streamReply(...).last`.
- `ChatScreen` keeps the arriving reply in `_liveReply` and moves it into `_messages` when it finishes. It shows once it has some of the answer, or reasoning while Show reasoning is on. Until then the typing line shows, and it reads "Sidekick is thinking…" while hidden reasoning arrives. An error removes the half-finished reply and keeps the user's message for Retry. `dispose` cancels the subscription, but the request only stops when its next piece arrives, because an `await for` in an `async*` function notices a cancel at its next `yield`. A Stop button will need to deal with that.
- `MessageBubble` treats a reply with reasoning but no answer yet as thinking: the row reads Thinking… with the seconds so far (Thinking… 12s), stays open, and can't be tapped. When the answer starts, it's the usual collapsed Reasoning row.
- In widget tests, a fake provider hands out pieces from a `StreamController`. Call `tester.pump(Duration.zero)` after each piece, because a plain `pump()` doesn't draw when no frame is scheduled.
- Validation: `flutter analyze` passes; `flutter test` passes (165 tests). Checked in the iOS Simulator (iPhone 17 Pro) against a local mock of OpenRouter's stream: streamed reasoning with Show reasoning on and off, a long answer, an error piece and a dropped connection. Not checked yet: a real provider stream.

### Multi-conversation chat
- Added immutable Conversation / ConversationState models, a FileConversationStore and a serialized ConversationService. Each chat has its own ID, title, timestamps and capped 500-message history. Titles use the first user message (whitespace normalized, 60 Unicode code points); explicit renames are preserved.
- `conversations.json` in application documents stores the conversations and active ID in an atomic temporary-file/rename snapshot. First use migrates `chat_history.json`; only after a successful replacement write is the old file removed. Invalid existing history stays untouched and the UI offers Retry loading chats.
- The chat drawer offers New chat, switch, Rename, confirmed Delete, and confirmed Delete all conversations. Deleting the final chat creates a fresh empty chat. Settings → Chat History retains Clear chat for the active conversation and adds Delete all conversations.
- ChatService now injects ConversationStore. Reply persistence captures the originating ID and revision; deleting/clearing a chat invalidates late saves. Conversation changes are disabled in the UI during streaming; new chats clear drafts and speech callbacks are scoped to the current view. Providers and personalities remain global. Streaming, reasoning, formatting and retry behavior are retained.
- Only the active chat's newest 20 messages are sent to the provider. Last active conversation is restored on startup. No database or new dependencies.
- Test coverage includes JSON round trips, migration, corrupt-file preservation, limits, serialized operations, failed writes, reply routing after selection/deletion, restart restoration, and UI rename/delete confirmations. Manual device relaunch and real-provider testing remain recommended.

### Streaming scroll quality of life
- The reversed chat viewport separates the live reply into an exactly measured sliver ahead of lazy message history. AnchoredReplySliver compensates for live extent changes when the user has scrolled away, preserving the message being read without relying on estimated list extents.
- A Jump to latest button appears more than 40 pixels from the latest end. Tapping returns to offset zero and resumes following. Switching chats resets scroll state. Existing manual reasoning expansion retains its own scroll adjustment.
- Widget tests measure old messages' on-screen positions through streaming answer/reasoning growth, completion/failure, jump-to-latest, and conversation changes.

### Stop generation
- During a request, Send becomes a Stop generating button. Stop signals a request-specific GenerationControl, aborts supported HTTP requests, and ends the UI stream promptly even before the first chunk.
- Received answer text (with reasoning when present) is saved once in the originating conversation. Stopping before answer text leaves only the user message. Late chunks from stopped requests cannot enter subsequent requests.
- AiProvider sendChat/streamChat now accept optional abortTrigger; HTTP streaming and custom-server requests use AbortableRequest when supplied. Provider implementations/fakes must accept this optional parameter.
### Issue #27 - Model selection per provider
- `AiProviderType` has `defaultModel` and `suggestedModels`, with the default first. The provider classes take their default from there, and `test/ai/ai_provider_test.dart` checks that the two match. The custom server has neither, because the server picks its own model.
- The suggested IDs were copied from each provider's models page on 2026-09-28. OpenRouter: `openrouter/free`, `openai/gpt-6-luna`, `deepseek/deepseek-v4-flash`, `google/gemini-3.5-flash-lite`, `anthropic/claude-sonnet-5.5`. OpenAI: `gpt-6-luna`, `gpt-6-sol`, `gpt-6-astra`. Groq: `openai/gpt-oss-20b`, `openai/gpt-oss-120b`, `qwen/qwen3.8-27b`. Groq retired its Llama models for free and developer keys on 2026-08-16, so they aren't suggested. Names change often, so check the list when a suggested model stops working.
- `sendChat` and `streamChat` take an optional `model`, where null means the provider's default. `OpenAiCompatibleProvider` sends `model ?? this.model`, and `CustomServerProvider` ignores it. New providers and test fakes need the parameter too.
- `AppSettingsStore.loadModel` and `saveModel` keep one model per provider under `ai.model.<type.name>`. Null or blank removes the key, which means the default. Picking the default in AI Settings removes it too, so the provider follows the built-in default if that changes.
- `ChatService` sends the model saved for the selected provider with every reply. `ProviderConnectionService` now takes the settings store and tests with the same model, so Test Connection checks what chat will use.
- AI Settings has a Model menu (`DropdownMenu<String>`) under the provider, except for the custom server, which says "The custom server picks its own model." instead. The menu lists the suggested models, the saved model if it isn't one of them, and Custom…, which opens a Model ID field. "Larger models may cost more." sits under it. Reset to default clears the saved model.
- Custom… focuses its field through a `FocusNode`. `autofocus` doesn't work there, because the menu gives the focus back to itself before it calls `onSelected`.
- All models opens `ModelListScreen`: every chat model from the provider's `GET {baseUrl}/models`, sorted, with a search field. It goes through `ModelListService` (a `ModelLister`, passed down like `ConnectionTester`) to `OpenAiCompatibleProvider.listModels`. OpenRouter's list is public (`publicModelList`), so it works without a key. OpenAI and Groq need the saved key. When the list can't load, the page shows the suggested models and says why.
- The list leaves out models that can't chat. OpenRouter's entries say what each model writes (`architecture.output_modalities`), and its `:batch` entries only work through its Batch API. OpenAI and Groq don't say, so IDs with words like `whisper`, `tts`, `embedding`, `image`, `realtime` or `guard` are left out (`_nonChatWords`), along with Groq's `"active": false` models. A model the filter misses fails with the usual error when it's asked.
- More replies count as `ModelNotAvailableException`: OpenRouter's 400 "… is not a valid model ID", its 404s (an unknown model, or no endpoint the account's privacy settings allow), and Groq's 400 `model_decommissioned`. In chat, that error's Settings button now opens AI Settings, where the model is picked. Key and custom server errors still open API Credentials.
- Validation: `flutter analyze` passes; `flutter test` passes (200 tests). A test failed for each of 26 pieces broken on purpose. Checked in the iOS Simulator (iPhone 17 Pro): the picker for each provider, Custom…, Reset to default, OpenRouter's live list (387 models) with search, and the fallback without a Groq key. OpenAI's list fell back there too, because the saved key got a 401/403 from `GET /v1/models`. Not checked yet: a chat reply with a chosen model and a real key, OpenAI's and Groq's live lists with keys that can list models, and OpenRouter's real reply to a bad model ID (the 400 shape comes from public reports as of June 2026).
