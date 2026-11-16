/**
 * ESP32-S3 + 1.3" SH1106 OLED (I2C) + WiFi 配网 + HA 按键
 * 接线: VCC->3V3, GND->GND, SCL->GPIO9, SDA->GPIO8
 * 按键: 槽位 1..8 的 GPIO 映射在设备设置页配置（存 NVS），对地短接即触发
 *
 * 逻辑:
 *  1. 读取 NVS 里保存的 WiFi / 控制端地址 / 按键槽位，首次上电用下方默认值
 *  2. 15 秒内连上 -> 屏幕显示 IP，向服务端注册并拉取当前页
 *  3. 连不上 -> 开热点 Potatokid-Screen-Setup，手机访问 http://192.168.4.1 配网
 *  4. 配网期间每 60 秒用已保存的账号重试一次，连上就关热点
 *  5. 按键按下 -> 请求服务端执行当前页对应槽位的动作（后台按页配置）
 */
#include <Wire.h>
#include <U8g2lib.h>
#include <WiFi.h>
#include <WebServer.h>
#include <DNSServer.h>
#include <Preferences.h>
#include <HTTPClient.h>
#include <HTTPUpdate.h>
#include <freertos/FreeRTOS.h>
#include <freertos/task.h>
#include <freertos/semphr.h>
#include "secrets.h"  // WiFi 默认账号 / 网页口令（本地文件，不入库）

static const int PIN_SDA = 8;
static const int PIN_SCL = 9;

// 物理按键槽位：最多 8 个，槽位号与后台页面里的「槽位」一一对应。
// GPIO 映射保存在 NVS（btns 命名空间），设备设置页可增删槽位、改引脚。
// 默认槽位 1/2/3 = GPIO4/5/6；-1 表示该槽位未启用。
static const int MAX_BTN = 8;
static const int DEFAULT_BTN_PINS[] = {4, 5, 6};

static const char *AP_SSID      = "Potatokid-Screen-Setup";
static const char *DEFAULT_SSID = SECRET_WIFI_SSID;
static const char *DEFAULT_PASS = SECRET_WIFI_PASS;

static const uint32_t STA_TIMEOUT_MS = 15000;  // 开机连网超时
static const uint32_t AP_RETRY_MS     = 60000;  // 热点模式下重试间隔
static const uint32_t LOST_RESET_MS   = 60000;  // 联网后掉线多久转配网

// 局域网配置页口令（热点配网模式不校验，避免首次配置被挡住）
static const char *WEB_USER = SECRET_WEB_USER;
static const char *WEB_PASS = SECRET_WEB_PASS;

// 控制端地址：可在线修改（存 NVS），换域名不用重新烧录
static const char *DEFAULT_SERVER_BASE = "http://ptool.w1.luyouxia.net";
static const char *DEVICE_NAME         = "ESP32-S3 小屏";
// 版本号要递增，否则 OTA 检测不到更新（服务端比对 APP_VER != 发布版本）。
// oled-2.0：中文字库主屏 + 顶栏真实 IP + 分速跑马灯 + 单色适配 + 四行协议 + 翻页。
// oled-2.1：设置页新增「自动更新」开关，检测到新版本自动安装（失败冷却 30 分钟重试）。
// oled-2.2：支持服务端分页（PAGE 行），状态栏页码与翻页真正生效。
// oled-2.3：页面化配置（一页 = 一台设备）；按键槽位 1..8 的 GPIO 在本地设置页
//           配置（NVS）；支持 loop/空闲回首页；按键回执按槽位号匹配。
// oled-2.4：设置页「可控设备」直接显示每个按钮对应的板上 GPIO 编号，
//           并标明未映射的槽位，方便排查接线。
// oled-2.5：注册/心跳上报本机槽位→GPIO 映射，后台可直接看到实际引脚与未映射项。
// oled-2.6：心跳/拉配置/查 OTA 移到后台 FreeRTOS 任务，主循环不再被 HTTP 阻塞
//           （消除约每分钟一次的卡顿）；主/副状态没有值时留白，不显示 `--`。
// oled-2.7：按键动作成功后约 0.7 秒自动拉一次显示，状态即时刷新，不用等 60 秒心跳。
static const char *APP_VER             = "oled-2.7";
static const uint32_t REPORT_MS        = 60000;  // 心跳间隔

// 1.3 寸面板控制器为 SH1106（显存 132 列，可见窗口从第 2 列开始）。
// 用 SSD1306 驱动会出现左移 2px + 右侧几列乱码，故用 SH1106 构造。
U8G2_SH1106_128X64_NONAME_F_HW_I2C u8g2(U8G2_R0, U8X8_PIN_NONE);
WebServer server(80);
DNSServer dns;
Preferences prefs;

bool oledOk = false;
bool portal = false;
bool gApMode = false;
bool serverStarted = false;
bool srvOk = false;
String ssid, pass;
String serverBase;  // 控制端地址（NVS 可改）
String deviceId;
uint32_t lastRetry = 0;
uint32_t lostSince = 0;

// 屏幕临时提示（按键结果）与按钮名称缓存（来自服务端当前页按键表）
uint32_t toastUntil = 0;
String btnLabel[MAX_BTN + 1];   // 短标签（屏幕底部提示条用）
String btnName[MAX_BTN + 1];    // 完整名称（按键反馈 / 设置页展示）
int btnCount = sizeof(DEFAULT_BTN_PINS) / sizeof(DEFAULT_BTN_PINS[0]);
int btnPins[MAX_BTN] = {4, 5, 6, -1, -1, -1, -1, -1};
struct BtnState { bool down; uint32_t changedAt; };
BtnState buttons[MAX_BTN];

// ---- 后台网络任务 ----
// 心跳 / 拉配置 / 查 OTA 以前都塞在 loop 里同步执行，每次 HTTP 会阻塞
// 1~3 秒（超时 5~6 秒），表现为「画面和按键每分钟停一下」。
// 现在由独立任务负责网络，loop 只绘制与轮询按键：
// - 任务把结果写进自己的 NetSnapshot，再加锁发布到 netPending；
// - loop 在 applyNetSnapshot() 里把快照搬进全局变量并重绘，String 不会跨任务撕裂。
struct NetSnapshot {
  bool valid;          // 本次拿到了有效的页面/按键/显示数据
  bool fwKnown;        // 本次成功查询了服务端固件版本
  bool hasDisplay;     // 收到 DISPLAY 行（主状态可能为空 = 正常留白）
  int pageCount, pageIndex, currentPage;
  bool pageLoop;
  int idleSeconds;
  String title, main, sub, keys;
  String label[MAX_BTN + 1];
  String name[MAX_BTN + 1];
  bool fwAvailable;
  String fwVersion, fwNotes;
  uint32_t fwSize;
};
SemaphoreHandle_t netMux = nullptr;
NetSnapshot netPending;
volatile bool netEnabled = false;   // 注册成功后才开始周期拉取
volatile uint32_t netRefreshAt = 0; // 到点后立即拉一次（0 = 无排队；按键执行后延迟刷新）
volatile int  netPage = 1;          // 后台任务要拉的页码

// ---- 屏幕四行内容（服务端按设备类型字典下发，固件只管显示）----
// 顶栏固定：页码 + 真实 IP（WiFi.localIP，拿到前留空）+ WiFi 信号格。
String scrTitle = "", scrMain = "", scrSub = "", scrKeys = "";
bool haveDisplay = false;               // 收到过 DISPLAY 行（空主状态也要正常绘制）
int  pageCount = 1, pageIndex = 1;      // 页码来自服务端（若下发）；>=1
uint32_t lastMarquee = 0;               // 跑马灯相位推进节拍（~10fps）
uint32_t phaseTitle = 0, phaseMain = 0, phaseSub = 0, phaseKeys = 0;  // 各行独立相位

