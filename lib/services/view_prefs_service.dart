import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/app_logger.dart';

/// Persists per-user UI view state (filters, sort, columns, view modes, ...)
/// across sessions and devices, with low overhead on the hot path.
///
/// Storage stack:
///   in-memory (canonical) → SharedPreferences (~150 ms debounce, per-user) →
///   Supabase user_preferences.preferences['views'] (~1.5 s debounce).
///
/// Each scope key (e.g. `projects.list.v1`, `project.{id}.tasks.v1`) owns
/// a small JSON blob plus two reserved fields: `_v` (schema version) and
/// `_ts` (millisecond timestamp, used for last-write-wins per key when the
/// same user edits in two tabs).
class SupabaseViewPrefsService {
  static const _localKeyPrefix = 'view_prefs_v1_';
  static const _serverParentKey = 'views';
  static const _localDebounce = Duration(milliseconds: 150);
  static const _remoteDebounce = Duration(milliseconds: 1500);
  static const _projectScopePrefix = 'project.';
  static const _projectScopeMax = 50;
  static const _flushReconcileTimeout = Duration(seconds: 3);
  static const _schemaVersion = 1;

  final SupabaseClient _supabase = Supabase.instance.client;

  final Map<String, Map<String, dynamic>> _memory = {};
  final Set<String> _dirtyLocal = {};
  final Set<String> _dirtyRemote = {};
  final Map<String, StreamController<void>> _streams = {};

  Timer? _localTimer;
  Timer? _remoteTimer;

  /// Chain of pending remote upserts. Used to serialize network writes so
  /// two concurrent flushes can't clobber each other (the older snapshot
  /// finishing last would overwrite newer data).
  Future<void>? _remoteChain;

  String? _userId;
  SharedPreferences? _prefs;
  bool _isHydrated = false;
  Completer<void>? _reconcileCompleter;
  Completer<void>? _hydratedCompleter;

  bool get isHydrated => _isHydrated;

  /// Resolves once initial hydration (auth + local cache) has completed for
  /// the current user. Safe to await from `initState` — never throws.
  Future<void> get whenHydrated {
    if (_isHydrated) return Future.value();
    return (_hydratedCompleter ??= Completer<void>()).future;
  }

  /// Read the blob stored at [scopeKey], or null if none exists yet. The
  /// reserved `_v` / `_ts` fields are stripped before return.
  Map<String, dynamic>? read(String scopeKey) {
    final entry = _memory[scopeKey];
    if (entry == null) return null;
    return Map<String, dynamic>.from(entry)
      ..remove('_v')
      ..remove('_ts');
  }

  /// Write the blob for [scopeKey]. Fire-and-forget — persistence happens
  /// debounced in the background.
  void write(String scopeKey, Map<String, dynamic> data) {
    if (_userId == null) return;
    _memory[scopeKey] = <String, dynamic>{
      ...data,
      '_v': _schemaVersion,
      '_ts': DateTime.now().millisecondsSinceEpoch,
    };
    _dirtyLocal.add(scopeKey);
    _dirtyRemote.add(scopeKey);
    _enforceProjectScopeCap();
    _scheduleLocalFlush();
    _scheduleRemoteFlush();
    _streams[scopeKey]?.add(null);
  }

  /// Drop the entry for [scopeKey] from memory and storage.
  void remove(String scopeKey) {
    if (_memory.remove(scopeKey) == null) return;
    _dirtyLocal.add(scopeKey);
    _dirtyRemote.add(scopeKey);
    _scheduleLocalFlush();
    _scheduleRemoteFlush();
    _streams[scopeKey]?.add(null);
  }

  /// Stream that emits when [scopeKey]'s value changes (local edit or
  /// server reconcile).
  Stream<void> changes(String scopeKey) {
    return _streams
        .putIfAbsent(scopeKey, () => StreamController<void>.broadcast())
        .stream;
  }

  /// Force-flush both local and remote pending writes. Used on app pause /
  /// sign-out before clearing state.
  Future<void> flush() async {
    _localTimer?.cancel();
    _remoteTimer?.cancel();
    await _writeLocal();
    _enqueueRemoteWrite();
    await _remoteChain;
  }

  /// Hook called from AuthProvider when the active user changes. Flushes
  /// pending writes for the previous user, then hydrates state for the new
  /// user (or clears if signed out).
  Future<void> onAuthChanged(String? userId) async {
    if (_userId == userId && _isHydrated) return;
    await flush();
    _memory.clear();
    _dirtyLocal.clear();
    _dirtyRemote.clear();
    _isHydrated = false;
    _reconcileCompleter = null;
    if (_hydratedCompleter?.isCompleted ?? false) _hydratedCompleter = null;
    _userId = userId;

    if (userId == null) {
      _markHydrated();
      _notifyAll();
      return;
    }

    await _hydrateFromLocal();
    _markHydrated();
    _notifyAll();

    final completer = _reconcileCompleter = Completer<void>();
    unawaited(
      _reconcileFromServer().whenComplete(() {
        if (!completer.isCompleted) completer.complete();
      }),
    );
  }

