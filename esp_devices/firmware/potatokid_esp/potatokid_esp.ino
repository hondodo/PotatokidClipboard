/**
 * ESP32-S3 / ESP32-C6 + 1.3" SH1106 OLED (I2C) + WiFi 配网 + HA 按键
 * S3 接线: VCC->3V3, GND->GND, SCL->GPIO9, SDA->GPIO8
 * C6 接线: VCC->3V3, GND->GND, SCL->GPIO19, SDA->GPIO20（仅用外排针）
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
#include <esp_now.h>
#include <esp_wifi.h>
#include <esp_sleep.h>
#include <freertos/FreeRTOS.h>
#include <freertos/task.h>
#include <freertos/semphr.h>
#include "secrets.h"  // WiFi 默认账号 / 网页口令（本地文件，不入库）

// 芯片分流：S3 与 C6 共用同一份固件逻辑，仅引脚、设备 ID、型号和可用 GPIO 不同。
// S3 保持原接线与原 NVS 配置不变；C6 只用已焊的外排针（内部 12/13/21/22/23 不接）。
#if defined(CONFIG_IDF_TARGET_ESP32C6)
  #define CHIP_TAG       "esp32c6"
  #define CHIP_MODEL     "ESP32-C6 1.3 OLED"
  #define CHIP_NAME      "ESP32-C6 小屏"
  static const int PIN_SDA = 20;
  static const int PIN_SCL = 19;
  static const int DEFAULT_BTN_PINS[] = {0, 1, 2};
#else
  #define CHIP_TAG       "esp32s3"
  #define CHIP_MODEL     "ESP32-S3 1.3 OLED"
  #define CHIP_NAME      "ESP32-S3 小屏"
  static const int PIN_SDA = 8;
  static const int PIN_SCL = 9;
  static const int DEFAULT_BTN_PINS[] = {4, 5, 6};
#endif

// 物理按键槽位：最多 8 个，槽位号与后台页面里的「槽位」一一对应。
// GPIO 映射保存在 NVS（btns 命名空间），设备设置页可增删槽位、改引脚。
// 默认槽位 1/2/3 = S3 的 GPIO4/5/6、C6 的 GPIO0/1/2；-1 表示该槽位未启用。
static const int MAX_BTN = 8;

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
static const char *DEVICE_NAME         = CHIP_NAME;
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
// oled-2.8：翻页本地化——全部页面缓存进 RAM，翻页键不再发 HTTP，按下即出内容；
//           空闲时后台预取未缓存的页，进入某页后再异步刷新最新状态。
// oled-2.9：即时刷新只发一个请求（不再顺带心跳/查版本），穿透网络下状态更新更快；
//           心跳 60 秒、OTA 检查 5 分钟各自独立计时。
// oled-3.0：人体感应熄屏——OUT 接 GPIO（本机设置页配置），有人时亮屏，
//           人离开后按后台下发的秒数熄屏；屏灭期间只保留心跳，不拉页面。
// oled-3.1：按键/感应引脚加白名单（26~37 = Flash/PSRAM），NVS 里的旧非法值
//           启动时自动忽略；修复误填 GPIO35 导致开机卡在 Booting 的问题。
// oled-3.2：人体感应状态上报——有人/无人跳变时立即发一次心跳（不等 60 秒），
//           后台显示「有人 / 无人 + 最近进入/离开时间」。
// oled-3.3：修「亮屏后正文变空白、只剩顶栏页码/IP」——NetSnapshot 标量补默认值，
//           感应上报不再顺延 60 秒心跳计时（否则定时拉页面永远不触发）。
// oled-4.0：系统状态变量支持——每页状态栏配置（BAR 行，逐页显示/隐藏 + 元素勾选、
//           隐藏时内容上移重排）、状态栏时间（TIME 行）、图片点阵（IMG 行，128×64
//           1-bit 服务端下发，不烧固件）。{sys.*} 本机变量在绘制时替换。老配置/老固件兼容。
// oled-5.0：同固件适配 ESP32-S3 与 ESP32-C6（引脚/设备 ID/可用 GPIO 按芯片分流），
//           OTA 查询与下载带 target 参数，服务端按芯片分别发布。
// oled-5.1：ESP-NOW 主从中继——从机的注册/心跳/页面/按键经所属主机转发，
//           请求与回包分片传输；OTA 仍由从机直连下载。角色可在设置页切换。
// oled-5.2：从机电池休眠——C6 从机空闲后关屏关 WiFi 深睡，按键低电平唤醒，
//           唤醒后经主机重新注册；新增电池分压检测与电压上报。
// oled-5.3：后台访问期间自动推迟休眠；C6 的 GPIO15 允许接人体感应（不可作按键）。
// oled-5.4：从机电池唤醒优化——
//           1) 唤醒来源可区分（PIR / 查看键 / 普通键 / 冷启动）；
//           2) PIR 或「查看键」唤醒只显示缓存页 5 秒，不开 WiFi，超时回睡；
//              期间按普通键则升级为完整唤醒（联网 + 加载实时页）；
//           3) 当前页持久化到 NVS，深睡清空 RAM 后唤醒仍能立刻显示；
//           4) 后台可配置「查看键」槽位：按下仅亮屏看缓存，不触发动作、不主动联网；
//           5) 自动更新默认开启（两个芯片轨道）。
// oled-5.5：从机唤醒分三档，去掉与普通键重复的「查看键」——
//           1) 联网键（后台可选槽位）：按下连 AP、开后台、推迟休眠 5 分钟，不触发动作；
//           2) 普通动作键：只开射频（不连 AP、不拿 IP），经 ESP-NOW 让主机代发，
//              动作完成约 2.5 秒后回睡，不再空等 60 秒；
//              翻页/回首页这类本地动作连射频都不开；
//           3) PIR：亮屏看缓存 5 秒，不开射频；
//           4) 定时唤醒（默认 6 小时）只开射频问主机最新版本，有新版才连 AP 下载。
//           主机信道随 NVS 持久化：从机不关联 AP 时用它锁定 ESP-NOW 信道。
// oled-5.7：未配置联网键时，按键唤醒退回「连 AP」的旧行为，避免设备被锁在后台之外。
// oled-5.8：砍掉开机固定的 0.7 秒空等（Serial 后 300ms + 开机画面 400ms）；
//           只有冷启动才画开机图，动作/定时唤醒直接干活；睡前面板一律关闭。
// oled-5.9：定时唤醒查 OTA 时完全不初始化 OLED，屏幕保持熄灭、不闪屏；
//           只有真的发现新版本并开始下载时才点亮面板显示进度。
// oled-6.0：OTA 定时查询间隔后台可配（NVS cfg.otachk，默认 6 小时）；
//           新增「远程更新」：后台 admin 页可下发标记，设备随心跳取到后强制升级
//           （即使本机把自动更新关了）。标记按时间戳去重，重启不重复触发。
// oled-6.1：定时唤醒改为「一次心跳」——上报状态（电量/唤醒原因/间隔）同时取回
//           最新版本与远程更新标记，省掉单独的版本查询往返；
//           唤醒间隔后台可选 5/10/30 分钟、1/2/3/6 小时；从机即使关了自动更新也保留
//           定时唤醒（否则永远收不到后台的远程更新）；
//           后台按「最后上报 + 唤醒间隔」显示休眠中与预计唤醒时间。
// oled-6.2：新增远程配置下发——按键引脚/角色/主机 MAC/休眠/自动更新/唤醒间隔/
//           PIR/联网键/电池分压都存在服务端，带版本号随心跳下发；
//           设备发现版本变化就拉取纯文本配置写 NVS 并重启应用。
static const char *APP_VER             = "oled-7.1";
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
String btnAction[MAX_BTN + 1];  // 服务端动作名：next_page/prev_page 等系统动作在固件本地执行
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
// 注意：所有标量必须有默认值。任务里是 `NetSnapshot snap;` 局部变量，
// 默认初始化不会清零标量——而 String 成员每轮都会构造为空串。
// 少了默认值就会出现「state 沿用上一轮的真值、文本却是空串」的假快照，
// 发布出去会把屏幕正文刷成空白（只剩顶栏页码/IP）。oled-3.3 修的就是这个。
// 每页状态栏配置（BAR 行，位掩码）：
//   bit0 enabled / bit1 showPage / bit2 showTime / bit3 showWifiIcon / bit4 showRssi / bit5 showIp
// 默认 = enabled+page+time+wifiIcon（0b0001111 = 15），与服务端 normalizeEspStatusBar 默认一致。
#define SB_ENABLED   (1 << 0)
#define SB_PAGE      (1 << 1)
#define SB_TIME      (1 << 2)
#define SB_WIFI_ICON (1 << 3)
#define SB_RSSI      (1 << 4)
#define SB_IP        (1 << 5)
#define SB_DEFAULT   (SB_ENABLED | SB_PAGE | SB_TIME | SB_WIFI_ICON)

struct NetSnapshot {
  bool valid = false;         // 本次拿到了有效的页面/按键/显示数据
  bool fwKnown = false;       // 本次成功查询了服务端固件版本
  bool hasDisplay = false;    // 收到 DISPLAY 行（主状态可能为空 = 正常留白）
  int pageCount = 1, pageIndex = 1, currentPage = 1;
  int requestedPage = 0;      // 本次请求的页码（用于区分「预取」与「当前页刷新」）
  bool pageLoop = true;
  int idleSeconds = 0;
  int screenOnSec = 0;        // 人离开后熄屏秒数（0 = 常亮），来自 SCREEN 行
  uint8_t statusBar = 15;     // 每页状态栏位掩码（BAR 行）；默认 15
  String time = "";           // 状态栏时间 HH:MM（TIME 行，跨页共享）
  bool hasImage = false;      // 收到 IMG 行且解码成功
  uint8_t imageBits[1024];    // 128×64 1-bit 点阵（行优先，每行 16 字节，MSB 在前）
  bool imageInvert = false;   // 反色（暂保留，服务端可下发）
  String title, main, sub, keys;
  // v4.2：服务端下发的 ROWS| 四行内容（已按显示开关合并好），老服务端不下发则留空。
  String rows[4];
  int rowCount = 0;
  String label[MAX_BTN + 1];
  String name[MAX_BTN + 1];
  String action[MAX_BTN + 1];
  bool fwAvailable = false;
  String fwVersion, fwNotes;
  uint32_t fwSize = 0;
};
SemaphoreHandle_t netMux = nullptr;
NetSnapshot netPending;
volatile bool netEnabled = false;   // 注册成功后才开始周期拉取
volatile uint32_t netRefreshAt = 0; // 到点后立即拉一次（0 = 无排队；按键执行后延迟刷新）
volatile int  netPage = 1;          // 后台任务要拉的页码
volatile bool netBusy = false;      // 任务正在请求中（预取别重复排队同一页）

// ---- 屏幕四行内容（服务端按设备类型字典下发，固件只管显示）----
// 顶栏固定：页码 + 真实 IP（WiFi.localIP，拿到前留空）+ WiFi 信号格。
String scrTitle = "", scrMain = "", scrSub = "", scrKeys = "";
String scrRows[4];                      // v4.2 ROWS 行：服务端已排好序的四行内容
int  scrRowCount = 0;
bool haveDisplay = false;               // 收到过 DISPLAY 行（空主状态也要正常绘制）
int  pageCount = 1, pageIndex = 1;      // 页码来自服务端（若下发）；>=1
uint8_t curStatusBar = 15;              // 当前页状态栏位掩码（BAR 行）
bool curHasImage = false;               // 当前页是否下发图片点阵
uint8_t curImageBits[1024];             // 当前页 128×64 1-bit 点阵
bool curImageInvert = false;
String barTime = "";                    // 状态栏时间（服务端 TIME 行下发 HH:MM，设备本地走秒）
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

// ---- 页面缓存（本地翻页）----
// 翻页原本要「POST 按键 → 再 GET 新页」两次网络往返，等 1~3 秒。
// 页面内容只有四行文本 + 按键表，很小；把所有页缓存在 RAM 里，
// 按下翻页键直接本地绘制（零等待），再由后台拉一次最新状态做微调。
static const int PAGE_CACHE_MAX = 12;
struct PageCache {
  bool valid;
  int pageCount;
  bool pageLoop;
  uint8_t statusBar;          // 每页状态栏位掩码
  bool hasImage;
  uint8_t imageBits[1024];    // 128×64 1-bit 点阵
  String title, main, sub, keys;
  // v4.2：服务端下发的 ROWS| 四行内容（已按显示开关合并好），老服务端不下发则留空。
  String rows[4];
  int rowCount = 0;
  String label[MAX_BTN + 1];
  String name[MAX_BTN + 1];
  String action[MAX_BTN + 1];
};
PageCache pageCache[PAGE_CACHE_MAX];

// oled-5.4：深睡会清空 RAM，把「当前正在看的这一页」持久化到 NVS，
// PIR / 查看键唤醒时立刻显示缓存，不必等联网（也根本不开 WiFi）。
// 只存当前页，不存全部缓存页；字符串截断到 PERSIST_STR，足够屏幕显示。
#define PERSIST_MAGIC   0x504B   // 'PK'
#define PERSIST_VER     1
#define PERSIST_STR     48
struct PersistedPage {
  uint16_t magic;
  uint16_t version;
  int currentPage;
  int pageCount;
  int pageIndex;
  uint8_t statusBar;
  uint8_t hasImage;
  uint8_t imageBits[1024];
  char title[PERSIST_STR];
  char main[PERSIST_STR];
  char sub[PERSIST_STR];
  char keys[PERSIST_STR];
  char rows[4][PERSIST_STR];
  int rowCount;
  char label[MAX_BTN + 1][PERSIST_STR];
  char name[MAX_BTN + 1][PERSIST_STR];
  char action[MAX_BTN + 1][PERSIST_STR];
};
static void copyPersistStr(char *dst, const String &src) {
  int n = src.length();
  if (n > PERSIST_STR - 1) n = PERSIST_STR - 1;
  if (n > 0) memcpy(dst, src.c_str(), n);
  dst[n] = 0;
}

// 单色屏：实物有蓝光/白光/黄光三种。灰阶不存在，只有亮/灭两级；
// 层次靠字号 + 留白 + 反白块。这里用 U8G2 的像素翻转实现「反白」强调。
// 0=蓝 1=白 2=黄 由 NVS 保存，蓝屏/白屏/黄屏硬件本身发光色不同，固件绘制一致。
int screenColor = 0;

// ---- 人体感应熄屏 ----
// 模块 VCC 接 3V3、GND 共地、OUT 接下面这个 GPIO（NVS cfg.pir，-1 = 未接）。
// 人来时 OUT 为高电平；固件每次读到高电平都把「最后有人在」的时间刷新，
// 因此人持续在就一直亮屏，直到人走后才开始按 screenOnSec 倒计时。
int pirPin = -1;
int screenOnSec = 0;          // 服务端 SCREEN 行下发：人离开后多少秒熄屏（0 = 常亮）
volatile bool screenOff = false;
// OTA 升级期间强制常亮：升级在没人盯着时也会触发，此时屏幕已被 PIR 熄屏，
// 所有升级提示都会被 drawScreen 首行的 screenOff 拦截。升级全程置 true，
// 堵住 sleepScreen / loop 的超时熄屏，结束后复位恢复正常省电逻辑。
volatile bool otaInProgress = false;
uint32_t lastPresenceAt = 0;
// 人体感应状态上报：只在 0/1 跳变时发一次心跳，后台不必等 60 秒轮询。
bool pirPresent = false;
volatile bool pirReportPending = false;

// OTA：服务端发布的版本与本地 APP_VER 不同即提示可升级
bool fwAvailable = false;
String fwVersion;
String fwNotes;
uint32_t fwSize = 0;

// 自动更新（NVS cfg.auto）：检测到新版本后自行安装，不用每次进后台点按钮。
// 默认开启：新设备 / 从未保存过该开关的设备上电即自动更新；用户可在设置页关掉。
bool autoUpdate = true;
uint32_t autoOtaAt = 0;       // 延迟执行时间点（0 = 未排队）
String otaTriedVer;           // 上次尝试的版本，失败后按 OTA_RETRY_MS 冷却重试
uint32_t otaTriedAt = 0;
static const uint32_t OTA_RETRY_MS = 30UL * 60UL * 1000UL;
// 最近一次上报（注册/心跳）的响应体：用于解析后台下发的远程更新标记。
String lastPostResp;

// 主从角色（NVS cfg.role / cfg.masterMac）：
// - master：常供电、保持在线，既作为普通 ESP 设备，也给下属从机做中继；
// - slave ：经所属主机访问服务端，可配合电池休眠（中继链路在后续版本接入）。
// 芯片型号决定 OTA 轨道，角色只决定通信方式，两者互不影响。
String deviceRole = "master";
String masterMac = "";        // 从机保存的所属主机 MAC（AA:BB:CC:DD:EE:FF）

// 电池休眠（仅从机、仅 C6 生效）：
// - sleepSeconds = 无操作多久进入深度睡眠，0 = 不休眠；
// - 唤醒源为已配置按键（低电平），唤醒后重新联网、经主机注册并拉取页面；
// - batPin 接电池分压点（C6 只有 GPIO0~6 是 ADC1），batDiv 为分压比。
int sleepSeconds = 0;
int batPin = -1;
int batDiv = 2;
uint32_t lastActivityAt = 0;
uint32_t sleepHoldUntil = 0;   // 访问后台后临时推迟休眠，避免编辑途中设备睡过去

// oled-5.5：唤醒分档
//  联网键（netSlot）：连 AP、开后台、推迟休眠 5 分钟，不执行动作；
//  普通动作键：只开射频（不连 AP），经主机中继执行动作，动作后约 2.5 秒回睡；
//  PIR：亮屏看缓存 5 秒，不开射频；
//  定时唤醒：只开射频问主机最新版本，有新版才连 AP 下载。
int netSlot = 0;               // 联网键槽位：0=不启用；1..MAX_BTN=该槽位用于进后台
#define WAKE_COLD     0        // 上电 / 复位 / 未知来源 → 连 AP 走完整流程
#define WAKE_PIR      1        // 人体感应唤醒 → 只看缓存
#define WAKE_BUTTON   2        // 按键唤醒（联网键或动作键，用 wakeSlotHit 区分）
#define WAKE_TIMER    3        // RTC 定时唤醒 → 只开射频查 OTA
uint8_t wakeReason = WAKE_COLD;
// PIR 唤醒累计次数：放在 RTC 内存里，深睡不清零。
// 用于诊断「人体感应到底有没有把芯片唤醒」——PIR 唤醒不联网，
// 只能等下一次心跳把计数带上去，后台就能看出有没有增加。
RTC_DATA_ATTR uint32_t pirWakeCount = 0;
// 深睡唤醒注册的返回值（上一次入睡时记录，重启后上报）：
// 0=OK，负值=错误码。-2 表示引脚超出可唤醒范围。
RTC_DATA_ATTR int8_t rtcSlpErrBtn = 0;
RTC_DATA_ATTR int8_t rtcSlpErrPir = 0;
// PIR 实际走哪条唤醒通道：1=EXT1（RTC IO），2=GPIO wake。便于判断哪条生效。
RTC_DATA_ATTR int8_t rtcPirWakeMode = 0;
// 唤醒原始诊断（RTC 内存，重启后上报）：复位原因 / 唤醒原因 / 两条唤醒通道的
// 原始引脚位掩码。用于判断「根本没醒」还是「醒了但掩码对不上引脚」。
RTC_DATA_ATTR int8_t  rtcResetReason = 0;
RTC_DATA_ATTR int8_t  rtcWakeCause   = 0;
RTC_DATA_ATTR uint32_t rtcGpioMask   = 0;
RTC_DATA_ATTR uint32_t rtcExt1Mask   = 0;
int wakeSlotHit = 0;           // 唤醒引脚对应的槽位（0 = 认不出）
bool peekMode = false;
uint32_t peekUntil = 0;
static const uint32_t PEEK_MS = 5000;      // PIR 唤醒后显示缓存的时长
volatile int peekActionSlot = 0;            // PIR peek 期间按下动作键 → 升级执行

uint8_t relayCh = 0;           // 主机所在 WiFi 信道（NVS 持久化）
bool radioOnly = false;        // 本次唤醒不关联 AP，仅开射频
uint32_t actionSleepAt = 0;    // 动作完成后到点回睡
static const uint32_t ACTION_SLEEP_MS = 2500;   // 动作后停留多久再睡（让人看清结果）
// 定时唤醒查 OTA 的间隔（NVS cfg.otachk，秒）。后台可配，默认 6 小时。
// 若改短（如 5 分钟），OTA 轮询会变成整机最大耗电项，设置页会给出提示。
uint32_t otaCheckSec = 6UL * 3600UL;
static const uint32_t OTA_CHECK_MIN_SEC = 300;      // 最短 5 分钟
static const uint32_t OTA_CHECK_MAX_SEC = 21600;    // 最长 6 小时
// 远程更新：后台下发的时间戳（毫秒）。比本机记录的新就强制升级一次。
// 把 "oled-6.5" 解析成可比较的数字（主*100+次）。
// 不能用字符串比较：那样会把服务端上的旧版本（如 6.3）当成「有新版」而自动降级。
static long versionNumber(const String &v) {
  int dash = v.lastIndexOf('-');
  String tail = dash >= 0 ? v.substring(dash + 1) : v;
  int dot = tail.indexOf('.');
  long major = dot > 0 ? tail.substring(0, dot).toInt() : tail.toInt();
  long minor = dot > 0 ? tail.substring(dot + 1).toInt() : 0;
  if (major < 0) major = 0;
  if (minor < 0) minor = 0;
  return major * 100 + minor;
}

static bool isNewerVersion(const String &remote, const String &local) {
  if (remote.length() == 0) return false;
  return versionNumber(remote) > versionNumber(local);
}

uint64_t fwPushSeen = 0;      // 已处理过的 fwPush 时间戳（NVS 持久化）
bool fwPushForced = false;    // 本次启动内是否收到过强制更新标记
uint32_t cfgVerApplied = 0;   // 已应用的远程配置版本（NVS cfg.cfgver）

/* ---------------- OLED ---------------- */