// 分页：每个按键槽可绑到一个动作；翻页由服务端回执 sys 动作驱动。
// 当前页号随回执变化，屏幕提示与按键映射由服务端随页下发。
int currentPage = 1;

// 页面策略（随 PAGE 行下发，按当前页生效）：
// - pageLoop=true  末页按「下一页」回到第 1 页；false 停住。
// - idleSeconds>0  无操作多久自动回首页（0 = 不返回）。
bool pageLoop = true;
int  idleSeconds = 0;
uint32_t lastActionAt = 0;

// 单色屏：实物有蓝光/白光/黄光三种。灰阶不存在，只有亮/灭两级；
// 层次靠字号 + 留白 + 反白块。这里用 U8G2 的像素翻转实现「反白」强调。
// 0=蓝 1=白 2=黄 由 NVS 保存，蓝屏/白屏/黄屏硬件本身发光色不同，固件绘制一致。
int screenColor = 0;

// OTA：服务端发布的版本与本地 APP_VER 不同即提示可升级
bool fwAvailable = false;
String fwVersion;
String fwNotes;
uint32_t fwSize = 0;

// 自动更新（NVS cfg.auto）：检测到新版本后自行安装，不用每次进后台点按钮
bool autoUpdate = false;
uint32_t autoOtaAt = 0;       // 延迟执行时间点（0 = 未排队）
String otaTriedVer;           // 上次尝试的版本，失败后按 OTA_RETRY_MS 冷却重试
uint32_t otaTriedAt = 0;
static const uint32_t OTA_RETRY_MS = 30UL * 60UL * 1000UL;

/* ---------------- OLED ---------------- */

// 西文等宽：6x10 字体一行约 21 字符。保留给系统提示（英文/数字）。
String fit(const String &s) {
  return s.length() > 21 ? s.substring(0, 21) : s;
}

// UTF-8 显示宽度（ASCII 按 6px，中文按 12px），用于跑马灯测宽与反白块宽度。
int utf8Width(const String &s) {
  int px = 0, i = 0;
  while (i < (int)s.length()) {
    unsigned char c = (unsigned char)s[i];
    if (c < 0x80) { px += 6; i += 1; }
    else { px += 12; i += ((c >> 4) == 0xE ? 3 : ((c >> 5) == 0x6 ? 2 : 4)); }
  }
  return px;
}

// 跑马灯（E3/E4）：文字放得下就静止；放不下才在行带内无缝循环左滚。
// 每行独立相位 + 独立速度（标题最慢、按键提示最快），各行不同步。
// 用 u8g2 的 clip 把文字限制在本行显示带，避免滚出界压到相邻行。
// 只重绘变化的行带——不整屏 30fps，避免拖慢 I2C / 心跳 / 按键轮询。
static const float MARQUEE_SPEED[4] = { 0.45, 0.75, 1.1, 1.6 };  // 基准 15px/s 的倍率
void marqueeLine(const String &txt, int x, int baseline, int maxPx,
                 uint32_t &phase, float speed, bool useCn) {
  u8g2.setClipWindow(x, baseline - 10, min((int)(x + maxPx), 128), min(baseline + 3, 64));
  int w = useCn ? utf8Width(txt) : (int)txt.length() * 6;
  if (w <= maxPx) {
    if (useCn) u8g2.drawUTF8(x, baseline, txt.c_str());
    else u8g2.drawStr(x, baseline, txt.c_str());
  } else {
    int gap = 18;
    int cycle = w + gap;
    int shift = (int)(phase % (uint32_t)cycle);
    if (useCn) {
      u8g2.drawUTF8(x - shift, baseline, txt.c_str());
      u8g2.drawUTF8(x - shift + cycle, baseline, txt.c_str());
    } else {
      u8g2.drawStr(x - shift, baseline, txt.c_str());
      u8g2.drawStr(x - shift + cycle, baseline, txt.c_str());
    }
  }
  u8g2.setMaxClipWindow();
}

// 反白强调（E4）：单色屏唯一能做的「重点」——填满亮色 + 黑字。
// abnormal=true 时，主状态行整块反白（用于异常/警告，替代红黄告警色）。
void invertBlock(int x, int y, int w, int h) {
  for (int yy = y; yy < y + h; yy++) u8g2.drawHLine(x, yy, w);
}

// 顶部状态栏（E2）：页码 + 真实 IP（拿到前留空）+ WiFi 信号格。
// 只有 WiFi 已连接才画 IP；断网/配网由 drawSysMessage 单独处理，不显示假 IP。
void drawStatusBar() {
  u8g2.setFont(u8g2_font_6x10_tf);
  u8g2.setClipWindow(0, 0, 128, 12);
  // 左：页码
  char pg[12];
  snprintf(pg, sizeof(pg), "%d/%d", pageIndex, pageCount);
  u8g2.drawStr(2, 9, pg);
  // 中：真实 station IP（未连上则为空，绝不写死示例值）
  if (WiFi.status() == WL_CONNECTED) {
    String ip = WiFi.localIP().toString();
    u8g2.drawStr(30, 9, ip.c_str());
  }
  // 右：WiFi 信号格（3 条递增竖条）
  int sx = 114;
  u8g2.drawBox(sx, 6, 2, 3);
  u8g2.drawBox(sx + 4, 4, 2, 5);
  u8g2.drawBox(sx + 8, 2, 2, 7);
  u8g2.setMaxClipWindow();
}

// 主屏（E1/E2/E3/E4）：顶栏 + 标题 + 主状态 + 副状态 + 按键提示，四行分速滚动。
// 统一用 wqy12（12px，含 ASCII 字形），中英文都能画；字号 + 留白 + 反白分层。
void drawScreen(const String &title, const String &main, const String &sub, const String &keys, bool abnormal) {
  if (!oledOk) return;
  u8g2.clearBuffer();
  drawStatusBar();

  // ① 标题（10px 中文）：
  u8g2.setFont(u8g2_font_wqy12_t_gb2312);
  marqueeLine(title, 3, 22, 122, phaseTitle, MARQUEE_SPEED[0], true);

  // ② 主状态：异常时整行反白（亮底黑字），否则正常亮字。
  if (abnormal) {
    invertBlock(2, 27, 124, 14);
    u8g2.setDrawColor(0);
    u8g2.setFont(u8g2_font_wqy12_t_gb2312);
    marqueeLine(main, 3, 38, 122, phaseMain, MARQUEE_SPEED[1], true);
    u8g2.setDrawColor(1);
  } else {
    u8g2.setFont(u8g2_font_wqy12_t_gb2312);
    marqueeLine(main, 3, 38, 122, phaseMain, MARQUEE_SPEED[1], true);
  }

  // ③ 副状态（8px 用小一号中文，wqy12 已是最小中文字库，靠 y 间距分层）：
  u8g2.setFont(u8g2_font_wqy12_t_gb2312);
  marqueeLine(sub, 3, 51, 122, phaseSub, MARQUEE_SPEED[2], true);

  // ⑤ 按键提示行（底部 54..64）：
  if (keys.length()) {
    u8g2.setFont(u8g2_font_wqy12_t_gb2312);
    marqueeLine(keys, 3, 63, 124, phaseKeys, MARQUEE_SPEED[3], true);
  }
  u8g2.sendBuffer();
}

