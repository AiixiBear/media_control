import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../server/server_settings.dart';
import 'app_colors.dart';
import 'app_settings.dart';
import 'widgets.dart';

/// The app's Settings page (Traditional Chinese-first).
///
/// Edits the server settings (password/token, port, listen interface,
/// Web UI update mode) and the app appearance (theme). The password saved
/// here is the same credential the local server checks — it is stored in
/// SharedPreferences by the caller, never hard-coded.
class ServerSettingsPage extends StatefulWidget {
  const ServerSettingsPage({
    super.key,
    required this.initialSettings,
    required this.initialThemeMode,
    required this.availableInterfaces,
    required this.currentHost,
    required this.currentPort,
    required this.onSave,
  });

  final ServerSettings initialSettings;
  final AppThemeMode initialThemeMode;
  final List<String> availableInterfaces;
  final String currentHost;
  final int currentPort;
  final Future<void> Function(ServerSettings settings, AppThemeMode themeMode)
  onSave;

  @override
  State<ServerSettingsPage> createState() => _ServerSettingsPageState();
}

class _ServerSettingsPageState extends State<ServerSettingsPage> {
  late final TextEditingController _passwordController;
  late final TextEditingController _portController;
  late String _selectedInterface;
  late String _selectedUpdateMode;
  late AppThemeMode _selectedThemeMode;
  bool _saving = false;
  String? _validationError;

  void _generateToken() {
    _passwordController.text = ServerSettings.generateToken();
    setState(() {
      _validationError = null;
    });
  }

