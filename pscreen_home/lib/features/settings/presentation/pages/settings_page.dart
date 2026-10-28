import 'dart:async';

import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:pscreen_home/app/config/ha_config.dart';
import 'package:pscreen_home/core/di/injection.dart';
import 'package:pscreen_home/core/network/ha_ws_client.dart';
import 'package:pscreen_home/core/screensaver/screensaver_controller.dart';
import 'package:pscreen_home/core/server/device_reporter.dart';
import 'package:pscreen_home/core/storage/settings_store.dart';
import 'package:pscreen_home/core/ui/ui_scale.dart';
import 'package:pscreen_home/core/wallpaper/wallpaper_controller.dart';
import 'package:pscreen_home/features/connection/application/bloc/connection_bloc.dart';
import 'package:pscreen_home/features/connection/application/bloc/connection_event.dart';
import 'package:pscreen_home/features/connection/application/bloc/connection_state.dart';
import 'package:pscreen_home/features/home/application/metric_history.dart';
import 'package:pscreen_home/features/remote_control/core/control_log.dart';
import 'package:pscreen_screen/app/config/app_config.dart';
import 'package:pscreen_screen/app/config/app_constants.dart';
import 'package:pscreen_screen/core/network/realtime_channel.dart';
import 'package:pscreen_screen/core/utils/app_settings.dart';
import 'package:pscreen_screen/core/utils/device_credentials.dart';
import 'package:pscreen_screen/core/utils/ptools_util.dart';
import 'package:pscreen_screen/features/weather/application/bloc/weather_bloc.dart';
import 'package:pscreen_screen/features/weather/application/bloc/weather_event.dart';