// 兼容旧调用：oledShow(title,l1,l2,l3) 走同一套四行布局（无反白）。
// 系统提示（Booting / WiFi lost / Updating 等）仍用此入口，只是不显示反白块。
void oledShow(const String &title, const String &l1 = "", const String &l2 = "", const String &l3 = "") {
  drawScreen(title, l1, l2, l3, false);
}

// 按键反馈：临时占屏 2.5 秒，之后由主循环恢复常规页面。
// 控制项名称来自服务端，可能是中文，必须用 UTF-8 中文字库 + drawUTF8，
// 否则按字节渲染就是乱码。
void oledToast(const String &title, const String &name = "", const String &status = "") {
  if (!oledOk) return;
  // 按键反馈用同一套四行布局；第 2 行反白表示「这是临时反馈态」。
  // 单色屏做不到变暗，靠反白块 + 文案表达（E4）。
  drawScreen(title, name, status, "", true);
  toastUntil = millis() + 2500;
}

void initOled() {
  Wire.begin(PIN_SDA, PIN_SCL);
  Wire.setClock(400000);
  uint8_t addr = 0;
  for (uint8_t a : {0x3C, 0x3D}) {
    Wire.beginTransmission(a);
    if (Wire.endTransmission() == 0) { addr = a; break; }
  }
  if (!addr) {
    Serial.println("OLED not found, check SDA/SCL/VCC");
    return;
  }
  u8g2.setI2CAddress(addr << 1);
  u8g2.begin();
  u8g2.setPowerSave(0);
  oledOk = true;
  Serial.printf("OLED ready at 0x%02X\n", addr);
}

/* ---------------- WiFi ---------------- */

void loadCreds() {
  prefs.begin("wifi", true);
  ssid = prefs.getString("ssid", DEFAULT_SSID);
  pass = prefs.getString("pass", DEFAULT_PASS);
  prefs.end();

  prefs.begin("cfg", true);
  serverBase = prefs.getString("base", DEFAULT_SERVER_BASE);
  screenColor = prefs.getInt("color", 0);   // E4：0=蓝 1=白 2=黄（仅记录色别，绘制三色通用）
  if (screenColor < 0 || screenColor > 2) screenColor = 0;
  autoUpdate = prefs.getBool("auto", false);
  prefs.end();
  if (serverBase.isEmpty()) serverBase = DEFAULT_SERVER_BASE;

  // 按键槽位 → GPIO 映射（设备设置页维护）。首次上电沿用默认 4/5/6。
  prefs.begin("btns", true);
  int savedCount = prefs.getInt("n", -1);
  if (savedCount < 0) savedCount = sizeof(DEFAULT_BTN_PINS) / sizeof(DEFAULT_BTN_PINS[0]);
  if (savedCount > MAX_BTN) savedCount = MAX_BTN;
  btnCount = savedCount;
  for (int i = 0; i < MAX_BTN; i++) {
    int fallback = i < (int)(sizeof(DEFAULT_BTN_PINS) / sizeof(DEFAULT_BTN_PINS[0])) ? DEFAULT_BTN_PINS[i] : -1;
    String key = "p" + String(i + 1);
    btnPins[i] = prefs.getInt(key.c_str(), fallback);
    if (btnPins[i] < -1 || btnPins[i] > 48) btnPins[i] = -1;
  }
  prefs.end();

  Serial.printf("credssid=%s pass=%s\n", ssid.c_str(), pass.isEmpty() ? "(empty)" : "***");
  Serial.printf("serverBase=%s\n", serverBase.c_str());
  Serial.printf("buttons=%d", btnCount);
  for (int i = 0; i < btnCount; i++) Serial.printf(" %d:GPIO%d", i + 1, btnPins[i]);
  Serial.println();
}

bool connectSTA(uint32_t timeoutMs) {
  WiFi.mode(WIFI_STA);
  WiFi.setSleep(false);
  WiFi.begin(ssid.c_str(), pass.c_str());
  uint32_t t0 = millis();
  uint32_t drawn = 0;
  while (millis() - t0 < timeoutMs) {
    if (WiFi.status() == WL_CONNECTED) return true;
    if (millis() - drawn > 1000) {
      drawn = millis();
      oledShow("WiFi connecting", ssid, String("waited ") + (int)((millis() - t0) / 1000) + "s");
    }
    delay(50);
  }
  return WiFi.status() == WL_CONNECTED;
}

/* ---------------- pscreen_server 上报 ---------------- */

bool postJson(const String &path, const String &body) {
  WiFiClient client;
  HTTPClient http;
  if (!http.begin(client, serverBase + path)) return false;
  http.setTimeout(6000);
  http.addHeader("Content-Type", "application/json");
  int code = http.POST((uint8_t *)body.c_str(), body.length());
  String resp = code > 0 ? http.getString() : String();
  http.end();
  bool ok = (code == 200 && resp.indexOf("\"code\":0") >= 0);
  Serial.print("[srv] ");
  Serial.print(path);
  Serial.print(" -> HTTP ");
  Serial.print(code);
  if (ok) {
    Serial.println(" ok");
  } else {
    Serial.print(" fail: ");
    Serial.println(resp.substring(0, 80));
  }
  return ok;
}

bool getText(const String &path, String &out) {
  WiFiClient client;
  HTTPClient http;
  if (!http.begin(client, serverBase + path)) return false;
  http.setTimeout(5000);
  int code = http.GET();
  if (code == 200) out = http.getString();
  http.end();
  return code == 200;
}

void buildDeviceId() {
  String mac = WiFi.macAddress();  // 30:30:F9:6C:D0:3C
  mac.replace(":", "");
  mac.toLowerCase();
  deviceId = "esp32s3-" + mac;
}

void reportToServer(bool isRegister) {
  if (deviceId.isEmpty()) buildDeviceId();
  String body = "{\"deviceId\":\"" + deviceId + "\"";
  if (isRegister) {
    body += ",\"name\":\"" + String(DEVICE_NAME) + "\",\"platform\":\"esp32\",\"model\":\"ESP32-S3 1.3 OLED\"";
  }
  body += ",\"appVersion\":\"" + String(APP_VER) + "\"";
  body += ",\"rssi\":" + String(WiFi.RSSI());
  // 上报本机槽位→GPIO 映射：后台据此显示实际引脚，并提示未映射的槽位。
  body += ",\"espButtons\":[";
  bool firstBtn = true;
  for (int i = 0; i < btnCount; i++) {
    if (btnPins[i] < 0) continue;
    if (!firstBtn) body += ",";
    body += "{\"slot\":" + String(i + 1) + ",\"pin\":" + String(btnPins[i]) + "}";
    firstBtn = false;
  }
  body += "]";
  body += ",\"ip\":\"" + WiFi.localIP().toString() + "\"}";
  srvOk = postJson(isRegister ? "/api/device/register" : "/api/device/heartbeat", body);
}

/* ---------------- HA 控制 ---------------- */

// 从服务端拉取已放行的控制项（button|name|entityId|action|id），缓存按钮名称供屏幕提示用
// 按分隔符 | 取第 n 段（0 起）。文本里 | 已被服务端清洗掉，直接 split 即可。
String fieldAt(const String &line, int n) {
  int start = 0, idx = 0;
  while (idx < n) {
    int p = line.indexOf('|', start);
    if (p < 0) return "";
    start = p + 1; idx++;
  }
  int end = line.indexOf('|', start);
  return line.substring(start, end < 0 ? line.length() : end);
}

/**
 * 拉取某页的显示与按键，解析进快照（不碰共享全局变量）。
 * 返回 true 表示本次 HTTP 成功；失败时快照保持 invalid，调用方不会覆盖旧内容。
 */