/**
 * 本板可用作按键 / 人体感应的 GPIO 白名单。
 *
 * ESP32-S3（16MB Flash + 8MB OPI PSRAM）上这些脚被硬件占用，配成输入会直接死机：
 * - 26~32：Flash；
 * - 33~37：OPI PSRAM（本板 PSRAM=opi，最容易误填的就是这一段）；
 * - 19/20：USB；0/3/45/46：启动脚；8/9：OLED I2C。
 * ESP32-C6-SuperMini 只焊接了外排针（0~18），8/9/15 为板载外设，12/13 为 USB。
 * 存进 NVS 的旧值也要过这一层，避免升级后把设备带进重启循环。
 */
static bool pinUsable(int pin) {
  if (pin < 0 || pin > 48) return false;
#if defined(CONFIG_IDF_TARGET_ESP32C6)
  // C6-SuperMini：只用已焊的外排针（0~18）。内部 21/22/23 未焊，12/13 为板载 USB，
  // 4/5/8/9/15 为启动配置脚（开机被按下会改变启动模式），均不可配为按键/感应。
  if (pin > 18) return false;
  if (pin == 4 || pin == 5 || pin == 8 || pin == 9 || pin == 12 || pin == 13 || pin == 15) return false;
  if (pin == PIN_SDA || pin == PIN_SCL) return false;
  return true;
#else
  if (pin >= 26 && pin <= 37) return false;
  if (pin == 0 || pin == 3 || pin == 19 || pin == 20 || pin == 45 || pin == 46) return false;
  if (pin == PIN_SDA || pin == PIN_SCL) return false;
  return true;
#endif
}

// 人体感应可用的引脚：按键与 I2C 之外，再避开默认按键/启动脚。
static bool pinUsableForPir(int pin) {
#if defined(CONFIG_IDF_TARGET_ESP32C6)
  // GPIO15 是板载 LED 引脚，也参与启动配置：只允许接人体感应这类纯输入，
  // 不能配成按键；PIR 需为推挽输出，否则读数可能不稳。休眠时它不参与唤醒。
  if (pin == 15) return true;
  if (!pinUsable(pin)) return false;
  return !(pin == 0 || pin == 1 || pin == 2);
#else
  // 4~13 已接本机按键与 OLED I2C（8/9 上面已挡），人体感应脚不允许落在这段，
  // 避免和按键抢线；可用的是 14~18 / 21 / 38~42 / 47 / 48。
  return pinUsable(pin) && !(pin >= 4 && pin <= 13);
#endif
}

// 电池分压检测脚：C6 仅 GPIO0~6 属于 ADC1，且不能和按键/感应/I2C 抢线。
bool pinUsableForBat(int pin) {
#if defined(CONFIG_IDF_TARGET_ESP32C6)
  if (pin < 0 || pin > 6) return false;
  if (pin == PIN_SDA || pin == PIN_SCL) return false;
  if (pin == pirPin) return false;
  for (int i = 0; i < btnCount; i++) if (btnPins[i] == pin) return false;
  return true;
#else
  (void)pin;
  return false;   // S3 当前不做电池休眠，不提供分压检测
#endif
}

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

// 顶部状态栏（v0.5）：元素按本页 BAR 位掩码逐项绘制。
// enabled=0 时整条不画（内容区上移重排，见 drawScreen）。
// 省电/省宽：只画勾选的元素；IP 仅 WiFi 已连接显示，绝不写死示例值。
// 返回本页状态栏是否实际绘制，供 drawScreen 决定内容区起始 y。
bool drawStatusBar() {
  uint8_t sb = curStatusBar;
  if (!(sb & SB_ENABLED)) return false;
  u8g2.setFont(u8g2_font_6x10_tf);
  u8g2.setClipWindow(0, 0, 128, 12);
  int cursor = 2;
  // 页码
  if (sb & SB_PAGE) {
    char pg[12];
    snprintf(pg, sizeof(pg), "%d/%d", pageIndex, pageCount);
    u8g2.drawStr(cursor, 9, pg);
    cursor += strlen(pg) * 6 + 4;
  }
  // 时间（服务端 TIME 行下发 HH:MM；未下发时留空，不显示假时间）
  if ((sb & SB_TIME) && barTime.length()) {
    u8g2.drawStr(cursor, 9, barTime.c_str());
    cursor += barTime.length() * 6 + 4;
  }
  // 真实 station IP（未连上则为空）
  if ((sb & SB_IP) && WiFi.status() == WL_CONNECTED) {
    String ip = WiFi.localIP().toString();
    u8g2.drawStr(cursor, 9, ip.c_str());
    cursor += ip.length() * 6 + 4;
  }
  // RSSI 数值
  if ((sb & SB_RSSI) && WiFi.status() == WL_CONNECTED) {
    char rs[10];
    snprintf(rs, sizeof(rs), "%ddBm", (int)WiFi.RSSI());
    u8g2.drawStr(cursor, 9, rs);
    cursor += strlen(rs) * 6 + 4;
  }
  // WiFi 信号格（3 条递增竖条），靠右画，不与左侧文字重叠时显示
  if (sb & SB_WIFI_ICON) {
    int sx = 114;
    u8g2.drawBox(sx, 6, 2, 3);
    u8g2.drawBox(sx + 4, 4, 2, 5);
    u8g2.drawBox(sx + 8, 2, 2, 7);
  }
  u8g2.setMaxClipWindow();
  return true;
}

// 把正文里的本机 sys 变量 token 替换成实时值（服务端原样保留这些 token 下发）。
// 只在固件侧能拿到：联网状态/RSSI/人体/IP/页码。缺值替换为空串。
// 用字符串常量替换，避免临时 String::c_str() 悬垂指针。
String resolveLocalSys(String s) {
  if (s.indexOf("{sys.") < 0) return s;
  bool online = WiFi.status() == WL_CONNECTED;
  const int rssi = online ? WiFi.RSSI() : 0;
  String wifiBars = !online ? "" : (rssi > -60 ? "▇▇" : (rssi > -75 ? "▃▅" : "▁▃"));
  s.replace("{sys.online}",   online ? "已联网" : "未联网");
  s.replace("{sys.wifi}",     wifiBars.c_str());
  s.replace("{sys.rssi}",     online ? (String(rssi) + "dBm").c_str() : "");
  s.replace("{sys.present}",  pirPin >= 0 ? (pirPresent ? "有人" : "无人") : "");
  s.replace("{sys.occupied}", pirPin >= 0 ? (pirPresent ? "占用中" : "空闲") : "");
  s.replace("{sys.ip}",       online ? WiFi.localIP().toString().c_str() : "");
  s.replace("{sys.page}",     String(pageIndex).c_str());
  s.replace("{sys.total}",    String(pageCount).c_str());
  s.replace("{sys.pageOf}",   (String(pageIndex) + "/" + String(pageCount)).c_str());
  return s;
}

