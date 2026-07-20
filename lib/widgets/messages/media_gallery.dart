import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/message.dart';
import '../../models/message_attachment.dart';
import '../../services/service_locator.dart';
import '../../theme/theme.dart';

/// A grid view of all shared media (images + files) in a conversation
class MediaGallery extends StatelessWidget {
  final String conversationId;

  const MediaGallery({super.key, required this.conversationId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Message>>(
      stream: ServiceLocator.messageService.getMessages(conversationId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final messages = snapshot.data ?? [];
        final allAttachments = <_AttachmentEntry>[];

        for (final message in messages) {
          if (message.isDeleted) continue;
          for (final attachment in message.attachments) {
            allAttachments.add(_AttachmentEntry(
              attachment: attachment,
              senderName: message.senderName,
              timestamp: message.timestamp,
            ));
          }
        }

        if (allAttachments.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.image_not_supported_outlined,
                    size: 48, color: AppColors.textTertiary),
                const SizedBox(height: 12),
                Text(
                  'No shared media',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ],
            ),
          );
        }

        // Split into images and files
        final images =
            allAttachments.where((e) => e.attachment.isImage).toList();
        final files =
            allAttachments.where((e) => !e.attachment.isImage).toList();

        return DefaultTabController(
          length: 2,
          child: Column(
            children: [
              const TabBar(
                tabs: [
                  Tab(text: 'Images'),
                  Tab(text: 'Files'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    // Images grid
                    images.isEmpty
                        ? Center(
                            child: Text('No images',
                                style: TextStyle(color: AppColors.textSecondary)))
                        : GridView.builder(
                            padding: const EdgeInsets.all(AppSpacing.sm),
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              mainAxisSpacing: 4,
                              crossAxisSpacing: 4,
                            ),
                            itemCount: images.length,
                            itemBuilder: (context, index) {
                              final entry = images[index];
                              return GestureDetector(
                                onTap: () => _showImageViewer(
                                  context,
                                  entry.attachment.fileUrl,
                                  entry.attachment.fileName,
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: CachedNetworkImage(
                                    imageUrl: entry.attachment.thumbnailUrl ?? entry.attachment.fileUrl,
                                    fit: BoxFit.cover,
                                    errorWidget: (_, __, ___) => Container(
                                      color: AppColors.cardBorder,
                                      child: const Icon(Icons.broken_image),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),

                    // Files list
                    files.isEmpty
                        ? Center(
                            child: Text('No files',
                                style: TextStyle(color: AppColors.textSecondary)))
                        : ListView.builder(
                            itemCount: files.length,
                            itemBuilder: (context, index) {
                              final entry = files[index];
                              final a = entry.attachment;
                              return ListTile(
                                leading: Icon(
                                  a.isPdf
                                      ? Icons.picture_as_pdf
                                      : Icons.insert_drive_file,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                                title: Text(
                                  a.fileName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  '${entry.senderName} · ${a.formattedSize}',
                                  style: const TextStyle(fontSize: 12),
                                ),
                                trailing: const Icon(Icons.download, size: 20),
                                onTap: () => launchUrl(
                                  Uri.parse(a.fileUrl),
                                  mode: LaunchMode.externalApplication,
                                ),
                              );
                            },
                          ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  static void _showImageViewer(
    BuildContext context,
    String url,
    String fileName,
  ) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black87,
        barrierDismissible: true,
        pageBuilder: (_, __, ___) => Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            foregroundColor: Colors.white,
            title: Text(fileName, style: const TextStyle(fontSize: 14)),
            actions: [
              IconButton(
                icon: const Icon(Icons.download_rounded),
                onPressed: () => launchUrl(
                  Uri.parse(url),
                  mode: LaunchMode.externalApplication,
                ),
                tooltip: 'Download',
              ),
            ],
          ),
          body: GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Center(
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 4.0,
                child: CachedNetworkImage(
                  imageUrl: url,
                  fit: BoxFit.contain,
                  progressIndicatorBuilder: (_, __, progress) => Center(
                    child: CircularProgressIndicator(
                      value: progress.progress,
                      color: Colors.white,
                    ),
                  ),
                  errorWidget: (_, __, ___) => const Icon(
                    Icons.broken_image,
                    size: 64,
                    color: Colors.white54,
                  ),
                ),
              ),
            ),
          ),
        ),
        transitionsBuilder: (_, animation, __, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }
}

class _AttachmentEntry {
  final MessageAttachment attachment;
  final String senderName;
  final DateTime timestamp;

  _AttachmentEntry({
    required this.attachment,
    required this.senderName,
    required this.timestamp,
  });
}
