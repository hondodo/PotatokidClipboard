# Potatokid ESP32-S3 传感器小屏 — 原理图草稿 v1

本目录是根据 `esp_devices/README.md` 的接线约定和用户提供的模块图片生成的 **KiCad 原理图 + 网表**，
设计目标是导入嘉立创 EDA 专业版后继续画 PCB。

> 状态：草稿。已做括号配对、符号引用、网表/标签一致性校验；本机未安装 KiCad/Eeschema，
> 没有真正打开过 KiCad，导入后请在嘉立创 EDA 里跑一次 ERC 并人工复核。

## 文件

| 文件 | 说明 |
|---|---|
| `potatokid_esp_v1.kicad_sch` | KiCad 8 原理图（A3，自定义模块符号，78 条带标签连线） |
| `potatokid_esp_v1.net` | KiCad 网表（19 个元件 / 23 个网络），可单独导入或用于核对 |
| `potatokid_esp_v1.kicad_pro` | KiCad 工程文件 |
| `bom.csv` | 元件清单草稿 |
| `generate_schematic.py` | 生成脚本；改接线后重跑即可，UUID 固定可复现 |

## 嘉立创 EDA 导入步骤（专业版）

1. 打开嘉立创 EDA 专业版 → 开始页 → **导入** → **导入 KiCad**；
2. 选择 `potatokid_esp_v1.kicad_sch`（或整个 `.kicad_pro` 工程），确认导入；
3. 导入后先检查：所有模块符号是否完整、网络标签是否保留、有没有丢失的引脚；
4. 给每个模块符号关联实际封装（本草稿故意留空 `Footprint`，避免用错封装）：
   - OLED 模块：35.4 × 33.5 mm，4Pin 2.54 mm 单排针，SH1106 IIC；
   - INMP441 / MAX98357 / 按键 / PIR / 433：按你实际买到的模块_pin 间距量一下再选封装；
   - ESP32-S3 开发板：按手中板子的排针位置选 2.54 mm 排针/板对板封装；
5. 跑 ERC，处理 `GAIN` 悬空、`PIR_OUT` 未接 MCU 这两个**预期未连接项**；
6. 确认后执行「原理图转 PCB」。

## 接线表（来源：esp_devices/README.md）

| 网络 | 连接到 |
|---|---|
| `3V3` | ESP32 `3V3`、OLED `VCC`、INMP441 `VDD`、MAX98357 `SD`、8 个按键 `VCC`、PIR `VCC`、433 `VCC`、C3/C4 |
| `5V` | ESP32 `5V`、MAX98357 `VIN`、C1/C2 |
| `GND` | 所有模块 GND，INMP441 `L/R` 也接 GND（左声道） |
| `OLED_SCL` / `OLED_SDA` | GPIO9 / GPIO8 |
| `MIC_SCK` / `MIC_WS` / `MIC_SD` | GPIO14 / GPIO15 / GPIO16 |
| `AMP_BCLK` / `AMP_LRC` / `AMP_DIN` | GPIO17 / GPIO18 / GPIO47 |
| `BTN1`~`BTN8` | GPIO4/5/6/7/10/11/12/13，按键低电平有效（固件 `INPUT_PULLUP`） |
| `RF433_DATA` | GPIO21 |
| `SPK+` / `SPK-` | MAX98357 BTL 差分输出 → 4Ω/8Ω 喇叭，两端都不能接地 |
| `PIR_OUT` | PIR 输出，**暂未接到 MCU**：GPIO7 已被按键 4 占用；请选一个空闲 RTC GPIO(0~21，避开 14~18/21、8/9、19/20) 后在嘉立创里补一根线 |

## 明确的未接/可选项

- **MAX98357 `GAIN` 悬空** = 9 dB（接 GND 15 dB，接 VDD 3 dB）。
- **C1~C4 是可选去耦**：模块自带滤波，只有长线/满功率/弱 USB 供电导致重启时才需要焊。
- **PIR 是可选模块**，图片是 33×24 mm、3Pin（VCC/GND/OUT），README 说 OUT 高电平=有人。
- OLED 实物 4Pin 顺序不一定是 VCC/GND/SCL/SDA；原理图按功能命名，PCB 封装请按手中模块丝印确认。

## 修改方式

编辑 `generate_schematic.py` 里的 `add_symbol()` / `add_component()` 数据，然后：

```bash
python generate_schematic.py
```

会覆盖生成 `.kicad_sch` / `.net` / `.kicad_pro` / `bom.csv`。