// 绘制 128×64 1-bit 点阵（行优先，每行 16 字节，MSB 在前）。
// 图片作为整屏内容：在状态栏下方的内容区居中绘制，超出部分裁剪。
void drawImageBits(const uint8_t *bits, bool invert, int top, int contentH) {
  if (!bits) return;
  // 点阵是 128×64；内容区高度可能不足 64（有状态栏时约 52px），按比例裁掉底部。
  int rows = contentH < 64 ? contentH : 64;
  for (int y = 0; y < rows; y++) {
    for (int xb = 0; xb < 16; xb++) {
      uint8_t byte = bits[y * 16 + xb];
      if (invert) byte = ~byte;
      for (int bit = 0; bit < 8; bit++) {
        if (byte & (0x80 >> bit)) u8g2.drawPixel(xb * 8 + bit, top + y);
      }
    }
  }
}

// 主屏（v4.2）：顶栏 + 最多四行内容，四行统一 wqy12 字号、等距排列。
// - 服务端下发 ROWS| 时按「服务端合并好的行」画（隐藏标题/按键后内容自动上移）；
// - 老服务端只有 DISPLAY| 时，把 title/main/sub/keys 当四行画，兼容旧数据。
// - 异常态（按键反馈）反白第 2 行——与旧版观感一致。
// useArgs=true 时强制用传入的四行（系统提示：升级/Booting/WiFi lost），
// 不复用页面缓存 ROWS——否则正常页的 ROWS 会把 "Updating/进度%" 盖掉（v4.3 修）。
void drawScreen(const String &title, const String &main, const String &sub, const String &keys,
                bool abnormal, bool useArgs = false) {
  if (!oledOk || screenOff) return;
  u8g2.clearBuffer();
  bool hasBar = drawStatusBar();

  // 内容区：状态栏显示时从 y=12 起、每行 13px；隐藏时从 y=2 起、每行 15px。
  // 与 admin 预览 drawEspPreview 同一套坐标，所见即所得。
  int rowTop  = hasBar ? 12 : 2;
  int rowStep = hasBar ? 13 : 15;

  // 图片：作为正文背景绘制在状态栏下方（有图时正文文字仍可叠加）。
  if (curHasImage) {
    int imgTop = hasBar ? 12 : 0;
    drawImageBits(curImageBits, curImageInvert, imgTop, 64 - imgTop);
  }

  u8g2.setFont(u8g2_font_wqy12_t_gb2312);

  // 组装四行：优先 ROWS（服务端已合并 + 过滤空行），老服务端回落 DISPLAY 四段。
  String lines[4];
  int count = 0;
  // 异常态（toast / 升级提示）用自己的参数画，不复用页面缓存的 ROWS。
  if (!abnormal && !useArgs && scrRowCount > 0) {
    for (int i = 0; i < scrRowCount && i < 4; i++) {
      lines[i] = resolveLocalSys(scrRows[i]);
      if (lines[i].length()) count = i + 1;  // 保序，空行仍占位但最后不计
    }
    //  Servers 已经过滤过空行；这里再压实一次，避免中间空行留白。
    String packed[4]; int p = 0;
    for (int i = 0; i < scrRowCount && i < 4; i++) {
      if (lines[i].length()) packed[p++] = lines[i];
    }
    for (int i = 0; i < 4; i++) lines[i] = packed[i];
    count = p;
  } else {
    String src[4] = { title, main, sub, keys };
    for (int i = 0; i < 4; i++) {
      lines[i] = resolveLocalSys(src[i]);
      if (lines[i].length()) count = i + 1;
    }
  }

  uint32_t phases[4] = { phaseTitle, phaseMain, phaseSub, phaseKeys };
  for (int i = 0; i < count; i++) {
    int baseline = rowTop + rowStep * (i + 1) - 2;
    // 只画在屏幕内，避免超出行带。
    if (baseline > 63) baseline = 63;
    if (abnormal && i == 1) {
      invertBlock(2, baseline - 11, 124, 14);
      u8g2.setDrawColor(0);
      marqueeLine(lines[i], 3, baseline, 122, phases[i], MARQUEE_SPEED[i], true);
      u8g2.setDrawColor(1);
    } else {
      marqueeLine(lines[i], 3, baseline, 122, phases[i], MARQUEE_SPEED[i], true);
    }
  }
  u8g2.sendBuffer();
}

// 兼容旧调用：oledShow(title,l1,l2,l3) 走同一套四行布局（无反白）。
// 系统提示（Booting / WiFi lost / Updating 等）仍用此入口，只是不显示反白块。
void oledShow(const String &title, const String &l1 = "", const String &l2 = "", const String &l3 = "") {
  // 系统提示强制用传入文案（useArgs=true），不被页面 ROWS 覆盖。
  drawScreen(title, l1, l2, l3, false, true);
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
  autoUpdate = prefs.getBool("auto", true);
  deviceRole = prefs.getString("role", "master");
  if (deviceRole != "slave") deviceRole = "master";
  masterMac = prefs.getString("master", "");
  masterMac.trim();
  masterMac.toUpperCase();
  // 人体感应 OUT 引脚：-1 = 未接。旧的非法值（例如误填 33~37）一律忽略，
  // 否则 pinMode 会动到 PSRAM，设备开机就卡死。
  pirPin = prefs.getInt("pir", -1);
  if (!pinUsableForPir(pirPin)) {
    if (pirPin >= 0) Serial.printf("[pir] NVS 里的 GPIO%d 不可用（PSRAM/Flash/按键段），已忽略\n", pirPin);
    pirPin = -1;
  }
#if defined(CONFIG_IDF_TARGET_ESP32C6)
  // 从机默认 60 秒休眠；主机或手动设为 0 时不休眠。
  sleepSeconds = prefs.getInt("sleep", deviceRole == "slave" ? 60 : 0);
#else
  sleepSeconds = 0;   // S3 不参与电池休眠
#endif
  if (sleepSeconds < 0 || sleepSeconds > 3600) sleepSeconds = 0;
  batPin = prefs.getInt("batpin", -1);
  if (!pinUsableForBat(batPin)) batPin = -1;
  batDiv = prefs.getInt("batdiv", 2);
  if (batDiv < 1 || batDiv > 10) batDiv = 2;
  // 联网键槽位（oled-5.5）：0 = 不启用；1..8 = 按下连 AP 进后台并推迟休眠。
  netSlot = prefs.getInt("netslot", 0);
  if (netSlot < 0 || netSlot > MAX_BTN) netSlot = 0;
  // 主机所在信道：任意一次成功关联 AP 后记下来，供「只开射频」唤醒时锁定 ESP-NOW。
  relayCh = prefs.getInt("ch", 0);
  if (relayCh < 1 || relayCh > 13) relayCh = 0;
  // OTA 定时查询间隔（秒）：后台可配，越界回落到默认 6 小时。
  otaCheckSec = prefs.getUInt("otachk", 6UL * 3600UL);
  if (otaCheckSec < OTA_CHECK_MIN_SEC || otaCheckSec > OTA_CHECK_MAX_SEC) otaCheckSec = 6UL * 3600UL;
  // 远程更新：已处理过的下发时间戳，重启后不重复触发。
  fwPushSeen = prefs.getULong64("fwpush", 0);
  // 远程配置：已应用到的服务端配置版本，0 表示从未应用过。
  cfgVerApplied = prefs.getUInt("cfgver", 0);
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
    if (!pinUsable(btnPins[i])) btnPins[i] = -1;
  }
  prefs.end();

  // 联网键必须指向一个已启用的槽位，否则视为不启用。
  if (netSlot > 0 && (netSlot > btnCount || btnPins[netSlot - 1] < 0)) netSlot = 0;

  Serial.printf("credssid=%s pass=%s\n", ssid.c_str(), pass.isEmpty() ? "(empty)" : "***");
  Serial.printf("serverBase=%s\n", serverBase.c_str());
  Serial.printf("buttons=%d", btnCount);
  for (int i = 0; i < btnCount; i++) Serial.printf(" %d:GPIO%d", i + 1, btnPins[i]);
  Serial.printf(" netslot=%d ch=%d", netSlot, relayCh);
  Serial.println();
}

// 关联成功后把当前 AP 信道记进 NVS：从机后续不连 AP 时靠它锁定 ESP-NOW 信道。
void rememberChannel() {
  int ch = WiFi.channel();
  if (ch < 1 || ch > 13 || ch == relayCh) return;
  relayCh = (uint8_t)ch;
  prefs.begin("cfg", false);
  prefs.putInt("ch", ch);
  prefs.end();
  Serial.printf("[wifi] channel saved: %d\n", ch);
}

bool connectSTA(uint32_t timeoutMs) {
  WiFi.mode(WIFI_STA);
  WiFi.setSleep(false);
  WiFi.begin(ssid.c_str(), pass.c_str());
  uint32_t t0 = millis();
  uint32_t drawn = 0;
  while (millis() - t0 < timeoutMs) {
    if (WiFi.status() == WL_CONNECTED) {
      rememberChannel();
      return true;
    }
    if (millis() - drawn > 1000) {
      drawn = millis();
      oledShow("WiFi connecting", ssid, String("waited ") + (int)((millis() - t0) / 1000) + "s");
    }
    delay(50);
  }
  bool ok = WiFi.status() == WL_CONNECTED;
  if (ok) rememberChannel();
  return ok;
}

/* ---------------- ESP-NOW 主从中继 ----------------
 * 从机不直接访问服务端：注册/心跳/页面/按键都经 ESP-NOW 发给所属主机，
 * 主机代为 HTTP 转发并把回包分片送回。固件下载体积太大，仍由从机直连
 * WiFi 下载（仅 OTA 例外），避免多 MB 数据在 ESP-NOW 上分片。
 * 帧格式：11 字节头 + data[<=188]，请求与响应都按 seq 分片，按 total 收齐。
 */
#define RELAY_MAGIC       0x50
#define RELAY_REQ         1
#define RELAY_RESP        2
#define RELAY_CHUNK       188
#define RELAY_BUF         8192
#define RELAY_TIMEOUT_MS  4000

typedef struct __attribute__((packed)) {
  uint8_t magic;
  uint8_t type;      // RELAY_REQ / RELAY_RESP
  uint16_t id;       // 请求序号，响应原样带回
  uint8_t method;    // 0=GET 1=POST
  uint8_t status;    // 响应：1 = HTTP 200
  uint16_t total;    // 整个载荷字节数
  uint16_t seq;      // 本片起始偏移
  uint8_t len;
  uint8_t data[RELAY_CHUNK];
} RelayPacket;

bool relayReady = false;
bool haveMasterMac = false;
uint8_t relayMasterMac[6] = {0, 0, 0, 0, 0, 0};
uint16_t relaySeq = 0;

// 从机侧：等待中的响应
uint8_t relayRxBuf[RELAY_BUF];
uint16_t relayRxId = 0, relayRxTotal = 0, relayRxGot = 0;
volatile bool relayRespDone = false;
volatile bool relayRespOk = false;

// 主机侧：当前从机请求（一次处理一个，足够本场景）
struct RelayReq {
  uint8_t mac[6];
  uint16_t id;
  uint8_t method;
  uint16_t total;
  uint16_t got;
  uint32_t at;
  uint8_t buf[RELAY_BUF];
};
RelayReq relayReq;
volatile bool relayReqComplete = false;

bool parseMac(const String &text, uint8_t out[6]) {
  unsigned v[6];
  if (sscanf(text.c_str(), "%x:%x:%x:%x:%x:%x",
             &v[0], &v[1], &v[2], &v[3], &v[4], &v[5]) != 6) return false;
  for (int i = 0; i < 6; i++) {
    if (v[i] > 0xFF) return false;
    out[i] = (uint8_t)v[i];
  }
  return true;
}

// ESP-NOW 的工作信道：已关联 AP 时以 AP 信道为准，否则用 NVS 里记下的主机信道。
// 未关联时 WiFi.channel() 返回 0，直接拿来当 peer 信道会让帧发不出去。
uint8_t relayChannel() {
  int ch = WiFi.channel();
  if (ch >= 1 && ch <= 13) return (uint8_t)ch;
  return relayCh;
}

void relayAddPeer(const uint8_t *mac) {
  if (esp_now_is_peer_exist(mac)) return;
  esp_now_peer_info_t peer = {};
  memcpy(peer.peer_addr, mac, 6);
  peer.channel = relayChannel();
  peer.encrypt = false;
  esp_now_add_peer(&peer);
}

// 把载荷按片发出；total=0 也会发一个空片，让对端知道「成功但无内容」。
void relaySend(const uint8_t *mac, uint8_t type, uint16_t id, uint8_t method,
               uint8_t status, const uint8_t *data, uint16_t total) {
  uint16_t off = 0;
  do {
    RelayPacket pkt;
    memset(&pkt, 0, sizeof(pkt));
    pkt.magic = RELAY_MAGIC;
    pkt.type = type;
    pkt.id = id;
    pkt.method = method;
    pkt.status = status;
    pkt.total = total;
    pkt.seq = off;
    uint16_t n = total - off;
    if (n > RELAY_CHUNK) n = RELAY_CHUNK;
    pkt.len = (uint8_t)n;
    if (n) memcpy(pkt.data, data + off, n);
    esp_now_send(mac, (const uint8_t *)&pkt, offsetof(RelayPacket, data) + n);
    off += n;
    delay(10);   // 让对端回调来得及取走
  } while (off < total);
}

void onRelayRecv(const esp_now_recv_info_t *info, const uint8_t *data, int len) {
  if (len < (int)offsetof(RelayPacket, data)) return;
  const uint8_t *mac = info->src_addr;
  RelayPacket pkt;
  memcpy(&pkt, data, len < (int)sizeof(pkt) ? len : (int)sizeof(pkt));
  if (pkt.magic != RELAY_MAGIC || pkt.len > RELAY_CHUNK) return;
  if (pkt.seq + pkt.len > RELAY_BUF) return;

  if (pkt.type == RELAY_REQ && deviceRole == "master") {
    if (pkt.seq == 0) {
      memcpy(relayReq.mac, mac, 6);
      relayReq.id = pkt.id;
      relayReq.method = pkt.method;
      relayReq.total = pkt.total;
      relayReq.got = 0;
      relayReq.at = millis();
    } else if (relayReq.id != pkt.id || memcmp(relayReq.mac, mac, 6) != 0) {
      return;   // 不是当前请求的后续片，丢弃
    }
    memcpy(relayReq.buf + pkt.seq, pkt.data, pkt.len);
    if (pkt.seq + pkt.len > relayReq.got) relayReq.got = pkt.seq + pkt.len;
    if (relayReq.total <= RELAY_BUF - 1 && relayReq.got >= relayReq.total) {
      relayReq.buf[relayReq.total] = 0;
      relayReqComplete = true;
    }
    return;
  }

  if (pkt.type == RELAY_RESP && deviceRole == "slave") {
    if (pkt.id != relayRxId) return;
    if (memcmp(mac, relayMasterMac, 6) != 0) return;
    memcpy(relayRxBuf + pkt.seq, pkt.data, pkt.len);
    if (pkt.seq + pkt.len > relayRxGot) relayRxGot = pkt.seq + pkt.len;
    relayRxTotal = pkt.total;
    if (relayRxTotal <= RELAY_BUF - 1 && relayRxGot >= relayRxTotal) {
      relayRxBuf[relayRxTotal] = 0;
      relayRespOk = (pkt.status == 1);
      relayRespDone = true;
    }
  }
}

