#!/usr/bin/env python3
"""Generate a KiCad schematic + netlist for the Potatokid ESP32-S3 sensor hub.

Sources:
  - esp_devices/README.md (authoritative pin assignment)
  - module photos supplied by the user (OLED / INMP441 / MAX98357 / buttons / PIR)

Run: python generate_schematic.py
Output: potatokid_esp_v1.kicad_sch, potatokid_esp_v1.net, potatokid_esp_v1.kicad_pro, bom.csv
"""

from __future__ import annotations

import csv
import uuid
from datetime import datetime
from pathlib import Path

HERE = Path(__file__).resolve().parent
PROJECT = "potatokid_esp_v1"
ROOT_UUID = str(uuid.uuid5(uuid.NAMESPACE_DNS, PROJECT + "/root"))


def u(key: str) -> str:
    return str(uuid.uuid5(uuid.NAMESPACE_DNS, PROJECT + "/" + key))


def q(value: object) -> str:
    s = str(value).replace("\\", "\\\\").replace('"', '\\"')
    return '"' + s + '"'


def num(value: float) -> str:
    return ("%g" % value)


# ---------------------------------------------------------------------------
# Symbol definitions
# ---------------------------------------------------------------------------

SYMBOLS: dict[str, dict] = {}


def add_symbol(key: str, ref_prefix: str, value: str, pins: list[tuple[str, str]],
               side: str = "left", width: float = 30.48) -> None:
    part = key.split(":")[-1]
    height = max(10.16, 2.54 * len(pins) + 5.08)
    x = -width / 2 - 2.54 if side == "left" else width / 2 + 2.54
    angle = 0 if side == "left" else 180
    pin_rows = []
    for i, (name, pin_number) in enumerate(pins):
        y = height / 2 - 2.54 - i * 2.54
        pin_rows.append((name, pin_number, y))
    SYMBOLS[key] = {
        "part": part,
        "ref_prefix": ref_prefix,
        "value": value,
        "width": width,
        "height": height,
        "side": side,
        "x": x,
        "angle": angle,
        "pins": pin_rows,
    }


def render_symbol(key: str) -> str:
    s = SYMBOLS[key]
    part = s["part"]
    w, h = s["width"], s["height"]
    x, angle = s["x"], s["angle"]
    out = []
    out.append(f'(symbol {q(key)} (pin_names (offset 1.016)) (exclude_from_sim no) '
               f'(in_bom yes) (on_board yes)')
    out.append(f'  (property "Reference" {q(s["ref_prefix"])} (at 0 {num(h / 2 + 2.54)} 0) '
               f'(effects (font (size 1.27 1.27))))')
    out.append(f'  (property "Value" {q(s["value"])} (at 0 {num(-h / 2 - 2.54)} 0) '
               f'(effects (font (size 1.27 1.27))))')
    out.append(f'  (property "Footprint" "" (at 0 0 0) (effects (font (size 1.27 1.27)) (hide yes)))')
    out.append(f'  (property "Datasheet" "" (at 0 0 0) (effects (font (size 1.27 1.27)) (hide yes)))')
    out.append(f'  (symbol {q(part + "_0_1")}')
    out.append(f'    (rectangle (start {num(-w / 2)} {num(h / 2)}) '
               f'(end {num(w / 2)} {num(-h / 2)}) '
               f'(stroke (width 0.254) (type default)) (fill (type background)))')
    out.append('  )')
    out.append(f'  (symbol {q(part + "_1_1")}')
    for name, pin_number, y in s["pins"]:
        out.append(f'    (pin passive line (at {num(x)} {num(y)} {angle}) (length 2.54)')
        out.append(f'      (name {q(name)} (effects (font (size 1.016 1.016))))')
        out.append(f'      (number {q(pin_number)} (effects (font (size 1.016 1.016))))')
        out.append('    )')
    out.append('  )')
    out.append(')')
    return "\n".join(out)


# ---------------------------------------------------------------------------
# Components: (ref, symbol key, value, origin x/y, pin->net map)
# ---------------------------------------------------------------------------

add_symbol("Local:ESP32S3_DevKit", "U", "ESP32-S3 DevKit", [
    ("3V3", "3V3"), ("GND", "GND"), ("5V", "5V"),
    ("GPIO4", "GPIO4"), ("GPIO5", "GPIO5"), ("GPIO6", "GPIO6"), ("GPIO7", "GPIO7"),
    ("GPIO10", "GPIO10"), ("GPIO11", "GPIO11"), ("GPIO12", "GPIO12"), ("GPIO13", "GPIO13"),
    ("GPIO8_SDA", "GPIO8"), ("GPIO9_SCL", "GPIO9"),
    ("GPIO14_SCK", "GPIO14"), ("GPIO15_WS", "GPIO15"), ("GPIO16_SD", "GPIO16"),
    ("GPIO17_BCLK", "GPIO17"), ("GPIO18_LRC", "GPIO18"), ("GPIO47_DIN", "GPIO47"),
    ("GPIO21_433", "GPIO21"),
], side="right", width=40.64)

