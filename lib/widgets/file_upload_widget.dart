import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/service_locator.dart';
import '../services/supabase/storage_service.dart';
import '../theme/theme.dart';

class FileUploadWidget extends StatefulWidget {
  final String workspaceId;
  final String projectId;
  final String? taskId;
  final List<String>? tags;
  final String uploadedBy;
  final VoidCallback? onUploadComplete;

  const FileUploadWidget({
    super.key,
    required this.workspaceId,
    required this.projectId,
    this.taskId,
    this.tags,
    required this.uploadedBy,
    this.onUploadComplete,
  });

  @override
  State<FileUploadWidget> createState() => _FileUploadWidgetState();
}

class _FileUploadWidgetState extends State<FileUploadWidget> {
  final _storageService = ServiceLocator.storageService;
  final ImagePicker _imagePicker = ImagePicker();

  bool _isUploading = false;
  double _uploadProgress = 0.0;
  String? _errorMessage;
  int _totalUploads = 0;
  int _completedUploads = 0;
  String? _currentUploadFileName;

  Future<void> _pickAndUploadFile() async {
    try {
      setState(() {
        _errorMessage = null;
      });

      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: [
          'jpg',
          'jpeg',
          'png',
          'pdf',
          'doc',
          'docx',
          'xls',
          'xlsx',
        ],
        allowMultiple: true,
      );

      if (result != null && result.files.isNotEmpty) {
        await _uploadFiles(result.files);
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error picking file: $e';
      });
    }
  }

  Future<void> _pickAndUploadImage() async {
    try {
      setState(() {
        _errorMessage = null;
      });

      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 2048,
        maxHeight: 2048,
      );

      if (image != null) {
        final file = PlatformFile(
          name: image.name,
          size: await image.length(),
          path: image.path,
          bytes: kIsWeb ? await image.readAsBytes() : null,
        );
        await _uploadFiles([file]);
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error picking image: $e';
      });
    }
  }

  Future<void> _pickAndUploadCamera() async {
    if (kIsWeb) {
      setState(() {
        _errorMessage = 'Camera is not available on web';
      });
      return;
    }

    try {
      setState(() {
        _errorMessage = null;
      });

      final XFile? photo = await _imagePicker.pickImage(
        source: ImageSource.camera,
        maxWidth: 2048,
        maxHeight: 2048,
      );

      if (photo != null) {
        final file = PlatformFile(
          name: photo.name,
          size: await photo.length(),
          path: photo.path,
        );
        await _uploadFiles([file]);
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error taking photo: $e';
      });
    }
  }

  Future<void> _uploadFiles(List<PlatformFile> files) async {
    if (files.isEmpty) return;

    setState(() {
      _isUploading = true;
      _uploadProgress = 0.0;
      _errorMessage = null;
      _totalUploads = files.length;
      _completedUploads = 0;
      _currentUploadFileName = files.first.name;
    });

    final failedUploads = <String>[];

    for (var i = 0; i < files.length; i++) {
      final platformFile = files[i];

      setState(() {
        _currentUploadFileName = platformFile.name;
      });

      try {
        await _uploadFile(
          platformFile,
          onProgress: (progress) {
            if (!mounted) return;
            setState(() {
              _uploadProgress = (i + progress) / files.length;
            });
          },
        );
      } on StorageQuotaExceededException catch (e) {
        // Stop all uploads immediately on quota exceeded
        failedUploads.add(e.toString());
        break;
      } catch (e) {
        failedUploads.add('${platformFile.name}: $e');
      }

      if (!mounted) return;

      setState(() {
        _completedUploads = i + 1;
        _uploadProgress = (i + 1) / files.length;
      });
    }

    final successfulUploads = files.length - failedUploads.length;

    setState(() {
      _isUploading = false;
      _uploadProgress = 0.0;
      _errorMessage = failedUploads.isEmpty ? null : failedUploads.join('\n');
      _totalUploads = 0;
      _completedUploads = 0;
      _currentUploadFileName = null;
    });

    if (!mounted) return;

    if (successfulUploads > 0) {
      widget.onUploadComplete?.call();
    }

    if (failedUploads.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            successfulUploads == 1
                ? 'File uploaded successfully'
                : '$successfulUploads files uploaded successfully',
          ),
          backgroundColor: AppColors.success,
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          successfulUploads == 0
              ? 'All ${files.length} uploads failed'
              : 'Uploaded $successfulUploads of ${files.length} files',
        ),
        backgroundColor: successfulUploads == 0
            ? AppColors.error
            : AppColors.warning,
      ),
    );
  }

  Future<void> _uploadFile(
    PlatformFile platformFile, {
    Function(double)? onProgress,
  }) async {
    if (kIsWeb) {
      // On web, use bytes
      if (platformFile.bytes == null) {
        throw Exception('File bytes are null');
      }

      await _storageService.uploadFileBytes(
        bytes: platformFile.bytes!,
        fileName: platformFile.name,
        workspaceId: widget.workspaceId,
        projectId: widget.projectId,
        taskId: widget.taskId,
        tags: widget.tags,
        uploadedBy: widget.uploadedBy,
        onProgress: onProgress,
      );
    } else {
      // On mobile/desktop, use file path
      if (platformFile.path == null) {
        throw Exception('File path is null');
      }

      final file = File(platformFile.path!);

      await _storageService.uploadFile(
        file: file,
        fileName: platformFile.name,
        workspaceId: widget.workspaceId,
        projectId: widget.projectId,
        taskId: widget.taskId,
        tags: widget.tags,
        uploadedBy: widget.uploadedBy,
        onProgress: onProgress,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isUploading) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.base),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _totalUploads > 1
                    ? 'Uploading ${_completedUploads + 1} of $_totalUploads'
                    : 'Uploading...',
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(value: _uploadProgress),
              const SizedBox(height: 8),
              if (_currentUploadFileName != null)
                Text(
                  _currentUploadFileName!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              if (_currentUploadFileName != null) const SizedBox(height: 8),
              Text('${(_uploadProgress * 100).toStringAsFixed(0)}%'),
            ],
          ),
        ),
      );
    }

    final canUpload = context.watch<AuthProvider>().canUploadFiles;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: SelectableText(
                  _errorMessage!,
                  style: TextStyle(color: AppColors.error),
                ),
              ),
            Wrap(
              spacing: 8.0,
              runSpacing: 8.0,
              alignment: WrapAlignment.center,
              children: [
                ElevatedButton.icon(
                  onPressed: canUpload ? _pickAndUploadFile : null,
                  icon: const Icon(Icons.attach_file),
                  label: const Text('Choose Files'),
                ),
                ElevatedButton.icon(
                  onPressed: canUpload ? _pickAndUploadImage : null,
                  icon: const Icon(Icons.photo_library),
                  label: const Text('Photo Library'),
                ),
                if (!kIsWeb)
                  ElevatedButton.icon(
                    onPressed: canUpload ? _pickAndUploadCamera : null,
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('Camera'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Max size: 10MB. Supported: JPG, PNG, PDF, DOC, XLS',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
