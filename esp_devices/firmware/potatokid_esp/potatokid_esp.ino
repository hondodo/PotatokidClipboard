/**
 * ESP32-S3 + 1.3" SH1106 OLED (I2C) + WiFi 配网 + HA 按键
 * 接线: VCC->3V3, GND->GND, SCL->GPIO9, SDA->GPIO8
 * 按键: GPIO4/5/6 对地短接（内部上拉，按下=低电平）
 *
 * 逻辑:
 *  1. 读取 NVS 里保存的 WiFi / 控制端地址，首次上电用下方默认值
 *  2. 15 秒内连上 -> 屏幕显示 IP，向服务端注册并拉取控制项
 *  3. 连不上 -> 开热点 Potatokid-Screen-Setup，手机访问 http://192.168.4.1 配网
 *  4. 配网期间每 60 秒用已保存的账号重试一次，连上就关热点
 *  5. 按键按下 -> 请求服务端执行 HA 动作（白名单在 pscreen_server admin 页开关）
 */
#include <Wire.h>
#include <U8g2lib.h>
#include <WiFi.h>
#include <WebServer.h>
#include <DNSServer.h>
#include <Preferences.h>
#include <HTTPClient.h>
#include <HTTPUpdate.h>
#include "secrets.h"  // WiFi 默认账号 / 网页口令（本地文件，不入库）

static const int PIN_SDA = 8;
static const int PIN_SCL = 9;

// 物理按键：数组下标 + 1 就是 admin 页里的「按钮1/2/3」，对地短接即触发
static const int BTN_PINS[] = {4, 5, 6};
static const int BTN_COUNT = sizeof(BTN_PINS) / sizeof(BTN_PINS[0]);

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
static const char *APP_VER             = "oled-1.3";
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
uint32_t lastReport = 0;

// 屏幕临时提示（按键结果）与按钮名称缓存（来自服务端白名单）
uint32_t toastUntil = 0;
String btnLabel[8];
struct BtnState { bool down; uint32_t changedAt; };
BtnState buttons[BTN_COUNT];

// OTA：服务端发布的版本与本地 APP_VER 不同即提示可升级
bool fwAvailable = false;
String fwVersion;
String fwNotes;
uint32_t fwSize = 0;

/* ---------------- OLED ---------------- */

String fit(const String &s) {
  // 6x10 字体一行约 21 个字符
  return s.length() > 21 ? s.substring(0, 21) : s;
}

// 按「字符」截断 UTF-8 文本（中文一个字 3 字节），超出加 ..
String fitUtf8(const String &s, int maxChars) {
  String out;
  int i = 0, n = 0;
  while (i < (int)s.length() && n < maxChars) {
    unsigned char c = (unsigned char)s[i];
    int len = c < 0x80 ? 1 : (c >> 5) == 0x6 ? 2 : (c >> 4) == 0xE ? 3 : 4;
    out += s.substring(i, i + len);
    i += len;
    n++;
  }
  if (i < (int)s.length()) out += "..";
  return out;
}

void oledShow(const String &title, const String &l1 = "", const String &l2 = "", const String &l3 = "") {
  if (!oledOk) return;
  u8g2.clearBuffer();
  u8g2.setFont(u8g2_font_helvB10_tf);
  u8g2.drawStr(0, 13, fit(title).c_str());
  u8g2.drawHLine(0, 17, 128);
  u8g2.setFont(u8g2_font_6x10_tf);
  u8g2.drawStr(0, 31, fit(l1).c_str());
  u8g2.drawStr(0, 44, fit(l2).c_str());
  u8g2.drawStr(0, 57, fit(l3).c_str());
  u8g2.sendBuffer();
}

// 按键反馈：临时占屏 2.5 秒，之后由主循环恢复常规页面。
// 控制项名称来自服务端，可能是中文，必须用 UTF-8 中文字库 + drawUTF8，
// 否则按字节渲染就是乱码。
void oledToast(const String &title, const String &name = "", const String &status = "") {
  if (!oledOk) return;
  u8g2.clearBuffer();
  u8g2.setFont(u8g2_font_helvB10_tf);
  u8g2.drawStr(0, 13, fit(title).c_str());
  u8g2.drawHLine(0, 17, 128);
  // 12px 中文字库，128 宽约放 10 个汉字
  u8g2.setFont(u8g2_font_wqy12_t_gb2312);
  u8g2.drawUTF8(0, 34, fitUtf8(name, 10).c_str());
  u8g2.setFont(u8g2_font_6x10_tf);
  u8g2.drawStr(0, 50, fit(status).c_str());
  u8g2.sendBuffer();
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
  prefs.end();
  if (serverBase.isEmpty()) serverBase = DEFAULT_SERVER_BASE;

  Serial.printf("credssid=%s pass=%s\n", ssid.c_str(), pass.isEmpty() ? "(empty)" : "***");
  Serial.printf("serverBase=%s\n", serverBase.c_str());
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
  body += ",\"ip\":\"" + WiFi.localIP().toString() + "\"}";
  srvOk = postJson(isRegister ? "/api/device/register" : "/api/device/heartbeat", body);
}