// 从机：发一个请求并等回包。成功返回 true（HTTP 200）。
bool relayRequest(uint8_t method, const String &payload, String &out, bool needBody) {
  if (!relayReady || !haveMasterMac || payload.length() > RELAY_BUF - 1) return false;
  relayRespDone = false;
  relayRespOk = false;
  relayRxGot = 0;
  relayRxTotal = 0;
  uint16_t id = ++relaySeq;
  relayRxId = id;
  relaySend(relayMasterMac, RELAY_REQ, id, method, 0,
            (const uint8_t *)payload.c_str(), payload.length());
  uint32_t t0 = millis();
  while (!relayRespDone && millis() - t0 < RELAY_TIMEOUT_MS) delay(10);
  if (!relayRespDone) return false;
  if (needBody) out = String((const char *)relayRxBuf);
  return relayRespOk;
}

// 主机：在 netTask 里同步转发从机请求（不能在 WiFi 回调里做 HTTP）。
bool relayHttpGet(const String &path, String &out) {
  WiFiClient client;
  HTTPClient http;
  if (!http.begin(client, serverBase + path)) return false;
  http.setTimeout(6000);
  int code = http.GET();
  if (code == 200) out = http.getString();
  http.end();
  return code == 200;
}

bool relayHttpPost(const String &path, const String &body, String &out) {
  WiFiClient client;
  HTTPClient http;
  if (!http.begin(client, serverBase + path)) return false;
  http.setTimeout(6000);
  http.addHeader("Content-Type", "application/json");
  int code = http.POST((uint8_t *)body.c_str(), body.length());
  if (code == 200) out = http.getString();
  http.end();
  return code == 200;
}

void processRelayRequests() {
  if (deviceRole != "master" || !relayReady || !relayReqComplete) return;
  uint8_t mac[6];
  memcpy(mac, relayReq.mac, 6);
  uint16_t id = relayReq.id;
  uint8_t method = relayReq.method;
  String payload((const char *)relayReq.buf);
  relayReqComplete = false;

  int nl = payload.indexOf('\n');
  String path = nl < 0 ? payload : payload.substring(0, nl);
  String body = nl < 0 ? String() : payload.substring(nl + 1);
  String resp;
  bool ok = method == 1 ? relayHttpPost(path, body, resp) : relayHttpGet(path, resp);
  if (resp.length() > RELAY_BUF - 1) resp = resp.substring(0, RELAY_BUF - 1);
  relayAddPeer(mac);
  relaySend(mac, RELAY_RESP, id, method, ok ? 1 : 0,
            (const uint8_t *)resp.c_str(), resp.length());
  Serial.printf("[relay] %s %s -> %s %uB %lums\n", ok ? "ok" : "fail", path.c_str(),
                ok ? "200" : "ERR", (unsigned)resp.length(),
                (unsigned long)(millis() - relayReq.at));
}

void initRelay() {
  if (relayReady) return;
  if (esp_now_init() != ESP_OK) {
    Serial.println("[relay] esp_now_init failed");
    return;
  }
  esp_now_register_recv_cb(onRelayRecv);
  if (deviceRole == "slave") {
    if (!parseMac(masterMac, relayMasterMac)) {
      Serial.println("[relay] 从机未配置有效的主机 MAC，暂按直连运行");
      return;
    }
    relayAddPeer(relayMasterMac);
    haveMasterMac = true;
    Serial.printf("[relay] slave -> master %s ch=%d\n", masterMac.c_str(), relayChannel());
  } else {
    Serial.printf("[relay] master listen ch=%d mac=%s\n", relayChannel(), WiFi.macAddress().c_str());
  }
  relayReady = true;
}

/**
 * 只开射频，不关联 AP（不握手、不 DHCP、无 IP）。
 * ESP-NOW 只需要「射频启动 + 与主机同信道 + 有 peer」，不需要连路由器。
 * 信道优先用 NVS 里记下的主机信道；从未连过网时扫一次 AP 找到 SSID 对应信道。
 */
bool startRadioOnly() {
  WiFi.mode(WIFI_STA);
  WiFi.setSleep(false);
  uint8_t ch = relayCh;
  if (ch < 1 || ch > 13) {
    int n = WiFi.scanNetworks(false, false);
    for (int i = 0; i < n; i++) {
      if (WiFi.SSID(i) == ssid) { ch = (uint8_t)WiFi.channel(i); break; }
    }
    WiFi.scanDelete();
    if (ch >= 1 && ch <= 13) {
      relayCh = ch;
      prefs.begin("cfg", false);
      prefs.putInt("ch", ch);
      prefs.end();
    }
  }
  if (ch < 1 || ch > 13) {
    Serial.println("[radio] 不知道主机信道，无法只开射频");
    return false;
  }
  esp_wifi_set_channel(ch, WIFI_SECOND_CHAN_NONE);
  Serial.printf("[radio] radio-only on ch=%d\n", ch);
  initRelay();
  radioOnly = true;
  return relayReady;
}

/* ---------------- pscreen_server 上报 ---------------- */

bool postJson(const String &path, const String &body) {
  // 从机：注册/心跳经所属主机转发（主机在 netTask 里替它发 HTTP）。
  if (deviceRole == "slave" && relayReady) {
    String resp;
    bool ok = relayRequest(1, path + "\n" + body, resp, true);
    bool pass = ok && resp.indexOf("\"code\":0") >= 0;
    if (pass) lastPostResp = resp;   // 供远程更新标记解析
    Serial.print("[srv] ");
    Serial.print(path);
    Serial.println(pass ? " -> relay ok" : " -> relay fail");
    return pass;
  }
  WiFiClient client;
  HTTPClient http;
  if (!http.begin(client, serverBase + path)) return false;
  http.setTimeout(6000);
  http.addHeader("Content-Type", "application/json");
  int code = http.POST((uint8_t *)body.c_str(), body.length());
  String resp = code > 0 ? http.getString() : String();
  http.end();
  bool ok = (code == 200 && resp.indexOf("\"code\":0") >= 0);
  if (ok) lastPostResp = resp;   // 供远程更新标记解析
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
  // 从机：页面/固件版本查询经主机转发，主机返回原始响应体。
  if (deviceRole == "slave" && relayReady) {
    return relayRequest(0, path, out, true);
  }
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
  deviceId = String(CHIP_TAG) + "-" + mac;
}

int readBatteryMv() {
  if (batPin < 0) return 0;
  // analogReadMilliVolts 已做校准，返回分压点电压；乘分压比得到电池电压。
  return (int)(analogReadMilliVolts(batPin) * (uint32_t)batDiv);
}

void reportToServer(bool isRegister) {
  if (deviceId.isEmpty()) buildDeviceId();
  String body = "{\"deviceId\":\"" + deviceId + "\"";
  if (isRegister) {
    body += ",\"name\":\"" + String(DEVICE_NAME) + "\",\"platform\":\"esp32\",\"model\":\"" + String(CHIP_MODEL) + "\"";
  }
  body += ",\"appVersion\":\"" + String(APP_VER) + "\"";
  // OTA 轨道：后台据此下发对应芯片的发布版本号，避免 S3/C6 互相装错固件。
  body += ",\"target\":\"" + String(CHIP_TAG) + "\"";
  body += ",\"role\":\"" + deviceRole + "\"";
  if (deviceRole == "slave") body += ",\"masterMac\":\"" + masterMac + "\"";
  // 定时唤醒间隔：后台用它推算「预计唤醒时间」，深睡设备不再笼统显示离线。
  if (deviceRole == "slave") body += ",\"sleepSec\":" + String(otaCheckSec);
  // 只在真正关联 AP 时上报信号强度；只开射频时 RSSI 无意义。
  if (WiFi.status() == WL_CONNECTED) body += ",\"rssi\":" + String(WiFi.RSSI());
  // 人体感应状态（1=有人 / 0=无人）：未接感应时不上报，后台保持「未知」。
  if (pirPin >= 0) body += ",\"pir\":" + String(pirPresent ? 1 : 0);
  // 电池电压：未接检测脚时不上报。
  if (batPin >= 0) body += ",\"batteryMv\":" + String(readBatteryMv());
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
  // 远程配置：本机已应用版本 + 当前实际值，后台据此对照并编辑「期望配置」。
  body += ",\"cfgVer\":" + String(cfgVerApplied);
  // 唤醒诊断：本次唤醒来源 + PIR 唤醒累计次数（RTC 内存，深睡不清零）。
  static const char *wakeTag[] = {"cold", "pir", "button", "timer"};
  body += ",\"wake\":\"" + String(wakeTag[wakeReason <= 3 ? wakeReason : 0]) + "\"";
  body += ",\"pirWakes\":" + String(pirWakeCount);
  // 人体感应当前电平：用来区分「传感器没信号」和「能醒但没点亮屏幕」。
  body += ",\"pirLevel\":" + String(pirPin >= 0 ? (digitalRead(pirPin) == HIGH ? 1 : 0) : -1);
  // 上一次入睡时唤醒注册的返回值，排查 PIR 为什么唤不醒。
  body += ",\"slpErr\":{\"btn\":" + String((int)rtcSlpErrBtn) + ",\"pir\":" + String((int)rtcSlpErrPir) + "}";
  body += ",\"pirMode\":" + String((int)rtcPirWakeMode);
  // 唤醒原始诊断：复位原因 / 唤醒原因 / 两条通道的引脚掩码（十进制位掩码）。
  // 例：rst=4(deep sleep 退出) cause=7(GPIO) gpio=64(GPIO6) ext1=0
  body += ",\"diag\":{\"rst\":" + String((int)rtcResetReason) +
          ",\"cause\":" + String((int)rtcWakeCause) +
          ",\"gpio\":" + String((unsigned long)rtcGpioMask) +
          ",\"ext1\":" + String((unsigned long)rtcExt1Mask) + "}";
  body += ",\"cfgNow\":{\"role\":\"" + deviceRole + "\",\"master\":\"" + masterMac + "\"";
  body += ",\"auto\":" + String(autoUpdate ? 1 : 0);
  body += ",\"sleep\":" + String(sleepSeconds);
  body += ",\"otachk\":" + String(otaCheckSec);
  body += ",\"pir\":" + String(pirPin);
  body += ",\"net\":" + String(netSlot);
  body += ",\"batpin\":" + String(batPin);
  body += ",\"batdiv\":" + String(batDiv);
  body += ",\"pins\":[";
  for (int i = 0; i < btnCount; i++) {
    if (i) body += ",";
    body += String(btnPins[i]);
  }
  body += "]}";
  if (WiFi.status() == WL_CONNECTED) body += ",\"ip\":\"" + WiFi.localIP().toString() + "\"}";
  else body += "}";
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

// base64 字符 → 6bit 值；非 base64 字符返回 -1。
int b64val(char c) {
  if (c >= 'A' && c <= 'Z') return c - 'A';
  if (c >= 'a' && c <= 'z') return c - 'a' + 26;
  if (c >= '0' && c <= '9') return c - '0' + 52;
  if (c == '+') return 62;
  if (c == '/') return 63;
  return -1;
}

// 把 base64 字符串解到 out[outLen]；返回写入字节数，输入非法返回 0。
// 用于 IMG 行的 128×64 1-bit 点阵（1024 字节 → base64 约 1368 字符）。
size_t base64Decode(const String &src, uint8_t *out, size_t outLen) {
  size_t o = 0;
  int buf = 0, bits = 0;
  for (int i = 0; i < src.length(); i++) {
    char c = src.charAt(i);
    if (c == '=') break;
    int v = b64val(c);
    if (v < 0) continue;              // 跳过换行/空白等
    buf = (buf << 6) | v;
    bits += 6;
    if (bits >= 8) {
      bits -= 8;
      if (o >= outLen) return o;      // 超长保护
      out[o++] = (uint8_t)((buf >> bits) & 0xFF);
    }
  }
  return o;
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
  snap.requestedPage = page;
  snap.pageLoop = true;
  snap.idleSeconds = 0;
  snap.screenOnSec = 0;
  snap.statusBar = SB_DEFAULT;
  snap.hasImage = false;
  snap.imageInvert = false;
  for (int i = 0; i < 1024; i++) snap.imageBits[i] = 0;
  for (int i = 0; i <= MAX_BTN; i++) { snap.label[i] = ""; snap.name[i] = ""; snap.action[i] = ""; }
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
    // 熄屏：SCREEN|秒 —— 设备级配置，人离开后多少秒熄屏（0 = 常亮）。
    // 老服务端不下发这一行，保持 0，行为与以前一致。
    if (line.startsWith("SCREEN|")) {
      int sec = fieldAt(line, 1).toInt();
      snap.screenOnSec = sec > 0 ? sec : 0;
      continue;
    }
    // 每页状态栏：BAR|enabled|page|time|wifiIcon|rssi|ip（各 0/1）→ 位掩码。
    // 老服务端不下发这一行，保持默认（页码+时间+WiFi图标），行为接近现状。
    if (line.startsWith("BAR|")) {
      uint8_t sb = 0;
      if (fieldAt(line, 1) == "1") sb |= SB_ENABLED;
      if (fieldAt(line, 2) == "1") sb |= SB_PAGE;
      if (fieldAt(line, 3) == "1") sb |= SB_TIME;
      if (fieldAt(line, 4) == "1") sb |= SB_WIFI_ICON;
      if (fieldAt(line, 5) == "1") sb |= SB_RSSI;
      if (fieldAt(line, 6) == "1") sb |= SB_IP;
      snap.statusBar = sb;
      continue;
    }
    // 状态栏时间：TIME|HH:MM（服务端按设备时区算好）。
    if (line.startsWith("TIME|")) {
      snap.time = fieldAt(line, 1);
      continue;
    }
    // 图片点阵：IMG|pageId|base64(128×64 1-bit，1024 字节)|invert(0/1)。
    // 第 4 段缺省按 0 处理，兼容尚未下发该段的旧服务端。
    if (line.startsWith("IMG|")) {
      String b64 = fieldAt(line, 2);
      size_t n = base64Decode(b64, snap.imageBits, 1024);
      if (n >= 1024) { snap.hasImage = true; snap.imageInvert = fieldAt(line, 3) == "1"; }
      continue;
    }
    // 显示层：DISPLAY|title|main|sub|keys —— 老四段，保持兼容。
    // main/sub 允许为空（没有值就留白），固件不要补 `--`。
    if (line.startsWith("DISPLAY")) {
      snap.title = fieldAt(line, 1);
      snap.main  = fieldAt(line, 2);
      snap.sub   = fieldAt(line, 3);
      snap.keys  = fieldAt(line, 4);
      gotDisplay = true;
      continue;
    }
    // v4.2：ROWS|<row1>|<row2>|<row3>|<row4>（最多四行，服务端已按显示开关合并）。
    // 老服务端不下发这一行，snap.rowCount 保持 0，drawScreen 回落 DISPLAY 四段。
    if (line.startsWith("ROWS|")) {
      int n = 0;
      for (int i = 1; i <= 4; i++) {
        String v = fieldAt(line, i);
        if (!v.length()) break;
        snap.rows[i - 1] = v;
        n++;
      }
      snap.rowCount = n;
      gotDisplay = true;
      continue;
    }
    // 当前页按键：slot|短标签|完整名称|entityId|action|id
    int slot = fieldAt(line, 0).toInt();
    if (slot >= 1 && slot <= MAX_BTN) {
      snap.label[slot] = fieldAt(line, 1);
      snap.name[slot]  = fieldAt(line, 2);
      // action 段用于识别系统动作（next_page/prev_page/home_page），
      // 固件据此本地翻页，不再走按键 HTTP 请求。
      snap.action[slot] = fieldAt(line, 4);
    }
  }
  snap.hasDisplay = gotDisplay;
  // 没收到 DISPLAY 行（老服务端 / 未分类）时给明确提示，不显示假内容。
  if (!gotDisplay) {
    snap.title = "";
    snap.main  = "未配置显示";
    snap.sub   = "请在 Admin 设备分类页设置";
    snap.keys  = "";
    snap.rowCount = 0;
  }
  Serial.printf("[esp] 已放行控制项 %u 字节，显示行 %d\n", (unsigned)text.length(), gotDisplay ? 1 : 0);
  return true;
}