  void _markHydrated() {
    _isHydrated = true;
    final c = _hydratedCompleter;
    if (c != null && !c.isCompleted) c.complete();
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  String get _localKey => '$_localKeyPrefix${_userId ?? "anon"}';

  Future<void> _hydrateFromLocal() async {
    final prefs = _prefs ??= await SharedPreferences.getInstance();
    final raw = prefs.getString(_localKey);
    if (raw == null) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        decoded.forEach((key, value) {
          if (key is String && value is Map) {
            _memory[key] = Map<String, dynamic>.from(value);
          }
        });
      }
    } catch (e) {
      AppLogger.warning(
        'Failed to decode local view prefs',
        metadata: {'error': e.toString()},
      );
    }
  }

  Future<void> _reconcileFromServer() async {
    final userId = _userId;
    if (userId == null) return;
    try {
      final row = await _supabase
          .from('user_preferences')
          .select('preferences')
          .eq('user_id', userId)
          .maybeSingle();
      final prefs = row == null
          ? const <String, dynamic>{}
          : Map<String, dynamic>.from(row['preferences'] as Map? ?? {});
      final views = prefs[_serverParentKey];
      if (views is! Map) return;

      final changedKeys = <String>{};
      views.forEach((key, value) {
        if (key is! String || value is! Map) return;
        final serverBlob = Map<String, dynamic>.from(value);
        final serverTs = (serverBlob['_ts'] as num?)?.toInt() ?? 0;
        final localTs = (_memory[key]?['_ts'] as num?)?.toInt() ?? 0;
        if (serverTs > localTs) {
          _memory[key] = serverBlob;
          changedKeys.add(key);
        }
      });

      if (changedKeys.isNotEmpty) {
        _dirtyLocal.addAll(changedKeys);
        _scheduleLocalFlush();
        for (final key in changedKeys) {
          _streams[key]?.add(null);
        }
      }
    } catch (e) {
      AppLogger.debug(
        'View prefs server reconcile failed',
        metadata: {'error': e.toString()},
      );
    }
  }

  void _scheduleLocalFlush() {
    _localTimer?.cancel();
    _localTimer = Timer(_localDebounce, () {
      unawaited(_writeLocal());
    });
  }

  void _scheduleRemoteFlush() {
    _remoteTimer?.cancel();
    _remoteTimer = Timer(_remoteDebounce, _enqueueRemoteWrite);
  }

  void _enqueueRemoteWrite() {
    _remoteChain = (_remoteChain ?? Future<void>.value())
        .then((_) => _writeRemote())
        .catchError((_) {}); // _writeRemote already swallows errors; defensive.
  }

  Future<void> _writeLocal() async {
    if (_dirtyLocal.isEmpty) return;
    _dirtyLocal.clear();
    final prefs = _prefs ??= await SharedPreferences.getInstance();
    try {
      if (_memory.isEmpty) {
        await prefs.remove(_localKey);
      } else {
        await prefs.setString(_localKey, jsonEncode(_memory));
      }
    } catch (e) {
      AppLogger.warning(
        'Failed to write view prefs locally',
        metadata: {'error': e.toString()},
      );
    }
  }

  Future<void> _writeRemote() async {
    if (_dirtyRemote.isEmpty) return;
    final userId = _userId;
    if (userId == null) {
      _dirtyRemote.clear();
      return;
    }

    // Wait for the initial server reconcile so we don't clobber keys that
    // exist on the server but haven't been merged into local memory yet.
    final reconcile = _reconcileCompleter?.future;
    if (reconcile != null) {
      try {
        await reconcile.timeout(_flushReconcileTimeout);
      } on TimeoutException {
        // Reconcile is slow; don't block forever — but skip this remote
        // flush so we don't risk clobbering. Keep the dirty set; the next
        // change (or next flush()) will retry.
        return;
      }
    }
    if (_userId != userId) {
      _dirtyRemote.clear();
      return;
    }

    final keysBeingFlushed = Set<String>.from(_dirtyRemote);
    _dirtyRemote.clear();
    try {
      final row = await _supabase
          .from('user_preferences')
          .select('preferences')
          .eq('user_id', userId)
          .maybeSingle();
      final current = row == null
          ? <String, dynamic>{}
          : Map<String, dynamic>.from(row['preferences'] as Map? ?? {});
      current[_serverParentKey] = Map<String, dynamic>.from(_memory);
      await _supabase.from('user_preferences').upsert({
        'user_id': userId,
        'preferences': current,
        'updated_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      AppLogger.warning(
        'Failed to write view prefs remotely',
        metadata: {'error': e.toString()},
      );
      // Re-queue — the next change or flush() retries.
      _dirtyRemote.addAll(keysBeingFlushed);
    }
  }

  /// LRU-style eviction of `project.*` entries beyond [_projectScopeMax].
  /// Recency comes from `_ts` — `write()` always stamps `now`, so the
  /// most-recently-touched scopes survive.
  void _enforceProjectScopeCap() {
    final projectKeys = _memory.keys
        .where((k) => k.startsWith(_projectScopePrefix))
        .toList();
    if (projectKeys.length <= _projectScopeMax) return;
    projectKeys.sort((a, b) {
      final ta = (_memory[a]?['_ts'] as num?)?.toInt() ?? 0;
      final tb = (_memory[b]?['_ts'] as num?)?.toInt() ?? 0;
      return ta.compareTo(tb);
    });
    final evictCount = projectKeys.length - _projectScopeMax;
    for (final key in projectKeys.take(evictCount)) {
      _memory.remove(key);
      _dirtyLocal.add(key);
      _dirtyRemote.add(key);
      _streams[key]?.add(null);
    }
  }

  void _notifyAll() {
    for (final c in _streams.values) {
      if (!c.isClosed) c.add(null);
    }
  }
}