/* ---------------- HA 控制 ---------------- */

// 从服务端拉取已放行的控制项（button|name|entityId|action|id），缓存按钮名称供屏幕提示用
void fetchActions() {
  if (WiFi.status() != WL_CONNECTED) return;
  if (deviceId.isEmpty()) buildDeviceId();
  for (int i = 0; i < 8; i++) btnLabel[i] = "";
  String text;
  if (!getText("/api/device/esp/actions?format=text&deviceId=" + deviceId, text)) return;
  int start = 0;
  while (start < (int)text.length()) {
    int end = text.indexOf('\n', start);
    if (end < 0) end = text.length();
    String line = text.substring(start, end);
    line.trim();
    start = end + 1;
    int p1 = line.indexOf('|');
    if (p1 < 0) continue;
    int p2 = line.indexOf('|', p1 + 1);
    if (p2 < 0) continue;
    int btn = line.substring(0, p1).toInt();
    if (btn >= 1 && btn < 8) btnLabel[btn] = line.substring(p1 + 1, p2);
  }
  Serial.printf("[esp] 已放行控制项 %u 个\n", (unsigned)text.length());
}

// 让服务端执行某个按钮 / 控制项对应的 HA 动作
bool pressAction(const String &body) {
  return postJson("/api/device/esp/press", body);
}

/* ---------------- 固件升级（OTA） ---------------- */

// 查服务端发布版本：version|size|sha256|notes，与 APP_VER 不同即可升级
void checkFirmware() {
  if (WiFi.status() != WL_CONNECTED) return;
  String text;
  if (!getText("/api/device/firmware/latest?format=text", text)) return;
  text.trim();
  fwAvailable = false;
  fwNotes = "";
  fwSize = 0;
  if (text.length() == 0) return;
  int p1 = text.indexOf('|');
  if (p1 <= 0) return;
  int p2 = text.indexOf('|', p1 + 1);
  int p3 = p2 < 0 ? -1 : text.indexOf('|', p2 + 1);
  fwVersion = text.substring(0, p1);
  if (p2 > 0) fwSize = text.substring(p1 + 1, p2).toInt();
  if (p3 >= 0) fwNotes = text.substring(p3 + 1);
  fwAvailable = fwVersion.length() > 0 && fwVersion != String(APP_VER);
  if (fwAvailable) Serial.printf("[ota] 可升级: %s -> %s (%uKB)\n", APP_VER, fwVersion.c_str(), (unsigned)(fwSize / 1024));
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
  oledShow("Update failed", String(httpUpdate.getLastError()), err.substring(0, 21));
  toastUntil = millis() + 5000;
}

void onButtonPress(int button) {
  if (deviceId.isEmpty()) buildDeviceId();
  Serial.printf("[btn] %d pressed\n", button);
  oledToast(String("Button ") + button, btnLabel[button].length() ? btnLabel[button] : "sending...");
  String body = "{\"deviceId\":\"" + deviceId + "\",\"button\":" + String(button) + "}";
  bool ok = pressAction(body);
  oledToast(String("Button ") + button, btnLabel[button].length() ? btnLabel[button] : "-",
            ok ? "sent ok" : "failed, see serial");
}

// 轮询物理按键：内部上拉，对地短接为按下；60ms 去抖
void pollButtons() {
  uint32_t now = millis();
  for (int i = 0; i < BTN_COUNT; i++) {
    bool down = digitalRead(BTN_PINS[i]) == LOW;
    if (down == buttons[i].down) continue;
    if (now - buttons[i].changedAt < 60) continue;
    buttons[i].down = down;
    buttons[i].changedAt = now;
    if (down) onButtonPress(i + 1);
  }
}