bool fetchActionsInto(int page, NetSnapshot &snap) {
  snap.hasDisplay = false;
  snap.pageCount = 1;
  snap.pageIndex = 1;
  snap.currentPage = page;
  snap.pageLoop = true;
  snap.idleSeconds = 0;
  for (int i = 0; i <= MAX_BTN; i++) { snap.label[i] = ""; snap.name[i] = ""; }
  if (WiFi.status() != WL_CONNECTED) return false;
  if (deviceId.isEmpty()) buildDeviceId();
  String text;
  if (!getText("/api/device/esp/actions?format=text&deviceId=" + deviceId + "&page=" + String(page), text)) return false;
  int start = 0;
  bool gotDisplay = false;
  while (start < (int)text.length()) {
    int end = text.indexOf('\n', start);
    if (end < 0) end = text.length();
    String line = text.substring(start, end);
    line.trim();
    start = end + 1;
    if (!line.length()) continue;

    // 分页：PAGE|当前页|总页数|循环(0/1)|空闲秒（后两段旧服务端可能没有）
    if (line.startsWith("PAGE|")) {
      int cur = fieldAt(line, 1).toInt();
      int tot = fieldAt(line, 2).toInt();
      String loopText = fieldAt(line, 3);
      String idleText = fieldAt(line, 4);
      if (tot < 1) tot = 1;
      if (cur < 1) cur = 1;
      if (cur > tot) cur = tot;
      snap.pageCount = tot;
      snap.pageIndex = cur;
      snap.currentPage = cur;  // 服务端会按实际页数收敛，避免页被删后卡在空页
      snap.pageLoop = loopText != "0";
      if (idleText.length()) snap.idleSeconds = idleText.toInt();
      continue;
    }
    // 显示层：DISPLAY|title|main|sub|keys —— 服务端按字典解析好的四行。
    // main/sub 允许为空（没有值就留白），固件不要补 `--`。
    if (line.startsWith("DISPLAY")) {
      snap.title = fieldAt(line, 1);
      snap.main  = fieldAt(line, 2);
      snap.sub   = fieldAt(line, 3);
      snap.keys  = fieldAt(line, 4);
      gotDisplay = true;
      continue;
    }
    // 当前页按键：slot|短标签|完整名称|entityId|action|id
    int slot = fieldAt(line, 0).toInt();
    if (slot >= 1 && slot <= MAX_BTN) {
      snap.label[slot] = fieldAt(line, 1);
      snap.name[slot]  = fieldAt(line, 2);
    }
  }
  snap.hasDisplay = gotDisplay;
  // 没收到 DISPLAY 行（老服务端 / 未分类）时给明确提示，不显示假内容。
  if (!gotDisplay) {
    snap.title = "";
    snap.main  = "未配置显示";
    snap.sub   = "请在 Admin 设备分类页设置";
    snap.keys  = "";
  }
  Serial.printf("[esp] 已放行控制项 %u 字节，显示行 %d\n", (unsigned)text.length(), gotDisplay ? 1 : 0);
  return true;
}

// 让服务端执行某个按钮 / 控制项对应的 HA 动作。
// 返回服务端响应体（含 sys 翻页回执），失败返回空串。
String pressAction(const String &body) {
  WiFiClient client;
  HTTPClient http;
  String out;
  if (!http.begin(client, serverBase + "/api/device/esp/press")) return out;
  http.setTimeout(6000);
  http.addHeader("Content-Type", "application/json");
  int code = http.POST((uint8_t *)body.c_str(), body.length());
  if (code == 200) out = http.getString();
  http.end();
  return out;
}

/* ---------------- 固件升级（OTA） ---------------- */

// 查服务端发布版本：version|size|sha256|notes，与 APP_VER 不同即可升级。
// 只写快照；自动更新的排队放到主循环（applyNetSnapshot）里做，避免跨任务写
// autoOtaAt。返回 true 表示本次成功查到服务端（空内容也算）。
bool checkFirmwareInto(NetSnapshot &snap) {
  snap.fwAvailable = false;
  snap.fwVersion = "";
  snap.fwNotes = "";
  snap.fwSize = 0;
  if (WiFi.status() != WL_CONNECTED) return false;
  String text;
  if (!getText("/api/device/firmware/latest?format=text", text)) return false;
  text.trim();
  if (text.length() == 0) return true;
  int p1 = text.indexOf('|');
  if (p1 <= 0) return true;
  int p2 = text.indexOf('|', p1 + 1);
  int p3 = p2 < 0 ? -1 : text.indexOf('|', p2 + 1);
  snap.fwVersion = text.substring(0, p1);
  if (p2 > 0) snap.fwSize = text.substring(p1 + 1, p2).toInt();
  if (p3 >= 0) snap.fwNotes = text.substring(p3 + 1);
  snap.fwAvailable = snap.fwVersion.length() > 0 && snap.fwVersion != String(APP_VER);
  if (snap.fwAvailable) {
    Serial.printf("[ota] 可升级: %s -> %s (%uKB)\n", APP_VER, snap.fwVersion.c_str(), (unsigned)(snap.fwSize / 1024));
  }
  return true;
}

// 下载并写入另一个 OTA 槽；成功自动重启，失败保留旧固件
void runOta() {
  if (!fwAvailable) return;
  Serial.printf("[ota] start download %s\n", fwVersion.c_str());
  oledShow("Updating", "connecting...");
  WiFiClient client;
  String url = serverBase + "/api/device/firmware/download";
  httpUpdate.rebootOnUpdate(false);
  httpUpdate.onProgress([](int cur, int total) {
    static uint32_t last = 0;
    if (millis() - last < 300) return;
    last = millis();
    int pct = total > 0 ? (int)((long)cur * 100 / total) : 0;
    oledShow("Updating", String(pct) + "%",
             String(cur / 1024) + " / " + String(total / 1024) + "KB");
  });
  t_httpUpdate_return ret = httpUpdate.update(client, url);
  if (ret == HTTP_UPDATE_OK) {
    Serial.println("[ota] ok, rebooting");
    oledShow("Update done", "rebooting...");
    delay(1200);
    ESP.restart();
  }
  String err = httpUpdate.getLastErrorString();
  Serial.printf("[ota] failed code=%d msg=%s\n", (int)httpUpdate.getLastError(), err.c_str());
  otaTriedVer = fwVersion;   // 自动更新用：记录失败版本与时间，冷却后再试
  otaTriedAt = millis();
  oledShow("Update failed", String(httpUpdate.getLastError()), err.substring(0, 21));
  toastUntil = millis() + 5000;
}

void onButtonPress(int slot) {
  if (deviceId.isEmpty()) buildDeviceId();
  lastActionAt = millis();
  Serial.printf("[btn] slot %d pressed (page %d)\n", slot, currentPage);
  String shown = btnName[slot].length() ? btnName[slot] : (btnLabel[slot].length() ? btnLabel[slot] : "sending...");
  oledToast(String("Slot ") + slot, shown);
  String body = "{\"deviceId\":\"" + deviceId + "\",\"slot\":" + String(slot)
              + ",\"page\":" + String(currentPage) + "}";
  String resp = pressAction(body);
  bool ok = resp.indexOf("\"code\":0") >= 0;

  // 系统动作（翻页/回首页）——服务端回执里带 sys=next_page/prev_page/home_page。
  // loop=false 时末页按「下一页」停住（不再绕回第 1 页）。
  if (resp.indexOf("next_page") >= 0) {
    if (currentPage < pageCount) currentPage += 1;
    else if (pageLoop) currentPage = 1;
    requestPage(currentPage);
    drawMain();
    return;
  } else if (resp.indexOf("prev_page") >= 0) {
    if (currentPage > 1) currentPage -= 1;
    else if (pageLoop) currentPage = pageCount;
    requestPage(currentPage);
    drawMain();
    return;
  } else if (resp.indexOf("home_page") >= 0) {
    currentPage = 1;
    requestPage(currentPage);
    drawMain();
    return;
  }

  oledToast(String("Slot ") + slot, shown, ok ? "sent ok" : "failed, see serial");

  // 动作已下发：约 0.7 秒后（等 HA 状态机更新）立刻拉一次显示，
  // 不用等 60 秒心跳，按下后屏幕状态基本即时更新。
  if (ok) netRefreshAt = millis() + 700;
}

