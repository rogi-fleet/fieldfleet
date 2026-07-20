import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

typedef AiProgressCallback = void Function(String providerName, String status);
typedef AiStreamCallback = void Function(
    String providerName, String delta, String accumulated);

/// Exception thrown when JSON parsing fails - can be retried
class JsonParseException implements Exception {
  final String message;
  final String? rawContent;

  JsonParseException(this.message, {this.rawContent});

  @override
  String toString() => 'JsonParseException: $message';
}

/// Persona context for personalizing AI responses
class AiPersonaContext {
  final String? name;
  final String?
      style; // preset slug: mentor|analyst|coach|concise|expert|custom
  final String? customStyle; // free-text when style == 'custom'
  final String? customContext; // workspace specialty/notes
  final String? workspaceName;
  final String? companyType;

  const AiPersonaContext({
    this.name,
    this.style,
    this.customStyle,
    this.customContext,
    this.workspaceName,
    this.companyType,
  });

  bool get hasPersona =>
      name != null ||
      (style != null && style != 'mentor') ||
      customContext != null;

  /// Returns the personality description for the selected style slug.
  static String? _personalityForStyle(String? style, String? customStyle) {
    switch (style) {
      case 'mentor':
        return 'You are The Experienced Mentor: calm authority, practical field examples, actionable guidance.';
      case 'analyst':
        return 'You are The Detail Analyst: structured responses with numbered risks, quantified estimates, and precise data.';
      case 'coach':
        return 'You are The Motivating Coach: upbeat, solutions-focused. Always end with a clear next step.';
      case 'concise':
        return 'You are The No-Nonsense Foreman: use the fewest words possible. Skip pleasantries entirely.';
      case 'expert':
        return 'You are The Technical Expert: cite industry codes and standards, always explain the "why" behind recommendations.';
      case 'custom':
        return customStyle?.isNotEmpty == true ? customStyle : null;
      default:
        return null;
    }
  }

  /// Build a persona block to prepend to system prompts.
  String buildPersonaBlock() {
    final parts = <String>[];

    if (workspaceName != null && companyType != null) {
      parts.add('You are assisting $workspaceName, a $companyType contractor.');
    } else if (workspaceName != null) {
      parts.add('You are assisting $workspaceName.');
    }

    if (name != null && name!.isNotEmpty) {
      parts.add('Your name is $name.');
    }

    final personality = _personalityForStyle(style, customStyle);
    if (personality != null) {
      parts.add('Personality: $personality');
    }

    if (customContext != null && customContext!.isNotEmpty) {
      parts.add('\nAdditional workspace context:\n$customContext');
    }

    return parts.join('\n');
  }
}

/// Project context for AI budget generation
class AiProjectContext {
  final String? projectName;
  final String? location; // Address/city for regional pricing
  final String? jobType; // e.g., "Renovation", "New Construction"
  final double? estimatedBudget;
  final double? materialMarkupPercent;
  final double? laborMarkupPercent;
  final String? currency; // ISO 4217 currency code (e.g., "USD", "CAD", "GBP")

  const AiProjectContext({
    this.projectName,
    this.location,
    this.jobType,
    this.estimatedBudget,
    this.materialMarkupPercent,
    this.laborMarkupPercent,
    this.currency,
  });

  bool get hasContext =>
      projectName != null ||
      location != null ||
      jobType != null ||
      estimatedBudget != null ||
      currency != null;
}

/// Configuration for AI providers
class AiProviderConfig {
  final String name;
  final String baseUrl;
  final String? model;
  final String? apiKey;
  final Map<String, String>? extraHeaders;
  final bool isLlamaServer;

  const AiProviderConfig({
    required this.name,
    required this.baseUrl,
    this.model,
    this.apiKey,
    this.extraHeaders,
    this.isLlamaServer = false,
  });
}

/// Generated budget item from AI
class AiBudgetItem {
  final String name;
  final double quantity;
  final String unit;
  final double unitCost;
  final double unitPrice;

  AiBudgetItem({
    required this.name,
    required this.quantity,
    required this.unit,
    required this.unitCost,
    required this.unitPrice,
  });

  factory AiBudgetItem.fromJson(Map<String, dynamic> json) {
    return AiBudgetItem(
      name: json['name'] as String? ?? 'Unknown Item',
      quantity: (json['quantity'] as num?)?.toDouble() ?? 1.0,
      unit: json['unit'] as String? ?? 'ea',
      unitCost: (json['unitCost'] as num?)?.toDouble() ??
          (json['unit_cost'] as num?)?.toDouble() ??
          0.0,
      unitPrice: (json['unitPrice'] as num?)?.toDouble() ??
          (json['unit_price'] as num?)?.toDouble() ??
          0.0,
    );
  }
}

/// AI-generated document draft content
class AiDocumentDraft {
  final String scopeContent;
  final String footerContent;
  final String emailSubject;
  final String emailMessage;

  const AiDocumentDraft({
    this.scopeContent = '',
    this.footerContent = '',
    this.emailSubject = '',
    this.emailMessage = '',
  });
}

/// Budget item input for task generation
class BudgetItemInput {
  final String id;
  final String name;
  final String? parentName; // Group name if this item is under a group
  final double? laborHours; // If unit is "hr", this is the quantity
  final String? unit;
  final double? quantity;

  BudgetItemInput({
    required this.id,
    required this.name,
    this.parentName,
    this.laborHours,
    this.unit,
    this.quantity,
  });

  Map<String, dynamic> toPromptJson() {
    return {
      'id': id,
      'name': name,
      if (parentName != null) 'group': parentName,
      if (laborHours != null) 'laborHours': laborHours,
      if (unit != null) 'unit': unit,
      if (quantity != null) 'quantity': quantity,
    };
  }
}

/// Input for property area context in AI task generation
class PropertyAreaInput {
  final String name;
  final String status;
  final bool isAffected;
  final String? trend;

  PropertyAreaInput({
    required this.name,
    required this.status,
    this.isAffected = false,
    this.trend,
  });
}

/// Generated task from AI
class AiGeneratedTask {
  final String tempId;
  final String title;
  final String? description;
  final String taskType; // "summary" or "standard"
  final String? parentTempId;
  final List<String> predecessorTempIds;
  final double? estimatedDuration; // in hours
  final String priority; // "high", "medium", "low"
  final List<String> checklistItems;
  final String? sourceBudgetItemId; // Link back to budget item
  final String? areaName; // Area name for property-based tasks
  bool isSelected;

  AiGeneratedTask({
    required this.tempId,
    required this.title,
    this.description,
    required this.taskType,
    this.parentTempId,
    this.predecessorTempIds = const [],
    this.estimatedDuration,
    this.priority = 'medium',
    this.checklistItems = const [],
    this.sourceBudgetItemId,
    this.areaName,
    this.isSelected = true,
  });

  bool get isSummary => taskType == 'summary';
  bool get isStandard => taskType == 'standard';

  factory AiGeneratedTask.fromJson(Map<String, dynamic> json) {
    return AiGeneratedTask(
      tempId: json['tempId'] as String? ?? json['id'] as String? ?? '',
      title: json['title'] as String? ?? 'Untitled Task',
      description: json['description'] as String?,
      taskType: json['taskType'] as String? ?? 'standard',
      parentTempId:
          json['parentTempId'] as String? ?? json['parentId'] as String?,
      predecessorTempIds:
          (json['predecessorTempIds'] as List?)?.cast<String>() ??
              (json['predecessorIds'] as List?)?.cast<String>() ??
              [],
      estimatedDuration: (json['estimatedDuration'] as num?)?.toDouble() ??
          (json['duration'] as num?)?.toDouble(),
      priority: json['priority'] as String? ?? 'medium',
      checklistItems: (json['checklistItems'] as List?)?.cast<String>() ??
          (json['checklist'] as List?)?.cast<String>() ??
          [],
      sourceBudgetItemId: json['sourceBudgetItemId'] as String? ??
          json['budgetItemId'] as String?,
      areaName: json['areaName'] as String?,
      isSelected: true,
    );
  }
}

/// AI-generated project plan
class AiProjectPlan {
  final List<AiProjectPhase> phases;
  final List<AiProjectProperty> properties;

  AiProjectPlan({required this.phases, this.properties = const []});

  Map<String, dynamic> toJson() => {
        'phases': phases.map((p) => p.toJson()).toList(),
        'properties': properties.map((p) => p.toJson()).toList(),
      };

