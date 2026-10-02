import 'package:flutter/material.dart';

class ChatHeader extends StatelessWidget {
  const ChatHeader({super.key, required this.onSettingsTap, this.onChatsTap});
  final VoidCallback? onSettingsTap;
  final VoidCallback? onChatsTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
    // A Row, so large text shortens the title instead of covering the
    // buttons.
    child: Row(
      children: <Widget>[
        IconButton(
          key: const Key('chatsButton'),
          tooltip: 'Conversations',
          onPressed: onChatsTap,
          icon: const Icon(Icons.menu_rounded),
        ),
        // The menu button is 4 px narrower than Settings. This keeps the
        // title in the middle of the screen.
        const SizedBox(width: 4),
        Expanded(
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const CircleAvatar(
                  radius: 24,
                  backgroundColor: Color(0xFFFFD99B),
                  child: Text('✨', style: TextStyle(fontSize: 25)),
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    'Cozy Sidekick',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
        ),
        IconButton.filledTonal(
          key: const Key('settingsButton'),
          onPressed: onSettingsTap,
          icon: const Icon(Icons.settings_rounded),
          tooltip: 'Settings',
          iconSize: 27,
          constraints: const BoxConstraints(minWidth: 52, minHeight: 52),
        ),
      ],
    ),
  );
}