// 让服务端执行某个按钮 / 控制项对应的 HA 动作。
// 返回服务端响应体（含 sys 翻页回执），失败返回空串。
String pressAction(const String &body) {
  // 从机：按键动作经主机转发，返回值仍是服务端原始响应体。
  if (deviceRole == "slave" && relayReady) {
    String out;
    relayRequest(1, String("/api/device/esp/press\n") + body, out, true);
    return out;
  }
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
  if (!getText("/api/device/firmware/latest?format=text&target=" + String(CHIP_TAG), text)) return false;
  text.trim();
  if (text.length() == 0) return true;
  int p1 = text.indexOf('|');
  if (p1 <= 0) return true;
  int p2 = text.indexOf('|', p1 + 1);
  int p3 = p2 < 0 ? -1 : text.indexOf('|', p2 + 1);
  snap.fwVersion = text.substring(0, p1);
  if (p2 > 0) snap.fwSize = text.substring(p1 + 1, p2).toInt();
  if (p3 >= 0) snap.fwNotes = text.substring(p3 + 1);
  snap.fwAvailable = isNewerVersion(snap.fwVersion, String(APP_VER));
  if (snap.fwAvailable) {
    Serial.printf("[ota] 可升级: %s -> %s (%uKB)\n", APP_VER, snap.fwVersion.c_str(), (unsigned)(snap.fwSize / 1024));
  }
  return true;
}

// 下载并写入另一个 OTA 槽；成功自动重启，失败保留旧固件
void runOta() {
  if (!fwAvailable) return;
  // 升级可能在没人盯着时自动触发（PIR 早已熄屏）。先点亮并锁住屏幕，
  // 否则下面所有 oledShow 进度提示都会被 drawScreen 的 screenOff 拦截。
  otaInProgress = true;
  wakeScreen();
  Serial.printf("[ota] start download %s\n", fwVersion.c_str());
  oledShow("Updating", "connecting...");
  WiFiClient client;
  String url = serverBase + "/api/device/firmware/download?target=" + String(CHIP_TAG);
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
    otaInProgress = false;   // 复位（随即重启，主要为语义完整）
    ESP.restart();
  }
  String err = httpUpdate.getLastErrorString();
  Serial.printf("[ota] failed code=%d msg=%s\n", (int)httpUpdate.getLastError(), err.c_str());
  otaTriedVer = fwVersion;   // 自动更新用：记录失败版本与时间，冷却后再试
  otaTriedAt = millis();
  otaInProgress = false;     // 失败后恢复常规熄屏节奏
  oledShow("Update failed", String(httpUpdate.getLastError()), err.substring(0, 21));
  toastUntil = millis() + 5000;
}

/**
 * 解析注册/心跳响应里服务端下发的字段：
 *  - fwPush：后台「远程更新」时间戳，比本机记录新就强制升级一次（无视 autoUpdate）
 *  - latestFw：服务端当前发布版本，与本机不同就标记有新版
 * 全部来自同一次上报的响应，不再额外请求 /firmware/latest，
 * 所以从机定时唤醒只需一次往返就能同时完成「报状态 + 查版本」。
 */
void handleServerVars() {
  if (lastPostResp.length() == 0) return;

  int p = lastPostResp.indexOf("\"fwPush\"");
  if (p >= 0) {
    int c = lastPostResp.indexOf(':', p);
    if (c >= 0) {
      uint64_t v = strtoull(lastPostResp.c_str() + c + 1, nullptr, 10);
      if (v > 0 && v > fwPushSeen) {
        fwPushSeen = v;
        fwPushForced = true;
        prefs.begin("cfg", false);
        prefs.putULong64("fwpush", fwPushSeen);
        prefs.end();
        Serial.printf("[ota] remote push %llu\n", (unsigned long long)fwPushSeen);
      }
    }
  }

  int q = lastPostResp.indexOf("\"latestFw\"");
  if (q < 0) return;
  int c2 = lastPostResp.indexOf(':', q);
  if (c2 < 0) return;
  int s = lastPostResp.indexOf('"', c2 + 1);
  if (s < 0) return;
  int e = lastPostResp.indexOf('"', s + 1);
  if (e < 0) return;
  String ver = lastPostResp.substring(s + 1, e);
  if (!isNewerVersion(ver, String(APP_VER))) return;
  fwAvailable = true;
  fwVersion = ver;
  fwNotes = "";
  Serial.printf("[ota] latest %s\n", ver.c_str());
}

// 有新版，且（开了自动更新 或 后台强制推送）时排队；主循环到点执行下载。
void queueOtaIfNeeded() {
  if (!fwAvailable || autoOtaAt != 0) return;
  if (!autoUpdate && !fwPushForced) return;
  autoOtaAt = millis() + 3000;
  Serial.println("[ota] queued");
}

/**
 * 应用服务端下发的远程配置（key=value 逐行）。
 * 设备深睡后连不上自己的设置页，这些值只能靠心跳带回来。
 * 写入 NVS 后由调用方重启，让引脚/角色等按新配置重新初始化。
 */
bool applyDeviceConfig(const String &text) {
  String role = deviceRole, master = masterMac;
  bool autoUpd = autoUpdate;
  int sleepS = sleepSeconds, pir = pirPin, net = netSlot, batp = batPin, batd = batDiv;
  int count = btnCount;
  int pins[MAX_BTN];
  for (int i = 0; i < MAX_BTN; i++) pins[i] = btnPins[i];
  uint32_t ver = 0;

  int start = 0;
  while (start < (int)text.length()) {
    int end = text.indexOf('\n', start);
    if (end < 0) end = text.length();
    String line = text.substring(start, end);
    line.trim();
    start = end + 1;
    int eq = line.indexOf('=');
    if (eq <= 0) continue;
    String k = line.substring(0, eq);
    String v = line.substring(eq + 1);
    k.trim();
    v.trim();
    if (k == "ver") {
      // 必须用 strtoul：String::toInt() 是 32 位有符号，秒级时间戳在 2038 年后才溢出，
      // 但用毫秒会立刻被夹成 LONG_MAX，导致版本永远对不上、设备反复拉取重启。
      ver = (uint32_t)strtoul(v.c_str(), nullptr, 10);
    } else if (k == "role") {
      role = (v == "slave") ? "slave" : "master";
    } else if (k == "master") {
      master = v;
      master.toUpperCase();
    } else if (k == "auto") {
      autoUpd = (v == "1");
    } else if (k == "sleep") {
      sleepS = v.toInt();
    } else if (k == "otachk") {
      uint32_t t = (uint32_t)v.toInt();
      if (t >= OTA_CHECK_MIN_SEC && t <= OTA_CHECK_MAX_SEC) otaCheckSec = t;
    } else if (k == "pir") {
      int p = v.toInt();
      if (p < 0) pir = -1;
      else if (pinUsableForPir(p)) pir = p;
    } else if (k == "net") {
      net = v.toInt();
    } else if (k == "batpin") {
      int p = v.toInt();
      if (p < 0) batp = -1;
      else if (pinUsableForBat(p)) batp = p;
    } else if (k == "batdiv") {
      int d = v.toInt();
      if (d >= 1 && d <= 10) batd = d;
    } else if (k == "npins") {
      count = v.toInt();
    } else if (k.length() >= 2 && k[0] == 'p' && isdigit((unsigned char)k[1])) {
      int idx = k.substring(1).toInt() - 1;
      if (idx >= 0 && idx < MAX_BTN) {
        int p = v.toInt();
        pins[idx] = pinUsable(p) ? p : -1;
      }
    }
  }
  if (ver == 0) return false;
  if (sleepS < 0 || sleepS > 3600) sleepS = 0;
  if (count < 0) count = 0;
  if (count > MAX_BTN) count = MAX_BTN;
  if (net < 0 || net > count) net = 0;

  prefs.begin("cfg", false);
  prefs.putString("role", role);
  prefs.putString("master", master);
  prefs.putBool("auto", autoUpd);
  prefs.putInt("sleep", sleepS);
  prefs.putInt("pir", pir);
  prefs.putInt("netslot", net);
  prefs.putInt("batpin", batp);
  prefs.putInt("batdiv", batd);
  prefs.putUInt("otachk", otaCheckSec);
  prefs.putUInt("cfgver", ver);
  prefs.end();
  prefs.begin("btns", false);
  prefs.putInt("n", count);
  for (int i = 0; i < MAX_BTN; i++) {
    String key = "p" + String(i + 1);
    prefs.putInt(key.c_str(), pins[i]);
  }
  prefs.end();
  Serial.printf("[cfg] applied ver=%lu role=%s pins=%d\n",
                (unsigned long)ver, role.c_str(), count);
  return true;
}

/**
 * 心跳/注册响应里带 cfgVer：与本机已应用版本不同就拉取远程配置并重启应用。
 * 设备深睡时后台改不了它的设置，靠的就是这条通道。
 */
void checkRemoteConfig() {
  if (lastPostResp.length() == 0) return;
  int p = lastPostResp.indexOf("\"cfgVer\"");
  if (p < 0) return;
  int c = lastPostResp.indexOf(':', p);
  if (c < 0) return;
  uint32_t ver = (uint32_t)strtoul(lastPostResp.c_str() + c + 1, nullptr, 10);
  // 0 = 未配置；超过 10 位数的值像是毫秒时间戳（旧格式），忽略以免反复重启。
  if (ver == 0 || ver > 4000000000UL || ver == cfgVerApplied) return;
  Serial.printf("[cfg] remote ver=%lu local=%lu, fetching\n",
                (unsigned long)ver, (unsigned long)cfgVerApplied);
  String text;
  if (!getText("/api/device/esp/config?format=text&deviceId=" + deviceId, text)) return;
  if (!applyDeviceConfig(text)) return;
  delay(200);
  ESP.restart();
}