void drawMain() {
  if (fwAvailable) {
    // 有更新时优先提示，引导用户打开本机设置页升级
    oledShow("Update ready", String("cur ") + APP_VER, String("new ") + fwVersion, "open web page");
    return;
  }
  oledShow("WiFi connected", ssid, WiFi.localIP().toString(),
           (srvOk ? "srv ok " : "srv fail ") + String(WiFi.RSSI()) + "dBm");
}

void showConnected() {
  String ip = WiFi.localIP().toString();
  Serial.printf("WiFi connected: ssid=%s ip=%s rssi=%d\n", WiFi.SSID().c_str(), ip.c_str(), WiFi.RSSI());
  Serial.printf("web config: http://%s/\n", ip.c_str());
  gApMode = false;
  if (!serverStarted) setupServer();  // 局域网内也能打开配置页

  buildDeviceId();
  reportToServer(true);
  fetchActions();
  checkFirmware();
  lastReport = millis();

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
    h += "<div class='empty'>服务端没有放行任何控制项。请到 pscreen_server 管理页「设备状态 → ESP 控制」里添加并勾选「放行」。</div>";
  } else {
    h += "<table><tr><th>按钮</th><th>名称 / 实体</th><th>动作</th><th></th></tr>";
    int start = 0;
    while (start < (int)listText.length()) {
      int end = listText.indexOf('\n', start);
      if (end < 0) end = listText.length();
      String line = listText.substring(start, end);
      line.trim();
      start = end + 1;
      if (line.length() == 0) continue;
      int p1 = line.indexOf('|');
      int p2 = p1 < 0 ? -1 : line.indexOf('|', p1 + 1);
      int p3 = p2 < 0 ? -1 : line.indexOf('|', p2 + 1);
      int p4 = p3 < 0 ? -1 : line.indexOf('|', p3 + 1);
      if (p4 < 0) continue;
      String btn = line.substring(0, p1);
      String name = line.substring(p1 + 1, p2);
      String entity = line.substring(p2 + 1, p3);
      String act = line.substring(p3 + 1, p4);
      String id = line.substring(p4 + 1);
      String actLabel = act == "toggle" ? "切换" : act == "turn_on" ? "开" : act == "turn_off" ? "关" : "执行";
      h += String("<tr><td>") + (btn == "0" ? String("-") : btn) + "</td>";
      h += String("<td>") + name + "<div class='mono'>" + entity + "</div></td>";
      h += String("<td>") + actLabel + "</td>";
      h += "<td><form method='POST' action='/settings/press' style='margin:0'>";
      if (btn == "0") {
        h += String("<input type='hidden' name='actionId' value='") + id + "'>";
      } else {
        h += String("<input type='hidden' name='button' value='") + btn + "'>";
      }
      h += "<button class='mini' type='submit'>测试</button></form></td></tr>";
    }
    h += "</table>";
  }

  h += "<h3>物理按键</h3>";
  h += "<div class='tip'>GPIO4 = 按钮1，GPIO5 = 按钮2，GPIO6 = 按钮3；用杜邦线把对应 GPIO 与 GND 短接即触发。<br>";
  h += "按键动作由服务端白名单决定：在 pscreen_server 管理页给每项选「按钮1/2/3」并勾选「放行」，设备才会执行。</div>";

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

  // 网页「测试」按钮：直接请服务端执行对应动作（同样受白名单约束）
  server.on("/settings/press", HTTP_POST, []() {
    if (authBlocked()) return;
    if (deviceId.isEmpty()) buildDeviceId();
    String actionId = server.arg("actionId");
    String button = server.arg("button");
    String body = "{\"deviceId\":\"" + deviceId + "\"";
    if (actionId.length()) body += ",\"actionId\":\"" + actionId + "\"";
    else body += ",\"button\":" + button;
    body += "}";
    bool ok = WiFi.status() == WL_CONNECTED && pressAction(body);
    String msg = ok ? "已执行" : "执行失败：设备未联网，或服务端未放行 / HA 未配置（详见设备串口日志）";
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

  // 按键：内部上拉，对地短接即按下（杜邦线即可测试）
  for (int i = 0; i < BTN_COUNT; i++) {
    pinMode(BTN_PINS[i], INPUT_PULLUP);
    buttons[i].down = false;
    buttons[i].changedAt = 0;
  }

  initOled();
  oledShow("Booting", "OLED test ok");
  delay(400);

  loadCreds();
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

  if (millis() - lastReport > REPORT_MS) {
    lastReport = millis();
    reportToServer(false);
    fetchActions();  // 白名单可能在后台改过
    checkFirmware(); // 服务端可能发布了新固件
  }

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
