import fs from 'node:fs';
import path from 'node:path';

const ROOT = path.resolve(process.argv[2] ?? '.');
const SRC = path.join(ROOT, 'pscreen_control', 'lib');
const DST = path.join(ROOT, 'pscreen_home', 'lib', 'features', 'remote_control');

// 源相对路径 -> 目标相对路径（相对 features/remote_control/）
const MOVES = {
  'app/config/app_config.dart': 'core/control_config.dart',
  'app/storage/app_settings.dart': 'data/control_settings.dart',
  'app/utils/app_log.dart': 'core/control_log.dart',
  'core/nim_client.dart': 'data/nim_client.dart',
  'core/chat_message_item.dart': 'domain/chat_message_item.dart',
  'features/send/application/send_cubit.dart': 'application/send_cubit.dart',
  'features/send/application/send_state.dart': 'application/send_state.dart',
  'features/send/data/tv_directory.dart': 'data/tv_directory.dart',
  'features/send/presentation/send_page.dart': 'presentation/send_page.dart',
  'features/send/presentation/widgets/command_panel.dart': 'presentation/widgets/command_panel.dart',
  'features/send/presentation/widgets/target_picker.dart': 'presentation/widgets/target_picker.dart',
  'features/admin/application/conversation_list_cubit.dart': 'application/conversation_list_cubit.dart',
  'features/admin/application/conversation_list_state.dart': 'application/conversation_list_state.dart',
  'features/admin/application/conversation_source.dart': 'application/conversation_source.dart',
  'features/admin/presentation/conversation_list_page.dart': 'presentation/conversation_list_page.dart',
  'features/admin/presentation/chat_page.dart': 'presentation/chat_page.dart',
  'features/scan/presentation/qr_scan_page.dart': 'presentation/qr_scan_page.dart',
};

const DROP = [
  'app/di/injection.dart',
  'features/settings/presentation/settings_page.dart',
  'main.dart',
];

const SYMBOL_RENAMES = [
  ['AppConfig', 'ControlConfig'],
  ['AppSettings', 'ControlSettings'],
  ['AppLog', 'ControlLog'],
];

const IMPORT_MAP = {
  'package:pscreen_control/app/config/app_config.dart':
    'package:pscreen_home/features/remote_control/core/control_config.dart',
  'package:pscreen_control/app/storage/app_settings.dart':
    'package:pscreen_home/features/remote_control/data/control_settings.dart',
  'package:pscreen_control/app/utils/app_log.dart':
    'package:pscreen_home/features/remote_control/core/control_log.dart',
  'package:pscreen_control/core/nim_client.dart':
    'package:pscreen_home/features/remote_control/data/nim_client.dart',
  'package:pscreen_control/core/chat_message_item.dart':
    'package:pscreen_home/features/remote_control/domain/chat_message_item.dart',
  'package:pscreen_control/features/send/application/send_cubit.dart':
    'package:pscreen_home/features/remote_control/application/send_cubit.dart',
  'package:pscreen_control/features/send/data/tv_directory.dart':
    'package:pscreen_home/features/remote_control/data/tv_directory.dart',
  'package:pscreen_control/features/send/presentation/widgets/command_panel.dart':
    'package:pscreen_home/features/remote_control/presentation/widgets/command_panel.dart',
  'package:pscreen_control/features/send/presentation/widgets/target_picker.dart':
    'package:pscreen_home/features/remote_control/presentation/widgets/target_picker.dart',
  'package:pscreen_control/features/scan/presentation/qr_scan_page.dart':
    'package:pscreen_home/features/remote_control/presentation/qr_scan_page.dart',
  'package:pscreen_control/features/admin/application/conversation_list_cubit.dart':
    'package:pscreen_home/features/remote_control/application/conversation_list_cubit.dart',
  'package:pscreen_control/features/admin/presentation/conversation_list_page.dart':
    'package:pscreen_home/features/remote_control/presentation/conversation_list_page.dart',
  'package:pscreen_control/features/admin/presentation/chat_page.dart':
    'package:pscreen_home/features/remote_control/presentation/chat_page.dart',
  'package:pscreen_control/features/protocol/envelope_builder.dart':
    'package:pscreen_screen/features/msg/protocol/envelope_builder.dart',
};

function rewrite(text) {
  let out = text;
  for (const [from, to] of Object.entries(IMPORT_MAP)) {
    out = out.replaceAll(from, to);
  }
  for (const [from, to] of SYMBOL_RENAMES) {
    out = out.replace(new RegExp(`\\b${from}\\b`, 'g'), to);
  }
  // 遥控端自带的 Injection 门面统一改用宿主 Injection
  out = out.replaceAll(
    "import 'package:pscreen_control/app/di/injection.dart';",
    "import 'package:pscreen_home/core/di/injection.dart';",
  );
  out = out.replaceAll('getIt<', 'Injection.get<');
  return out;
}

for (const [from, to] of Object.entries(MOVES)) {
  const src = path.join(SRC, from);
  if (!fs.existsSync(src)) {
    console.log(`跳过（不存在）：${from}`);
    continue;
  }
  const dest = path.join(DST, to);
  fs.mkdirSync(path.dirname(dest), { recursive: true });
  fs.writeFileSync(dest, rewrite(fs.readFileSync(src, 'utf8')));
  fs.rmSync(src);
  console.log(`迁移：${from} -> features/remote_control/${to}`);
}

for (const rel of DROP) {
  const p = path.join(SRC, rel);
  if (fs.existsSync(p)) {
    fs.rmSync(p);
    console.log(`删除：${rel}`);
  }
}
