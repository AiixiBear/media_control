import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/media_control_api.dart';
import '../models/media.dart';
import '../server/media_control_server.dart';
import '../server/server_settings.dart';
import 'app_colors.dart';
import 'app_settings.dart';
import 'settings_page.dart';
import 'widgets.dart';

class MediaControlApp extends StatefulWidget {
  const MediaControlApp({
    super.key,
    this.api = const PlatformMediaControlApi(),
    this.autoStartServer = true,
    this.autoStartBackgroundProtection = false,
  });

  final MediaControlApi api;
  final bool autoStartServer;
  final bool autoStartBackgroundProtection;

  @override
  State<MediaControlApp> createState() => _MediaControlAppState();
}

class _MediaControlAppState extends State<MediaControlApp>
    with WidgetsBindingObserver {
  late final MediaControlServer _server;
  Timer? _pollTimer;

  MediaSnapshot? _snapshot;
  Uri? _serverUri;
  String? _localAddress;
  String? _errorMessage;
  ServerSettings _settings = const ServerSettings();
  AppThemeMode _themeMode = AppThemeMode.dark;
  List<String> _availableInterfaces = <String>['0.0.0.0'];
  bool _backgroundProtectionEnabled = false;
  bool _startingServer = false;
  bool _startingBackgroundProtection = false;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _server = MediaControlServer(api: widget.api);
    _bootstrap();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshSnapshot();
    }
  }

  Future<void> _bootstrap() async {
    await _loadSettings();
    if (widget.autoStartBackgroundProtection) {
      await _startBackgroundProtection();
    }
    if (widget.autoStartServer) {
      await _startServer();
    }
    await _refreshSnapshot();
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _refreshSnapshot();
    });
  }

  Future<void> _startBackgroundProtection() async {
    if (_backgroundProtectionEnabled || _startingBackgroundProtection) {
      return;
    }

    setState(() {
      _startingBackgroundProtection = true;
      _errorMessage = null;
    });

    try {
      final permissionGranted = await widget.api.ensureNotificationPermission();
      if (!permissionGranted) {
        throw StateError('Notification permission was not granted.');
      }

      await widget.api.startBackgroundProtection();
      if (!mounted) {
        return;
      }
      setState(() {
        _backgroundProtectionEnabled = true;
      });
      await _syncBackgroundProtectionNotification();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _startingBackgroundProtection = false;
        });
      }
    }
  }

  Future<void> _startServer({bool confirmRestart = true}) async {
    if (_startingServer) {
      return;
    }

    if (_serverUri != null && confirmRestart) {
      final confirmed = await _confirmRestartServer();
      if (!confirmed) {
        return;
      }
    }

    setState(() {
      _startingServer = true;
      _errorMessage = null;
    });

    try {
      if (_serverUri != null) {
        await _server.stop();
      }
      final uri = await _server.start(port: _settings.normalizedPort);
      final localAddress = await _resolveServerAddress();
      if (!mounted) {
        return;
      }
      setState(() {
        _serverUri = uri;
        _localAddress = localAddress;
      });
      await _syncBackgroundProtectionNotification();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _startingServer = false;
        });
      }
    }
  }

  Future<void> _stopServer() async {
    if (_serverUri == null) {
      return;
    }
    await _server.stop();
    if (!mounted) {
      return;
    }
    setState(() {
      _serverUri = null;
      _localAddress = null;
    });
    await _syncBackgroundProtectionNotification();
  }

  Future<void> _syncBackgroundProtectionNotification() async {
    if (!_backgroundProtectionEnabled || _serverUri == null) {
      return;
    }

    final webUrl = _settings.buildUrl(
      _localAddress ?? 'localhost',
      _serverUri!.port,
    );
    await widget.api.updateBackgroundProtectionNotification(webUrl: webUrl);
  }

  Future<void> _refreshSnapshot() async {
    if (_refreshing) {
      return;
    }

    _refreshing = true;
    try {
      final snapshot = await widget.api.getSnapshot();
      if (!mounted) {
        return;
      }
      setState(() {
        _snapshot = snapshot;
        _errorMessage = null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = error.toString();
      });
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _control(Future<void> Function() action) async {
    try {
      await action();
      await _refreshSnapshot();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = error.toString();
      });
    }
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final password = prefs.getString('server_password') ?? '';
      final listenInterface =
          prefs.getString('server_listen_interface') ?? '0.0.0.0';
      final port = prefs.getInt('server_port') ?? ServerSettings.defaultPort;
      final updateMode =
          prefs.getString('webui_update_mode') ??
          ServerSettings.defaultWebUiUpdateMode;
      final themeMode = AppThemeMode.fromStorage(
        prefs.getString('app_theme_mode'),
      );
      final interfaces = await _discoverInterfaces();
      if (!mounted) {
        return;
      }
      setState(() {
        _settings = ServerSettings(
          password: password,
          listenInterface: listenInterface,
          port: port,
          webUiUpdateMode: updateMode,
        );
        _themeMode = themeMode;
        _availableInterfaces = interfaces;
      });
      _server.updateSettings(_settings);
    } catch (_) {
      final interfaces = await _discoverInterfaces();
      if (!mounted) {
        return;
      }
      setState(() {
        _settings = const ServerSettings();
        _availableInterfaces = interfaces;
      });
      _server.updateSettings(_settings);
    }
  }

  Future<void> _saveSettings(
    ServerSettings settings,
    AppThemeMode themeMode,
  ) async {
    setState(() {
      _settings = settings;
      _themeMode = themeMode;
    });
    _server.updateSettings(settings);

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('server_password', settings.normalizedPassword);
      await prefs.setString(
        'server_listen_interface',
        settings.normalizedListenInterface,
      );
      await prefs.setInt('server_port', settings.normalizedPort);
      await prefs.setString(
        'webui_update_mode',
        settings.normalizedWebUiUpdateMode,
      );
      await prefs.setString('app_theme_mode', themeMode.storageValue);
      if (_serverUri != null) {
        final confirmed = await _confirmRestartServer();
        if (confirmed) {
          await _startServer(confirmRestart: false);
        }
      } else {
        await _startServer(confirmRestart: false);
      }
    } catch (_) {
      // Ignore persistence failures and keep the in-memory settings active.
    }
  }

  Future<bool> _confirmRestartServer() async {
    if (!mounted) {
      return false;
    }

    return await showDialog<bool>(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              backgroundColor: const Color(0xFF10253B),
              title: const Text(
                '重新啟動伺服器',
                style: TextStyle(color: Colors.white),
              ),
              content: const Text(
                '設定已變更，是否要重新啟動伺服器以套用新的網址與權限設定？',
                style: TextStyle(color: Colors.white70),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text(
                    '取消',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('重新啟動'),
                ),
              ],
            );
          },
        ) ??
        false;
  }

  Future<List<String>> _discoverInterfaces() async {
    final discovered = <String>{'0.0.0.0'};
    try {
      final interfaces = await NetworkInterface.list(
        includeLinkLocal: false,
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );

      for (final networkInterface in interfaces) {
        for (final address in networkInterface.addresses) {
          if (!address.isLoopback && !address.address.startsWith('169.254.')) {
            discovered.add(address.address);
          }
        }
      }
    } catch (_) {
      // Fall back to the default list.
    }
    return discovered.toList()..sort();
  }

  Future<String?> _resolveServerAddress() async {
    final preferredInterface = _settings.normalizedListenInterface;
    if (preferredInterface != '0.0.0.0' && preferredInterface != 'all') {
      return preferredInterface;
    }

    try {
      final interfaces = await NetworkInterface.list(
        includeLinkLocal: false,
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );

      for (final networkInterface in interfaces) {
        for (final address in networkInterface.addresses) {
          if (!address.isLoopback && !address.address.startsWith('169.254.')) {
            return address.address;
          }
        }
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  String _formatDuration(int milliseconds) {
    if (milliseconds <= 0) {
      return '--:--';
    }
    final totalSeconds = (milliseconds / 1000).floor();
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  Future<void> _copyToClipboard(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('網址已複製到剪貼簿')));
  }

  Future<void> _openSettingsPage() async {
    // The page calls onSave (_saveSettings) itself before popping, so
    // there is nothing to save again here; doing so would ask to restart
    // the server a second time.
    await Navigator.of(context).push<ServerSettings>(
      MaterialPageRoute<ServerSettings>(
        builder: (BuildContext context) {
          return ServerSettingsPage(
            initialSettings: _settings,
            initialThemeMode: _themeMode,
            availableInterfaces: _availableInterfaces,
            currentHost: _localAddress ?? 'localhost',
            currentPort: _settings.normalizedPort,
            onSave: _saveSettings,
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF5CE1E6),
      brightness: Brightness.dark,
    );
    final snapshot = _snapshot ?? MediaSnapshot.empty();
    final activeSession = snapshot.activeSession;

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '大便媒體控制',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF5CE1E6),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF4F7FA),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: colorScheme,
        scaffoldBackgroundColor: const Color(0xFF07111D),
        useMaterial3: true,
      ),
      themeMode: _themeMode.themeMode,
      home: Builder(
        builder: (BuildContext context) {
          return Scaffold(
            body: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: AppColors.pageGradient(context),
                ),
              ),
              child: SafeArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 980),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          HeroCard(
                            snapshot: snapshot,
                            serverRunning: _serverUri != null,
                            serverLoading: _startingServer,
                            serverError: _errorMessage,
                            serverPort: _serverUri?.port,
                            authRequired: _settings.authRequired,
                            onStartServer: _startServer,
                            onStopServer: _stopServer,
                            onRefresh: _refreshSnapshot,
                            onOpenSettings: _openSettingsPage,
                          ),
                          const SizedBox(height: 20),
                          if (_serverUri != null && !_settings.authRequired)
                            InlineMessage(
                              icon: Icons.warning_amber_outlined,
                              title: '未設定密碼',
                              message: '區網內任何裝置都可開啟 Web UI 並控制播放。請到「設定」設定一組密碼。',
                            ),
                          if (_serverUri != null && !_settings.authRequired)
                            const SizedBox(height: 20),
                          ServerCard(
                            serverUri: _serverUri,
                            displayUrl: _serverUri == null
                                ? null
                                : _settings.buildUrl(
                                    _localAddress ?? 'localhost',
                                    _serverUri!.port,
                                  ),
                            onCopy: _serverUri == null
                                ? null
                                : () => _copyToClipboard(
                                    _settings.buildUrl(
                                      _localAddress ?? 'localhost',
                                      _serverUri!.port,
                                    ),
                                  ),
                            authRequired: _settings.authRequired,
                            updateModeLabel: _settings.webUiUpdateModeLabel,
                          ),
                          const SizedBox(height: 20),
                          BackgroundProtectionCard(
                            enabled: _backgroundProtectionEnabled,
                            loading: _startingBackgroundProtection,
                            onEnable: _startBackgroundProtection,
                          ),
                          const SizedBox(height: 20),
                          PermissionCard(
                            enabled: snapshot.listenerEnabled,
                            onOpenSettings: () =>
                                _control(widget.api.openNotificationSettings),
                          ),
                          const SizedBox(height: 20),
                          if (activeSession != null)
                            NowPlayingCard(
                              session: activeSession,
                              formatDuration: _formatDuration,
                              onPlay: () => _control(
                                () => widget.api.play(
                                  packageName: activeSession.packageName,
                                ),
                              ),
                              onPause: () => _control(
                                () => widget.api.pause(
                                  packageName: activeSession.packageName,
                                ),
                              ),
                              onNext: () => _control(
                                () => widget.api.next(
                                  packageName: activeSession.packageName,
                                ),
                              ),
                              onPrevious: () => _control(
                                () => widget.api.previous(
                                  packageName: activeSession.packageName,
                                ),
                              ),
                              onSeekTo: (Duration position) => _control(
                                () => widget.api.seekTo(
                                  packageName: activeSession.packageName,
                                  position: position,
                                ),
                              ),
                            )
                          else
                            EmptyStateCard(title: '沒有媒體進程', message: '去播音樂阿'),
                          const SizedBox(height: 20),
                          SessionListCard(
                            sessions: snapshot.sessions,
                            formatDuration: _formatDuration,
                            onPlay: (MediaSessionInfo session) => _control(
                              () => widget.api.play(
                                packageName: session.packageName,
                              ),
                            ),
                            onPause: (MediaSessionInfo session) => _control(
                              () => widget.api.pause(
                                packageName: session.packageName,
                              ),
                            ),
                            onNext: (MediaSessionInfo session) => _control(
                              () => widget.api.next(
                                packageName: session.packageName,
                              ),
                            ),
                            onPrevious: (MediaSessionInfo session) => _control(
                              () => widget.api.previous(
                                packageName: session.packageName,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
