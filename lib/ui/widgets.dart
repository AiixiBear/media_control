import 'package:flutter/material.dart';

import '../models/media.dart';
import 'app_colors.dart';

class HeroCard extends StatelessWidget {
  const HeroCard({
    super.key,
    required this.snapshot,
    required this.serverRunning,
    required this.serverLoading,
    required this.serverError,
    required this.serverPort,
    required this.authRequired,
    required this.onStartServer,
    required this.onStopServer,
    required this.onRefresh,
    required this.onOpenSettings,
  });

  final MediaSnapshot snapshot;
  final bool serverRunning;
  final bool serverLoading;
  final String? serverError;
  final int? serverPort;
  final bool authRequired;
  final Future<void> Function() onStartServer;
  final Future<void> Function() onStopServer;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: AppColors.heroGradient(context),
        ),
        border: Border.all(color: AppColors.panelBorder(context)),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0xAA000000),
            blurRadius: 30,
            offset: Offset(0, 18),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        '大便媒體控制',
                        style: theme.textTheme.displaySmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.8,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '就字面上的意思看不懂嗎？',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: AppColors.muted(context),
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        serverRunning
                            ? '運行中 · 連接埠 ${serverPort ?? '—'} · ${authRequired ? '已設密碼' : '未設密碼'}'
                            : '已停止 — 點「啟動伺服器」開始，其他裝置就能在區網內開啟 Web UI。',
                        style: TextStyle(
                          color: AppColors.muted(context),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                StatusChip(
                  label: serverRunning ? '正在跑' : '已停止',
                  color: serverRunning
                      ? const Color(0xFF15C89A)
                      : const Color(0xFFF59E0B),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: <Widget>[
                FilledButton.icon(
                  onPressed: serverLoading ? null : onStartServer,
                  icon: serverLoading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.public),
                  label: Text(serverRunning ? '重新啟動伺服器' : '啟動伺服器'),
                ),
                if (serverRunning)
                  OutlinedButton.icon(
                    onPressed: serverLoading ? null : onStopServer,
                    icon: const Icon(Icons.stop_outlined),
                    label: const Text('停止伺服器'),
                  ),
                OutlinedButton.icon(
                  onPressed: onRefresh,
                  icon: const Icon(Icons.refresh),
                  label: const Text('重新整理媒體狀態'),
                ),
                OutlinedButton.icon(
                  onPressed: onOpenSettings,
                  icon: const Icon(Icons.settings_outlined),
                  label: const Text('設定'),
                ),
              ],
            ),
            if (serverError != null) ...<Widget>[
              const SizedBox(height: 16),
              InlineMessage(
                icon: Icons.error_outline,
                title: '伺服器錯誤',
                message: serverError!,
              ),
            ],
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class ServerCard extends StatelessWidget {
  const ServerCard({
    super.key,
    required this.serverUri,
    required this.displayUrl,
    required this.onCopy,
    required this.authRequired,
    required this.updateModeLabel,
  });

  final Uri? serverUri;
  final String? displayUrl;
  final VoidCallback? onCopy;
  final bool authRequired;
  final String updateModeLabel;

  @override
  Widget build(BuildContext context) {
    return PanelCard(
      title: '蜘蛛網 UI 端點',
      subtitle: '在同一個網路中的其他裝置上開啟這個網址',
      child: serverUri == null
          ? Text(
              '先啟動伺服器，才能取得本機網址。',
              style: TextStyle(color: AppColors.muted(context)),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SelectableText(
                  displayUrl ?? 'http://localhost:${serverUri!.port}',
                  style: TextStyle(
                    color: AppColors.text(context),
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '密碼保護：${authRequired ? '已啟用' : '未啟用（區網內任何裝置都可控制）'}',
                  style: TextStyle(color: AppColors.muted(context)),
                ),
                const SizedBox(height: 4),
                Text(
                  '更新方式：$updateModeLabel',
                  style: TextStyle(color: AppColors.muted(context)),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: <Widget>[
                    if (onCopy != null)
                      OutlinedButton.icon(
                        onPressed: onCopy,
                        icon: const Icon(Icons.copy),
                        label: const Text('拷貝URL'),
                      ),
                    Text(
                      'Loopback: http://127.0.0.1:${serverUri!.port}',
                      style: TextStyle(color: AppColors.muted(context)),
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}

class PermissionCard extends StatelessWidget {
  const PermissionCard({
    super.key,
    required this.enabled,
    required this.onOpenSettings,
  });

  final bool enabled;
  final Future<void> Function() onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final accent = enabled ? const Color(0xFF15C89A) : const Color(0xFFF97316);

    return PanelCard(
      title: '通知進入',
      subtitle: '需要這個設定讓我去查其他的App',
      trailing: StatusChip(label: enabled ? '啟用' : '需要設定上面', color: accent),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            enabled
                ? '這個應用程式已可讀取通知。'
                : '還沒開啟通知存取權限，App 就看不到其他 App 在播什麼。\n1. 點下面的「開啟設定」\n2. 在清單裡找到「大便媒體控制」\n3. 開啟「通知存取」後回到這裡',
            style: TextStyle(color: AppColors.muted(context)),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () => onOpenSettings(),
            icon: const Icon(Icons.settings),
            label: const Text('開啟設定'),
          ),
        ],
      ),
    );
  }
}

class BackgroundProtectionCard extends StatelessWidget {
  const BackgroundProtectionCard({
    super.key,
    required this.enabled,
    required this.loading,
    required this.onEnable,
  });

  final bool enabled;
  final bool loading;
  final Future<void> Function() onEnable;

  @override
  Widget build(BuildContext context) {
    final accent = enabled ? const Color(0xFF15C89A) : const Color(0xFFF59E0B);

    return PanelCard(
      title: '背景保護',
      subtitle: '簡單來說就是防止安卓大大殺你後台',
      trailing: StatusChip(label: enabled ? '正在跑' : 'Stopped', color: accent),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            enabled ? '背景保護已啟動，應該不會那麼容易被系統切掉。' : '開啟通知權限後，背景保護就能更穩定地運作。',
            style: TextStyle(color: AppColors.muted(context)),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: loading ? null : onEnable,
            icon: loading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.notifications_active),
            label: Text(enabled ? '重新啟動保護' : '啟用保護'),
          ),
        ],
      ),
    );
  }
}