// 轮询物理按键：内部上拉，对地短接为按下；60ms 去抖。
// 槽位表来自 NVS（btnCount / btnPins），未启用（-1）的槽位跳过。
void pollButtons() {
  uint32_t now = millis();
  for (int i = 0; i < btnCount; i++) {
    if (btnPins[i] < 0) continue;
    bool down = digitalRead(btnPins[i]) == LOW;
    if (down == buttons[i].down) continue;
    if (now - buttons[i].changedAt < 60) continue;
    buttons[i].down = down;
    buttons[i].changedAt = now;
    if (down) onButtonPress(i + 1);
  }
}

void drawMain() {
  if (fwAvailable) {
    // 有更新时优先提示：自动更新会自己装，否则引导用户打开本机设置页
    drawScreen("Update ready", String("cur ") + APP_VER, String("new ") + fwVersion,
               autoUpdate ? "auto updating..." : "open web page", false);
    return;
  }
  // 常规页：优先显示服务端下发的四行（设备类型字典解析），没配置时退回连接信息。
  // haveDisplay 为真但 main 为空是**正常留白**，不能退回到 WiFi 提示。
  if (haveDisplay || scrMain.length()) {
    drawScreen(scrTitle, scrMain, scrSub, scrKeys, false);
  } else {
    drawScreen("WiFi connected", ssid, WiFi.localIP().toString(),
               (srvOk ? "srv ok " : "srv fail ") + String(WiFi.RSSI()) + "dBm", false);
  }
}

/* ---------------- 后台网络任务 ---------------- */

/** 请求后台任务立刻拉一次指定页（翻页 / 空闲回首页后调用）。 */
void requestPage(int page) {
  netPage = page;
  netRefreshAt = millis();
}

/** 把任务解析好的快照发布到共享槽位（任务侧调用，只写 netPending）。 */
void publishSnapshot(NetSnapshot &snap) {
  if (!netMux) return;
  if (xSemaphoreTake(netMux, portMAX_DELAY) == pdTRUE) {
    netPending = snap;
    xSemaphoreGive(netMux);
  }
}

/**
 * 主循环侧：把快照搬进全局变量并重绘。
 *
 * 用非阻塞加锁（0 超时），拿不到锁就下一轮再取——主循环绝不被网络任务卡住。
 */
void applyNetSnapshot() {
  if (!netMux) return;
  if (xSemaphoreTake(netMux, 0) != pdTRUE) return;
  NetSnapshot snap = netPending;
  bool dirty = snap.valid || snap.fwKnown;
  netPending.valid = false;
  netPending.fwKnown = false;
  xSemaphoreGive(netMux);
  if (!dirty) return;

  if (snap.valid) {
    scrTitle = snap.title;
    scrMain  = snap.main;
    scrSub   = snap.sub;
    scrKeys  = snap.keys;
    haveDisplay = snap.hasDisplay;
    for (int i = 0; i <= MAX_BTN; i++) {
      btnLabel[i] = snap.label[i];
      btnName[i]  = snap.name[i];
    }
    pageCount   = snap.pageCount;
    pageIndex   = snap.pageIndex;
    currentPage = snap.currentPage;
    netPage     = currentPage;
    pageLoop    = snap.pageLoop;
    idleSeconds = snap.idleSeconds;
  }

  if (snap.fwKnown) {
    fwAvailable = snap.fwAvailable;
    fwVersion   = snap.fwVersion;
    fwNotes     = snap.fwNotes;
    fwSize      = snap.fwSize;
    if (!fwAvailable) {
      autoOtaAt = 0;
    } else if (autoUpdate) {
      // 自动更新：延迟 8 秒再写 Flash；同一版本失败过则冷却 OTA_RETRY_MS，
      // 避免远程设备陷入「失败-重启-再失败」。
      bool firstTry = otaTriedVer != fwVersion;
      bool cooled = (millis() - otaTriedAt) > OTA_RETRY_MS;
      if ((firstTry || cooled) && autoOtaAt == 0) {
        autoOtaAt = millis() + 8000;
        Serial.printf("[ota] 自动更新已排队: %s\n", fwVersion.c_str());
      }
    }
  }

  if (!toastUntil) drawMain();
}

/** 后台任务：心跳 / 拉配置 / 查固件，全部不占用主循环的绘制时间。 */
void netTask(void *) {
  uint32_t lastCycle = 0;
  for (;;) {
    // 到点刷新：翻页是立即，按键动作后延迟 ~0.7 秒等 HA 状态机更新。
    // 用有符号差值比较，millis() 回绕也不会漏触发。
    bool refresh = netRefreshAt != 0 && (int32_t)(millis() - netRefreshAt) >= 0;
    if (refresh) netRefreshAt = 0;
    if (netEnabled && WiFi.status() == WL_CONNECTED
        && (refresh || millis() - lastCycle >= REPORT_MS)) {
      lastCycle = millis();
      int page = netPage;
      reportToServer(false);
      NetSnapshot snap;
      snap.valid = fetchActionsInto(page, snap);
      snap.fwKnown = checkFirmwareInto(snap);
      if (snap.valid || snap.fwKnown) publishSnapshot(snap);
    }
    vTaskDelay(pdMS_TO_TICKS(200));   // 轮询刷新请求的粒度
  }
}

// 跑马灯节拍（E3）：~10fps 推进各行相位，只在有超长文本被滚动时才重绘，
// 避免整屏高频刷新拖慢 I2C / 心跳 / 按键轮询。相位 = 时间 × 15px/s × 各行倍率。
void tickMarquee() {
  if (!oledOk) return;
  static uint32_t lastTickMs = 0;
  uint32_t now = millis();
  if (now - lastTickMs < 100) return;         // ~10fps
  uint32_t dt = now - lastTickMs;
  lastTickMs = now;
  if (toastUntil && now < toastUntil) return; // 按键反馈占屏期间不滚
  // 只有文字确实超宽才需要滚动；静止文本不动相位。
  bool needScroll = utf8Width(scrTitle) > 122 || utf8Width(scrMain) > 122
                 || utf8Width(scrSub) > 122 || utf8Width(scrKeys) > 124;
  if (!needScroll) return;
  float base = 15.0f * dt / 1000.0f;          // 基准 15px/s
  phaseTitle += (uint32_t)(base * MARQUEE_SPEED[0]);
  phaseMain  += (uint32_t)(base * MARQUEE_SPEED[1]);
  phaseSub   += (uint32_t)(base * MARQUEE_SPEED[2]);
  phaseKeys  += (uint32_t)(base * MARQUEE_SPEED[3]);
  drawMain();                                  // 用新相位重绘
}