add_symbol("Local:OLED_SH1106_4P", "J", "1.3in OLED SH1106 4Pin IIC", [
    ("VCC", "1"), ("GND", "2"), ("SCL", "3"), ("SDA", "4"),
])

add_symbol("Local:INMP441", "J", "INMP441 MEMS microphone", [
    ("VDD", "1"), ("GND", "2"), ("L/R", "3"), ("SCK", "4"), ("WS", "5"), ("SD", "6"),
])

add_symbol("Local:MAX98357", "J", "MAX98357 I2S amplifier", [
    ("VIN", "1"), ("GND", "2"), ("BCLK", "3"), ("LRC", "4"), ("DIN", "5"),
    ("SD", "6"), ("GAIN", "7"), ("SPK+", "8"), ("SPK-", "9"),
])

add_symbol("Local:Button3P", "SW", "Tactile switch module", [
    ("VCC", "1"), ("GND", "2"), ("OUT", "3"),
])

add_symbol("Local:PIR3P", "J", "PIR motion sensor (optional)", [
    ("VCC", "1"), ("GND", "2"), ("OUT", "3"),
])

add_symbol("Local:RF433_3P", "J", "433MHz receiver (reserved)", [
    ("VCC", "1"), ("GND", "2"), ("DATA", "3"),
])

add_symbol("Local:Speaker2P", "J", "Speaker 4-8 ohm", [
    ("+", "1"), ("-", "2"),
])

add_symbol("Local:C_Polarized", "C", "Electrolytic capacitor", [("1", "1"), ("2", "2")], width=20.32)
add_symbol("Local:C_Ceramic", "C", "Ceramic capacitor", [("1", "1"), ("2", "2")], width=20.32)

COMPONENTS: list[dict] = []


def add_component(ref: str, key: str, value: str, x: float, y: float,
                  pin_nets: dict[str, str | None]) -> None:
    COMPONENTS.append({"ref": ref, "key": key, "value": value,
                       "x": x, "y": y, "pin_nets": pin_nets})


add_component("U1", "Local:ESP32S3_DevKit", "ESP32-S3 DevKit", 70, 100, {
    "3V3": "3V3", "GND": "GND", "5V": "5V",
    "GPIO4": "BTN1", "GPIO5": "BTN2", "GPIO6": "BTN3", "GPIO7": "BTN4",
    "GPIO10": "BTN5", "GPIO11": "BTN6", "GPIO12": "BTN7", "GPIO13": "BTN8",
    "GPIO8": "OLED_SDA", "GPIO9": "OLED_SCL",
    "GPIO14": "MIC_SCK", "GPIO15": "MIC_WS", "GPIO16": "MIC_SD",
    "GPIO17": "AMP_BCLK", "GPIO18": "AMP_LRC", "GPIO47": "AMP_DIN",
    "GPIO21": "RF433_DATA",
})

add_component("J1", "Local:OLED_SH1106_4P", "1.3in OLED SH1106 4Pin IIC", 175, 60, {
    "1": "3V3", "2": "GND", "3": "OLED_SCL", "4": "OLED_SDA",
})

add_component("J2", "Local:INMP441", "INMP441", 175, 115, {
    "1": "3V3", "2": "GND", "3": "GND", "4": "MIC_SCK", "5": "MIC_WS", "6": "MIC_SD",
})

add_component("J3", "Local:MAX98357", "MAX98357", 175, 180, {
    "1": "5V", "2": "GND", "3": "AMP_BCLK", "4": "AMP_LRC", "5": "AMP_DIN",
    "6": "3V3", "7": None, "8": "SPK+", "9": "SPK-",
})

for i, gpio in enumerate(["BTN1", "BTN2", "BTN3", "BTN4", "BTN5", "BTN6", "BTN7", "BTN8"]):
    col = i // 4
    row = i % 4
    add_component(f"SW{i + 1}", "Local:Button3P", "Button " + str(i + 1),
                  290 + col * 70, 45 + row * 35,
                  {"1": "3V3", "2": "GND", "3": gpio})