void onButtonPress(int slot) {
  // PIR peek 期间（还没开射频）：把槽位交给主循环，由它决定开射频执行还是进后台。
  if (peekMode) {
    peekActionSlot = slot;
    Serial.printf("[btn] peek -> execute (slot %d)\n", slot);
    return;
  }

  if (deviceId.isEmpty()) buildDeviceId();
  lastActionAt = millis();
  lastActivityAt = millis();
  lastPresenceAt = millis();
  wakeScreen();
  Serial.printf("[btn] slot %d pressed (page %d)\n", slot, currentPage);

  // 系统动作（翻页/回首页）完全在本地执行：不占用网络，按下即出内容。
  // 服务端随每页下发 action 段（next_page/prev_page/home_page），这里直接读缓存切页。
  const String act = btnAction[slot];
  if (act == "next_page" || act == "prev_page" || act == "home_page") {
    int target = currentPage;
    if (act == "next_page") {
      if (currentPage < pageCount) target = currentPage + 1;
      else if (pageLoop) target = 1;
    } else if (act == "prev_page") {
      if (currentPage > 1) target = currentPage - 1;
      else if (pageLoop) target = pageCount;
    } else {
      target = 1;
    }
    Serial.printf("[btn] %s: %d -> %d\n", act.c_str(), currentPage, target);
    if (target != currentPage) switchPageLocal(target);
    return;
  }

  String shown = btnName[slot].length() ? btnName[slot] : (btnLabel[slot].length() ? btnLabel[slot] : "sending...");
  oledToast(String("Slot ") + slot, shown);
  String body = "{\"deviceId\":\"" + deviceId + "\",\"slot\":" + String(slot)
              + ",\"page\":" + String(currentPage) + "}";
  String resp = pressAction(body);
  bool ok = resp.indexOf("\"code\":0") >= 0;

  // 兜底：老固件缓存里没有 action 段时，仍按服务端回执切页（本地执行）。
  if (resp.indexOf("next_page") >= 0 || resp.indexOf("prev_page") >= 0
      || resp.indexOf("home_page") >= 0) {
    int target = currentPage;
    if (resp.indexOf("next_page") >= 0) {
      if (currentPage < pageCount) target = currentPage + 1;
      else if (pageLoop) target = 1;
    } else if (resp.indexOf("prev_page") >= 0) {
      if (currentPage > 1) target = currentPage - 1;
      else if (pageLoop) target = pageCount;
    } else {
      target = 1;
    }
    toastUntil = 0;
    if (target != currentPage) switchPageLocal(target);
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
  if (screenOff) return;   // 熄屏期间不往面板写数据，等感应到人再恢复
  if (fwAvailable) {
    // 有更新时优先提示：自动更新会自己装，否则引导用户打开本机设置页。
    // 走 oledShow(useArgs=true)，避免正常页的 ROWS 把升级提示盖掉。
    oledShow("Update ready", String("cur ") + APP_VER, String("new ") + fwVersion,
             autoUpdate ? "auto updating..." : "open web page");
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

/* ---------------- 人体感应熄屏 ---------------- */

// 亮屏：真正写面板前把 screenOff 清掉；顺手排队一次刷新，唤醒时内容最新。
void wakeScreen() {
  if (!screenOff) return;
  screenOff = false;
  if (oledOk) u8g2.setPowerSave(0);
  drawMain();
  netRefreshAt = millis();
  Serial.println("[screen] wake");
}

// 熄屏：面板进 power save（SH1106 关显示，功耗从 ~18mA 降到 ~1mA 以内）。
void sleepScreen() {
  if (otaInProgress) return;   // 升级期间禁止熄屏，保证进度可见
  if (screenOff || !oledOk) return;
  screenOff = true;
  u8g2.setPowerSave(1);
  Serial.println("[screen] off");
}

// 人在地感应：高电平 = 有人。持续有人就不断刷新 lastPresenceAt，
// 计时永远从「最后一次检测到人」开始，人走后才会熄屏。
// 同时把 0/1 跳变标记为待上报，后台立刻能看到「有人进入 / 人已离开」。
void pollPir() {
  if (pirPin < 0) return;
  bool present = digitalRead(pirPin) == HIGH;
  if (present) {
    lastPresenceAt = millis();
    lastActivityAt = millis();
    wakeScreen();
  }
  if (present != pirPresent) {
    pirPresent = present;
    pirReportPending = true;
  }
}

/* ---------------- 后台网络任务 ---------------- */

/** 请求后台任务立刻拉一次指定页（翻页 / 空闲回首页后调用）。 */
void requestPage(int page) {
  netPage = page;
  netRefreshAt = millis();
}

/* ---------------- 页面持久化（NVS，深睡唤醒显示缓存） ---------------- */

static PersistedPage lastPersisted;    // 最近一次写入的内容，用于跳过重复写（减少 NVS 磨损）
static bool lastPersistedValid = false;

static void fillPersisted(PersistedPage &p) {
  memset(&p, 0, sizeof(p));
  p.magic = PERSIST_MAGIC;
  p.version = PERSIST_VER;
  p.currentPage = currentPage;
  p.pageCount = pageCount;
  p.pageIndex = pageIndex;
  p.statusBar = curStatusBar;
  p.hasImage = curHasImage ? 1 : 0;
  if (curHasImage) memcpy(p.imageBits, curImageBits, 1024);
  copyPersistStr(p.title, scrTitle);
  copyPersistStr(p.main, scrMain);
  copyPersistStr(p.sub, scrSub);
  copyPersistStr(p.keys, scrKeys);
  p.rowCount = scrRowCount;
  for (int i = 0; i < 4; i++) copyPersistStr(p.rows[i], scrRows[i]);
  for (int i = 0; i <= MAX_BTN; i++) {
    copyPersistStr(p.label[i], btnLabel[i]);
    copyPersistStr(p.name[i], btnName[i]);
    copyPersistStr(p.action[i], btnAction[i]);
  }
}

// 把当前显示页写入 NVS；内容未变则跳过（心跳每 60s 拉一次，但大多数轮次内容相同）。
void persistPage() {
  PersistedPage p;
  fillPersisted(p);
  if (lastPersistedValid && memcmp(&p, &lastPersisted, sizeof(p)) == 0) return;
  prefs.begin("page", false);
  prefs.putBytes("p", &p, sizeof(p));
  prefs.end();
  lastPersisted = p;
  lastPersistedValid = true;
}

// 深睡唤醒后从 NVS 恢复当前页到全局变量，返回 true 表示有有效缓存。
bool restorePage() {
  prefs.begin("page", true);
  size_t n = prefs.getBytesLength("p");
  if (n != sizeof(PersistedPage)) { prefs.end(); return false; }
  PersistedPage p;
  prefs.getBytes("p", &p, sizeof(p));
  prefs.end();
  if (p.magic != PERSIST_MAGIC || p.version != PERSIST_VER) return false;
  currentPage = p.currentPage < 1 ? 1 : p.currentPage;
  pageCount   = p.pageCount < 1 ? 1 : p.pageCount;
  pageIndex   = p.pageIndex < 1 ? currentPage : p.pageIndex;
  curStatusBar = p.statusBar;
  curHasImage  = p.hasImage != 0;
  if (curHasImage) memcpy(curImageBits, p.imageBits, 1024);
  scrTitle = p.title; scrMain = p.main; scrSub = p.sub; scrKeys = p.keys;
  scrRowCount = p.rowCount;
  for (int i = 0; i < 4; i++) scrRows[i] = p.rows[i];
  for (int i = 0; i <= MAX_BTN; i++) {
    btnLabel[i] = p.label[i]; btnName[i] = p.name[i]; btnAction[i] = p.action[i];
  }
  haveDisplay = true;
  lastPersisted = p;
  lastPersistedValid = true;
  return true;
}

/**
 * 本地切页：有缓存就直接画出来（零等待），随后后台再拉一次最新状态微调。
 * 翻页键不再走按键 HTTP，按下即出内容。
 */
void switchPageLocal(int target) {
  if (target < 1) target = 1;
  if (target > pageCount) target = pageCount;
  if (target > PAGE_CACHE_MAX) target = PAGE_CACHE_MAX;
  currentPage = target;
  pageIndex = target;
  PageCache &c = pageCache[target - 1];
  if (c.valid) {
    scrTitle = c.title;
    scrMain  = c.main;
    scrSub   = c.sub;
    scrKeys  = c.keys;
    scrRowCount = c.rowCount;
    for (int i = 0; i < 4; i++) scrRows[i] = c.rows[i];
    haveDisplay = true;
    for (int i = 0; i <= MAX_BTN; i++) {
      btnLabel[i]  = c.label[i];
      btnName[i]   = c.name[i];
      btnAction[i] = c.action[i];
    }
    pageLoop = c.pageLoop;
    curStatusBar = c.statusBar;
    curHasImage  = c.hasImage;
    for (int i = 0; i < 1024; i++) curImageBits[i] = c.imageBits[i];
    drawMain();
    persistPage();   // 切到的页要成为下次唤醒显示的缓存
  } else {
    // 该页还没缓存（首次翻到）：先给页码反馈，不等 HTTP 返回。
    drawScreen(String("第 ") + target + "/" + pageCount + " 页", "加载中...", "", "", false);
  }
  requestPage(target);   // 后台补最新数据
}

/**
 * 空闲时预取还没缓存的页：翻页几乎总是命中缓存。
 * 有排队请求、或刚按过键时不抢网络（按键后的刷新优先）。
 */
void schedulePrefetch() {
  static uint32_t lastPrefetchAt = 0;
  if (screenOff) return;   // 熄屏时不预取，省掉无意义的请求
  if (!netEnabled || WiFi.status() != WL_CONNECTED) return;
  if (netRefreshAt != 0 || netBusy) return;         // 已有排队/正在请求
  if (millis() - lastActionAt < 4000) return;       // 操作期间不预取
  if (millis() - lastPrefetchAt < 400) return;      // 节流
  if (pageCount < 2) return;
  int limit = pageCount > PAGE_CACHE_MAX ? PAGE_CACHE_MAX : pageCount;
  for (int p = 1; p <= limit; p++) {
    if (pageCache[p - 1].valid) continue;
    netPage = p;
    netRefreshAt = millis();
    lastPrefetchAt = millis();
    Serial.printf("[prefetch] page %d\n", p);
    return;
  }
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
    // 不论这一页是不是当前页，先入缓存：预取回来的邻页也要留着给本地翻页用。
    if (snap.currentPage >= 1 && snap.currentPage <= PAGE_CACHE_MAX) {
      PageCache &c = pageCache[snap.currentPage - 1];
      c.valid = true;
      c.pageCount = snap.pageCount;
      c.pageLoop  = snap.pageLoop;
      c.statusBar = snap.statusBar;
      c.hasImage  = snap.hasImage;
      for (int i = 0; i < 1024; i++) c.imageBits[i] = snap.imageBits[i];
      c.title = snap.title;
      c.main  = snap.main;
      c.sub   = snap.sub;
      c.keys  = snap.keys;
      c.rowCount = snap.rowCount;
      for (int i = 0; i < 4; i++) c.rows[i] = snap.rows[i];
      for (int i = 0; i <= MAX_BTN; i++) {
        c.label[i]  = snap.label[i];
        c.name[i]   = snap.name[i];
        c.action[i] = snap.action[i];
      }
    }
    // 只有「请求的就是当前页」（或服务端把页号收敛到当前页）时才更新屏幕；
    // 预取的其它页只入缓存，不抢当前显示。
    if (snap.requestedPage == currentPage || snap.currentPage == currentPage) {
      scrTitle = snap.title;
      scrMain  = snap.main;
      scrSub   = snap.sub;
      scrKeys  = snap.keys;
      scrRowCount = snap.rowCount;
      for (int i = 0; i < 4; i++) scrRows[i] = snap.rows[i];
      haveDisplay = snap.hasDisplay;
      for (int i = 0; i <= MAX_BTN; i++) {
        btnLabel[i] = snap.label[i];
        btnName[i]  = snap.name[i];
        btnAction[i] = snap.action[i];
      }
      pageCount   = snap.pageCount;
      pageIndex   = snap.pageIndex;
      currentPage = snap.currentPage;
      pageLoop    = snap.pageLoop;
      idleSeconds = snap.idleSeconds;
      screenOnSec = snap.screenOnSec;
      curStatusBar = snap.statusBar;
      curHasImage  = snap.hasImage;
      curImageInvert = snap.imageInvert;
      for (int i = 0; i < 1024; i++) curImageBits[i] = snap.imageBits[i];
      if (snap.time.length()) barTime = snap.time;  // 时钟跨页共享
      persistPage();   // 当前页内容刷新 → 更新 NVS 缓存（内容未变会自动跳过）
    }
    // 预取完成后把任务拉回当前页：心跳只刷新用户正在看的那一页。
    // 若有新的刷新请求在排队（requestPage/schedulePrefetch），不要覆盖页码。
    if (netRefreshAt == 0) netPage = currentPage;
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
  uint32_t lastHeartbeat = 0;
  uint32_t lastFwCheck = 0;
  uint32_t pirRetryAt = 0;
  static const uint32_t FW_CHECK_MS = 5UL * 60UL * 1000UL;  // OTA 检查 5 分钟一次
  for (;;) {
    // 主机：先把从机排队的请求转发完，再做自己的心跳/拉页面。
    processRelayRequests();
    // 到点刷新：翻页是立即，按键动作后延迟 ~0.7 秒等 HA 状态机更新。
    // 用有符号差值比较，millis() 回绕也不会漏触发。
    bool refresh = netRefreshAt != 0 && (int32_t)(millis() - netRefreshAt) >= 0;
    bool heartbeatDue = millis() - lastHeartbeat >= REPORT_MS;
    // 人体感应跳变：不等心跳立刻上报一次；失败 5 秒后重试。
    bool pirDue = pirReportPending && (int32_t)(millis() - pirRetryAt) >= 0;
    if (netEnabled && WiFi.status() == WL_CONNECTED && (refresh || heartbeatDue || pirDue)) {
      // 先清排队标志，避免主循环在这轮请求期间重复排队同一页。
      if (refresh) netRefreshAt = 0;
      netBusy = true;
      int page = netPage;
      // 心跳按 60 秒节奏上报；翻页/按键后的即时刷新只拉页面，
      // 省掉穿透链路上每个请求几百毫秒的往返，状态显示更快。
      if (heartbeatDue || pirDue) {
        reportToServer(false);
        // 心跳响应同时带回最新版本和远程更新标记：一次往返完成状态上报与版本检查。
        if (heartbeatDue) {
          handleServerVars();
          checkRemoteConfig();   // 远程配置有更新就拉取并重启
          queueOtaIfNeeded();
        }
        // 只有「到点的 60 秒心跳」才顺延计时。感应跳变的即时上报不算心跳，
        // 否则 PIR 抖动时每几秒报一次，60 秒的心跳（也是唯一的定时拉页面时机）
        // 会被无限顺延，屏幕内容就再也不会自动刷新。
        if (heartbeatDue) lastHeartbeat = millis();
        if (srvOk) pirReportPending = false;
        else if (pirDue) pirRetryAt = millis() + 5000;
      }
      NetSnapshot snap;
      // 屏灭期间只保心跳（后台在线判定 90 秒），不拉页面：
      // 感应到人时 wakeScreen() 会排队一次立即刷新，醒来后内容照样是最新的。
      // 单纯上报感应状态时也不必拉页面。
      if (!screenOff && (refresh || heartbeatDue)) snap.valid = fetchActionsInto(page, snap);
      // 固件版本检查不影响显示，按 5 分钟自己走，不搭每次刷新的便车。
      if (millis() - lastFwCheck >= FW_CHECK_MS) {
        snap.fwKnown = checkFirmwareInto(snap);
        lastFwCheck = millis();
      }
      if (snap.valid || snap.fwKnown) publishSnapshot(snap);
      netBusy = false;
    }
    vTaskDelay(pdMS_TO_TICKS(200));   // 轮询刷新请求的粒度
  }
}

// 跑马灯节拍（E3）：~10fps 推进各行相位，只在有超长文本被滚动时才重绘，
// 避免整屏高频刷新拖慢 I2C / 心跳 / 按键轮询。相位 = 时间 × 15px/s × 各行倍率。
void tickMarquee() {
  if (!oledOk || screenOff) return;
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
  initRelay();
  reportToServer(true);
  handleServerVars();      // 注册响应里也可能带最新版本和远程更新标记
  checkRemoteConfig();     // 后台改了设备配置就拉取并应用（会重启）
  queueOtaIfNeeded();
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

  // 主从角色：芯片型号决定 OTA 轨道，角色只决定通信方式（从机经主机访问服务端）。
  h += "<h3>主从角色</h3>";
  h += "<form method='POST' action='/settings/role'>";
  h += "<label>本机角色</label><select name='role'>";
  h += String("<option value='master'") + (deviceRole == "master" ? " selected" : "") + ">主机（常供电，保持在线）</option>";
  h += String("<option value='slave'") + (deviceRole == "slave" ? " selected" : "") + ">从机（经主机访问服务端）</option>";
  h += "</select>";
  h += "<label>所属主机 MAC（从机填写，主机可留空）</label>";
  h += String("<input name='master' value='") + masterMac + "' placeholder='AA:BB:CC:DD:EE:FF'>";
  h += "<button type='submit'>保存角色并重启</button></form>";
  h += String("<div class='tip'>当前芯片：") + String(CHIP_MODEL) +
       "（固件轨道 " + String(CHIP_TAG) +
       "）。主机切从机前请先确认其下属从机已解绑；从机切主机会自动解除原绑定。</div>";

  // 电池与休眠：仅 C6 从机生效。S3 为市电常供，不显示这项。
#if defined(CONFIG_IDF_TARGET_ESP32C6)
  h += "<h3>电池与休眠</h3>";
  h += "<form method='POST' action='/settings/power'>";
  h += String("<label>空闲休眠秒数（0 = 不休眠）</label><input name='sleep' type='number' min='0' max='3600' value='") + sleepSeconds + "'>";
  h += String("<label>电池检测 GPIO（-1 = 未接，C6 仅 0~6 可用）</label><input name='batpin' type='number' min='-1' max='6' value='") + batPin + "'>";
  h += String("<label>分压比（电池电压 = 引脚电压 × 该值）</label><input name='batdiv' type='number' min='1' max='10' value='") + batDiv + "'>";
  h += "<button type='submit'>保存并重启</button></form>";
  h += "<div class='tip'>休眠时关屏关 WiFi，按已配置按键（低电平）唤醒；唤醒后重新联网并经主机注册。"
       "人体感应只在本机清醒时生效，休眠期间不唤醒。分压点请勿直接接电池，需加分压电阻。</div>";
#endif

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
  h += "<div class='tip' style='margin-top:12px'>人体感应：VCC→<b>3V3</b>，GND→GND，OUT→下面填的 GPIO。<br>"
       "有人时 OUT 输出高电平，屏幕立即亮起；人持续在就一直亮，人离开后按后台设置的秒数熄屏。</div>";
  h += "<label>人体感应 OUT GPIO（-1 = 未接，屏幕常亮）</label>";
  h += "<input name='pir' inputmode='numeric' value='" + String(pirPin) + "'>";
#if defined(CONFIG_IDF_TARGET_ESP32C6)
  h += "<div class='tip'>省电考虑：C6 只有 <b>GPIO0~7</b> 能唤醒深睡，接在 8 以上的引脚"
       "只能在本机已醒时起作用，睡着时按人体感应不会亮屏。</div>";
#endif
  // oled-5.5：联网键——按下连 AP 进后台并推迟休眠 5 分钟，不执行该槽位的动作。
  // 普通键只开射频走主机中继，所以进后台需要这颗专用键。
  h += "<label>联网键（按下连 WiFi 进后台，不执行动作；不启用时所有按键都连 WiFi）</label>";
  h += "<select name='netslot'>";
  h += String("<option value='0'") + (netSlot == 0 ? " selected" : "") + ">不启用</option>";
  for (int i = 0; i < btnCount; i++) {
    if (btnPins[i] < 0) continue;
    h += String("<option value='") + (i + 1) + "'" + (netSlot == i + 1 ? " selected" : "")
         + ">槽位 " + (i + 1) + "（GPIO" + btnPins[i] + "）</option>";
  }
  h += "</select>";
  h += "<button class='mini' type='button' onclick='addSlot()' style='margin-top:8px'>＋ 添加槽位</button>";
  h += "<button type='submit'>保存按键映射并重启</button></form>";
#if defined(CONFIG_IDF_TARGET_ESP32C6)
  h += "<div class='tip'>本机为 ESP32-C6：OLED 占用 GPIO19/20，可用按键 0~3、6、7、10、11、14、16~18；"
       "避开 4/5/8/9/15（启动配置脚）、12/13（USB）。GPIO15 只能接人体感应，不可配按键。</div>";
  h += "<script>function addSlot(){var ins=document.querySelectorAll('.pin');"
       "var used={};for(var i=0;i<ins.length;i++){if(ins[i].value!=='-1'&&ins[i].value!=='')used[ins[i].value]=1;}"
       "var cand=[3,6,7,10,11,14,16,17,18];"
       "for(var j=0;j<ins.length;j++){if(ins[j].value==='-1'||ins[j].value===''){"
       "for(var k=0;k<cand.length;k++){if(!used[cand[k]]){ins[j].value=cand[k];return;}}}}"
       "alert('槽位已满');}</script>";
#else
  h += "<div class='tip'>避开 GPIO4~13（本机按键 + OLED I2C）、26~37（Flash / PSRAM）、"
       "0/3/19/20/45/46（USB / 启动脚）。人体感应建议 14~18/21/38~42/47/48。</div>";
  h += "<script>function addSlot(){var ins=document.querySelectorAll('.pin');"
       "var used={};for(var i=0;i<ins.length;i++){if(ins[i].value!=='-1'&&ins[i].value!=='')used[ins[i].value]=1;}"
       "var cand=[14,15,16,17,18,21,38,39,40,41,42,47,48];"
       "for(var j=0;j<ins.length;j++){if(ins[j].value==='-1'||ins[j].value===''){"
       "for(var k=0;k<cand.length;k++){if(!used[cand[k]]){ins[j].value=cand[k];return;}}}}"
       "alert('槽位已满');}</script>";
#endif

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
  // 定时唤醒间隔：从机深睡时唯一能上报状态 / 发现新版本的途径。
  h += "<label>休眠时唤醒的间隔</label>";
  h += "<select name='otachk'>";
  const uint32_t opts[] = {300, 600, 1800, 3600, 7200, 10800, 21600};
  const char *names[] = {"5 分钟", "10 分钟", "30 分钟", "1 小时", "2 小时", "3 小时", "6 小时（默认）"};
  for (int i = 0; i < 7; i++) {
    h += String("<option value='") + opts[i] + "'" +
         (otaCheckSec == opts[i] ? " selected" : "") + ">" + names[i] + "</option>";
  }
  h += "</select>";
  h += "<div class='tip'>只对从机有效：到点唤醒发一次心跳（顺带上报状态、取最新版本），"
       "有新版才连 WiFi 下载。间隔越短越费电（5 分钟约 6 mAh/天，6 小时约 0.1 mAh/天）。</div>";
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
    // 访问后台后 5 分钟内不休眠，避免页面刚打开或保存途中设备睡过去。
    sleepHoldUntil = millis() + 300000UL;
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
    sleepHoldUntil = millis() + 300000UL;
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

  // 角色切换：master 会自动解除原本机作为从机的绑定；slave 保留填写的所属主机。
  server.on("/settings/role", HTTP_POST, []() {
    if (authBlocked()) return;
    sleepHoldUntil = millis() + 300000UL;
    String role = server.hasArg("role") ? server.arg("role") : String("master");
    role.trim();
    role.toLowerCase();
    if (role != "slave") role = "master";
    String master = server.hasArg("master") ? server.arg("master") : String();
    master.trim();
    master.toUpperCase();
    master.replace(" ", "");
    if (master.length() && master.length() != 17) master = "";
    prefs.begin("cfg", false);
    prefs.putString("role", role);
    prefs.putString("master", master);
    prefs.end();
    Serial.printf("[role] role=%s master=%s\n", role.c_str(), master.c_str());
    server.send(200, "text/html; charset=utf-8",
                "<meta charset='utf-8'><h3>角色已保存，设备正在重启…</h3>");
    delay(1200);
    ESP.restart();
  });

  // 电池与休眠（仅 C6）：校验引脚后写入 NVS，重启生效。
  server.on("/settings/power", HTTP_POST, []() {
    if (authBlocked()) return;
    sleepHoldUntil = millis() + 300000UL;
    int sleepArg = server.hasArg("sleep") ? server.arg("sleep").toInt() : 0;
    if (sleepArg < 0) sleepArg = 0;
    if (sleepArg > 3600) sleepArg = 3600;
    int pinArg = server.hasArg("batpin") ? server.arg("batpin").toInt() : -1;
    if (!pinUsableForBat(pinArg)) pinArg = -1;
    int divArg = server.hasArg("batdiv") ? server.arg("batdiv").toInt() : 2;
    if (divArg < 1 || divArg > 10) divArg = 2;
    prefs.begin("cfg", false);
    prefs.putInt("sleep", sleepArg);
    prefs.putInt("batpin", pinArg);
    prefs.putInt("batdiv", divArg);
    prefs.end();
    Serial.printf("[power] sleep=%ds batPin=%d div=%d\n", sleepArg, pinArg, divArg);
    server.send(200, "text/html; charset=utf-8",
                "<meta charset='utf-8'><h3>电池与休眠已保存，设备正在重启…</h3>");
    delay(1200);
    ESP.restart();
  });

  // 按键槽位映射：槽位号 = 表单行号，空 / -1 / 重复引脚视为停用；保存后重启生效。
  server.on("/settings/buttons", HTTP_POST, []() {
    if (authBlocked()) return;
    sleepHoldUntil = millis() + 300000UL;
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
        valid = pinUsable(pin);
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

    // 人体感应 OUT 引脚（设备级）：空 / -1 = 未接；与任一按键脚冲突时也视为未接。
    String pirRaw = server.hasArg("pir") ? server.arg("pir") : String();
    pirRaw.trim();
    int pir = -1;
    if (pirRaw.length() && pirRaw != "-1") {
      int pin = pirRaw.toInt();
      if (pinUsableForPir(pin)) {
        bool clash = false;
        for (int i = 0; i < MAX_BTN; i++) if (pins[i] == pin) clash = true;
        if (!clash) pir = pin;
      }
    }
    // 联网键槽位（oled-5.5）：0 = 不启用；必须指向一个已启用（pins[]>=0）的槽位。
    int ns = server.hasArg("netslot") ? server.arg("netslot").toInt() : 0;
    if (ns < 0 || ns > MAX_BTN) ns = 0;
    if (ns > 0 && (ns > maxSlot || pins[ns - 1] < 0)) ns = 0;
    prefs.begin("cfg", false);
    prefs.putInt("pir", pir);
    prefs.putInt("netslot", ns);
    prefs.end();
    Serial.printf("[pir] 人体感应 GPIO: %d\n", pir);
    Serial.printf("[cfg] 联网键槽位: %d\n", ns);
    server.send(200, "text/html; charset=utf-8",
                "<meta charset='utf-8'><h3>已保存，设备正在重启…</h3>");
    delay(1200);
    ESP.restart();
  });

  // 自动更新开关：只写 NVS，不重启；开启时若已有待装版本则立刻排队
  server.on("/settings/auto", HTTP_POST, []() {
    if (authBlocked()) return;
    autoUpdate = server.arg("auto") == "1";
    // OTA 定时查询间隔：表单没带就保持原值；越界回落到 6 小时。
    uint32_t chk = otaCheckSec;
    if (server.hasArg("otachk")) chk = (uint32_t)server.arg("otachk").toInt();
    if (chk < OTA_CHECK_MIN_SEC || chk > OTA_CHECK_MAX_SEC) chk = 6UL * 3600UL;
    otaCheckSec = chk;
    prefs.begin("cfg", false);
    prefs.putBool("auto", autoUpdate);
    prefs.putUInt("otachk", otaCheckSec);
    prefs.end();
    Serial.printf("[ota] 自动更新: %s, 检查间隔: %lus\n",
                  autoUpdate ? "开" : "关", (unsigned long)otaCheckSec);
    if (autoUpdate && fwAvailable && autoOtaAt == 0) autoOtaAt = millis() + 8000;
    server.sendHeader("Location", "/settings");
    server.send(303, "text/plain", "");
  });

  // 网页「测试」按钮：直接请服务端执行对应动作（同样受白名单约束）
  server.on("/settings/press", HTTP_POST, []() {
    if (authBlocked()) return;
    sleepHoldUntil = millis() + 300000UL;
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

/* ---------------- 电池休眠（C6 从机） ---------------- */

// 空闲到点后进入深度睡眠：关屏、关射频。
// 唤醒源：已配置按键（低电平）+ 人体感应（高电平，若接了）+ 定时（查 OTA）。
// quiet=true 时不亮屏、不提示（定时唤醒查 OTA 回来后静默入睡）。
void enterDeepSleep(bool quiet = false) {
  Serial.printf("[sleep] deep sleep, wake pins:");
  for (int i = 0; i < btnCount; i++) if (btnPins[i] >= 0) Serial.printf(" GPIO%d", btnPins[i]);
  if (pirPin >= 0) Serial.printf(" PIR=GPIO%d(H)", pirPin);
  if (autoUpdate && deviceRole == "slave") Serial.printf(" timer=%lus", (unsigned long)otaCheckSec);
  else if (deviceRole == "slave") Serial.printf(" timer=%lus(status only)", (unsigned long)otaCheckSec);
  Serial.println();
  if (!quiet) {
    oledShow("Sleep", "key or PIR to wake", String(sleepSeconds) + "s idle");
    delay(400);
  }
  // 不论是否静默，睡之前都要把面板关掉：OLED 保持点亮会持续耗电。
  if (oledOk) u8g2.setPowerSave(1);
#if defined(CONFIG_IDF_TARGET_ESP32C6)
  // 注：深睡唤醒 = 整机复位，按键/PIR 映射只能在重启后改变，
  // 故无需先禁用旧唤醒源（避免向 disable 接口传入不兼容枚举）。
  uint64_t mask = 0;
  for (int i = 0; i < btnCount; i++) {
    if (btnPins[i] < 0) continue;
    pinMode(btnPins[i], INPUT_PULLUP);
    mask |= (1ULL << btnPins[i]);
  }
  rtcSlpErrBtn = 0;
  rtcSlpErrPir = 0;
  if (mask) rtcSlpErrBtn = (int8_t)esp_deep_sleep_enable_gpio_wakeup(mask, ESP_GPIO_WAKEUP_GPIO_LOW);
  // PIR 为高电平唤醒：与按键低电平分两次调用，各自设置引脚触发电平。
  // 必须开内部下拉：未接传感器时引脚悬空会被拉高，导致「刚睡下就立刻被唤醒」
  // 的循环（每次唤醒都联网，电池很快耗尽）。
  // C6 只有 RTCIO 0~7 能作为深睡唤醒源，其它引脚配了也不会生效。
  if (pirPin >= 0) {
    pinMode(pirPin, INPUT_PULLDOWN);
    if (pirPin < 8) {
      // 先试 EXT1（RTC IO 通道，专门用于 RTC 引脚电平唤醒），失败再退回 GPIO wake。
      esp_err_t e = esp_sleep_enable_ext1_wakeup_io(1ULL << pirPin, ESP_EXT1_WAKEUP_ANY_HIGH);
      if (e == ESP_OK) {
        rtcPirWakeMode = 1;
        rtcSlpErrPir = 0;
      } else {
        rtcPirWakeMode = 2;
        rtcSlpErrPir = (int8_t)esp_deep_sleep_enable_gpio_wakeup(1ULL << pirPin, ESP_GPIO_WAKEUP_GPIO_HIGH);
        if (rtcSlpErrPir != 0) rtcSlpErrPir = (int8_t)e;   // 两条都失败时保留 EXT1 的错误码
      }
    } else {
      rtcPirWakeMode = 0;
      rtcSlpErrPir = -2;
      Serial.printf("[sleep] PIR GPIO%d cannot wake this chip (only GPIO0-7)\n", pirPin);
    }
  }
  // 定时唤醒：从机一律启用（即使关了自动更新也要定期上报状态、接收远程更新标记）。
  // 到点只开射频发一次心跳，有新版且允许更新时才连 AP。
  if (deviceRole == "slave" && otaCheckSec > 0) {
    esp_sleep_enable_timer_wakeup((uint64_t)otaCheckSec * 1000000ULL);
  }
#endif
  WiFi.disconnect(true);
  WiFi.mode(WIFI_OFF);
  delay(100);
  esp_deep_sleep_start();
}

// 不同芯片获取「哪个 GPIO 唤醒了深睡」的接口不同：
// C6/C5/H2 走 gpio 唤醒源（get_gpio_wakeup_status），S3/经典 ESP32 走 EXT1
// （get_ext1_wakeup_status）。两者都返回引脚位掩码。
static uint64_t wakeGpioStatus() {
#if defined(CONFIG_IDF_TARGET_ESP32C6)
  // PIR 可能走 EXT1、按键走 GPIO wake，两条都要查，否则会把唤醒判成「冷启动」。
  return esp_sleep_get_gpio_wakeup_status() | esp_sleep_get_ext1_wakeup_status();
#else
  return esp_sleep_get_ext1_wakeup_status();
#endif
}

// 识别深睡唤醒来源（冷启动返回 WAKE_COLD），并把命中的槽位记到 wakeSlotHit。
// 依据：唤醒原因是 GPIO/EXT1 时用引脚位掩码判断是 PIR 脚还是某个按键脚。
// S3 不深睡，恒为冷启动。
uint8_t detectWakeReason() {
  wakeSlotHit = 0;
  esp_sleep_wakeup_cause_t cause = esp_sleep_get_wakeup_cause();
  // 原始诊断先记录，再判断，避免返回太早丢数据。
  rtcWakeCause   = (int8_t)cause;
  rtcResetReason = (int8_t)esp_reset_reason();
#if defined(CONFIG_IDF_TARGET_ESP32C6)
  rtcGpioMask    = (uint32_t)esp_sleep_get_gpio_wakeup_status();
#else
  rtcGpioMask    = 0;
#endif
  rtcExt1Mask    = (uint32_t)esp_sleep_get_ext1_wakeup_status();
  if (cause == ESP_SLEEP_WAKEUP_TIMER) return WAKE_TIMER;
  bool gpioWake = (cause == ESP_SLEEP_WAKEUP_GPIO) || (cause == ESP_SLEEP_WAKEUP_EXT1);
  if (!gpioWake) return WAKE_COLD;
  uint64_t mask = wakeGpioStatus();
  if (pirPin >= 0 && (mask & (1ULL << pirPin))) return WAKE_PIR;
  for (int i = 0; i < btnCount; i++) {
    if (btnPins[i] >= 0 && (mask & (1ULL << btnPins[i]))) {
      wakeSlotHit = i + 1;
      return WAKE_BUTTON;
    }
  }
  return WAKE_COLD;
}

/**
 * 唤醒键直接执行动作：不等 pollButtons，所以"按一下"就能生效，无需按住。
 * 本地动作（翻页/回首页）连射频都不开；实体动作只开射频走主机中继。
 */
void executeActionOnWake(int slot) {
  screenOff = false;
  if (oledOk) u8g2.setPowerSave(0);
  if (haveDisplay) drawMain();

  const String act = btnAction[slot];
  bool local = (act == "next_page" || act == "prev_page" || act == "home_page");
  if (!local) {
    // 实体动作要发给服务器：只开射频，不连 AP。
    if (!startRadioOnly()) {
      // 射频起不来（例如从未连过网、扫不到 AP）→ 退化为连 AP 后执行。
      if (connectSTA(STA_TIMEOUT_MS)) showConnected();
    }
  }
  onButtonPress(slot);
  actionSleepAt = millis() + ACTION_SLEEP_MS;
  Serial.printf("[wake] action slot %d done, sleep in %lums\n", slot, (unsigned long)ACTION_SLEEP_MS);
}

// 定时唤醒：开射频发一次心跳（上报状态 + 拿最新版本 + 远程更新标记），
// 有新版才连 AP 下载，否则立刻回睡。整个流程只有一次中继往返。
void timerWakeOtaCheck() {
  Serial.println("[wake] timer: status + fw check");
  if (!startRadioOnly()) { enterDeepSleep(true); return; }
  reportToServer(false);
  handleServerVars();
  checkRemoteConfig();   // 后台改了配置，醒来时顺手应用（会重启）
  Serial.printf("[wake] timer: latest=%s local=%s forced=%d\n",
                fwVersion.c_str(), APP_VER, fwPushForced ? 1 : 0);
  if (fwAvailable && (autoUpdate || fwPushForced)) {
    // 确实要装才连 AP（TCP 大文件），并点亮面板显示进度。
    if (connectSTA(STA_TIMEOUT_MS)) {
      initOled();
      runOta();
    }
  }
  enterDeepSleep(true);
}

void setup() {
  // 不再固定空等。原来「Serial 后 300ms + 开机画面 400ms」共 0.7 秒，
  // 对每次按键唤醒都是纯浪费。C6 走 USB CDC，最早几行日志可能丢，
  // 但随后的 [wake] 日志仍在，排查够用。
  Serial.begin(115200);
  loadCreds();

  // 按键：槽位映射要先由 loadCreds 从 NVS 读出来，再按槽位配置上拉输入。
  // down 取当前电平而不是一律 false：唤醒那颗键可能还按着，
  // 若当成「新按下」，唤醒时已执行过一次的动作会被重复执行。
  for (int i = 0; i < MAX_BTN; i++) {
    if (i < btnCount && btnPins[i] >= 0) {
      pinMode(btnPins[i], INPUT_PULLUP);
      buttons[i].down = digitalRead(btnPins[i]) == LOW;
    } else {
      buttons[i].down = false;
    }
    buttons[i].changedAt = 0;
  }

  // 人体感应输入：模块 OUT 是推挽输出，不需要上拉。
  // 上电先把「最后有人在」记为当前时间，避免刚开机就按旧的 0 熄屏。
  if (pirPin >= 0) {
    pinMode(pirPin, INPUT);
    pirPresent = digitalRead(pirPin) == HIGH;
  }
  lastPresenceAt = millis();
  lastActivityAt = millis();

  // 先识别唤醒来源 + 恢复缓存页，再决定要不要亮屏/联网。
  wakeReason = detectWakeReason();
  bool restored = restorePage();

  // 定时唤醒只查 OTA：连 OLED 都不初始化，面板保持熄灭，不闪屏也不耗电。
  // 其余唤醒（冷启动 / 按键 / PIR）才点亮面板。
  if (wakeReason != WAKE_TIMER) initOled();

  // 只有冷启动才画开机画面并短暂停留：按键 / PIR 直接干活，
  // 不画开机图也不空等，省下这 0.4 秒。
  if (wakeReason == WAKE_COLD) {
    Serial.println("\n=== Potatokid screen boot ===");
    oledShow("Booting", "OLED test ok");
    delay(150);
  }
  Serial.printf("[wake] reason=%d slot=%d restored=%d page=%d\n",
                wakeReason, wakeSlotHit, restored ? 1 : 0, currentPage);

  // 网络任务固定在 core 0：主循环（绘制/I2C/按键）留在 core 1，互不打断。
  // C6 为单核，不能指定 core 1，直接创建普通任务。
  netMux = xSemaphoreCreateMutex();
#if defined(CONFIG_IDF_TARGET_ESP32C6)
  xTaskCreate(netTask, "net", 12288, nullptr, 1, nullptr);
#else
  xTaskCreatePinnedToCore(netTask, "net", 12288, nullptr, 1, nullptr, 0);
#endif

  // ① 定时唤醒：只查 OTA，不亮屏、不打扰。
  if (wakeReason == WAKE_TIMER) {
    timerWakeOtaCheck();
    return;
  }

  // ② PIR 唤醒：只亮屏显示缓存 5 秒，不开射频；
  //    期间按键则交给主循环去执行对应动作。
  if (wakeReason == WAKE_PIR) {
    pirWakeCount++;
    peekMode = true;
    peekUntil = millis() + PEEK_MS;
    screenOff = false;
    if (oledOk) u8g2.setPowerSave(0);
    if (restored) drawMain();
    else oledShow("Wake", "no cached page", "press key", "to load");
    Serial.printf("[wake] peek %lums\n", (unsigned long)PEEK_MS);
    return;
  }

  // ③ 按键唤醒：联网键进后台；动作键只开射频执行。
  if (wakeReason == WAKE_BUTTON && wakeSlotHit > 0) {
    if (netSlot > 0 && wakeSlotHit == netSlot) {
      Serial.println("[wake] net key -> connect AP");
      if (connectSTA(STA_TIMEOUT_MS)) {
        showConnected();
        sleepHoldUntil = millis() + 300000UL;   // 留 5 分钟操作后台
      } else {
        startPortal();
      }
      return;
    }
    // 没配联网键时，动作键仍按旧行为联网：否则用户没有任何途径打开后台去配它。
    if (netSlot == 0) {
      Serial.println("[wake] no net key configured -> connect AP");
      if (connectSTA(STA_TIMEOUT_MS)) showConnected();
      else startPortal();
      return;
    }
    executeActionOnWake(wakeSlotHit);
    return;
  }

  // ④ 冷启动 / 认不出唤醒键：走完整联网流程（注册、后台、配网都需要）。
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

  // peek 模式（PIR 唤醒）：只显示缓存，不开射频；超时回睡。
  // 期间按键：联网键 → 连 AP 进后台；动作键 → 只开射频执行动作。
  // 必须在 WiFi 状态检查之前返回，否则未联网会被误判成「WiFi 掉线」去重连 / 开热点。
  if (peekMode) {
    pollButtons();
    if (peekActionSlot != 0) {
      int slot = peekActionSlot;
      peekActionSlot = 0;
      peekMode = false;
      if (netSlot > 0 && slot == netSlot) {
        Serial.println("[wake] net key -> connect AP");
        if (!connectSTA(STA_TIMEOUT_MS)) startPortal();
        else {
          showConnected();
          sleepHoldUntil = millis() + 300000UL;
        }
      } else if (netSlot == 0) {
        // 没配联网键：保持旧行为（按键即联网），保证后台始终可达。
        if (!connectSTA(STA_TIMEOUT_MS)) startPortal();
        else showConnected();
        onButtonPress(slot);
      } else {
        executeActionOnWake(slot);
      }
    }
    if (peekMode && (int32_t)(millis() - peekUntil) >= 0) {
      peekMode = false;
      Serial.println("[wake] peek timeout, back to sleep");
      enterDeepSleep();
    }
    return;
  }

  // 只开射频模式：本来就没打算关联 AP，不能走「WiFi 掉线 → 重连 / 开热点」。
  if (!radioOnly && WiFi.status() != WL_CONNECTED) {
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

  // 人体感应：有人立即亮屏并刷新计时；人走后按服务端给的秒数熄屏。
  // 没接感应（pirPin=-1）或后台设为常亮（screenOnSec=0）时这里什么都不做。
  pollPir();
  if (pirPin >= 0 && screenOnSec > 0 && !screenOff && !otaInProgress
      && millis() - lastPresenceAt > (uint32_t)screenOnSec * 1000UL) {
    sleepScreen();
  }

  // 应用后台任务刚拉到的配置（非阻塞；没有新数据时立刻返回）。
  applyNetSnapshot();
  // 空闲时把还没缓存的页补齐，之后翻页全部命中本地缓存。
  schedulePrefetch();

#if defined(CONFIG_IDF_TARGET_ESP32C6)
  // 动作执行完（只开射频的那次唤醒）：停留一小会儿让人看清结果就回睡，
  // 不等 sleepSeconds。对电池机来说这是每次按键的耗电大头。
  if (actionSleepAt && (int32_t)(millis() - actionSleepAt) >= 0) {
    actionSleepAt = 0;
    Serial.println("[sleep] action done, back to sleep");
    enterDeepSleep(true);   // 静默入睡：不再画 Sleep 页、不多等 0.4 秒
  }
  // 从机电池休眠：按键/人在场会刷新 lastActivityAt；OTA 中或待自动更新时不睡。
  if (deviceRole == "slave" && sleepSeconds > 0 && !otaInProgress
      && !(autoUpdate && fwAvailable)
      && (int32_t)(millis() - sleepHoldUntil) > 0
      && millis() - lastActivityAt > (uint32_t)sleepSeconds * 1000UL) {
    enterDeepSleep();
  }
#endif

  // 空闲回首页（页面级配置）：超过 idleSeconds 没有按键就回到第 1 页。
  if (idleSeconds > 0 && currentPage != 1
      && millis() - lastActionAt > (uint32_t)idleSeconds * 1000UL) {
    lastActionAt = millis();
    switchPageLocal(1);
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
    // 放在联网之后打印：USB 原生串口在复位时会重新枚举，启动最早那几行常丢失。
    static const char *wakeNames[] = {"cold", "pir", "button", "timer"};
    Serial.printf("[boot] wake=%s slot=%d reset=%d\n",
                  wakeNames[wakeReason <= 3 ? wakeReason : 0], wakeSlotHit,
                  (int)esp_reset_reason());
    Serial.printf("online ip=%s rssi=%d heap=%u\n", WiFi.localIP().toString().c_str(),
                  WiFi.RSSI(), (unsigned)ESP.getFreeHeap());
  }
}