void showConnected() {
  String ip = WiFi.localIP().toString();
  Serial.printf("WiFi connected: ssid=%s ip=%s rssi=%d\n", WiFi.SSID().c_str(), ip.c_str(), WiFi.RSSI());
  Serial.printf("web config: http://%s/\n", ip.c_str());
  gApMode = false;
  if (!serverStarted) setupServer();  // 局域网内也能打开配置页

  buildDeviceId();
  reportToServer(true);
  // 注册完成后交给后台任务：首次拉取 + 之后每 REPORT_MS 一次心跳/配置。
  netEnabled = true;
  netPage = currentPage;
  netRefreshAt = millis();

  drawMain();
}

/* ---------------- 配网页面 ---------------- */

String pageCss() {
  String c;
  c += "body{font-family:-apple-system,sans-serif;margin:0;padding:24px;background:#f5f6f8;color:#222}";
  c += ".card{max-width:460px;margin:0 auto;background:#fff;border-radius:12px;padding:20px;box-shadow:0 2px 12px rgba(0,0,0,.08)}";
  c += "h2{margin:0 0 16px;font-size:20px}h3{margin:18px 0 8px;font-size:15px}";
  c += "label{display:block;font-size:13px;color:#666;margin:12px 0 6px}";
  c += "input{width:100%;box-sizing:border-box;padding:10px;font-size:15px;border:1px solid #ccd;border-radius:8px}";
  c += "button{width:100%;margin-top:18px;padding:12px;font-size:16px;border:0;border-radius:8px;background:#2f6fed;color:#fff}";
  c += "button.mini{width:auto;margin:0;padding:6px 12px;font-size:13px;background:#eef4ff;color:#2f6fed}";
  c += ".tip{font-size:12px;color:#888;margin-top:14px;line-height:1.5}";
  c += ".st{font-size:13px;background:#eef4ff;color:#2f6fed;padding:10px;border-radius:8px;margin-bottom:6px}";
  c += ".err{background:#fdecec;color:#c0392b}";
  c += ".nav{display:flex;gap:8px;margin-bottom:14px}";
  c += ".nav a{padding:6px 12px;border-radius:8px;background:#eef4ff;color:#2f6fed;text-decoration:none;font-size:14px}";
  c += ".nav a.on{background:#2f6fed;color:#fff}";
  c += "table{width:100%;border-collapse:collapse;font-size:13px}";
  c += "th,td{text-align:left;padding:8px 4px;border-bottom:1px solid #eee;vertical-align:middle}";
  c += "th{color:#999;font-weight:500}.mono{font-family:ui-monospace,monospace;font-size:12px;color:#666}";
  c += ".empty{font-size:13px;color:#999;padding:10px 0}";
  c += ".chk{display:flex;align-items:center;gap:8px;font-size:13px;color:#333;margin:12px 0}";
  c += ".chk input{width:auto;margin:0}";
  return c;
}

String pageHead(const String &title) {
  String h;
  h += "<!DOCTYPE html><html><head><meta charset='utf-8'>";
  h += "<meta name='viewport' content='width=device-width,initial-scale=1'>";
  h += "<title>";
  h += title;
  h += "</title><style>";
  h += pageCss();
  h += "</style></head>";
  return h;
}

String pageNav(const char *active) {
  String n = "<div class='nav'>";
  n += String("<a href='/'") + (strcmp(active, "wifi") == 0 ? " class='on'" : "") + ">WiFi</a>";
  n += String("<a href='/settings'") + (strcmp(active, "settings") == 0 ? " class='on'" : "") + ">设置</a>";
  n += "</div>";
  return n;
}

String pageHtml(bool apMode) {
  String opts;
  if (apMode) {
    int n = WiFi.scanNetworks();
    for (int i = 0; i < n; i++) {
      opts += "<option value=\"" + WiFi.SSID(i) + "\">" + WiFi.SSID(i) + " (" + WiFi.RSSI(i) + "dBm)</option>";
    }
  }

  String status;
  if (apMode) {
    status = "当前为配网热点模式，请填写要连接的路由器 WiFi";
  } else {
    status = "已连接 " + WiFi.SSID() + "，IP " + WiFi.localIP().toString() +
             "，信号 " + String(WiFi.RSSI()) + " dBm";
  }

  String h = pageHead("WiFi 设置");
  h += "<body><div class='card'>";
  h += pageNav("wifi");
  h += "<h2>屏幕 WiFi 设置</h2><div class='st'>" + status + "</div>";
  h += "<form method='POST' action='/save'>";
  h += "<label>WiFi 名称（2.4G）</label><input name='ssid' list='nets' value='" + ssid + "' required>";
  h += "<datalist id='nets'>" + opts + "</datalist>";
  h += "<label>WiFi 密码</label><input name='pass' type='password' placeholder='留空表示不修改'>";
  h += "<button type='submit'>保存并连接</button></form>";
  h += "<div class='tip'>保存后设备会自动重启并连接。若连接失败会重新开启热点，可再次配置。</div>";
  h += "</div></body></html>";
  return h;
}

