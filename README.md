# Cozy Sidekick

Cozy Sidekick is a Flutter chat app for iOS and Android. You bring your own AI provider, and you choose the sidekick's personality. Chats, personalities and settings are stored on the device. API keys are kept in the platform's secure storage.

## Features

- **Choose your provider.** Use OpenRouter, OpenAI, Groq or your own HTTP(S) chat server. You can switch providers at any time without restarting the app.
- **Choose a model for each provider.** Pick a suggested model, type any model ID, or search the provider's full model list.
- **Free-quota auto-routing.** Set up an ordered list of free routes (OpenRouter free models, Groq, and OpenAI's daily free tokens). The app sends each message to the first route that still has quota left. Each route can have its own daily limit, and the app shows how much of it is used and when it resets.
- **Streaming replies.** Replies appear as they arrive. A Stop button ends a reply early and keeps what has arrived so far, and Jump to latest returns you to the newest message.
- **Model reasoning.** Turn on Show reasoning to see a collapsible Reasoning section on replies from models that share their thinking.
- **Markdown and math.** Replies are formatted with Markdown and LaTeX. Long-press a reply to copy the original text.
- **Personalities.** Start from the presets (Cozy, Curious, Adventure, Planner, Captain Quip) or write your own system instructions. You can switch personalities during a session or choose which one the app starts with.
- **Multiple conversations.** Start, switch, rename and delete chats from the drawer. Only the newest 20 messages of the current chat are sent to the provider.
- **Voice.** Dictate messages with speech-to-text, and choose to send them automatically when you stop speaking. Replies can be read aloud with your choice of device voice, language and speed.
- **Friendly errors.** Network, key, rate-limit and model-access problems appear as plain messages, with a button to the setting that fixes them.

## Providers

| Provider | Default model | Key | Notes |
| --- | --- | --- | --- |
| [OpenRouter](https://openrouter.ai/keys) | `openrouter/free` | API key | The default on a new install. Free models have a daily request quota. |
| [OpenAI](https://platform.openai.com/api-keys) | `gpt-6-luna` | API key | Needs account credit. The project's model allowlist must include the model you pick. |
| [Groq](https://console.groq.com/keys) | `openai/gpt-oss-20b` | API key | Free tier with rate limits that vary by model. |
| Custom server | Chosen by the server | Access token | Any HTTP(S) server that implements the contract below. |

### Custom server contract

The app sends `POST {baseUrl}/chat` with `Authorization: Bearer <token>`:

```json
{
  "messages": [
    { "role": "system", "content": "<personality instructions>" },
    { "role": "user", "content": "Hi!" },
    { "role": "assistant", "content": "Hello!" },
    { "role": "user", "content": "What's new?" }
  ]
}
```

It expects a JSON reply that contains `message` and may also contain `reasoning`:

```json
{ "message": "Not much!", "reasoning": "optional" }
```

## Getting started

### Requirements

- Flutter (stable channel) with Dart 3.13.3 or later
- Xcode and CocoaPods for iOS (iOS 15.0 or later)
- Android Studio or the Android SDK for Android

### Run the app

```bash
git clone https://github.com/scotty2hottyy/cozy_sidekick.git
```

```bash
cd cozy_sidekick
```

```bash
flutter pub get
```

```bash
flutter run
```

### Set up in the app

1. Open **Settings → API Credentials**, paste a key for your provider, and tap **Test Connection**.
2. Open **Settings → AI Settings** to choose the provider and model. You can also turn on **Auto-route to free quota** there.
3. Optional: change the personality in **Settings → Personality** and the voice options in **Settings → Voice & Speech**.

No keys are included in the repository, and the app never displays or logs a saved key.

### Install the Android build

Each merge to `main` builds a release APK. To install it, open the latest successful run of the **Android CI** workflow under the repository's [Actions](https://github.com/scotty2hottyy/cozy_sidekick/actions) tab and download `app-release.apk`. Only the newest APK is kept, for 14 days.

## Settings

| Screen | What it controls |
| --- | --- |
| AI Settings | Provider, model, auto-routing and its routes, Show reasoning |
| API Credentials | Keys for each provider, the custom server URL and token, Test Connection |
| Personality | Presets, saved personalities, the current personality and the startup default |
| Voice & Speech | Dictation language, send when done, read-aloud mode, voice and speed |
| Appearance | Format replies, Show math, Dollar-sign math |
| Chat History | Clear the current chat, delete all conversations |

## Where data is stored

| Data | Storage |
| --- | --- |
| API keys and the custom server token | `flutter_secure_storage` (Keychain on iOS, Keystore on Android) |
| Conversations (up to 500 messages each) | `conversations.json` in the app's documents folder |
| Settings, personalities, routes and daily usage | `shared_preferences` |

Nothing is synced off the device except the messages you send to your chosen provider.

## Project structure

```
lib/
  ai/          Provider interface, the OpenAI-compatible base, each provider, the auto-router, HTTP helpers
  models/      Messages, conversations, personalities, quota routes, formatting and speech settings
  services/    Chat, conversation storage, settings, keys, model lists, quotas, usage, speech and text-to-speech
  screens/     Chat, Settings and each settings screen
  widgets/     Message bubbles, formatted replies, the composer and the chat header
test/          Unit and widget tests, organized the same way as lib/
```

`AI_passdown.md` has detailed notes on each feature and the decisions behind it. Read it before you change an area.

## Development

### Checks

```bash
flutter analyze
```

```bash
flutter test
```

```bash
dart format lib test
```

CI runs `flutter analyze` and `flutter test` on every pull request to `main`. It does not check formatting, so run `dart format` before you push.

### Workflow

1. Each change starts as an issue on the Cozy Sidekick project board, written as Card, Conversation and Confirmation.
2. Create a branch named `<type>/<issue#>-<description>`, for example `feature/27-model-selection-per-provider` or `bugfix/40-model-access-errors`.
3. Open a pull request that says `Closes #<issue>`, and complete the Definition of Done in the PR template. That includes tests for new behavior, no keys in the diff or logs, a teammate's review, and an updated `AI_passdown.md`.
4. The product owner runs the card's Confirmation tests on the branch before it is merged.