add_component("J4", "Local:PIR3P", "PIR (optional)", 290, 190, {
    "1": "3V3", "2": "GND", "3": "PIR_OUT",
})

add_component("J5", "Local:RF433_3P", "433MHz RX", 290, 230, {
    "1": "3V3", "2": "GND", "3": "RF433_DATA",
})

add_component("J6", "Local:Speaker2P", "Speaker 4-8R", 205, 255, {
    "1": "SPK+", "2": "SPK-",
})

add_component("C1", "Local:C_Polarized", "100uF opt", 380, 215, {"1": "5V", "2": "GND"})
add_component("C2", "Local:C_Ceramic", "100nF opt", 380, 235, {"1": "5V", "2": "GND"})
add_component("C3", "Local:C_Polarized", "10uF opt", 380, 255, {"1": "3V3", "2": "GND"})
add_component("C4", "Local:C_Ceramic", "100nF opt", 380, 275, {"1": "3V3", "2": "GND"})

# ---------------------------------------------------------------------------
# Netlist
# ---------------------------------------------------------------------------

NETS: dict[str, list[tuple[str, str]]] = {}
for comp in COMPONENTS:
    for pin_name, net in comp["pin_nets"].items():
        if net:
            NETS.setdefault(net, []).append((comp["ref"], pin_name))


def render_netlist() -> str:
    now = datetime.now().strftime("%Y-%m-%dT%H:%M:%S")
    out = ['(export (version "E")', '  (design',
           f'    (source {q(PROJECT + ".kicad_sch")})',
           f'    (date {q(now)})',
           f'    (tool {q("Eeschema 8.0")})',
           '    (sheet (number "1") (name "/") (tstamps "/"))',
           '  )', '  (components']
    for comp in COMPONENTS:
        key = comp["key"]
        out.append(f'    (comp (ref {q(comp["ref"])})')
        out.append(f'      (value {q(comp["value"])})')
        out.append('      (footprint "")')
        out.append(f'      (libsource (lib {q(key.split(":")[0])}) '
                   f'(part {q(key.split(":")[-1])}) (description ""))')
        out.append('      (sheetpath (names "/") (tstamps "/"))')
        out.append(f'      (tstamps {q(u("comp/" + comp["ref"]))})')
        out.append('    )')
    out.append('  )')
    out.append('  (nets')
    for code, (name, nodes) in enumerate(sorted(NETS.items()), start=1):
        out.append(f'    (net (code "{code}") (name {q(name)})')
        for ref, pin in nodes:
            out.append(f'      (node (ref {q(ref)}) (pin {q(pin)}) (pintype "passive"))')
        out.append('    )')
    out.append('  )')
    out.append(')')
    return "\n".join(out) + "\n"


# ---------------------------------------------------------------------------
# Schematic
# ---------------------------------------------------------------------------