/** 设置页：控制端地址 + 从服务端拉到的已放行控制项（含网页测试按钮）。 */
String pageSettings(const String &listText, const String &err) {
  String h = pageHead("屏幕设置");
  h += "<body><div class='card'>";
  h += pageNav("settings");
  h += "<h2>屏幕设置</h2>";
  h += String("<div class='st'>设备 id：") + deviceId + "</div>";

  h += "<form method='POST' action='/settings/save'>";
  h += "<label>控制端地址（上报 / 读取控制项）</label>";
  h += String("<input name='base' value='") + serverBase + "' placeholder='" + DEFAULT_SERVER_BASE + "'>";
  h += "<button type='submit'>保存并重启</button></form>";
  h += String("<div class='tip'>默认 ") + DEFAULT_SERVER_BASE +
       "；换域名或换服务端时在这里改，不用重新烧录。留空保存恢复默认。</div>";

  h += "<h3>可控设备</h3>";
  if (err.length()) {
    h += String("<div class='st err'>") + err + "</div>";
  } else if (listText.length() == 0) {
    h += "<div class='empty'>服务端第 1 页还没有按键。请到 pscreen_server 管理页「ESP 设备分类」里添加页面和按键。</div>";
  } else {
    h += "<table><tr><th>槽位</th><th>板上 GPIO</th><th>名称 / 实体</th><th>动作</th><th></th></tr>";
    int start = 0;
    while (start < (int)listText.length()) {
      int end = listText.indexOf('\n', start);
      if (end < 0) end = listText.length();
      String line = listText.substring(start, end);
      line.trim();
      start = end + 1;
      if (line.length() == 0) continue;
      // 当前页按键：slot|名称|名称|entityId|action|id（第 2 段兼容旧格式）
      String btn = fieldAt(line, 0);
      String label = fieldAt(line, 1);
      String name = fieldAt(line, 2);
      String entity = fieldAt(line, 3);
      String act = fieldAt(line, 4);
      String id = fieldAt(line, 5);
      if (btn.length() == 0) continue;
      String actLabel = act == "toggle" ? "切换" : act == "turn_on" ? "开" : act == "turn_off" ? "关" : "执行";
      String shownName = name.length() ? name : label;
      // 板上 GPIO：来自下方「物理按键槽位」的槽位→引脚映射。
      // 槽位 0 = 仅网页；槽位超出已启用数量 / 引脚为 -1 时显示未映射。
      int slotNo = btn.toInt();
      String pinText = "—";
      if (slotNo >= 1) {
        if (slotNo <= btnCount && btnPins[slotNo - 1] >= 0) {
          pinText = "GPIO" + String(btnPins[slotNo - 1]);
        } else {
          pinText = "未映射";
        }
      }
      h += String("<tr><td>") + (btn == "0" ? String("-") : btn) + "</td>";
      h += "<td>" + pinText + "</td>";
      h += "<td>" + shownName + "<div class='mono'>" + entity + "</div></td>";
      h += String("<td>") + actLabel + "</td>";
      h += "<td><form method='POST' action='/settings/press' style='margin:0'>";
      if (btn == "0") {
        h += String("<input type='hidden' name='actionId' value='") + id + "'>";
      } else {
        h += String("<input type='hidden' name='slot' value='") + btn + "'>";
      }
      h += "<button class='mini' type='submit'>测试</button></form></td></tr>";
    }
    h += "</table>";
    h += "<div class='tip'>「板上 GPIO」来自下方「物理按键槽位」的映射：槽位可增删、"
         "GPIO 可改，保存后重启生效；槽位 0 表示只允许在网页里点。</div>";
  }

  // 物理按键槽位：槽位号 = 行号，与后台页面里的「槽位」一一对应。
  // GPIO 留空 / -1 = 该槽位停用；保存后重启生效。
  h += "<h3>物理按键槽位</h3>";
  h += "<div class='tip'>槽位号要和后台页面里的「槽位」一致。GPIO 留空或填 -1 表示停用；"
       "保存后设备重启生效。用杜邦线把 GPIO 与 GND 短接即触发。</div>";
  h += "<form method='POST' action='/settings/buttons'>";
  h += "<table><tr><th>槽位</th><th>GPIO</th></tr>";
  for (int i = 0; i < MAX_BTN; i++) {
    h += "<tr><td>" + String(i + 1) + "</td><td>";
    h += "<input class='pin' name='p" + String(i + 1) + "' inputmode='numeric' value='"
         + String(btnPins[i] >= 0 ? btnPins[i] : -1) + "'></td></tr>";
  }
  h += "</table>";
  h += "<button class='mini' type='button' onclick='addSlot()' style='margin-top:8px'>＋ 添加槽位</button>";
  h += "<button type='submit'>保存按键映射并重启</button></form>";
  h += "<div class='tip'>避开 GPIO26~32（Flash 占用）以及 0/45/46（启动脚）。"
       "建议 4/5/6/7/10~18/21/33~42/47/48。</div>";
  h += "<script>function addSlot(){var ins=document.querySelectorAll('.pin');"
       "var used={};for(var i=0;i<ins.length;i++){if(ins[i].value!=='-1'&&ins[i].value!=='')used[ins[i].value]=1;}"
       "var cand=[4,5,6,7,10,11,12,13,14,15,16,17,18,21,33,34,35,36,37,38,39,40,41,42,43,44,47,48];"
       "for(var j=0;j<ins.length;j++){if(ins[j].value==='-1'||ins[j].value===''){"
       "for(var k=0;k<cand.length;k++){if(!used[cand[k]]){ins[j].value=cand[k];return;}}}}"
       "alert('槽位已满');}</script>";

  h += "<h3>固件升级</h3>";
  h += String("<div class='st'>当前版本：") + APP_VER + "</div>";
  if (fwAvailable) {
    h += String("<div class='st'>新版本：") + fwVersion + "（" + String(fwSize / 1024) + "KB）</div>";
    if (fwNotes.length()) h += String("<div class='tip'>") + fwNotes + "</div>";
    h += "<form method='POST' action='/update'><button type='submit'>立即升级</button></form>";
    h += "<div class='tip'>升级期间不要断电；完成后设备会自动重启，配置不会丢。</div>";
  } else {
    h += "<div class='tip'>已是最新版本（服务端未发布新固件时也显示此项）。</div>";
  }
  h += "<form method='POST' action='/settings/auto'>";
  h += String("<label class='chk'><input type='checkbox' name='auto' value='1'") +
       (autoUpdate ? " checked" : "") + "> 自动更新</label>";
  h += "<div class='tip'>开启后检测到新版本会自动下载安装（约 20 秒，屏幕显示进度），完成后自动重启；"
       "失败会保留当前固件并在 30 分钟后重试。远程设备建议开启。</div>";
  h += "<button type='submit'>保存自动更新设置</button></form>";
  h += "</div></body></html>";
  return h;
}

// STA / AP 两种模式共用同一套页面，apMode 在请求时读取
// 返回 true 表示已发出 401，调用方直接 return
bool authBlocked() {
  if (gApMode) return false;
  if (server.authenticate(WEB_USER, WEB_PASS)) return false;
  server.requestAuthentication();
  return true;
}

