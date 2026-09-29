import 'package:flutter/material.dart';

class ChatHeader extends StatelessWidget {
  const ChatHeader({super.key, required this.onSettingsTap, this.onChatsTap});
  final VoidCallback? onSettingsTap;
  final VoidCallback? onChatsTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
    child: Stack(
      alignment: Alignment.center,
      children: <Widget>[
        Align(
          alignment: Alignment.centerLeft,
          child: IconButton(
            key: const Key('chatsButton'),
            tooltip: 'Conversations',
            onPressed: onChatsTap,
            icon: const Icon(Icons.menu_rounded),
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: IconButton.filledTonal(
            key: const Key('settingsButton'),
            onPressed: onSettingsTap,
            icon: const Icon(Icons.settings_rounded),
            tooltip: 'Settings',
            iconSize: 27,
            constraints: const BoxConstraints(minWidth: 52, minHeight: 52),
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const CircleAvatar(
              radius: 24,
              backgroundColor: Color(0xFFFFD99B),
              child: Text('✨', style: TextStyle(fontSize: 25)),
            ),
            const SizedBox(width: 10),
            Text(
              'Cozy Sidekick',
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ],
    ),
  );
}
