import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/project.dart';
import '../../providers/auth_provider.dart';
import '../../providers/workspace_provider.dart';
import '../../services/ai_service.dart';
import '../../services/ai_generation_service.dart';
import '../../services/service_locator.dart';
import '../../widgets/ai/ai_project_setup_wizard.dart';
import '../../widgets/ai/ai_wizard_dialog.dart';
import '../../widgets/ai_persona_picker.dart';
import '../../theme/theme.dart';

/// Full-page screen shown when the user taps an ai_plan_ready notification.
///
/// Loads the persisted plan from ai_generated_plans, fetches the project,
/// then opens the AI wizard in review mode (skipping the generate step).
class AiPlanReviewScreen extends StatefulWidget {
  final String projectId;
  final String planId;

  const AiPlanReviewScreen({
    super.key,
    required this.projectId,
    required this.planId,
  });

  @override
  State<AiPlanReviewScreen> createState() => _AiPlanReviewScreenState();
}

class _AiPlanReviewScreenState extends State<AiPlanReviewScreen> {
  final _supabase = Supabase.instance.client;

  _LoadState _state = _LoadState.loading;
  String? _errorMessage;
  Project? _project;
  AiProjectPlan? _plan;
  bool _wizardOpened = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _state = _LoadState.loading;
      _errorMessage = null;
    });

    try {
      // Fetch the plan row
      final planRow = await _supabase
          .from('ai_generated_plans')
          .select()
          .eq('id', widget.planId)
          .single();

      final status = planRow['status'] as String;

      if (status == 'failed') {
        setState(() {
          _state = _LoadState.failed;
          _errorMessage = planRow['error_message'] as String? ??
              'An unknown error occurred.';
        });
        return;
      }

      if (status == 'generating') {
        // Still running — poll via realtime subscription handled below
        setState(() => _state = _LoadState.generating);
        _subscribeToStatusUpdates();
        return;
      }

      // status == 'ready'
      final planJson = planRow['plan_json'] as Map<String, dynamic>?;
      if (planJson == null) {
        setState(() {
          _state = _LoadState.failed;
          _errorMessage = 'Plan data is missing.';
        });
        return;
      }

      // Fetch the project
      final project = await ServiceLocator.projectService.getProject(
        widget.projectId,
      ) as Project?;

      if (project == null) {
        setState(() {
          _state = _LoadState.failed;
          _errorMessage = 'Could not load project.';
        });
        return;
      }

      setState(() {
        _project = project;
        _plan = AiProjectPlan.fromJson(planJson);
        _state = _LoadState.ready;
      });
    } catch (e) {
      setState(() {
        _state = _LoadState.failed;
        _errorMessage = e.toString();
      });
    }
  }

  RealtimeChannel? _channel;

  void _subscribeToStatusUpdates() {
    _channel = _supabase
        .channel('ai_plan_${widget.planId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'ai_generated_plans',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: widget.planId,
          ),
          callback: (payload) {
            final newStatus = payload.newRecord['status'] as String?;
            if (newStatus == 'ready' || newStatus == 'failed') {
              _channel?.unsubscribe();
              _load();
            }
          },
        )
        .subscribe();
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    super.dispose();
  }

  Future<void> _retry() async {
    final authProvider = context.read<AuthProvider>();
    final appUser = authProvider.appUser;
    if (appUser == null || _project == null) return;

    try {
      await AiGenerationService.instance.generateInBackground(
        project: _project!,
        workspaceId: appUser.currentWorkspaceId,
        userId: appUser.id,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Retrying plan generation. You\'ll be notified when ready.'),
        ),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to retry: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Once ready, open the wizard dialog on top of this screen (once only)
    if (_state == _LoadState.ready && !_wizardOpened) {
      _wizardOpened = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _openWizard());
    }

    return Scaffold(
      appBar: AppBar(title: const Text('AI Plan')),
      body: switch (_state) {
        _LoadState.loading => const Center(child: CircularProgressIndicator()),
        _LoadState.generating => const _GeneratingView(),
        _LoadState.failed => _FailedView(
            message: _errorMessage ?? 'Something went wrong.',
            onRetry: _project != null ? _retry : null,
          ),
        _LoadState.ready => const Center(child: CircularProgressIndicator()),
      },
    );
  }

  void _openWizard() {
    if (!mounted || _project == null || _plan == null) return;
    final appUser = context.read<AuthProvider>().appUser;
    final workspaceId = appUser?.currentWorkspaceId ?? widget.projectId;

    final ws = context.read<WorkspaceProvider>().activeWorkspace;
    final emoji = kPersonaAvatarEmojis[ws?.aiPersonaAvatar ?? 'hard_hat'] ?? '🤖';
    final avatarAssetPath =
        kPersonaAvatars[ws?.aiPersonaAvatar ?? 'hard_hat'] ??
        'assets/images/avatars/robot.png';
    showAiWizardDialog(
      context,
      title: 'Review AI Plan',
      personaEmoji: emoji,
      personaAvatarAssetPath: avatarAssetPath,
      width: 750,
      child: AiProjectSetupWizard(
        project: _project!,
        workspaceId: workspaceId,
        initialPlan: _plan,
        onComplete: () => Navigator.of(context).pop(),
      ),
    );
  }
}

enum _LoadState { loading, generating, ready, failed }

class _GeneratingView extends StatelessWidget {
  const _GeneratingView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 20),
          Text(
            'Your AI plan is still generating…',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          const Text(
            'This page will update automatically when it\'s ready.',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _FailedView extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  const _FailedView({required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 56, color: AppColors.error),
            const SizedBox(height: 16),
            Text(
              'Plan generation failed',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(color: AppColors.error),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry in Background'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