  @override
  void initState() {
    super.initState();
    _passwordController = TextEditingController(
      text: widget.initialSettings.password,
    );
    _portController = TextEditingController(
      text: widget.initialSettings.normalizedPort.toString(),
    );
    _selectedInterface = widget.initialSettings.normalizedListenInterface;
    _selectedUpdateMode = widget.initialSettings.normalizedWebUiUpdateMode;
    _selectedThemeMode = widget.initialThemeMode;
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _portController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final passwordError = ServerSettings.validatePassword(
      _passwordController.text,
    );
    if (passwordError != null) {
      setState(() {
        _validationError = passwordError;
      });
      return;
    }
    final portError = ServerSettings.validatePort(_portController.text);
    if (portError != null) {
      setState(() {
        _validationError = portError;
      });
      return;
    }

    setState(() {
      _validationError = null;
      _saving = true;
    });

    final settings = ServerSettings(
      password: _passwordController.text,
      listenInterface: _selectedInterface,
      port: int.parse(_portController.text.trim()),
      webUiUpdateMode: _selectedUpdateMode,
    );

    try {
      await widget.onSave(settings, _selectedThemeMode);
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(settings);
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  String get _previewUrl {
    final settings = ServerSettings(
      password: _passwordController.text,
      listenInterface: _selectedInterface,
      port: int.tryParse(_portController.text.trim()) ?? widget.currentPort,
      webUiUpdateMode: _selectedUpdateMode,
    );
    return settings.buildUrl(widget.currentHost, settings.normalizedPort);
  }

  Future<void> _copyUrl() async {
    await Clipboard.setData(ClipboardData(text: _previewUrl));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('網址已複製到剪貼簿')));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('設定'),
        backgroundColor: AppColors.appBar(context),
        foregroundColor: AppColors.text(context),
      ),
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '設定本機 Web UI 與 App 外觀',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '密碼、連接埠或更新方式變更後，需要重新啟動伺服器才會生效；主題會立即套用。',
                  style: TextStyle(color: AppColors.muted(context)),
                ),
                const SizedBox(height: 20),
                PanelCard(
                  title: '密碼保護',
                  subtitle:
                      '至少 8 個字元，不可含空白與 / ? # \\ < >。留空代表不設密碼，但區網內任何裝置都可控制播放。',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      TextField(
                        controller: _passwordController,
                        onChanged: (_) => setState(() {}),
                        style: TextStyle(color: AppColors.text(context)),
                        decoration: InputDecoration(
                          labelText: '密碼',
                          labelStyle: TextStyle(
                            color: AppColors.muted(context),
                          ),
                          suffixIcon: IconButton(
                            icon: Icon(
                              Icons.clear,
                              color: AppColors.muted(context),
                            ),
                            onPressed: () {
                              _passwordController.clear();
                              setState(() {});
                            },
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(
                              color: AppColors.panelBorder(context),
                            ),
                          ),
                          focusedBorder: const OutlineInputBorder(
                            borderSide: BorderSide(color: Color(0xFF5CE1E6)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: <Widget>[
                          OutlinedButton.icon(
                            onPressed: _generateToken,
                            icon: const Icon(Icons.casino_outlined),
                            label: const Text('產生隨機密碼'),
                          ),
                        ],
                      ),
                      if (_validationError != null) ...<Widget>[
                        const SizedBox(height: 12),
                        Text(
                          _validationError!,
                          style: const TextStyle(color: Color(0xFFFF8A8A)),
                        ),
                      ],
                      if (_passwordController.text.trim().isEmpty) ...<Widget>[
                        const SizedBox(height: 12),
                        const Text(
                          '未設定密碼：區網內任何裝置都可控制播放，建議設定一組密碼。',
                          style: TextStyle(color: Color(0xFFF59E0B)),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Text(
                        '更換密碼後，Home Assistant 也要同步更新（標頭或網址前綴擇一），舊密碼會立即失效。',
                        style: TextStyle(color: AppColors.muted(context)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                PanelCard(
                  title: '伺服器',
                  subtitle: '連接埠、監聽介面與 Web UI 更新方式。',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      TextField(
                        controller: _portController,
                        keyboardType: TextInputType.number,
                        onChanged: (_) => setState(() {}),
                        style: TextStyle(color: AppColors.text(context)),
                        decoration: InputDecoration(
                          labelText: '連接埠',
                          labelStyle: TextStyle(
                            color: AppColors.muted(context),
                          ),
                          hintText: '8080',
                          hintStyle: TextStyle(color: AppColors.faint(context)),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(
                              color: AppColors.panelBorder(context),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: Color(0xFF5CE1E6)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        initialValue: _selectedInterface,
                        decoration: InputDecoration(
                          labelText: '監聽介面',
                          labelStyle: TextStyle(
                            color: AppColors.muted(context),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(
                              color: AppColors.panelBorder(context),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: Color(0xFF5CE1E6)),
                          ),
                        ),
                        dropdownColor: const Color(0xFF10253B),
                        items: widget.availableInterfaces
                            .map((String interface) {
                              return DropdownMenuItem<String>(
                                value: interface,
                                child: Text(
                                  interface,
                                  style: TextStyle(
                                    color: AppColors.text(context),
                                  ),
                                ),
                              );
                            })
                            .toList(growable: false),
                        onChanged: (String? value) {
                          if (value != null) {
                            setState(() {
                              _selectedInterface = value;
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Web UI 更新方式',
                        style: TextStyle(
                          color: AppColors.text(context),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SegmentedButton<String>(
                        segments: const <ButtonSegment<String>>[
                          ButtonSegment<String>(
                            value: 'sse',
                            label: Text('即時推送'),
                            icon: Icon(Icons.bolt_outlined),
                          ),
                          ButtonSegment<String>(
                            value: 'polling',
                            label: Text('每秒輪詢'),
                            icon: Icon(Icons.refresh_outlined),
                          ),
                        ],
                        selected: <String>{_selectedUpdateMode},
                        onSelectionChanged: (Set<String> selected) {
                          setState(() {
                            _selectedUpdateMode = selected.first;
                          });
                        },
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _selectedUpdateMode == 'polling'
                            ? '瀏覽器每秒重新抓取一次狀態，相容性最好，但比較耗電。'
                            : '伺服器有變化就立刻推送，更新最即時；連線中斷時會自動改用輪詢。',
                        style: TextStyle(color: AppColors.muted(context)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                PanelCard(
                  title: 'Web UI 網址',
                  subtitle: '在同一個網路中的其他裝置上開啟這個網址。',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      SelectableText(
                        _previewUrl,
                        style: TextStyle(
                          color: AppColors.text(context),
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _copyUrl,
                        icon: const Icon(Icons.copy),
                        label: const Text('複製網址'),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '若上面顯示 localhost，請先回到主畫面啟動伺服器，取得區網 IP 後再回來看。',
                        style: TextStyle(color: AppColors.muted(context)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                PanelCard(
                  title: '主題',
                  subtitle: 'App 的外觀，會立即套用。',
                  child: SegmentedButton<AppThemeMode>(
                    segments: AppThemeMode.values
                        .map(
                          (AppThemeMode mode) => ButtonSegment<AppThemeMode>(
                            value: mode,
                            label: Text(mode.label),
                          ),
                        )
                        .toList(growable: false),
                    selected: <AppThemeMode>{_selectedThemeMode},
                    onSelectionChanged: (Set<AppThemeMode> selected) {
                      setState(() {
                        _selectedThemeMode = selected.first;
                      });
                    },
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _saving ? null : _save,
                        icon: _saving
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.save_outlined),
                        label: Text(_saving ? '儲存中...' : '儲存設定'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
