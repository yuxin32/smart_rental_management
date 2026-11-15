import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../communication/data/chat_service.dart';
import '../../../communication/presentation/widgets/chat_conversation_view.dart';

class TenantChatPage extends StatelessWidget {
  const TenantChatPage({required this.conversation, super.key});

  final ChatConversationSummary conversation;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 21),
        ),
        titleSpacing: 0,
        title: Row(
          children: [
            CircleAvatar(
              radius: 21,
              backgroundColor: const Color(0xFFE0E7FF),
              child: Text(
                conversation.initials,
                style: const TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    conversation.otherPartyName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.heading,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Text(
                    'Apartment administrator',
                    style: TextStyle(color: AppColors.body, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: ChatConversationView(conversation: conversation),
    );
  }
}