  factory AiProjectPlan.fromJson(Map<String, dynamic> json) {
    final phasesList = json['phases'] as List? ?? [];
    return AiProjectPlan(
      phases: phasesList
          .asMap()
          .entries
          .map(
            (e) =>
                AiProjectPhase.fromJson(e.value as Map<String, dynamic>, e.key),
          )
          .toList(),
      properties: (json['properties'] as List? ?? [])
          .map((p) => AiProjectProperty.fromJson(p as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// A phase in an AI-generated project plan
class AiProjectPhase {
  final String tempId;
  final String name;
  final String? description;
  final int sortOrder;
  final List<AiPhaseTask> tasks;
  final List<AiPhaseBudgetItem> budgetItems;

  AiProjectPhase({
    required this.tempId,
    required this.name,
    this.description,
    required this.sortOrder,
    this.tasks = const [],
    this.budgetItems = const [],
  });

  Map<String, dynamic> toJson() => {
        'tempId': tempId,
        'name': name,
        if (description != null) 'description': description,
        'sortOrder': sortOrder,
        'tasks': tasks.map((t) => t.toJson()).toList(),
        'budgetItems': budgetItems.map((bi) => bi.toJson()).toList(),
      };

  factory AiProjectPhase.fromJson(Map<String, dynamic> json, int index) {
    return AiProjectPhase(
      tempId: json['tempId'] as String? ?? 'phase_$index',
      name: json['name'] as String? ?? 'Phase ${index + 1}',
      description: json['description'] as String?,
      sortOrder: json['sortOrder'] as int? ?? index,
      tasks: (json['tasks'] as List?)
              ?.asMap()
              .entries
              .map(
                (e) => AiPhaseTask.fromJson(
                  e.value as Map<String, dynamic>,
                  'phase_${index}_task_${e.key}',
                ),
              )
              .toList() ??
          [],
      budgetItems: (json['budgetItems'] as List?)
              ?.asMap()
              .entries
              .map(
                (e) => AiPhaseBudgetItem.fromJson(
                  e.value as Map<String, dynamic>,
                  'phase_${index}_bi_${e.key}',
                ),
              )
              .toList() ??
          [],
    );
  }
}

/// A task within a phase of an AI project plan
class AiPhaseTask {
  final String tempId;
  final String title;
  final String? description;
  final List<String> predecessorTempIds;
  final double? estimatedDuration;
  final String priority;
  final List<String> checklistItems;
  bool isSelected;

  AiPhaseTask({
    required this.tempId,
    required this.title,
    this.description,
    this.predecessorTempIds = const [],
    this.estimatedDuration,
    this.priority = 'medium',
    this.checklistItems = const [],
    this.isSelected = true,
  });

  Map<String, dynamic> toJson() => {
        'tempId': tempId,
        'title': title,
        if (description != null) 'description': description,
        'predecessorTempIds': predecessorTempIds,
        if (estimatedDuration != null) 'estimatedDuration': estimatedDuration,
        'priority': priority,
        'checklistItems': checklistItems,
        'isSelected': isSelected,
      };

  factory AiPhaseTask.fromJson(
    Map<String, dynamic> json,
    String defaultTempId,
  ) {
    return AiPhaseTask(
      tempId: json['tempId'] as String? ?? defaultTempId,
      title: json['title'] as String? ?? 'Untitled Task',
      description: json['description'] as String?,
      predecessorTempIds:
          (json['predecessorTempIds'] as List?)?.cast<String>() ?? [],
      estimatedDuration: (json['estimatedDuration'] as num?)?.toDouble(),
      priority: json['priority'] as String? ?? 'medium',
      checklistItems: (json['checklistItems'] as List?)?.cast<String>() ?? [],
      isSelected: true,
    );
  }
}

/// A budget item within a phase of an AI project plan
class AiPhaseBudgetItem {
  final String tempId;
  final String name;
  final double quantity;
  final String unit;
  final double unitCost;
  final double unitPrice;
  bool isSelected;

  AiPhaseBudgetItem({
    required this.tempId,
    required this.name,
    required this.quantity,
    required this.unit,
    required this.unitCost,
    required this.unitPrice,
    this.isSelected = true,
  });

  double get totalCost => quantity * unitCost;
  double get totalPrice => quantity * unitPrice;

  Map<String, dynamic> toJson() => {
        'tempId': tempId,
        'name': name,
        'quantity': quantity,
        'unit': unit,
        'unitCost': unitCost,
        'unitPrice': unitPrice,
        'isSelected': isSelected,
      };

  factory AiPhaseBudgetItem.fromJson(
    Map<String, dynamic> json,
    String defaultTempId,
  ) {
    return AiPhaseBudgetItem(
      tempId: json['tempId'] as String? ?? defaultTempId,
      name: json['name'] as String? ?? 'Unknown Item',
      quantity: (json['quantity'] as num?)?.toDouble() ?? 1.0,
      unit: json['unit'] as String? ?? 'ea',
      unitCost: (json['unitCost'] as num?)?.toDouble() ??
          (json['unit_cost'] as num?)?.toDouble() ??
          0.0,
      unitPrice: (json['unitPrice'] as num?)?.toDouble() ??
          (json['unit_price'] as num?)?.toDouble() ??
          0.0,
      isSelected: true,
    );
  }
}

/// A property (unit/area) in an AI project plan for emergency/restoration jobs
class AiProjectProperty {
  final String name;
  final String identifier;
  final String? floor;
  final List<String> areas;
  bool isSelected;

  AiProjectProperty({
    required this.name,
    required this.identifier,
    this.floor,
    this.areas = const [],
    this.isSelected = true,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'identifier': identifier,
        if (floor != null) 'floor': floor,
        'areas': areas,
        'isSelected': isSelected,
      };

  factory AiProjectProperty.fromJson(Map<String, dynamic> json) {
    return AiProjectProperty(
      name: json['name'] as String? ?? 'Unknown',
      identifier: json['identifier'] as String? ?? '',
      floor: json['floor'] as String?,
      areas: (json['areas'] as List?)?.cast<String>() ?? [],
      isSelected: true,
    );
  }
}

/// AI Service for generating budget items
class AiService {
  // Provider configurations

  // 1. OpenAI
  static const _openRouterMimo = AiProviderConfig(
    name: 'AI',
    baseUrl: 'https://openrouter.ai/api/v1/chat/completions',
    model: 'openai/gpt-oss-120b:free',
    apiKey: String.fromEnvironment('OPENROUTER_API_KEY'),
    extraHeaders: {
      'HTTP-Referer': 'https://example.com',
      'X-Title': 'FieldFleet',
    },
  );

  // 2. Fallback: GLM 4.5 Air (free)
  static const _openRouterGlm = AiProviderConfig(
    name: 'AI',
    baseUrl: 'https://openrouter.ai/api/v1/chat/completions',
    model: 'tencent/hy3-preview:free',
    apiKey: String.fromEnvironment('OPENROUTER_API_KEY'),
    extraHeaders: {
      'HTTP-Referer': 'https://example.com',
      'X-Title': 'FieldFleet',
    },
  );

  // 3. Last resort: FieldFleet AI (local llama-server)
  static const _taskfleetAi = AiProviderConfig(
    name: 'FieldFleet AI',
    baseUrl: 'https://ai.example.com/completion',
    model: null,
    isLlamaServer: true,
  );

  /// Build a system prompt that prepends persona context when available.
  String _buildSystemPrompt(String basePrompt, AiPersonaContext? persona) {
    if (persona == null || !persona.hasPersona) return basePrompt;
    final personaBlock = persona.buildPersonaBlock();
    if (personaBlock.isEmpty) return basePrompt;
    debugPrint('🧑‍💼 PERSONA BLOCK:\n$personaBlock');
    return '$personaBlock\n\n$basePrompt';
  }

  /// List of providers to try in order (primary first, fallbacks after)
  static final List<AiProviderConfig> _providers = [
    _openRouterMimo, // 2. Then Mimo
    _openRouterGlm, // 1. Try GLM first (reliable JSON output)
    _taskfleetAi, // 3. Then local llama-server
  ];

  Future<T> _runWithProviderFallback<T>({
    required Future<T> Function(AiProviderConfig provider) invoke,
    required bool Function(T result) isValidResult,
    int maxRetries = 2,
    required String initialProgressMessage,
    required String retryProgressMessage,
    required String jsonRetryProgressMessage,
    required String fallbackProgressMessage,
    required AiProgressCallback? onProgress,
    void Function(
      AiProviderConfig provider,
      T result,
      int attempt,
      Stopwatch stopwatch,
    )? onSuccess,
  }) async {
    Exception? lastError;

    for (int i = 0; i < _providers.length; i++) {
      final provider = _providers[i];
      final isLast = i == _providers.length - 1;

      for (int attempt = 1; attempt <= maxRetries; attempt++) {
        try {
          debugPrint('');
          debugPrint(
            '🔄 Trying provider ${i + 1}/${_providers.length}: ${provider.name}${attempt > 1 ? " (retry $attempt/$maxRetries)" : ""}',
          );
          debugPrint('   URL: ${provider.baseUrl}');
          debugPrint(
            '   Format: ${provider.isLlamaServer ? "llama-server" : "OpenAI-compatible"}',
          );

          onProgress?.call(
            provider.name,
            attempt > 1 ? retryProgressMessage : initialProgressMessage,
          );

          final stopwatch = Stopwatch()..start();
          final result = await invoke(provider);
          stopwatch.stop();

          if (isValidResult(result)) {
            onSuccess?.call(provider, result, attempt, stopwatch);
            onProgress?.call(provider.name, 'Complete!');
            return result;
          }

          lastError = Exception('Provider returned an empty result');
          if (attempt < maxRetries) {
            debugPrint('   ⚠️ Empty result, retrying same provider...');
            await Future.delayed(const Duration(milliseconds: 500));
            continue;
          }
          debugPrint('   ❌ Max retries reached for empty result');
          break;
        } on JsonParseException catch (e) {
          debugPrint('');
          debugPrint(
            '⚠️ JSON PARSE ERROR: ${provider.name} (attempt $attempt/$maxRetries)',
          );
          debugPrint('   Error: ${e.message}');

          lastError = e;
          if (attempt < maxRetries) {
            debugPrint('   🔁 Retrying same provider...');
            onProgress?.call(provider.name, jsonRetryProgressMessage);
            await Future.delayed(const Duration(milliseconds: 500));
            continue;
          }
          debugPrint('   ❌ Max retries reached for JSON errors');
          break;
        } catch (e) {
          debugPrint('');
          debugPrint('❌ FAILED: ${provider.name}');
          debugPrint('   Error: $e');
          lastError = e is Exception ? e : Exception(e.toString());
          break;
        }
      }

      if (!isLast) {
        debugPrint('   ➡️  Falling back to next provider...');
        onProgress?.call(_providers[i + 1].name, fallbackProgressMessage);
      }
    }

    throw lastError ?? Exception('All AI providers failed');
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // GENERIC PROVIDER CALLING
  // ═══════════════════════════════════════════════════════════════════════════

  bool _isOpenRouterProvider(AiProviderConfig provider) {
    return provider.baseUrl.contains('openrouter.ai');
  }

  /// Generic helper to call an AI provider and return raw content string.
  /// All public methods delegate to this for HTTP calls.
  ///
  /// [promptPrime] is prepended to llama-server responses and appended to
  /// the llama prompt (e.g. '[' for arrays, '{' for objects, '' for text).
  Future<String> _callProviderGeneric(
    AiProviderConfig provider,
    String systemPrompt,
    String userPrompt, {
    int maxTokens = 4000,
    int nPredict = 6000,
    String promptPrime = '',
    Duration timeout = const Duration(seconds: 120),
    AiProgressCallback? onProgress,
    AiStreamCallback? onStream,
    String progressMessage = 'Generating...',
    String? pdfBase64,
    String? imageBase64,
    List<Map<String, String>>? conversationHistory,
  }) async {
    final headers = <String, String>{'Content-Type': 'application/json'};

    if (provider.apiKey != null && provider.apiKey!.isNotEmpty) {
      headers['Authorization'] = 'Bearer ${provider.apiKey}';
    }

    if (provider.extraHeaders != null) {
      headers.addAll(provider.extraHeaders!);
    }

    Map<String, dynamic> body;

    if (provider.isLlamaServer) {
      final historyBlock =
          conversationHistory != null && conversationHistory.isNotEmpty
              ? '${conversationHistory.map((m) {
                  final role =
                      m['role'] == 'user' ? '### User:' : '### Assistant:';
                  return '$role\n${m['content']}';
                }).join('\n\n')}\n\n'
              : '';
      final fullPrompt = '''### System:
$systemPrompt

$historyBlock### User:
$userPrompt

### Assistant:
$promptPrime''';
      body = {
        'prompt': fullPrompt,
        'n_predict': nPredict,
        'temperature': 0.7,
        'stop': ['### User:', '### System:', '\n\n\n', '```'],
      };
      if (imageBase64 != null && imageBase64.isNotEmpty) {
        // llama.cpp multimodal: image is referenced inline in the prompt as
        // [img-1]. Caller is responsible for putting the marker in userPrompt.
        body['image_data'] = [
          {'data': imageBase64, 'id': 1},
        ];
      }
      debugPrint('   Request format: llama-server /completion');
    } else {
      // Build user message content – multimodal when PDF is attached
      dynamic userContent;
      if (pdfBase64 != null && _isOpenRouterProvider(provider)) {
        userContent = [
          {'type': 'text', 'text': userPrompt},
          {
            'type': 'file',
            'file': {
              'filename': 'budget.pdf',
              'file_data': 'data:application/pdf;base64,$pdfBase64',
            },
          },
        ];
      } else {
        userContent = userPrompt;
      }

      body = {
        'messages': [
          {'role': 'system', 'content': systemPrompt},
          if (conversationHistory != null) ...conversationHistory,
          {'role': 'user', 'content': userContent},
        ],
        'temperature': 0.7,
        'max_tokens': maxTokens,
      };

      // Add PDF parsing plugin for OpenRouter
      if (pdfBase64 != null && _isOpenRouterProvider(provider)) {
        body['plugins'] = [
          {
            'id': 'file-parser',
            'pdf': {'engine': 'pdf-text'},
          },
        ];
      }

      if (provider.model != null) {
        body['model'] = provider.model;
        debugPrint('   Model: ${provider.model}');
      }

      if (_isOpenRouterProvider(provider)) {
        body['stream'] = true;
        // Reasoning models (gpt-oss, o1, deepseek-r1) otherwise stream their
        // chain-of-thought via `delta.reasoning` and prefix the answer with
        // prose like "Need JSON. Assume 800x600..." which then poisons
        // jsonDecode. `exclude: true` keeps reasoning enabled server-side
        // (so the model still thinks) but drops the tokens from the stream.
        body['reasoning'] = {'exclude': true};
      }
      debugPrint('   Request format: OpenAI chat/completions');
    }

    debugPrint('   📤 Sending request...');
    onProgress?.call(provider.name, progressMessage);
    String? content;

    if (!provider.isLlamaServer && _isOpenRouterProvider(provider)) {
      content = await _callOpenAiStream(
        provider: provider,
        headers: headers,
        body: body,
        timeout: timeout,
        onProgress: onProgress,
        onStream: onStream,
      );
    } else {
      final response = await http
          .post(
            Uri.parse(provider.baseUrl),
            headers: headers,
            body: jsonEncode(body),
          )
          .timeout(timeout);

      debugPrint('   📥 Response status: ${response.statusCode}');

      if (response.statusCode != 200) {
        debugPrint(
          '   Response body: ${response.body.substring(0, (response.body.length).clamp(0, 500))}',
        );
        throw Exception('HTTP ${response.statusCode}: ${response.body}');
      }

      debugPrint('   Response length: ${response.body.length} bytes');
      onProgress?.call(provider.name, 'Parsing response...');

      final responseData = jsonDecode(response.body) as Map<String, dynamic>;

      if (provider.isLlamaServer) {
        final rawContent = responseData['content'] as String?;
        content = rawContent != null && promptPrime.isNotEmpty
            ? '$promptPrime$rawContent'
            : rawContent;
      } else {
        content = _extractOpenAiContent(responseData);
      }
    }

    if (content == null || content.isEmpty) {
      throw Exception('Empty content in response');
    }

    debugPrint(
      '   Content preview: ${content.substring(0, content.length.clamp(0, 200))}...',
    );
    return content;
  }

  Future<String> _callOpenAiStream({
    required AiProviderConfig provider,
    required Map<String, String> headers,
    required Map<String, dynamic> body,
    required Duration timeout,
    AiProgressCallback? onProgress,
    AiStreamCallback? onStream,
  }) async {
    final client = http.Client();
    try {
      final request = http.Request('POST', Uri.parse(provider.baseUrl))
        ..headers.addAll(headers)
        ..body = jsonEncode(body);

      final response = await client.send(request).timeout(timeout);
      debugPrint('   📥 Stream response status: ${response.statusCode}');

      if (response.statusCode != 200) {
        final error = await response.stream.bytesToString();
        throw Exception('HTTP ${response.statusCode}: $error');
      }

      onProgress?.call(provider.name, 'Streaming response...');

      final fullText = StringBuffer();
      var pending = '';
      final eventDataLines = <String>[];

      void processEventData(List<String> lines) {
        if (lines.isEmpty) {
          return;
        }

        final payload = lines.join('\n').trim();
        if (payload.isEmpty || payload == '[DONE]') {
          return;
        }

        try {
          final event = jsonDecode(payload) as Map<String, dynamic>;
          final delta = _extractOpenAiDelta(event);
          if (delta != null && delta.isNotEmpty) {
            fullText.write(delta);
            onStream?.call(provider.name, delta, fullText.toString());
          }
        } catch (_) {
          // Ignore malformed stream fragments and keep processing.
        }
      }

      await for (final chunk in response.stream.timeout(timeout)) {
        pending += utf8.decode(chunk, allowMalformed: true);

        while (true) {
          final newlineIndex = pending.indexOf('\n');
          if (newlineIndex == -1) break;

          final rawLine = pending.substring(0, newlineIndex);
          pending = pending.substring(newlineIndex + 1);
          final line = rawLine.trim();
          if (line.isEmpty) {
            processEventData(eventDataLines);
            eventDataLines.clear();
            continue;
          }

          if (!line.startsWith('data:')) {
            continue;
          }

          eventDataLines.add(line.substring(5).trim());
        }
      }

      // Flush any trailing in-progress event when stream closes.
      if (pending.trim().isNotEmpty) {
        final trailing = pending.trim();
        if (trailing.startsWith('data:')) {
          eventDataLines.add(trailing.substring(5).trim());
        }
      }
      processEventData(eventDataLines);

      onProgress?.call(provider.name, 'Parsing response...');
      return fullText.toString();
    } finally {
      client.close();
    }
  }

  /// Parse raw content to extract a JSON structure between [startChar] and [endChar].
  /// Strips markdown code blocks and finds the outermost delimiters.
  String _extractJson(String content, String startChar, String endChar) {
    String jsonStr = content.trim();

    // Remove markdown code blocks if present
    if (jsonStr.startsWith('```json')) {
      jsonStr = jsonStr.substring(7);
    } else if (jsonStr.startsWith('```')) {
      jsonStr = jsonStr.substring(3);
    }
    if (jsonStr.endsWith('```')) {
      jsonStr = jsonStr.substring(0, jsonStr.length - 3);
    }
    jsonStr = jsonStr.trim();

    // Handle responses that contain explanatory text before/after JSON.
    final validSegments = <String>[];
    for (final segment in _extractBalancedJsonSegments(
      jsonStr,
      startChar,
      endChar,
    )) {
      try {
        final decoded = jsonDecode(segment);
        final isExpectedType =
            (startChar == '{' && decoded is Map<String, dynamic>) ||
                (startChar == '[' && decoded is List<dynamic>);
        if (isExpectedType) {
          validSegments.add(segment);
        }
      } catch (_) {
        // Ignore malformed segments and continue scanning.
      }
    }
    if (validSegments.isNotEmpty) {
      validSegments.sort((a, b) => b.length.compareTo(a.length));
      return validSegments.first;
    }

    final startIndex = jsonStr.indexOf(startChar);
    final endIndex = jsonStr.lastIndexOf(endChar);

    if (startIndex == -1 || endIndex == -1 || endIndex <= startIndex) {
      throw JsonParseException(
        'No JSON $startChar...$endChar found in response',
        rawContent: content,
      );
    }

    return jsonStr.substring(startIndex, endIndex + 1);
  }

  List<String> _extractBalancedJsonSegments(
    String input,
    String startChar,
    String endChar,
  ) {
    final segments = <String>[];
    var depth = 0;
    var startIndex = -1;
    var inString = false;
    var isEscaping = false;

    for (var i = 0; i < input.length; i++) {
      final ch = input[i];

      if (inString) {
        if (isEscaping) {
          isEscaping = false;
          continue;
        }
        if (ch == r'\') {
          isEscaping = true;
          continue;
        }
        if (ch == '"') {
          inString = false;
        }
        continue;
      }

      if (ch == '"') {
        inString = true;
        continue;
      }

      if (ch == startChar) {
        if (depth == 0) {
          startIndex = i;
        }
        depth++;
        continue;
      }

      if (ch == endChar && depth > 0) {
        depth--;
        if (depth == 0 && startIndex >= 0) {
          segments.add(input.substring(startIndex, i + 1));
          startIndex = -1;
        }
      }
    }

    return segments;
  }

  /// OpenAI-compatible providers can return message content as plain string,
  /// or as an array of typed parts. Normalize both into a text string.
  String? _extractOpenAiContent(Map<String, dynamic> responseData) {
    final choices = responseData['choices'] as List<dynamic>?;
    if (choices == null || choices.isEmpty) {
      throw Exception('No choices in response');
    }

    final firstChoice = choices[0];
    if (firstChoice is! Map<String, dynamic>) {
      return null;
    }

    final message = firstChoice['message'] as Map<String, dynamic>?;
    final fromMessage = _normalizeContentToText(message?['content']);
    if (fromMessage != null && fromMessage.isNotEmpty) {
      return fromMessage;
    }

    // Some providers still include completion-style `text`.
    final fromText = _normalizeContentToText(firstChoice['text']);
    if (fromText != null && fromText.isNotEmpty) {
      return fromText;
    }

    return null;
  }

  String? _extractOpenAiDelta(Map<String, dynamic> responseData) {
    final choices = responseData['choices'] as List<dynamic>?;
    if (choices == null || choices.isEmpty) {
      return null;
    }

    final firstChoice = choices[0];
    if (firstChoice is! Map<String, dynamic>) {
      return null;
    }

    final delta = firstChoice['delta'] as Map<String, dynamic>?;
    final fromDelta = _normalizeStreamDelta(delta?['content']);
    if (fromDelta != null && fromDelta.isNotEmpty) {
      return fromDelta;
    }

    // Some providers stream "reasoning" separately.
    final fromReasoning = _normalizeStreamDelta(delta?['reasoning']);
    if (fromReasoning != null && fromReasoning.isNotEmpty) {
      return fromReasoning;
    }

    // Some stream chunks can include message content instead of delta.
    final message = firstChoice['message'] as Map<String, dynamic>?;
    final fromMessage = _normalizeStreamDelta(message?['content']);
    if (fromMessage != null && fromMessage.isNotEmpty) {
      return fromMessage;
    }

    final fromText = _normalizeStreamDelta(firstChoice['text']);
    if (fromText != null && fromText.isNotEmpty) {
      return fromText;
    }

    return null;
  }

  @visibleForTesting
  String? extractStreamDeltaForTesting(Map<String, dynamic> responseData) {
    return _extractOpenAiDelta(responseData);
  }

  /// Normalize a streaming delta, preserving whitespace so words are not
  /// concatenated. Unlike [_normalizeContentToText] which is used for full
  /// response bodies, this keeps leading/trailing spaces intact.
  String? _normalizeStreamDelta(dynamic rawContent) {
    if (rawContent == null) return null;
    if (rawContent is String) return rawContent;
    // Delegate to full normalizer for complex types (rare in streaming)
    return _normalizeContentToText(rawContent);
  }

  String? _normalizeContentToText(dynamic rawContent) {
    if (rawContent == null) {
      return null;
    }

    if (rawContent is String) {
      return rawContent.trim();
    }

    if (rawContent is List) {
      final parts = <String>[];
      for (final part in rawContent) {
        if (part is String && part.trim().isNotEmpty) {
          parts.add(part.trim());
          continue;
        }

        if (part is Map) {
          final text = part['text'] ?? part['content'];
          if (text is String && text.trim().isNotEmpty) {
            parts.add(text.trim());
          }
        }
      }
      return parts.isEmpty ? null : parts.join('\n');
    }

    if (rawContent is Map) {
      final text = rawContent['text'] ?? rawContent['content'];
      if (text is String && text.trim().isNotEmpty) {
        return text.trim();
      }
    }

    return null;
  }

  /// System prompt for budget item generation
  static const String _systemPrompt =
      '''You are a construction cost estimator for a contractor budgeting system. Your task is to generate a list of budget line items (materials, labor, equipment) for construction projects.

CRITICAL: Your response must be ONLY a valid JSON array. No text before or after. No explanations. No markdown code blocks. Just the raw JSON array starting with [ and ending with ].

Each budget item in the array must be a JSON object with exactly these 5 fields:
- "name": (string) descriptive item name, e.g. "Kitchen Cabinets - Oak"
- "quantity": (number) estimated quantity needed, e.g. 1, 25, 100
- "unit": (string) unit of measure: "ea" (each), "sqft", "lf" (linear feet), "hr", "gal", "set", "lot"
- "unitCost": (number) contractor's cost per unit in USD, e.g. 45.00
- "unitPrice": (number) selling price per unit in USD (typically 30-50% markup over cost), e.g. 65.00

EXAMPLE - If asked about a bathroom renovation, respond exactly like this:
[{"name":"Toilet - Standard","quantity":1,"unit":"ea","unitCost":250,"unitPrice":400},{"name":"Vanity with Sink","quantity":1,"unit":"ea","unitCost":450,"unitPrice":700},{"name":"Plumbing Labor","quantity":6,"unit":"hr","unitCost":85,"unitPrice":125}]

Guidelines:
- Generate 5-15 relevant items based on the project description
- Use realistic 2024 US market pricing
- Include both materials AND labor items
- Group related work (e.g. "Tile Installation Labor" separate from "Floor Tile")
- Use standard construction units of measure

Remember: Output ONLY the JSON array. Start your response with [ and end with ].''';

  /// Generate budget items from a description
  /// Tries providers in order, falling back on failure
  /// [onProgress] is called when status changes (provider name, status message)
  /// [projectContext] provides additional context for better estimates
  Future<List<AiBudgetItem>> generateBudgetItems({
    required String description,
    String? category,
    AiProjectContext? projectContext,
    AiPersonaContext? persona,
    AiProgressCallback? onProgress,
    AiStreamCallback? onStream,
    String? pdfBase64,
  }) async {
    final userPrompt = _buildUserPrompt(
      description,
      category,
      projectContext,
      hasPdf: pdfBase64 != null,
    );

    debugPrint('═══════════════════════════════════════════════════════════');
    debugPrint('🤖 AI SERVICE: Starting budget item generation');
    debugPrint('📝 Category: ${category ?? "none"}');
    debugPrint(
      '📝 Description: ${description.length > 100 ? "${description.substring(0, 100)}..." : description}',
    );
    debugPrint('═══════════════════════════════════════════════════════════');

    final items = await _runWithProviderFallback<List<AiBudgetItem>>(
      invoke: (provider) => _callProvider(
        provider,
        userPrompt,
        onProgress,
        onStream: onStream,
        pdfBase64: pdfBase64,
        persona: persona,
      ),
      isValidResult: (result) => result.isNotEmpty,
      initialProgressMessage: 'Connecting...',
      retryProgressMessage: 'Retrying...',
      jsonRetryProgressMessage: 'JSON error, retrying...',
      fallbackProgressMessage: 'Trying fallback...',
      onProgress: onProgress,
      onSuccess: (provider, result, attempt, stopwatch) {
        debugPrint('');
        debugPrint(
          '✅ SUCCESS from ${provider.name}${attempt > 1 ? " (on retry $attempt)" : ""}',
        );
        debugPrint(
          '   Generated ${result.length} items in ${stopwatch.elapsedMilliseconds}ms',
        );
        debugPrint('   Items: ${result.map((i) => i.name).join(", ")}');
        debugPrint(
          '═══════════════════════════════════════════════════════════',
        );
      },
    );

    return items;
  }

  String _buildUserPrompt(
    String description,
    String? category,
    AiProjectContext? context, {
    bool hasPdf = false,
  }) {
    final buffer = StringBuffer();

    if (hasPdf) {
      buffer.write(
        'I have uploaded a PDF budget/estimate document. '
        'Extract ALL line items from the PDF and convert them into a JSON array of construction budget items. '
        'Preserve the original item names, quantities, units, and pricing as closely as possible.',
      );
      if (description.isNotEmpty) {
        buffer.write('\n\nAdditional context: $description');
      }
      if (category != null) {
        buffer.write('\nCategory focus: $category');
      }
    } else {
      buffer.write(
        'Generate a JSON array of construction budget line items for ',
      );

      if (category != null) {
        buffer.write('a $category project');
        if (description.isNotEmpty) {
          buffer.write('. Project details: $description');
        }
      } else if (description.isNotEmpty) {
        buffer.write('this project: $description');
      } else {
        buffer.write('a general construction project');
      }
    }

    // Add project context if available
    if (context != null && context.hasContext) {
      buffer.write('\n\nProject Context:');

      if (context.projectName != null) {
        buffer.write('\n- Project Name: ${context.projectName}');
      }

      if (context.location != null) {
        buffer.write(
          '\n- Location: ${context.location} (use regional pricing for this area)',
        );
      }

      if (context.jobType != null) {
        buffer.write('\n- Job Type: ${context.jobType}');
      }

      if (context.currency != null) {
        buffer.write(
          '\n- Currency: ${context.currency} (use this currency for all prices)',
        );
      }

      if (context.estimatedBudget != null) {
        buffer.write(
          '\n- Target Budget: \$${context.estimatedBudget!.toStringAsFixed(0)} (scale items appropriately)',
        );
      }

      if (context.materialMarkupPercent != null) {
        buffer.write(
          '\n- Material Markup: ${context.materialMarkupPercent!.toStringAsFixed(0)}%',
        );
      }

      if (context.laborMarkupPercent != null) {
        buffer.write(
          '\n- Labor Markup: ${context.laborMarkupPercent!.toStringAsFixed(0)}%',
        );
      }
    }

    buffer.write('\n\nRespond with ONLY the JSON array, nothing else.');
    return buffer.toString();
  }

  Future<List<AiBudgetItem>> _callProvider(
    AiProviderConfig provider,
    String userPrompt,
    AiProgressCallback? onProgress, {
    AiStreamCallback? onStream,
    String? pdfBase64,
    AiPersonaContext? persona,
  }) async {
    final content = await _callProviderGeneric(
      provider,
      _buildSystemPrompt(_systemPrompt, persona),
      userPrompt,
      maxTokens: 2000,
      nPredict: 4000,
      promptPrime: '[',
      timeout: Duration(seconds: pdfBase64 != null ? 120 : 90),
      onProgress: onProgress,
      onStream: onStream,
      progressMessage:
          pdfBase64 != null ? 'Processing PDF...' : 'Generating items...',
      pdfBase64: pdfBase64,
    );

    return _parseBudgetItemsFromContent(content);
  }

  List<AiBudgetItem> _parseBudgetItemsFromContent(String content) {
    // Parse the JSON array from the content
    // Handle cases where the model might wrap it in markdown code blocks
    String jsonStr = content.trim();

    // Remove markdown code blocks if present
    if (jsonStr.startsWith('```json')) {
      jsonStr = jsonStr.substring(7);
    } else if (jsonStr.startsWith('```')) {
      jsonStr = jsonStr.substring(3);
    }
    if (jsonStr.endsWith('```')) {
      jsonStr = jsonStr.substring(0, jsonStr.length - 3);
    }
    jsonStr = jsonStr.trim();

    // Find the JSON array in the content
    final startIndex = jsonStr.indexOf('[');
    final endIndex = jsonStr.lastIndexOf(']');

    if (startIndex == -1 || endIndex == -1 || endIndex <= startIndex) {
      throw JsonParseException(
        'No JSON array found in response',
        rawContent: content,
      );
    }

    jsonStr = jsonStr.substring(startIndex, endIndex + 1);

    // Try to decode the JSON
    List<dynamic> items;
    try {
      items = jsonDecode(jsonStr) as List<dynamic>;
    } on FormatException catch (e) {
      throw JsonParseException(
        'Invalid JSON format: ${e.message}',
        rawContent: jsonStr,
      );
    }

    // Parse each item
    try {
      return items
          .map((item) => AiBudgetItem.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw JsonParseException(
        'Failed to parse budget items: $e',
        rawContent: jsonStr,
      );
    }
  }

  @visibleForTesting
  List<AiBudgetItem> parseBudgetItemsFromContentForTesting(String content) {
    return _parseBudgetItemsFromContent(content);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TASK GENERATION
  // ═══════════════════════════════════════════════════════════════════════════

  /// System prompt for task generation
  static const String _taskSystemPrompt =
      '''You are a construction project manager creating a task list from budget line items. Your task is to generate actionable tasks with dependencies, checklists, and proper sequencing.

CRITICAL: Your response must be ONLY a valid JSON array. No text before or after. No explanations. No markdown code blocks. Just the raw JSON array starting with [ and ending with ].

Each task in the array must be a JSON object with these fields:
- "tempId": (string) unique temporary ID for referencing dependencies, e.g. "task_1", "demo", "cabinets"
- "title": (string) action-oriented task title, e.g. "Install Kitchen Cabinets"
- "description": (string) brief description of the work
- "taskType": (string) either "summary" (group/container) or "standard" (actual work)
- "parentTempId": (string|null) tempId of parent summary task, or null for root-level
- "predecessorTempIds": (array of strings) tempIds of tasks that must complete before this one starts
- "estimatedDuration": (number) estimated hours to complete (null for summary tasks)
- "priority": (string) "high", "medium", or "low"
- "checklistItems": (array of strings) specific steps to complete this task
- "sourceBudgetItemId": (string|null) ID of the budget item this task was generated from

CONSTRUCTION SEQUENCING RULES:
1. Demo/removal work comes first
2. Rough MEP (mechanical, electrical, plumbing) before drywall
3. Framing before insulation, insulation before drywall
4. Drywall before paint, paint before trim
5. Cabinets before countertops, countertops before backsplash
6. Rough plumbing before fixtures, rough electrical before devices
7. Flooring typically after paint but before trim

TASK HIERARCHY:
- Create "summary" tasks to group related work (e.g., "Kitchen Renovation")
- Put individual work tasks under the appropriate summary with parentTempId
- Summary tasks have no duration (calculated from children)
- Standard tasks have estimatedDuration in hours

DEPENDENCIES (predecessorTempIds):
- Tasks that must finish before another can start
- Use for sequential work (cabinets → countertops → sink)
- Parallel work can have same predecessor (backsplash and sink both depend on countertops)

EXAMPLE OUTPUT:
[{"tempId":"kitchen","title":"Kitchen Renovation","taskType":"summary","parentTempId":null,"predecessorTempIds":[],"estimatedDuration":null,"priority":"high","checklistItems":[],"sourceBudgetItemId":null},{"tempId":"demo","title":"Demo Existing Kitchen","taskType":"standard","parentTempId":"kitchen","predecessorTempIds":[],"estimatedDuration":8,"priority":"high","checklistItems":["Disconnect utilities","Remove countertops","Remove cabinets","Dispose debris"],"sourceBudgetItemId":"budget_123"},{"tempId":"cabinets","title":"Install Cabinets","taskType":"standard","parentTempId":"kitchen","predecessorTempIds":["demo"],"estimatedDuration":16,"priority":"medium","checklistItems":["Mark stud locations","Install uppers","Install lowers","Level and shim","Install hardware"],"sourceBudgetItemId":"budget_456"}]

Guidelines:
- Generate 3-6 checklist items per standard task
- Use realistic duration estimates based on scope
- Group related budget items under summary tasks
- Create logical dependencies based on construction sequencing
- If budget items already have labor hours (unit="hr"), use that for duration

Remember: Output ONLY the JSON array. Start your response with [ and end with ].''';

  /// Generate tasks from budget items
  /// [budgetItems] - List of budget items to generate tasks from
  /// [additionalInstructions] - Optional user instructions for sequencing/priorities
  /// [projectContext] - Project context for better task generation
  /// [onProgress] - Callback for status updates
  Future<List<AiGeneratedTask>> generateTasks({
    required List<BudgetItemInput> budgetItems,
    String? additionalInstructions,
    AiProjectContext? projectContext,
    AiPersonaContext? persona,
    AiProgressCallback? onProgress,
    AiStreamCallback? onStream,
  }) async {
    final userPrompt = _buildTaskUserPrompt(
      budgetItems,
      additionalInstructions,
      projectContext,
    );

    debugPrint('═══════════════════════════════════════════════════════════');
    debugPrint('🤖 AI SERVICE: Starting task generation');
    debugPrint('📝 Budget items: ${budgetItems.length}');
    debugPrint('📝 Instructions: ${additionalInstructions ?? "none"}');
    debugPrint('═══════════════════════════════════════════════════════════');

    final tasks = await _runWithProviderFallback<List<AiGeneratedTask>>(
      invoke: (provider) => _callProviderForTasks(
        provider,
        userPrompt,
        onProgress,
        onStream: onStream,
        persona: persona,
      ),
      isValidResult: (result) => result.isNotEmpty,
      initialProgressMessage: 'Connecting...',
      retryProgressMessage: 'Retrying...',
      jsonRetryProgressMessage: 'JSON error, retrying...',
      fallbackProgressMessage: 'Trying fallback...',
      onProgress: onProgress,
      onSuccess: (provider, result, attempt, stopwatch) {
        debugPrint('');
        debugPrint(
          '✅ SUCCESS from ${provider.name}${attempt > 1 ? " (on retry $attempt)" : ""}',
        );
        debugPrint(
          '   Generated ${result.length} tasks in ${stopwatch.elapsedMilliseconds}ms',
        );
        debugPrint('   Tasks: ${result.map((t) => t.title).join(", ")}');
        debugPrint(
          '═══════════════════════════════════════════════════════════',
        );
      },
    );

    return tasks;
  }

  String _buildTaskUserPrompt(
    List<BudgetItemInput> budgetItems,
    String? additionalInstructions,
    AiProjectContext? context,
  ) {
    final buffer = StringBuffer();
    buffer.writeln(
      'Generate a JSON array of construction tasks from these budget items:',
    );
    buffer.writeln('');
    buffer.writeln('BUDGET ITEMS:');

    for (final item in budgetItems) {
      buffer.write('- ${item.name}');
      if (item.parentName != null) {
        buffer.write(' (in group: ${item.parentName})');
      }
      if (item.laborHours != null) {
        buffer.write(' [${item.laborHours} labor hours]');
      } else if (item.unit != null && item.quantity != null) {
        buffer.write(' [${item.quantity} ${item.unit}]');
      }
      buffer.write(' (id: ${item.id})');
      buffer.writeln();
    }

    if (context != null && context.hasContext) {
      buffer.writeln('');
      buffer.writeln('PROJECT CONTEXT:');
      if (context.projectName != null) {
        buffer.writeln('- Project: ${context.projectName}');
      }
      if (context.jobType != null) {
        buffer.writeln('- Job Type: ${context.jobType}');
      }
      if (context.location != null) {
        buffer.writeln('- Location: ${context.location}');
      }
    }

    if (additionalInstructions != null && additionalInstructions.isNotEmpty) {
      buffer.writeln('');
      buffer.writeln('SPECIAL INSTRUCTIONS:');
      buffer.writeln(additionalInstructions);
    }

    buffer.writeln('');
    buffer.writeln(
      'Create tasks with proper hierarchy (summary tasks for groups), dependencies based on construction sequencing, and detailed checklists. Respond with ONLY the JSON array.',
    );

    return buffer.toString();
  }

  Future<List<AiGeneratedTask>> _callProviderForTasks(
    AiProviderConfig provider,
    String userPrompt,
    AiProgressCallback? onProgress, {
    AiStreamCallback? onStream,
    AiPersonaContext? persona,
    String? systemPromptOverride,
  }) async {
    final content = await _callProviderGeneric(
      provider,
      _buildSystemPrompt(systemPromptOverride ?? _taskSystemPrompt, persona),
      userPrompt,
      maxTokens: 4000,
      nPredict: 6000,
      promptPrime: '[',
      timeout: const Duration(seconds: 120),
      onProgress: onProgress,
      onStream: onStream,
      progressMessage: 'Generating tasks...',
    );

    return _parseTaskResponseFromContent(content);
  }

  List<AiGeneratedTask> _parseTaskResponseFromContent(String content) {
    String jsonStr = content.trim();

    // Remove markdown code blocks if present
    if (jsonStr.startsWith('```json')) {
      jsonStr = jsonStr.substring(7);
    } else if (jsonStr.startsWith('```')) {
      jsonStr = jsonStr.substring(3);
    }
    if (jsonStr.endsWith('```')) {
      jsonStr = jsonStr.substring(0, jsonStr.length - 3);
    }
    jsonStr = jsonStr.trim();

    final startIndex = jsonStr.indexOf('[');
    final endIndex = jsonStr.lastIndexOf(']');

    if (startIndex == -1 || endIndex == -1 || endIndex <= startIndex) {
      throw JsonParseException(
        'No JSON array found in response',
        rawContent: content,
      );
    }

    jsonStr = jsonStr.substring(startIndex, endIndex + 1);

    List<dynamic> items;
    try {
      items = jsonDecode(jsonStr) as List<dynamic>;
    } on FormatException catch (e) {
      throw JsonParseException(
        'Invalid JSON format: ${e.message}',
        rawContent: jsonStr,
      );
    }

    try {
      return items
          .map((item) => AiGeneratedTask.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw JsonParseException(
        'Failed to parse tasks: $e',
        rawContent: jsonStr,
      );
    }
  }

  @visibleForTesting
  List<AiGeneratedTask> parseTaskResponseFromContentForTesting(String content) {
    return _parseTaskResponseFromContent(content);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PROPERTY-BASED TASK GENERATION
  // ═══════════════════════════════════════════════════════════════════════════

  /// System prompt for property-based task generation
  static const String _propertyTaskSystemPrompt =
      '''You are a restoration project manager creating a task list for a property/structure in a water damage, fire damage, or mold remediation project. Generate actionable tasks with checklists based on the property status and its areas.

CRITICAL: Your response must be ONLY a valid JSON array. No text before or after. No explanations. No markdown code blocks. Just the raw JSON array starting with [ and ending with ].

Each task in the array must be a JSON object with these fields:
- "tempId": (string) unique temporary ID, e.g. "task_1", "inspect_areas"
- "title": (string) action-oriented task title, e.g. "Set Up Containment in Kitchen"
- "description": (string) brief description of the work
- "taskType": (string) either "summary" (group/container) or "standard" (actual work)
- "parentTempId": (string|null) tempId of parent summary task, or null for root-level
- "predecessorTempIds": (array of strings) tempIds of tasks that must complete before this one
- "estimatedDuration": (number) estimated hours to complete (null for summary tasks)
- "priority": (string) "high", "medium", or "low"
- "checklistItems": (array of strings) specific steps to complete this task
- "areaName": (string|null) name of the area this task applies to (must match exactly if provided)

RESTORATION SEQUENCING RULES:
1. Emergency mitigation comes first (water extraction, board-up, tarping)
2. Inspection and documentation before remediation work
3. Containment setup before demolition/removal
4. Demo/removal before drying equipment placement
5. Drying and dehumidification before reconstruction
6. Monitoring readings throughout drying phase
7. Clearance testing before reconstruction
8. Reconstruction follows standard construction sequencing

TASK HIERARCHY:
- Create "summary" tasks for each major phase (Mitigation, Drying, Monitoring, Reconstruction)
- Group area-specific tasks under area-named summaries when multiple areas are affected
- Standard tasks have estimatedDuration in hours

Remember: Output ONLY the JSON array. Start your response with [ and end with ].''';

  /// Generate tasks for a property based on its status and areas.
  Future<List<AiGeneratedTask>> generatePropertyTasks({
    required String propertyName,
    required String propertyStatus,
    required List<PropertyAreaInput> areas,
    String? additionalInstructions,
    AiProjectContext? projectContext,
    AiPersonaContext? persona,
    AiProgressCallback? onProgress,
    AiStreamCallback? onStream,
  }) async {
    final userPrompt = _buildPropertyTaskUserPrompt(
      propertyName,
      propertyStatus,
      areas,
      additionalInstructions,
      projectContext,
    );

    debugPrint('═══════════════════════════════════════════════════════════');
    debugPrint('🤖 AI SERVICE: Starting property task generation');
    debugPrint('📝 Property: $propertyName ($propertyStatus)');
    debugPrint('📝 Areas: ${areas.length}');
    debugPrint('═══════════════════════════════════════════════════════════');

    final tasks = await _runWithProviderFallback<List<AiGeneratedTask>>(
      invoke: (provider) => _callProviderForTasks(
        provider,
        userPrompt,
        onProgress,
        onStream: onStream,
        persona: persona,
        systemPromptOverride: _propertyTaskSystemPrompt,
      ),
      isValidResult: (result) => result.isNotEmpty,
      initialProgressMessage: 'Connecting...',
      retryProgressMessage: 'Retrying...',
      jsonRetryProgressMessage: 'JSON error, retrying...',
      fallbackProgressMessage: 'Trying fallback...',
      onProgress: onProgress,
      onSuccess: (provider, result, attempt, stopwatch) {
        debugPrint('');
        debugPrint(
          '✅ SUCCESS from ${provider.name}${attempt > 1 ? " (on retry $attempt)" : ""}',
        );
        debugPrint(
          '   Generated ${result.length} tasks in ${stopwatch.elapsedMilliseconds}ms',
        );
        debugPrint(
          '═══════════════════════════════════════════════════════════',
        );
      },
    );

    return tasks;
  }

  String _buildPropertyTaskUserPrompt(
    String propertyName,
    String propertyStatus,
    List<PropertyAreaInput> areas,
    String? additionalInstructions,
    AiProjectContext? context,
  ) {
    final buffer = StringBuffer();
    buffer.writeln(
      'Generate a JSON array of restoration tasks for this property:',
    );
    buffer.writeln('');
    buffer.writeln('PROPERTY: $propertyName');
    buffer.writeln('STATUS: $propertyStatus');
    buffer.writeln('');

    if (areas.isNotEmpty) {
      buffer.writeln('AREAS/ROOMS:');
      for (final area in areas) {
        buffer.write('- ${area.name} (status: ${area.status}');
        if (area.isAffected) buffer.write(', affected');
        if (area.trend != null) buffer.write(', trend: ${area.trend}');
        buffer.writeln(')');
      }
    } else {
      buffer.writeln('No areas defined yet - generate general property tasks.');
    }

    if (context != null && context.hasContext) {
      buffer.writeln('');
      buffer.writeln('PROJECT CONTEXT:');
      if (context.projectName != null) {
        buffer.writeln('- Project: ${context.projectName}');
      }
      if (context.jobType != null) {
        buffer.writeln('- Job Type: ${context.jobType}');
      }
      if (context.location != null) {
        buffer.writeln('- Location: ${context.location}');
      }
    }

    if (additionalInstructions != null && additionalInstructions.isNotEmpty) {
      buffer.writeln('');
      buffer.writeln('SPECIAL INSTRUCTIONS:');
      buffer.writeln(additionalInstructions);
    }

    buffer.writeln('');
    buffer.writeln(
      'Generate tasks appropriate for this property\'s current status. '
      'Include area-specific tasks where applicable using the "areaName" field. '
      'Respond with ONLY the JSON array.',
    );

    return buffer.toString();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // GENERAL AI QUERY (for search/questions)
  // ═══════════════════════════════════════════════════════════════════════════

  /// System prompt for general assistant queries
  static const String _assistantSystemPrompt =
      '''You are a helpful AI assistant for FieldFleet, a construction contractor management application. You help users with:
- Understanding their projects, tasks, budgets, and schedules
- Providing guidance on construction best practices
- Answering questions about the application features
- Giving actionable suggestions

Keep responses concise but helpful. Use markdown formatting for clarity:
- **Bold** for emphasis
- Bullet points for lists
- Numbered lists for steps

If the user asks about specific data (like "how many projects"), explain that you don't have access to their live data yet, but describe how they can find that information in the app.

Be friendly and professional. Focus on being helpful for construction contractors.''';

  /// Ask a general question to the AI
  /// Returns a text response
  Future<String> askQuestion({
    required String question,
    String? context, // Optional context about current screen/project
    AiPersonaContext? persona,
    AiProgressCallback? onProgress,
    AiStreamCallback? onStream,
    List<Map<String, String>>? conversationHistory,
  }) async {
    debugPrint('═══════════════════════════════════════════════════════════');
    debugPrint('🤖 AI SERVICE: Processing question');
    debugPrint('📝 Question: $question');
    debugPrint('═══════════════════════════════════════════════════════════');

    final response = await _runWithProviderFallback<String>(
      invoke: (provider) => _callProviderForQuestion(
        provider,
        question,
        context,
        onProgress,
        onStream: onStream,
        persona: persona,
        conversationHistory: conversationHistory,
      ),
      isValidResult: (result) => result.isNotEmpty,
      maxRetries: 1,
      initialProgressMessage: 'Thinking...',
      retryProgressMessage: 'Thinking...',
      jsonRetryProgressMessage: 'Retrying...',
      fallbackProgressMessage: 'Trying fallback...',
      onProgress: onProgress,
      onSuccess: (provider, result, _, stopwatch) {
        debugPrint('');
        debugPrint('✅ SUCCESS from ${provider.name}');
        debugPrint(
          '   Response length: ${result.length} chars in ${stopwatch.elapsedMilliseconds}ms',
        );
        debugPrint(
          '═══════════════════════════════════════════════════════════',
        );
      },
    );

    return response;
  }

  Future<String> _callProviderForQuestion(
    AiProviderConfig provider,
    String question,
    String? context,
    AiProgressCallback? onProgress, {
    AiStreamCallback? onStream,
    AiPersonaContext? persona,
    List<Map<String, String>>? conversationHistory,
  }) async {
    // Build user prompt with optional context
    String userPrompt = question;
    if (context != null && context.isNotEmpty) {
      userPrompt = 'Context: $context\n\nQuestion: $question';
    }

    final content = await _callProviderGeneric(
      provider,
      _buildSystemPrompt(_assistantSystemPrompt, persona),
      userPrompt,
      maxTokens: 1000,
      nPredict: 1000,
      timeout: const Duration(seconds: 60),
      onProgress: onProgress,
      onStream: onStream,
      progressMessage: 'Generating response...',
      conversationHistory: conversationHistory,
    );

    return content.trim();
  }

  /// Vision entry point: describe an image as free text. Routed
  /// directly to the self-hosted llama.cpp endpoint (Qwen 3.5 9B),
  /// since the OpenRouter free models in the fallback chain are
  /// text-only. Caller supplies the system prompt that shapes what to
  /// extract (e.g. "describe this room as a floorplan brief"). The
  /// `[img-1]` marker is appended to [userPrompt] automatically.
  Future<String> describeImage({
    required String imageBase64,
    required String systemPrompt,
    required String userPrompt,
    int nPredict = 2000,
    Duration timeout = const Duration(seconds: 180),
    AiProgressCallback? onProgress,
    String progressMessage = 'Looking at image...',
  }) {
    return _callProviderGeneric(
      _taskfleetAi,
      systemPrompt,
      '$userPrompt\n[img-1]',
      nPredict: nPredict,
      timeout: timeout,
      onProgress: onProgress,
      progressMessage: progressMessage,
      imageBase64: imageBase64,
    );
  }

  /// Public entry point for generating raw JSON from a custom prompt.
  /// Used by feature-specific services (e.g. AiFloorplanService) that
  /// own their own system prompt + parsing but want to share the
  /// existing provider fallback chain + streaming callbacks.
  ///
  /// Returns the model's response as a string. Caller is responsible for
  /// trimming any markdown fences and parsing the JSON.
  Future<String> generateJson({
    required String systemPrompt,
    required String userPrompt,
    int maxTokens = 4000,
    int nPredict = 6000,
    Duration timeout = const Duration(seconds: 120),
    AiProgressCallback? onProgress,
    AiStreamCallback? onStream,
    String progressMessage = 'Generating...',
  }) {
    return _runWithProviderFallback<String>(
      onProgress: onProgress,
      initialProgressMessage: progressMessage,
      retryProgressMessage: 'Retrying...',
      jsonRetryProgressMessage: 'Retrying for valid JSON...',
      fallbackProgressMessage: 'Trying fallback provider...',
      isValidResult: (s) => s.trim().isNotEmpty,
      invoke: (provider) => _callProviderGeneric(
        provider,
        systemPrompt,
        userPrompt,
        maxTokens: maxTokens,
        nPredict: nPredict,
        timeout: timeout,
        onProgress: onProgress,
        onStream: onStream,
        progressMessage: progressMessage,
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PROJECT PLAN GENERATION
  // ═══════════════════════════════════════════════════════════════════════════

  /// System prompt for project plan generation
  static const String _projectPlanSystemPrompt =
      '''You are a construction project planner creating a comprehensive project plan with phases, tasks, and budget items.

CRITICAL: Your response must be ONLY a valid JSON object. No text before or after. No explanations. No markdown code blocks. Just the raw JSON object starting with { and ending with }.

The JSON object must have this structure:
{
  "phases": [
    {
      "tempId": "phase_0",
      "name": "Phase Name",
      "description": "Brief description of this phase",
      "sortOrder": 0,
      "tasks": [
        {
          "tempId": "phase_0_task_0",
          "title": "Task Title",
          "description": "What needs to be done",
          "predecessorTempIds": [],
          "estimatedDuration": 8,
          "priority": "high",
          "checklistItems": ["Step 1", "Step 2", "Step 3"]
        }
      ],
      "budgetItems": [
        {
          "tempId": "phase_0_bi_0",
          "name": "Material or Labor Item",
          "quantity": 1,
          "unit": "ea",
          "unitCost": 100.00,
          "unitPrice": 150.00
        }
      ]
    }
  ],
  "properties": []
}

PHASE TEMPLATES BY JOB TYPE:
- Emergency/Restoration: FNOL & Intake, Emergency Response, Mitigation, Drying & Monitoring, Repair Estimate, Repairs, Final Inspection & Close. Also include a "properties" array with affected units/areas (e.g. {"name":"Unit 101","identifier":"101","floor":"1st","areas":["Living Room","Kitchen","Master Bedroom"]})
- Renovation: Pre-Construction, Demolition, Rough-In, Finishes, Final Fit-Out, Closeout
- New Construction: Site Prep, Structure, Rough-In MEP, Envelope, Interior Finishes, Final Systems, Punch List & Closeout
- Maintenance/Small Repairs/Major Repairs: Assessment, Planning, Execution, Quality Check, Closeout

CONSTRUCTION SEQUENCING RULES:
1. Demo/removal work comes first
2. Rough MEP before drywall
3. Framing before insulation, insulation before drywall
4. Drywall before paint, paint before trim
5. Cabinets before countertops, countertops before backsplash
6. Rough plumbing before fixtures, rough electrical before devices

Guidelines:
- Generate 3-6 tasks per phase with realistic durations
- Generate 2-5 budget items per phase with realistic pricing
- Include both materials AND labor budget items
- Use proper construction sequencing for task dependencies (predecessorTempIds reference other task tempIds)
- 3-5 checklist items per task
- Use standard units: "ea", "sqft", "lf", "hr", "gal", "set", "lot"
- Priority: "high", "medium", or "low"
- Adapt number of phases and detail to project scope
- NEVER return a phase without child tasks
- NEVER return a phase without child budgetItems

Remember: Output ONLY the JSON object. Start with { and end with }.''';

  /// Generate a project plan with phases, tasks, and budget items
  Future<AiProjectPlan> generateProjectPlan({
    required String projectName,
    String? description,
    String? jobType,
    String? address,
    AiProjectContext? projectContext,
    AiPersonaContext? persona,
    String? workflowTemplateName,
    String? workflowTemplateDescription,
    String? workflowTemplateMarkdown,
    Map<String, dynamic>? workflowTemplateSchema,
    AiProgressCallback? onProgress,
    AiStreamCallback? onStream,
  }) async {
    final userPrompt = _buildProjectPlanUserPrompt(
      projectName: projectName,
      description: description,
      jobType: jobType,
      address: address,
      projectContext: projectContext,
      workflowTemplateName: workflowTemplateName,
      workflowTemplateDescription: workflowTemplateDescription,
      workflowTemplateMarkdown: workflowTemplateMarkdown,
      workflowTemplateSchema: workflowTemplateSchema,
    );

    debugPrint('═══════════════════════════════════════════════════════════');
    debugPrint('🤖 AI SERVICE: Starting project plan generation');
    debugPrint('📝 Project: $projectName');
    debugPrint('📝 Job Type: ${jobType ?? "none"}');
    debugPrint('═══════════════════════════════════════════════════════════');

    const maxRetries = 2;

    for (int i = 0; i < _providers.length; i++) {
      final provider = _providers[i];
      final isLast = i == _providers.length - 1;

      for (int attempt = 1; attempt <= maxRetries; attempt++) {
        try {
          debugPrint('');
          debugPrint(
            '🔄 Trying provider ${i + 1}/${_providers.length}: ${provider.name}${attempt > 1 ? " (retry $attempt/$maxRetries)" : ""}',
          );

          onProgress?.call(
            provider.name,
            attempt > 1 ? 'Retrying...' : 'Connecting...',
          );

          final stopwatch = Stopwatch()..start();
          final content = await _callProviderGeneric(
            provider,
            _buildSystemPrompt(_projectPlanSystemPrompt, persona),
            userPrompt,
            maxTokens: 8000,
            nPredict: 8000,
            promptPrime: '{',
            timeout: const Duration(seconds: 180),
            onProgress: onProgress,
            onStream: onStream,
            progressMessage: 'Generating project plan...',
          );
          stopwatch.stop();

          final plan = _parseProjectPlanResponse(content);

          if (_isProjectPlanComplete(plan)) {
            debugPrint('');
            debugPrint(
              '✅ SUCCESS from ${provider.name}${attempt > 1 ? " (on retry $attempt)" : ""}',
            );
            debugPrint(
              '   Generated ${plan.phases.length} phases in ${stopwatch.elapsedMilliseconds}ms',
            );
            debugPrint(
              '   Phases: ${plan.phases.map((p) => p.name).join(", ")}',
            );
            debugPrint(
              '═══════════════════════════════════════════════════════════',
            );

            onProgress?.call(provider.name, 'Complete!');
            return plan;
          }

          if (plan.phases.isNotEmpty) {
            debugPrint('');
            debugPrint(
              '⚠️ INCOMPLETE PLAN from ${provider.name}: phases found but missing child tasks/budget items',
            );

            final enrichedPlan = _enrichProjectPlan(plan);
            if (_isProjectPlanComplete(enrichedPlan)) {
              debugPrint('   ✅ Recovered by enriching missing phase children');
              onProgress?.call(provider.name, 'Complete!');
              return enrichedPlan;
            }

            if (attempt < maxRetries) {
              onProgress?.call(provider.name, 'Incomplete plan, retrying...');
              await Future.delayed(const Duration(milliseconds: 500));
              continue;
            }
          }
        } on JsonParseException catch (e) {
          debugPrint('');
          debugPrint(
            '⚠️ JSON PARSE ERROR: ${provider.name} (attempt $attempt/$maxRetries)',
          );
          debugPrint('   Error: ${e.message}');

          if (attempt < maxRetries) {
            debugPrint('   🔁 Retrying same provider...');
            onProgress?.call(provider.name, 'JSON error, retrying...');
            await Future.delayed(const Duration(milliseconds: 500));
            continue;
          } else {
            debugPrint('   ❌ Max retries reached for JSON errors');
            break;
          }
        } catch (e) {
          debugPrint('');
          debugPrint('❌ FAILED: ${provider.name}');
          debugPrint('   Error: $e');
          break;
        }
      }

      if (!isLast) {
        debugPrint('   ➡️  Falling back to next provider...');
        onProgress?.call(_providers[i + 1].name, 'Trying fallback...');
      }
    }

    debugPrint('');
    debugPrint('💥 ALL PROVIDERS FAILED - using fallback template');
    debugPrint('═══════════════════════════════════════════════════════════');

    // Fallback: return template phases based on job type
    return _getFallbackProjectPlan(jobType);
  }

  String _buildProjectPlanUserPrompt({
    required String projectName,
    String? description,
    String? jobType,
    String? address,
    AiProjectContext? projectContext,
    String? workflowTemplateName,
    String? workflowTemplateDescription,
    String? workflowTemplateMarkdown,
    Map<String, dynamic>? workflowTemplateSchema,
  }) {
    final buffer = StringBuffer();
    buffer.writeln(
      'Generate a comprehensive project plan as a JSON object for this construction project:',
    );
    buffer.writeln('');
    buffer.writeln('PROJECT: $projectName');

    if (description != null && description.isNotEmpty) {
      buffer.writeln('DESCRIPTION: $description');
    }

    if (jobType != null && jobType.isNotEmpty) {
      buffer.writeln('JOB TYPE: $jobType');
    }

    if (address != null && address.isNotEmpty) {
      buffer.writeln('LOCATION: $address (use regional pricing for this area)');
    }

    if (projectContext != null && projectContext.hasContext) {
      if (projectContext.currency != null) {
        buffer.writeln(
          'CURRENCY: ${projectContext.currency} (use this currency for all prices)',
        );
      }
      if (projectContext.estimatedBudget != null) {
        buffer.writeln(
          'TARGET BUDGET: \$${projectContext.estimatedBudget!.toStringAsFixed(0)} (scale items appropriately)',
        );
      }
      if (projectContext.materialMarkupPercent != null) {
        buffer.writeln(
          'MATERIAL MARKUP: ${projectContext.materialMarkupPercent!.toStringAsFixed(0)}%',
        );
      }
      if (projectContext.laborMarkupPercent != null) {
        buffer.writeln(
          'LABOR MARKUP: ${projectContext.laborMarkupPercent!.toStringAsFixed(0)}%',
        );
      }
    }

    if (workflowTemplateName != null && workflowTemplateName.isNotEmpty) {
      buffer.writeln('');
      buffer.writeln('WORKFLOW TEMPLATE BASELINE: $workflowTemplateName');
      if (workflowTemplateDescription != null &&
          workflowTemplateDescription.isNotEmpty) {
        buffer.writeln(
          'WORKFLOW TEMPLATE DESCRIPTION: $workflowTemplateDescription',
        );
      }
      if (workflowTemplateSchema != null && workflowTemplateSchema.isNotEmpty) {
        buffer.writeln(
          'WORKFLOW TEMPLATE STRUCTURED DATA: ${jsonEncode(workflowTemplateSchema)}',
        );
      }
      if (workflowTemplateMarkdown != null &&
          workflowTemplateMarkdown.trim().isNotEmpty) {
        buffer.writeln('WORKFLOW TEMPLATE DETAILS:');
        buffer.writeln(workflowTemplateMarkdown.trim());
      }
      buffer.writeln(
        'Use this workflow template as the baseline plan structure and adapt it to this project. Preserve safety-critical sequencing and conditional logic where relevant.',
      );
    }

    buffer.writeln('');
    buffer.writeln(
      'Create phases appropriate for this job type with tasks and budget items in each phase. Respond with ONLY the JSON object.',
    );

    return buffer.toString();
  }

  AiProjectPlan _parseProjectPlanResponse(String content) {
    final jsonStr = _extractJson(content, '{', '}');

    Map<String, dynamic> data;
    try {
      data = jsonDecode(jsonStr) as Map<String, dynamic>;
    } on FormatException catch (e) {
      throw JsonParseException(
        'Invalid JSON format: ${e.message}',
        rawContent: jsonStr,
      );
    }

    try {
      final phases = (data['phases'] as List?)
              ?.asMap()
              .entries
              .map(
                (e) => AiProjectPhase.fromJson(
                  e.value as Map<String, dynamic>,
                  e.key,
                ),
              )
              .toList() ??
          [];

      final properties = (data['properties'] as List?)
              ?.map(
                (p) => AiProjectProperty.fromJson(p as Map<String, dynamic>),
              )
              .toList() ??
          [];

      return AiProjectPlan(phases: phases, properties: properties);
    } catch (e) {
      throw JsonParseException(
        'Failed to parse project plan: $e',
        rawContent: jsonStr,
      );
    }
  }

  @visibleForTesting
  AiProjectPlan parseProjectPlanResponseForTesting(String content) {
    return _parseProjectPlanResponse(content);
  }

  bool _isProjectPlanComplete(AiProjectPlan plan) {
    if (plan.phases.isEmpty) {
      return false;
    }
    return plan.phases.every(
      (phase) => phase.tasks.isNotEmpty && phase.budgetItems.isNotEmpty,
    );
  }

  AiProjectPlan _enrichProjectPlan(AiProjectPlan plan) {
    final enrichedPhases = <AiProjectPhase>[];

    for (var i = 0; i < plan.phases.length; i++) {
      final phase = plan.phases[i];
      final phaseTempId = phase.tempId.isNotEmpty ? phase.tempId : 'phase_$i';

      final tasks = phase.tasks.isNotEmpty
          ? phase.tasks
          : [
              AiPhaseTask(
                tempId: '${phaseTempId}_task_0',
                title: 'Execute ${phase.name}',
                description:
                    phase.description ?? 'Complete work for ${phase.name}.',
                estimatedDuration: 8,
                priority: 'medium',
                checklistItems: const [
                  'Review scope',
                  'Perform field work',
                  'Quality check',
                ],
              ),
            ];

      final budgetItems = phase.budgetItems.isNotEmpty
          ? phase.budgetItems
          : [
              AiPhaseBudgetItem(
                tempId: '${phaseTempId}_bi_0',
                name: '${phase.name} Labor',
                quantity: 8,
                unit: 'hr',
                unitCost: 75,
                unitPrice: 115,
              ),
              AiPhaseBudgetItem(
                tempId: '${phaseTempId}_bi_1',
                name: '${phase.name} Materials',
                quantity: 1,
                unit: 'lot',
                unitCost: 500,
                unitPrice: 750,
              ),
            ];

      enrichedPhases.add(
        AiProjectPhase(
          tempId: phaseTempId,
          name: phase.name,
          description: phase.description,
          sortOrder: phase.sortOrder,
          tasks: tasks,
          budgetItems: budgetItems,
        ),
      );
    }

    return AiProjectPlan(phases: enrichedPhases, properties: plan.properties);
  }

  @visibleForTesting
  AiProjectPlan enrichProjectPlanForTesting(AiProjectPlan plan) {
    return _enrichProjectPlan(plan);
  }

  /// Fallback project plan when AI fails - returns template phases based on job type
  AiProjectPlan _getFallbackProjectPlan(String? jobType) {
    final type = jobType?.toLowerCase() ?? '';
    List<String> phaseNames;

    if (type.contains('emergency') || type.contains('restoration')) {
      phaseNames = [
        'FNOL & Intake',
        'Emergency Response',
        'Mitigation',
        'Drying & Monitoring',
        'Repair Estimate',
        'Repairs',
        'Final Inspection & Close',
      ];
    } else if (type.contains('renovation')) {
      phaseNames = [
        'Pre-Construction',
        'Demolition',
        'Rough-In',
        'Finishes',
        'Final Fit-Out',
        'Closeout',
      ];
    } else if (type.contains('new') || type.contains('construction')) {
      phaseNames = [
        'Site Prep',
        'Structure',
        'Rough-In MEP',
        'Envelope',
        'Interior Finishes',
        'Final Systems',
        'Punch List & Closeout',
      ];
    } else {
      phaseNames = [
        'Assessment',
        'Planning',
        'Execution',
        'Quality Check',
        'Closeout',
      ];
    }

    final fallbackPlan = AiProjectPlan(
      phases: phaseNames
          .asMap()
          .entries
          .map(
            (e) => AiProjectPhase(
              tempId: 'phase_${e.key}',
              name: e.value,
              sortOrder: e.key,
            ),
          )
          .toList(),
    );

    return _enrichProjectPlan(fallbackPlan);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // DOCUMENT DRAFT GENERATION
  // ═══════════════════════════════════════════════════════════════════════════

  static const String _documentDraftSystemPrompt =
      '''You are a professional document writer for a construction/contracting business. Generate content for a business document.

Output EXACTLY 4 labeled sections using these headers (each on its own line):
## SCOPE
## FOOTER
## EMAIL_SUBJECT
## EMAIL_MESSAGE

Rules:
- ## SCOPE: A professional scope of work / description for the document body. 2-4 paragraphs. Be specific to the project context provided.
- ## FOOTER: A brief professional footer with terms, conditions, or closing notes. 1-2 short paragraphs.
- ## EMAIL_SUBJECT: A single-line email subject for sending this document.
- ## EMAIL_MESSAGE: A brief professional email body (2-3 sentences) to accompany the document.
- Use plain text only, no markdown formatting within sections.
- Be concise and professional. Tailor content to the document type and project details provided.''';

  /// Generate a document draft with scope, footer, and email content.
  Future<AiDocumentDraft> generateDocumentDraft({
    required String documentTypeName,
    String? projectName,
    String? projectAddress,
    String? projectDescription,
    String? jobType,
    String? customerName,
    String? customerCompany,
    String? workspaceName,
    List<String>? lineItemNames,
    AiPersonaContext? persona,
    AiProgressCallback? onProgress,
    AiStreamCallback? onStream,
  }) async {
    debugPrint('═══════════════════════════════════════════════════════════');
    debugPrint('🤖 AI SERVICE: Generating document draft');
    debugPrint('📄 Document type: $documentTypeName');
    debugPrint('═══════════════════════════════════════════════════════════');

    final contextParts = <String>[];
    contextParts.add('Document type: $documentTypeName');
    if (workspaceName != null && workspaceName.isNotEmpty) {
      contextParts.add('Company: $workspaceName');
    }
    if (projectName != null && projectName.isNotEmpty) {
      contextParts.add('Project: $projectName');
    }
    if (projectAddress != null && projectAddress.isNotEmpty) {
      contextParts.add('Project address: $projectAddress');
    }
    if (projectDescription != null && projectDescription.isNotEmpty) {
      contextParts.add('Project description: $projectDescription');
    }
    if (jobType != null && jobType.isNotEmpty) {
      contextParts.add('Job type: $jobType');
    }
    if (customerName != null && customerName.isNotEmpty) {
      contextParts.add('Customer: $customerName');
    }
    if (customerCompany != null && customerCompany.isNotEmpty) {
      contextParts.add('Customer company: $customerCompany');
    }
    if (lineItemNames != null && lineItemNames.isNotEmpty) {
      contextParts.add('Line items: ${lineItemNames.join(', ')}');
    }

    final userPrompt =
        'Generate professional document content for the following:\n\n${contextParts.join('\n')}';

    final draft = await _runWithProviderFallback<AiDocumentDraft>(
      invoke: (provider) async {
        final content = await _callProviderGeneric(
          provider,
          _buildSystemPrompt(_documentDraftSystemPrompt, persona),
          userPrompt,
          maxTokens: 2000,
          nPredict: 2000,
          timeout: const Duration(seconds: 90),
          onProgress: onProgress,
          onStream: onStream,
          progressMessage: 'Drafting document...',
        );
        return _parseDocumentDraft(content);
      },
      isValidResult: (result) => result.scopeContent.isNotEmpty,
      maxRetries: 2,
      initialProgressMessage: 'Drafting document...',
      retryProgressMessage: 'Retrying draft...',
      jsonRetryProgressMessage: 'Retrying draft...',
      fallbackProgressMessage: 'Trying fallback...',
      onProgress: onProgress,
      onSuccess: (provider, result, _, stopwatch) {
        debugPrint('');
        debugPrint('✅ Document draft from ${provider.name}');
        debugPrint(
          '   Scope: ${result.scopeContent.length} chars, Footer: ${result.footerContent.length} chars',
        );
        debugPrint(
          '   Generated in ${stopwatch.elapsedMilliseconds}ms',
        );
      },
    );

    return draft;
  }

  AiDocumentDraft _parseDocumentDraft(String content) {
    final normalized = content.trim();
    String extractSection(String header) {
      final pattern = RegExp(
        '##\\s*$header\\s*\n(.*?)(?=\\n##\\s|\$)',
        caseSensitive: false,
        dotAll: true,
      );
      final match = pattern.firstMatch(normalized);
      return match?.group(1)?.trim() ?? '';
    }

    return AiDocumentDraft(
      scopeContent: extractSection('SCOPE'),
      footerContent: extractSection('FOOTER'),
      emailSubject: extractSection('EMAIL_SUBJECT'),
      emailMessage: extractSection('EMAIL_MESSAGE'),
    );
  }
}