/// 设置页：Home Assistant 连接配置（地址 + 长期访问令牌）。
///
/// - 输入框回显**生效值**：持久化覆盖 > `.env`（默认即 localhost）；
/// - 保存时：非空输入存入 `SettingsStore` 作为覆盖，**清空保存则删除覆盖
///   回落 `.env`**；生效值发生变化时触发 `Reconnect` 断开重建连接，
///   连接就绪后主页自动重新加载（刷新）；
/// - 底部实时显示连接状态，便于换地址后确认是否连通。
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController _hostController;
  late final TextEditingController _tokenController;
  late final TextEditingController _serverController;
  late final TextEditingController _remoteAccountController;
  late final TextEditingController _remoteTokenController;
  bool _tokenVisible = false;
  bool _saving = false;
  late int _sampleSeconds;
  late int _screensaverMinutes;
  late double _uiScale;
  late final WallpaperController _wallpaper;
  late final TextEditingController _wallpaperApiController;
  late bool _wallpaperEnabled;
  late int _wallpaperMinutes;

  /// 天气城市（空串 = 自动，按出口 IP 定位）。
  String _weatherCity = AppSettings.instance.weatherCity;

  @override
  void initState() {
    super.initState();
    final SettingsStore store = Injection.get<SettingsStore>();
    _hostController = TextEditingController(text: HaConfig.haHost);
    _tokenController = TextEditingController(text: HaConfig.haToken);
    _serverController = TextEditingController(text: HaConfig.serverBaseUrl);
    _sampleSeconds = store.powerSampleSeconds;
    _screensaverMinutes = Injection.get<ScreensaverController>().minutes;
    _uiScale = store.uiScale;
    _wallpaper = Injection.get<WallpaperController>();
    _wallpaperEnabled = _wallpaper.enabled;
    _wallpaperMinutes = _wallpaper.minutes;
    _wallpaperApiController = TextEditingController(text: _wallpaper.apiUrl);
    _remoteAccountController = TextEditingController(
      text: AppSettings.instance.remoteAccount,
    );
    _remoteTokenController = TextEditingController(
      text: AppSettings.instance.remotePassword,
    );
    // 天气城市由共享包 AppSettings 持久化：确保首次加载完成后再回显。
    AppSettings.instance.ensureLoaded().then((_) {
      if (!mounted) return;
      setState(() => _weatherCity = AppSettings.instance.weatherCity);
    });
  }

  @override
  void dispose() {
    _hostController.dispose();
    _tokenController.dispose();
    _serverController.dispose();
    _remoteAccountController.dispose();
    _remoteTokenController.dispose();
    _wallpaperApiController.dispose();
    super.dispose();
  }

  /// 保存：持久化输入 → 更新生效值 → 生效值变化时重连刷新。
  Future<void> _save() async {
    final String hostInput = _hostController.text.trim();
    final String tokenInput = _tokenController.text.trim();
    final String serverInput = _serverController.text.trim();

    // 覆盖语义：与 .env 默认值相同（或清空）= 不覆盖，保持跟随 .env；
    // 不同才存持久化。生效值据此归一化后与当前生效值比较，判定是否刷新。
    final String hostPersist = hostInput == HaConfig.envHost ? '' : hostInput;
    final String tokenPersist = tokenInput == HaConfig.envToken
        ? ''
        : tokenInput;
    final String serverPersist = serverInput == HaConfig.envServerBaseUrl
        ? ''
        : serverInput;
    final String newHost = hostPersist.isEmpty ? HaConfig.envHost : hostPersist;
    final String newToken = tokenPersist.isEmpty
        ? HaConfig.envToken
        : tokenPersist;
    final bool changed =
        newHost != HaConfig.haHost || newToken != HaConfig.haToken;
    final bool serverChanged = serverPersist != HaConfig.serverBaseUrl;

    setState(() => _saving = true);
    final SettingsStore store = Injection.get<SettingsStore>();
    await store.save(host: hostPersist, token: tokenPersist);
    await store.saveServerBaseUrl(serverPersist);
    // 从存储回读（保证与实际持久化结果一致，失败时自动回落）
    HaConfig.applyOverrides(
      host: store.hostOverride,
      token: store.tokenOverride,
      serverBaseUrl: store.serverBaseUrlOverride,
    );
    if (!mounted) return;
    setState(() => _saving = false);

    // 回显生效值：清空保存后输入框显示回落的 .env 值
    _hostController.text = HaConfig.haHost;
    _tokenController.text = HaConfig.haToken;
    _serverController.text = HaConfig.serverBaseUrl;

    if (changed) {
      context.read<ConnectionBloc>().add(const Reconnect());
    }
    if (serverChanged && mounted) {
      // 重新注册设备并同步布局；失败只记日志，不阻塞设置页。
      unawaited(Injection.get<DeviceReporter>().reinitialize());
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            changed
                ? '已保存，正在用新配置重新连接…'
                : (serverChanged ? '已保存，正在重新同步设备配置…' : '已保存'),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  /// 保存实时通道账号 / 口令，并立即重连（失败仅提示，不阻断中控台）。
  ///
  /// 账号留空 = 回落本机设备号（16hex）；口令留空 = 默认 123456。
  /// 重连顺序与启动一致：先 HTTP 登录（账号不存在时按默认口令自动建档），
  /// 再连 ws，否则 ws 握手会因「账号不存在」被拒。
  Future<void> _saveRemoteCredentials() async {
    final String account = _remoteAccountController.text.trim();
    final String password = _remoteTokenController.text.trim().isEmpty
        ? DeviceCredentials.defaultPassword
        : _remoteTokenController.text.trim();
    await AppSettings.instance.setRemoteAccount(account);
    await AppSettings.instance.setRemotePassword(password);

    // 立即用新凭据重连，让当前会话生效（失败只提示，不阻断中控台）。
    final RealtimeChannel channel = Injection.get<RealtimeChannel>();
    bool ok = false;
    await channel.disconnect();
    try {
      // 先 HTTP 登录完成账号建档（失败返回 false，不阻断：ws 侧独立报错）。
      await PtoolsUtil.loginWithSaved();
      await channel
          .connect(
            account: await DeviceCredentials.account(),
            token: DeviceCredentials.passwordMd5(),
            deviceId: await DeviceCredentials.deviceId(),
            role: 'controller',
            name: '中控台',
          )
          .timeout(const Duration(seconds: 25), onTimeout: () {
        throw const RealtimeException(-3, '连接超时');
      });
      ok = true;
    } catch (e) {
      ControlLog.e('[实时通道] 连接失败: $e');
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            account.isEmpty
                ? (ok ? '已恢复默认设备号账号' : '已恢复默认设备号，暂未连接成功')
                : (ok ? '已保存遥控配置' : '已保存，暂未连接成功（断网时自动重试）'),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  /// 选择功率采样间隔：持久化并即时生效（运行中调整采样周期）。
  Future<void> _applySampleSeconds(int seconds) async {
    setState(() => _sampleSeconds = seconds);
    final SettingsStore store = Injection.get<SettingsStore>();
    await store.savePowerSampleSeconds(seconds);
    Injection.get<MetricSampler>().setInterval(Duration(seconds: seconds));
  }

  /// 选择屏保空闲时长：持久化并立即重置全局计时。
  Future<void> _applyScreensaverMinutes(int minutes) async {
    setState(() => _screensaverMinutes = minutes);
    await Injection.get<ScreensaverController>().setMinutes(minutes);
  }

  /// 壁纸开关：立即生效并持久化。
  Future<void> _applyWallpaperEnabled(bool enabled) async {
    setState(() => _wallpaperEnabled = enabled);
    await _wallpaper.setEnabled(enabled);
  }

  /// 壁纸刷新间隔：立即生效并持久化。
  Future<void> _applyWallpaperMinutes(int minutes) async {
    setState(() => _wallpaperMinutes = minutes);
    await _wallpaper.setMinutes(minutes);
  }

  /// 保存壁纸 API；只接受 http/https 地址，空输入恢复默认风景接口。
  Future<void> _saveWallpaperApi() async {
    final String input = _wallpaperApiController.text.trim();
    if (input.isNotEmpty) {
      final Uri? uri = Uri.tryParse(input);
      if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text('壁纸 API 需要 http/https 地址'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        return;
      }
    }

    await _wallpaper.setApiUrl(input);
    if (!mounted) return;
    _wallpaperApiController.text = _wallpaper.apiUrl;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('已保存壁纸 API'),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  /// 恢复默认的 Uapis 风景接口。
  Future<void> _resetWallpaperApi() async {
    _wallpaperApiController.text = SettingsStore.defaultWallpaperApiUrl;
    await _saveWallpaperApi();
  }

  /// 切换天气城市：持久化并立即重新拉取；「自动」传空串（按出口 IP 定位）。
  ///
  /// 数据写入共享包的 [AppSettings]，天气页与中控台标题读的是同一个
  /// [WeatherBloc]，所以切换后两处同时更新。
  Future<void> _applyWeatherCity(String city) async {
    if (city == _weatherCity) return;
    setState(() => _weatherCity = city);
    await AppSettings.instance.setWeatherCity(city);
    if (!mounted) return;
    context.read<WeatherBloc>().add(const LoadWeather());
  }

  /// 界面缩放：松手后应用（拖动过程中实时改倍数会让滑块在手指下变大变小，
  /// 手感会飘），数值持久化，重启后保持。
  void _applyUiScale(double value) {
    setState(() => _uiScale = value);
    Injection.get<UiScaleController>().update(value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          TextField(
            controller: _hostController,
            decoration: InputDecoration(
              labelText: 'Home Assistant 地址',
              hintText: '如 192.168.1.10:8123 或 home.example.com:8123',
              helperText: HaConfig.hasHostOverride
                  ? '已手动设置，优先于 .env（清空保存可恢复）'
                  : '当前使用 .env 默认值',
              border: const OutlineInputBorder(),
            ),
            keyboardType: TextInputType.url,
            maxLines: 1,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _tokenController,
            obscureText: !_tokenVisible,
            decoration: InputDecoration(
              labelText: '长期访问令牌 (KEY)',
              helperText: HaConfig.hasTokenOverride
                  ? '已手动设置，优先于 .env（清空保存可恢复）'
                  : '当前使用 .env 默认值',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                tooltip: _tokenVisible ? '隐藏' : '显示',
                icon: Icon(
                  _tokenVisible
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded,
                ),
                onPressed: () => setState(() => _tokenVisible = !_tokenVisible),
              ),
            ),
            maxLines: 1,
          ),
          const SizedBox(height: 24),
          Text(
            'Admin 服务端（可选）',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            '填写运行 Admin 管理页的服务器地址（如 http://192.168.31.2:3000）。'
            '配置后由 Admin 决定本机可见家庭，并把首页卡片顺序同步到服务端；'
            '留空则完全按 .env 的 HONE_MANE 运行。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _serverController,
            decoration: InputDecoration(
              labelText: 'Admin 服务端地址',
              hintText: 'http://192.168.31.2:3000',
              helperText: HaConfig.hasServerBaseUrlOverride
                  ? '已手动设置，优先于 .env（清空保存可恢复）'
                  : '当前使用 .env 的 SERVER_BASE_URL',
              border: const OutlineInputBorder(),
            ),
            keyboardType: TextInputType.url,
            maxLines: 1,
          ),
          const SizedBox(height: 24),
          Text(
            '天气城市',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            '中控台标题与天气页共用的查询位置；「自动」每次按出口 IP 定位。可选城市来自 WEATHER_CITIES 配置。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              ChoiceChip(
                label: const Text('自动'),
                selected: _weatherCity.isEmpty,
                onSelected: (_) => _applyWeatherCity(''),
              ),
              for (final String city in AppConfig.weatherCities)
                ChoiceChip(
                  label: Text(city),
                  selected: _weatherCity == city,
                  onSelected: (_) => _applyWeatherCity(city),
                ),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            '功率采样间隔',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            '当前功率图表的记录频率，仅保留最近 1 小时（不持久化）。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final int seconds in SettingsStore.powerSampleOptions)
                ChoiceChip(
                  label: Text('$seconds 秒'),
                  selected: _sampleSeconds == seconds,
                  onSelected: (_) => _applySampleSeconds(seconds),
                ),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            '屏保时间',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            '无触摸操作达到设定时长后自动进入时钟屏保；直播页不触发。点击屏保任意位置返回上一页。选择「从不」则不再自动进入屏保。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final int minutes in SettingsStore.screensaverOptions)
                ChoiceChip(
                  label: Text(
                    minutes == SettingsStore.screensaverNeverMinutes
                        ? '从不'
                        : '$minutes 分钟',
                  ),
                  selected: _screensaverMinutes == minutes,
                  onSelected: (_) => _applyScreensaverMinutes(minutes),
                ),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            '屏保壁纸',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            '屏保时钟的背景图，默认 30 分钟换一张。默认使用真实风景照片接口；Uapis 随机壁纸可填 https://uapis.cn/api/v1/random/image?category=landscape，但它会聚合外部图源，仍可能混入动漫/插画。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
          const SizedBox(height: 10),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.wallpaper_rounded),
            title: const Text('启用屏保壁纸'),
            subtitle: const Text('关闭后屏保只显示黑底；时钟页左下角也可随时关闭/开启。'),
            value: _wallpaperEnabled,
            onChanged: _applyWallpaperEnabled,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _wallpaperApiController,
            decoration: const InputDecoration(
              labelText: '壁纸 API 地址',
              hintText: SettingsStore.defaultWallpaperApiUrl,
              helperText: '默认使用真实风景照片；也可以换成其它返回图片的 API。',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.url,
            minLines: 1,
            maxLines: 2,
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              FilledButton.tonalIcon(
                onPressed: _saveWallpaperApi,
                icon: const Icon(Icons.save_rounded),
                label: const Text('保存壁纸 API'),
              ),
              TextButton(
                onPressed: _resetWallpaperApi,
                child: const Text('恢复默认'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final int minutes in SettingsStore.wallpaperMinuteOptions)
                ChoiceChip(
                  label: Text(SettingsStore.wallpaperMinuteLabel(minutes)),
                  selected: _wallpaperMinutes == minutes,
                  onSelected: (_) => _applyWallpaperMinutes(minutes),
                ),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            '界面缩放',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            '整块界面（卡片、字号、间距、点击热区）等比放大，适配 15 寸大屏远距离触控；松开滑块生效并自动保存。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
          Row(
            children: <Widget>[
              Expanded(
                child: Slider(
                  value: _uiScale,
                  min: SettingsStore.minUiScale,
                  max: SettingsStore.maxUiScale,
                  divisions: 20,
                  label: '${(_uiScale * 100).round()}%',
                  onChanged: (double value) => setState(() => _uiScale = value),
                  onChangeEnd: _applyUiScale,
                ),
              ),
              SizedBox(
                width: 64,
                child: Text(
                  '${(_uiScale * 100).round()}%',
                  textAlign: TextAlign.end,
                  style: Theme.of(
                    context,
                  ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_rounded),
            label: const Text('保存'),
          ),
          const SizedBox(height: 24),
          Text(
            '遥控（实时通道）',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            '用于向电视端下发音量 / 切台 / 文本指令。账号与口令与电视端共用同一套实时网关。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _remoteAccountController,
            decoration: const InputDecoration(
              labelText: '实时账号',
              helperText: '留空则用本机设备号（16位）；管理员账号见遥控面板',
              border: OutlineInputBorder(),
            ),
            maxLines: 1,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _remoteTokenController,
            decoration: InputDecoration(
              labelText: '实时口令',
              helperText: '默认 ${DeviceCredentials.defaultPassword}',
              border: const OutlineInputBorder(),
            ),
            maxLines: 1,
          ),
          const SizedBox(height: 10),
          FilledButton.tonalIcon(
            onPressed: _saveRemoteCredentials,
            icon: const Icon(Icons.save_rounded),
            label: const Text('保存遥控配置'),
          ),
          const SizedBox(height: 10),
          const _RealtimeStatusLine(),
          const SizedBox(height: 24),
          const _ConnectionStatusLine(),
        ],
      ),
    );
  }
}

/// 遥控实时通道状态行：显示连接状态、网关地址与最近错误，便于现场排查。
class _RealtimeStatusLine extends StatelessWidget {
  const _RealtimeStatusLine();

  @override
  Widget build(BuildContext context) {
    final RealtimeChannel channel = Injection.get<RealtimeChannel>();
    return StreamBuilder<RealtimeConnectionState>(
      stream: channel.connectionState,
      initialData: channel.state,
      builder: (BuildContext context, AsyncSnapshot<RealtimeConnectionState> snapshot) {
        final RealtimeConnectionState state =
            snapshot.data ?? RealtimeConnectionState.disconnected;
        final (String label, Color color) = switch (state) {
          RealtimeConnectionState.connected => (
            '已连接（${channel.account}）',
            Colors.greenAccent,
          ),
          RealtimeConnectionState.connecting => ('连接中…', Colors.orangeAccent),
          RealtimeConnectionState.disconnected => ('未连接', Colors.redAccent),
          RealtimeConnectionState.error => ('连接错误', Colors.redAccent),
        };
        final TextStyle? hint = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.outline,
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Text('遥控通道：$label', style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
            if (channel.lastError != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text('最近错误：${channel.lastError}', style: hint),
              ),
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('网关：${AppConstants.realtimeWsUrl}', style: hint),
            ),
          ],
        );
      },
    );
  }
}

/// 底部连接状态行：换地址保存后无需返回主页即可确认连通性。
class _ConnectionStatusLine extends StatelessWidget {
  const _ConnectionStatusLine();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ConnectionBloc, ConnectionState>(
      builder: (BuildContext context, ConnectionState state) {
        final (String label, Color color) = switch (state.phase) {
          HaConnectionPhase.ready => ('已连接', Colors.greenAccent),
          HaConnectionPhase.connecting => ('连接中…', Colors.orangeAccent),
          HaConnectionPhase.authenticating => ('认证中…', Colors.orangeAccent),
          HaConnectionPhase.authFailed => (
            state.message ?? '认证失败',
            Colors.redAccent,
          ),
          HaConnectionPhase.disconnected => (
            state.isRetrying ? '重连中…' : '未连接',
            Colors.redAccent,
          ),
        };
        return Row(
          children: <Widget>[
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ],
        );
      },
    );
  }
}
