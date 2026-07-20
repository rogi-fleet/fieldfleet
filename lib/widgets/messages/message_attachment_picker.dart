import 'package:flutter/material.dart';
import 'package:taskfleet_ops/utils/user_facing_error.dart';
import 'package:file_picker/file_picker.dart';
import '../../models/message_attachment.dart';
import '../../services/attachment_service.dart';
import '../../theme/theme.dart';

/// Widget to select and preview files before sending
class MessageAttachmentPicker extends StatefulWidget {
  final String conversationId;
  final String workspaceId;
  final Function(List<MessageAttachment>) onAttachmentsReady;

  const MessageAttachmentPicker({
    super.key,
    required this.conversationId,
    required this.workspaceId,
    required this.onAttachmentsReady,
  });

  @override
  State<MessageAttachmentPicker> createState() =>
      _MessageAttachmentPickerState();
}

class _MessageAttachmentPickerState extends State<MessageAttachmentPicker> {
  final AttachmentService _attachmentService = AttachmentService();
  final List<PlatformFile> _selectedFiles = [];
  final List<MessageAttachment> _uploadedAttachments = [];
  final Map<String, double> _uploadProgress = {};
  bool _isUploading = false;

  Future<void> _pickFiles() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.any,
      );

      if (result != null) {
        setState(() {
          _selectedFiles.addAll(result.files);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              UserFacingError.uiMessage(e, action: 'picking files'),
            ),
          ),
        );
      }
    }
  }

  Future<void> _uploadFiles() async {
    if (_selectedFiles.isEmpty) return;

    setState(() {
      _isUploading = true;
    });

    try {
      final uploadedFiles = <MessageAttachment>[];

      for (final file in _selectedFiles) {
        final attachment = await _attachmentService.uploadFile(
          file: file.bytes ?? file.path!,
          fileName: file.name,
          mimeType: file.extension != null
              ? _getMimeType(file.extension!)
              : 'application/octet-stream',
          conversationId: widget.conversationId,
          workspaceId: widget.workspaceId,
          onProgress: (progress) {
            setState(() {
              _uploadProgress[file.name] = progress;
            });
          },
        );
        uploadedFiles.add(attachment);
      }

      setState(() {
        _uploadedAttachments.addAll(uploadedFiles);
        _isUploading = false;
      });

      // Notify parent
      widget.onAttachmentsReady(_uploadedAttachments);

      // Clear selection
      setState(() {
        _selectedFiles.clear();
        _uploadProgress.clear();
      });
    } catch (e) {
      setState(() {
        _isUploading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              UserFacingError.uiMessage(e, action: 'uploading files'),
            ),
          ),
        );
      }
    }
  }

  void _removeFile(int index) {
    setState(() {
      _selectedFiles.removeAt(index);
    });
  }

  void _removeUploadedFile(int index) {
    setState(() {
      _uploadedAttachments.removeAt(index);
    });
    widget.onAttachmentsReady(_uploadedAttachments);
  }

  String _getMimeType(String extension) {
    switch (extension.toLowerCase()) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'pdf':
        return 'application/pdf';
      case 'doc':
        return 'application/msword';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      default:
        return 'application/octet-stream';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_selectedFiles.isEmpty && _uploadedAttachments.isEmpty) {
      return IconButton(
        icon: const Icon(Icons.attach_file),
        onPressed: _pickFiles,
        tooltip: 'Attach files',
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Show selected files (not yet uploaded)
        if (_selectedFiles.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${_selectedFiles.length} file(s) selected',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Row(
                      children: [
                        TextButton.icon(
                          onPressed: _pickFiles,
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text('Add more'),
                        ),
                        TextButton.icon(
                          onPressed: _isUploading ? null : _uploadFiles,
                          icon: _isUploading
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.upload, size: 16),
                          label: Text(_isUploading ? 'Uploading...' : 'Upload'),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ...List.generate(_selectedFiles.length, (index) {
                  final file = _selectedFiles[index];
                  final progress = _uploadProgress[file.name] ?? 0.0;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        Icon(_getFileIcon(file.extension ?? ''), size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                file.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (_isUploading && progress > 0)
                                LinearProgressIndicator(value: progress),
                            ],
                          ),
                        ),
                        if (!_isUploading)
                          IconButton(
                            icon: const Icon(Icons.close, size: 16),
                            onPressed: () => _removeFile(index),
                          ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        // Show uploaded attachments
        if (_uploadedAttachments.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            margin: const EdgeInsets.only(top: 8),
            decoration: BoxDecoration(
              color: AppColors.successLight,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(color: AppColors.success),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_uploadedAttachments.length} file(s) ready to send',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.success,
                  ),
                ),
                const SizedBox(height: 8),
                ...List.generate(_uploadedAttachments.length, (index) {
                  final attachment = _uploadedAttachments[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        Icon(
                          attachment.isImage
                              ? Icons.image
                              : Icons.insert_drive_file,
                          size: 20,
                          color: AppColors.success,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            attachment.fileName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 16),
                          onPressed: () => _removeUploadedFile(index),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
      ],
    );
  }

  IconData _getFileIcon(String extension) {
    switch (extension.toLowerCase()) {
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
        return Icons.image;
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'doc':
      case 'docx':
        return Icons.description;
      default:
        return Icons.insert_drive_file;
    }
  }
}