void setupServer() {
  server.on("/", []() {
    if (authBlocked()) return;
    server.send(200, "text/html; charset=utf-8", pageHtml(gApMode));
  });
  server.on("/save", HTTP_POST, []() {
    if (authBlocked()) return;
    String s = server.arg("ssid");
    String p = server.arg("pass");
    s.trim();
    if (s.length()) {
      if (p.length() == 0) p = pass;  // 密码留空表示沿用原密码
      prefs.begin("wifi", false);
      prefs.putString("ssid", s);
      prefs.putString("pass", p);
      prefs.end();
      server.send(200, "text/html; charset=utf-8",
                  "<meta charset='utf-8'><h3>已保存，设备正在重启…</h3>");
      delay(1200);
      ESP.restart();
    } else {
      server.send(400, "text/html; charset=utf-8", "<meta charset='utf-8'><h3>SSID 不能为空</h3>");
    }
  });

  // 设置页：控制端地址 + 服务端已放行的控制项
  server.on("/settings", []() {
    if (authBlocked()) return;
    if (deviceId.isEmpty()) buildDeviceId();
    String text, err;
    if (gApMode) {
      err = "当前是配网热点模式，连上 WiFi 后才有控制端数据";
    } else {
      String path = "/api/device/esp/actions?format=text&deviceId=" + deviceId;
      if (!getText(path, text)) err = "读取控制项失败：检查控制端地址是否可达";
    }
    server.send(200, "text/html; charset=utf-8", pageSettings(text, err));
  });

  server.on("/settings/save", HTTP_POST, []() {
    if (authBlocked()) return;
    String base = server.arg("base");
    base.trim();
    while (base.endsWith("/")) base.remove(base.length() - 1);
    if (base.length() == 0) base = DEFAULT_SERVER_BASE;
    if (!base.startsWith("http://") && !base.startsWith("https://")) base = "http://" + base;
    prefs.begin("cfg", false);
    prefs.putString("base", base);
    prefs.end();
    server.send(200, "text/html; charset=utf-8",
                "<meta charset='utf-8'><h3>已保存，设备正在重启…</h3>");
    delay(1200);
    ESP.restart();
  });

  // 按键槽位映射：槽位号 = 表单行号，空 / -1 / 重复引脚视为停用；保存后重启生效。
  server.on("/settings/buttons", HTTP_POST, []() {
    if (authBlocked()) return;
    int pins[MAX_BTN];
    int maxSlot = 0;
    for (int i = 0; i < MAX_BTN; i++) {
      String key = "p" + String(i + 1);
      String raw = server.hasArg(key.c_str()) ? server.arg(key.c_str()) : String();
      raw.trim();
      int pin = -1;
      bool valid = false;
      if (raw.length() && raw != "-1") {
        pin = raw.toInt();
        valid = pin >= 0 && pin <= 48;
      }
      // 同一 GPIO 只能绑一个槽位，避免两个槽位抢同一颗按键。
      if (valid) {
        for (int j = 0; j < i; j++) {
          if (pins[j] == pin) valid = false;
        }
      }
      pins[i] = valid ? pin : -1;
      if (valid) maxSlot = i + 1;
    }
    prefs.begin("btns", false);
    prefs.putInt("n", maxSlot);
    for (int i = 0; i < MAX_BTN; i++) {
      prefs.putInt(("p" + String(i + 1)).c_str(), pins[i]);
    }
    prefs.end();
    Serial.printf("[btn] 槽位映射已保存：%d 个\n", maxSlot);
    server.send(200, "text/html; charset=utf-8",
                "<meta charset='utf-8'><h3>已保存，设备正在重启…</h3>");
    delay(1200);
    ESP.restart();
  });

  // 自动更新开关：只写 NVS，不重启；开启时若已有待装版本则立刻排队
  server.on("/settings/auto", HTTP_POST, []() {
    if (authBlocked()) return;
    autoUpdate = server.arg("auto") == "1";
    prefs.begin("cfg", false);
    prefs.putBool("auto", autoUpdate);
    prefs.end();
    Serial.printf("[ota] 自动更新: %s\n", autoUpdate ? "开" : "关");
    if (autoUpdate && fwAvailable && autoOtaAt == 0) autoOtaAt = millis() + 8000;
    server.sendHeader("Location", "/settings");
    server.send(303, "text/plain", "");
  });

  // 网页「测试」按钮：直接请服务端执行对应动作（同样受白名单约束）
  server.on("/settings/press", HTTP_POST, []() {
    if (authBlocked()) return;
    if (deviceId.isEmpty()) buildDeviceId();
    String actionId = server.arg("actionId");
    String slot = server.arg("slot");
    String body = "{\"deviceId\":\"" + deviceId + "\"";
    if (actionId.length()) body += ",\"actionId\":\"" + actionId + "\"";
    else body += ",\"slot\":" + (slot.length() ? slot : String("0"));
    body += "}";
    bool ok = WiFi.status() == WL_CONNECTED && pressAction(body);
    String msg = ok ? "已执行" : "执行失败：设备未联网，或该槽位未在后台配置 / HA 未配置（详见设备串口日志）";
    server.send(200, "text/html; charset=utf-8",
                String("<meta charset='utf-8'><div style='font-family:-apple-system;padding:24px'>") +
                msg + "<p><a href='/settings'>返回设置</a></p></div>");
  });
  // 本地页面「立即升级」：先回包再下载，浏览器不用等整个 OTA
  server.on("/update", HTTP_POST, []() {
    if (authBlocked()) return;
    if (!fwAvailable) {
      server.send(200, "text/html; charset=utf-8",
                  "<meta charset='utf-8'><div style='font-family:-apple-system;padding:24px'>没有可用更新"
                  "<p><a href='/settings'>返回设置</a></p></div>");
      return;
    }
    server.send(200, "text/html; charset=utf-8",
                String("<meta charset='utf-8'><div style='font-family:-apple-system;padding:24px'>"
                       "<h3>正在升级到 ") + fwVersion +
                "</h3><p>屏幕会显示进度，完成后设备会自动重启。</p></div>");
    delay(300);
    runOta();
  });

  server.onNotFound([]() {
    if (gApMode) {
      server.sendHeader("Location", "http://192.168.4.1/");
      server.send(302, "text/plain", "");
    } else {
      server.send(404, "text/plain", "not found");
    }
  });
  server.begin();
  serverStarted = true;
}

void startPortal() {
  Serial.println("STA failed -> starting setup AP");
  if (serverStarted) {
    server.stop();
    serverStarted = false;
  }
  gApMode = true;
  WiFi.mode(WIFI_AP);
  WiFi.softAP(AP_SSID);
  IPAddress ip = WiFi.softAPIP();

  dns.start(53, "*", ip);
  setupServer();

  portal = true;
  lastRetry = millis();
  oledShow("WiFi setup AP", AP_SSID, ip.toString(), "open 192.168.4.1");
}

// 热点模式下用已保存账号偷偷重试，成功就重启回到正常 STA 流程
void portalRetry() {
  Serial.println("portal retry...");
  WiFi.mode(WIFI_AP_STA);
  WiFi.begin(ssid.c_str(), pass.c_str());
  for (int i = 0; i < 40 && WiFi.status() != WL_CONNECTED; i++) delay(250);
  if (WiFi.status() == WL_CONNECTED) {
    Serial.println("portal retry ok, restarting into STA mode");
    delay(300);
    ESP.restart();
  }
  WiFi.disconnect();
  WiFi.mode(WIFI_AP);
  oledShow("WiFi setup AP", AP_SSID, "192.168.4.1", "still not joined");
}

/* ---------------- 主流程 ---------------- */

void setup() {
  Serial.begin(115200);
  delay(300);
  Serial.println("\n=== Potatokid screen boot ===");

  initOled();
  oledShow("Booting", "OLED test ok");
  delay(400);

  loadCreds();

  // 按键：槽位映射要先由 loadCreds 从 NVS 读出来，再按槽位配置上拉输入。
  for (int i = 0; i < MAX_BTN; i++) {
    if (i < btnCount && btnPins[i] >= 0) pinMode(btnPins[i], INPUT_PULLUP);
    buttons[i].down = false;
    buttons[i].changedAt = 0;
  }

  // 网络任务固定在 core 0：主循环（绘制/I2C/按键）留在 core 1，互不打断。
  netMux = xSemaphoreCreateMutex();
  xTaskCreatePinnedToCore(netTask, "net", 12288, nullptr, 1, nullptr, 0);

  if (connectSTA(STA_TIMEOUT_MS)) {
    showConnected();
  } else {
    startPortal();
  }
}

void loop() {
  if (portal) {
    dns.processNextRequest();
    server.handleClient();
    if (millis() - lastRetry > AP_RETRY_MS) {
      lastRetry = millis();
      portalRetry();
    }
    return;
  }

  if (serverStarted) server.handleClient();  // 局域网配置页需要持续处理请求

  if (WiFi.status() != WL_CONNECTED) {
    if (lostSince == 0) {
      lostSince = millis();
      Serial.println("WiFi lost, reconnecting");
      oledShow("WiFi lost", ssid, "reconnecting...");
      WiFi.reconnect();
    } else if (millis() - lostSince > LOST_RESET_MS) {
      lostSince = 0;
      startPortal();
    }
    return;
  }

  lostSince = 0;
  pollButtons();

  // 应用后台任务刚拉到的配置（非阻塞；没有新数据时立刻返回）。
  applyNetSnapshot();

  // 空闲回首页（页面级配置）：超过 idleSeconds 没有按键就回到第 1 页。
  if (idleSeconds > 0 && currentPage != 1
      && millis() - lastActionAt > (uint32_t)idleSeconds * 1000UL) {
    currentPage = 1;
    lastActionAt = millis();
    requestPage(currentPage);
    drawMain();
  }

  // 自动更新：排队时间到且仍在线才写 Flash（失败后由冷却期避免死循环）
  if (autoOtaAt && millis() >= autoOtaAt) {
    autoOtaAt = 0;
    if (fwAvailable && WiFi.status() == WL_CONNECTED) {
      Serial.println("[ota] auto update start");
      runOta();
    }
  }

  tickMarquee();   // E3：~10fps 分速滚动（仅超长文本触发）

  static uint32_t lastDraw = 0;
  if (toastUntil && millis() > toastUntil) {
    toastUntil = 0;
    drawMain();
  }
  if (millis() - lastDraw > 5000) {
    lastDraw = millis();
    if (!toastUntil) drawMain();
    Serial.printf("online ip=%s rssi=%d heap=%u\n", WiFi.localIP().toString().c_str(),
                  WiFi.RSSI(), (unsigned)ESP.getFreeHeap());
  }
}