def render_schematic() -> str:
    out = []
    out.append(f'(kicad_sch (version 20231120) (generator {q("eeschema")})')
    out.append(f'  (uuid {q(ROOT_UUID)})')
    out.append('  (paper "A3")')
    out.append('  (lib_symbols')
    for key in sorted(SYMBOLS):
        out.append(render_symbol(key))
    out.append('  )')

    # Wires and global labels for every connected pin
    for comp in COMPONENTS:
        s = SYMBOLS[comp["key"]]
        for name, pin_number, y_rel in s["pins"]:
            net = comp["pin_nets"].get(name)
            if net is None:
                net = comp["pin_nets"].get(pin_number)
            if not net:
                continue
            x_end = comp["x"] + s["x"]
            y_end = comp["y"] + y_rel
            x_outer = x_end + (-5.08 if s["side"] == "left" else 5.08)
            out.append('  (wire (pts (xy %s %s) (xy %s %s)) '
                       '(stroke (width 0) (type default)) (uuid %s))'
                       % (num(x_end), num(y_end), num(x_outer), num(y_end),
                          q(u("wire/" + comp["ref"] + "/" + name))))
            out.append('  (label %s (at %s %s 0) '
                       '(effects (font (size 1.27 1.27)) (justify left bottom)) (uuid %s))'
                       % (q(net), num(x_outer), num(y_end),
                          q(u("label/" + comp["ref"] + "/" + name))))

    # Notes
    notes = [
        "Potatokid ESP32-S3 sensor hub - schematic draft v1",
        "Source: esp_devices/README.md; module pinout from seller photos.",
        "All module VCC/GND follow the README: OLED/INMP441/PIR/433 -> 3V3, MAX98357 VIN -> 5V.",
        "MAX98357 SD must be tied to 3V3 (module has internal pull-down). GAIN left open = 9dB.",
        "INMP441 L/R tied to GND (left channel). Speaker is BTL differential: never tie either terminal to GND.",
        "Buttons are active-low with INPUT_PULLUP: pressed = 0V. Do not feed 5V into any GPIO.",
        "PIR_OUT is intentionally unassigned: GPIO7 is button slot 4. Pick a free RTC GPIO (0-21) in JLCEDA.",
        "Capacitors C1-C4 are optional; modules already have on-board decoupling.",
        "Before PCB: assign footprints, run ERC, and verify the board header pin order against your physical board.",
    ]
    for i, line in enumerate(notes):
        out.append('  (text %s (at 20 %s 0) '
                   '(effects (font (size 1.27 1.27)) (justify left top)) (uuid %s))'
                   % (q(line), num(252 + i * 4.5), q(u("note/" + str(i)))))

    # Symbol instances
    for comp in COMPONENTS:
        s = SYMBOLS[comp["key"]]
        ox, oy = comp["x"], comp["y"]
        h = s["height"]
        ref_y = oy - h / 2 - 2.54
        val_y = oy + h / 2 + 2.54
        out.append(f'  (symbol (lib_id {q(comp["key"])}) (at {num(ox)} {num(oy)} 0) (unit 1)')
        out.append('    (exclude_from_sim no) (in_bom yes) (on_board yes) (dnp no)')
        out.append(f'    (uuid {q(u("instance/" + comp["ref"]))})')
        out.append(f'    (property "Reference" {q(comp["ref"])} (at {num(ox)} {num(ref_y)} 0) '
                   f'(effects (font (size 1.27 1.27))))')
        out.append(f'    (property "Value" {q(comp["value"])} (at {num(ox)} {num(val_y)} 0) '
                   f'(effects (font (size 1.27 1.27))))')
        out.append(f'    (property "Footprint" "" (at {num(ox)} {num(oy)} 0) '
                   f'(effects (font (size 1.27 1.27)) (hide yes)))')
        out.append(f'    (property "Datasheet" "" (at {num(ox)} {num(oy)} 0) '
                   f'(effects (font (size 1.27 1.27)) (hide yes)))')
        for name, pin_number, _ in s["pins"]:
            out.append(f'    (pin {q(pin_number)} (uuid {q(u("pin/" + comp["ref"] + "/" + name))}))')
        out.append(f'    (instances (project {q(PROJECT)} '
                   f'(path {q("/" + ROOT_UUID)} (reference {q(comp["ref"])}) (unit 1))))')
        out.append('  )')

    out.append(f'  (sheet_instances (path "/" (page "1")))')
    out.append('  (embedded_fonts no)')
    out.append(')')
    return "\n".join(out) + "\n"


def render_project() -> str:
    import json
    data = {
        "meta": {"filename": PROJECT + ".kicad_pro", "version": 1},
        "boards": [],
        "cvpcb": {"equivalence_files": []},
        "erc": {"erc_exclusions": []},
        "libraries": {"pinned_footprint_libs": [], "pinned_symbol_libs": []},
        "net_settings": {"classes": [{"name": "Default"}]},
        "schematic": {"legacy_lib_dir": "", "legacy_lib_list": []},
        "sheets": [[ROOT_UUID, "Root"]],
        "text_variables": {},
    }
    return json.dumps(data, indent=2, ensure_ascii=False) + "\n"


def write_bom() -> None:
    with (HERE / "bom.csv").open("w", newline="", encoding="utf-8-sig") as fh:
        writer = csv.writer(fh)
        writer.writerow(["Ref", "Value", "Description", "Note"])
        for comp in COMPONENTS:
            note = ""
            if comp["ref"] == "J4":
                note = "Optional; assign a free RTC GPIO for PIR_OUT"
            elif comp["ref"] == "J3":
                note = "GAIN open = 9dB; SD tied to 3V3"
            elif comp["ref"].startswith("C"):
                note = "Optional decoupling"
            writer.writerow([comp["ref"], comp["value"], comp["key"], note])


def main() -> None:
    (HERE / (PROJECT + ".kicad_sch")).write_text(render_schematic(), encoding="utf-8")
    (HERE / (PROJECT + ".net")).write_text(render_netlist(), encoding="utf-8")
    (HERE / (PROJECT + ".kicad_pro")).write_text(render_project(), encoding="utf-8")
    write_bom()
    print("generated:", PROJECT + ".kicad_sch", PROJECT + ".net",
          PROJECT + ".kicad_pro", "bom.csv")
    print("nets:", len(NETS), "components:", len(COMPONENTS))


if __name__ == "__main__":
    main()