class NowPlayingCard extends StatelessWidget {
  const NowPlayingCard({
    super.key,
    required this.session,
    required this.formatDuration,
    required this.onPlay,
    required this.onPause,
    required this.onNext,
    required this.onPrevious,
    required this.onSeekTo,
  });

  final MediaSessionInfo session;
  final String Function(int milliseconds) formatDuration;
  final Future<void> Function() onPlay;
  final Future<void> Function() onPause;
  final Future<void> Function() onNext;
  final Future<void> Function() onPrevious;
  final Future<void> Function(Duration position) onSeekTo;

  @override
  Widget build(BuildContext context) {
    final progress = session.progressFraction;
    final durationLabel = formatDuration(session.durationMs);
    final positionLabel = formatDuration(session.positionMs);

    return PanelCard(
      title: '現在正在播放',
      subtitle: session.appName,
      trailing: StatusChip(
        label: session.isPlaying ? '正在播放' : '已暫停',
        color: session.isPlaying
            ? const Color(0xFF15C89A)
            : const Color(0xFF60A5FA),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              ArtworkThumbnail(
                artworkDataUrl: session.artworkDataUrl,
                size: 96,
                radius: 22,
                fallbackIconSize: 40,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      session.title,
                      style: TextStyle(
                        color: AppColors.text(context),
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      session.displayArtist,
                      style: TextStyle(
                        color: AppColors.muted(context),
                        fontSize: 15,
                      ),
                    ),
                    if (session.album.isNotEmpty &&
                        session.album != session.artist) ...<Widget>[
                      const SizedBox(height: 2),
                      Text(
                        '專輯：${session.album}',
                        style: TextStyle(
                          color: AppColors.faint(context),
                          fontSize: 13,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Text(
                      session.packageName,
                      style: TextStyle(
                        color: AppColors.faint(context),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 10,
              value: progress,
              backgroundColor: AppColors.rowBackground(context),
              color: const Color(0xFF5CE1E6),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Text(
                positionLabel,
                style: TextStyle(color: AppColors.muted(context)),
              ),
              Text(
                durationLabel,
                style: TextStyle(color: AppColors.muted(context)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: <Widget>[
              OutlinedButton.icon(
                onPressed: onPrevious,
                icon: const Icon(Icons.skip_previous),
                label: const Text('上一首'),
              ),
              FilledButton.icon(
                onPressed: session.isPlaying ? onPause : onPlay,
                icon: Icon(session.isPlaying ? Icons.pause : Icons.play_arrow),
                label: Text(session.isPlaying ? '暫停' : '播放'),
              ),
              OutlinedButton.icon(
                onPressed: onNext,
                icon: const Icon(Icons.skip_next),
                label: const Text('下一首'),
              ),
            ],
          ),
          if (session.canSeekTo) ...<Widget>[
            const SizedBox(height: 16),
            Slider(
              min: 0,
              max: session.durationMs > 0 ? session.durationMs.toDouble() : 1,
              value: session.positionMs.clamp(0, session.durationMs).toDouble(),
              onChanged: (double value) {},
              onChangeEnd: (double value) =>
                  onSeekTo(Duration(milliseconds: value.round())),
            ),
          ],
        ],
      ),
    );
  }
}

class SessionListCard extends StatelessWidget {
  const SessionListCard({
    super.key,
    required this.sessions,
    required this.formatDuration,
    required this.onPlay,
    required this.onPause,
    required this.onNext,
    required this.onPrevious,
  });

  final List<MediaSessionInfo> sessions;
  final String Function(int milliseconds) formatDuration;
  final Future<void> Function(MediaSessionInfo session) onPlay;
  final Future<void> Function(MediaSessionInfo session) onPause;
  final Future<void> Function(MediaSessionInfo session) onNext;
  final Future<void> Function(MediaSessionInfo session) onPrevious;

  @override
  Widget build(BuildContext context) {
    return PanelCard(
      title: '活躍進程',
      subtitle: '${sessions.length} 個進程已偵測',
      child: sessions.isEmpty
          ? Text(
              '目前沒有可顯示的媒體進程。',
              style: TextStyle(color: AppColors.muted(context)),
            )
          : Column(
              children: sessions
                  .map(
                    (MediaSessionInfo session) => Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppColors.rowBackground(context),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: AppColors.rowBorder(context),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  ArtworkThumbnail(
                                    artworkDataUrl: session.artworkDataUrl,
                                    size: 56,
                                    radius: 14,
                                    fallbackIconSize: 22,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: <Widget>[
                                        Text(
                                          session.appName,
                                          style: TextStyle(
                                            color: AppColors.text(context),
                                            fontSize: 18,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          session.title,
                                          style: TextStyle(
                                            color: AppColors.muted(context),
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          session.displayArtist,
                                          style: TextStyle(
                                            color: AppColors.faint(context),
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  StatusChip(
                                    label: session.isPlaying
                                        ? '播放中'
                                        : session.playbackState,
                                    color: session.isPlaying
                                        ? const Color(0xFF15C89A)
                                        : const Color(0xFF64748B),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                session.displayArtist,
                                style: TextStyle(
                                  color: AppColors.muted(context),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${formatDuration(session.positionMs)} / ${formatDuration(session.durationMs)}',
                                style: TextStyle(
                                  color: AppColors.faint(context),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 10,
                                runSpacing: 10,
                                children: <Widget>[
                                  OutlinedButton.icon(
                                    onPressed: () => onPrevious(session),
                                    icon: const Icon(Icons.skip_previous),
                                    label: const Text('上一首'),
                                  ),
                                  FilledButton.icon(
                                    onPressed: session.isPlaying
                                        ? () => onPause(session)
                                        : () => onPlay(session),
                                    icon: Icon(
                                      session.isPlaying
                                          ? Icons.pause
                                          : Icons.play_arrow,
                                    ),
                                    label: Text(
                                      session.isPlaying ? '暫停' : '播放',
                                    ),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed: () => onNext(session),
                                    icon: const Icon(Icons.skip_next),
                                    label: const Text('下一首'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
    );
  }
}

class ArtworkThumbnail extends StatelessWidget {
  const ArtworkThumbnail({
    super.key,
    required this.artworkDataUrl,
    required this.size,
    required this.radius,
    required this.fallbackIconSize,
  });

  final String? artworkDataUrl;
  final double size;
  final double radius;
  final double fallbackIconSize;

  @override
  Widget build(BuildContext context) {
    final dataUrl = artworkDataUrl;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[Color(0xFF20324B), Color(0xFF0F172A)],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      clipBehavior: Clip.antiAlias,
      child: dataUrl == null || dataUrl.isEmpty
          ? Icon(
              Icons.album,
              color: Colors.white.withValues(alpha: 0.7),
              size: fallbackIconSize,
            )
          : Image.memory(
              decodeDataUrl(dataUrl),
              fit: BoxFit.cover,
              errorBuilder:
                  (BuildContext context, Object error, StackTrace? stackTrace) {
                    return Icon(
                      Icons.album,
                      color: Colors.white.withValues(alpha: 0.7),
                      size: fallbackIconSize,
                    );
                  },
            ),
    );
  }
}

class EmptyStateCard extends StatelessWidget {
  const EmptyStateCard({super.key, required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return PanelCard(
      title: title,
      subtitle: '等待媒體播放',
      child: Text(message, style: TextStyle(color: AppColors.muted(context))),
    );
  }
}

class PanelCard extends StatelessWidget {
  const PanelCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.panel(context),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.panelBorder(context)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        title,
                        style: TextStyle(
                          color: AppColors.text(context),
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(color: AppColors.muted(context)),
                      ),
                    ],
                  ),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Text(
        label,
        style: TextStyle(color: color, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class InlineMessage extends StatelessWidget {
  const InlineMessage({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF3A1D24),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFFFF7A90).withValues(alpha: 0.3),
        ),
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, color: const Color(0xFFFF8A8A)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(message, style: const TextStyle(color: Colors.white70)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
