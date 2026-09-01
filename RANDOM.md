# UTL Gamma+ Hybrid Inverter Brain Replacement — Full Project Context v5

## Complete A-Z Reference — Paste Into New Chat To Continue

### (v5 adds: Chapter 1 harness built + Chapter 2 Phase 1 tests passed. v4 corrected CN2A pin numbering.)

---

## PROGRESS LOG (read this first when resuming)

**Chapter 1 — CN2A Breakout Harness: ✅ DONE**
(unchanged — see below)

**Chapter 2 — Phase 1 Voltage & Signal Tests: ✅ DONE — all passed**
(unchanged — see below)

**Chapter 3 — Arduino IDE + ESP32-S3 Setup + Base FUGU Flash: ✅ DONE**

- Firmware compiled and flashed successfully. All four boot messages confirmed
  on Serial Monitor: Serial Initialized → FLASH MEMORY: STORAGE INITIALIZED →
  FLASH MEMORY: SAVED DATA LOADED → MPPT HAS INITIALIZED. No crash, no boot loop.
- Serial output stops after boot messages. Expected, not a bug: loop() calls
  Read_Sensors() first, which blocks waiting on the ADS1015 over I2C. Nothing is
  on the bus yet. Resolves when real I2C hardware is attached, and disappears
  entirely once sensing code is rewritten (ADS1015 already ruled out in Ch.2).

**Next immediate step:** Chapter 4 — wire 16×2 LCD to I2C (GPIO 8 SDA / GPIO 9 SCL),
run I2C scanner to confirm address (0x27 vs 0x3F), get text on the physical screen.
Still no UTL board, still no battery.

---

## 0. CHANGELOG

### v3 → v4 (August 2026) — CN2A PIN NUMBERING CORRECTED

**What was wrong:** v3's CN2A table had a phantom pin — "SENS1" — listed as pin 4, between MAINS SENS (pin 3) and B- (pin 5). This pin does not exist on the real board. It was carried over from earlier documentation without being verified against the physical hardware.

**How this was caught and proven (three independent checks, all agreeing):**

1. **Direct label count on the dead brain daughter-board photo** — counted 23 labels total (O/P SYNC through BATT SENS), not 24. No "SENS1" label appears anywhere in the sequence.
2. **User's own earlier multimeter measurement** — 3.3V was measured and logged as "pin 12" at the time. Under the old (wrong) table, pin 12 = GND, which is nonsensical — GND cannot read 3.3V. Under the corrected table below, pin 12 = 3U3, which matches perfectly.
3. **Physical continuity test on the last physical pin position (24th hole)** — probed against R48 (the resistor feeding BATT SENS from the board's internal circuit). Result: **no beep — isolated, no connection.** This proves the 24th physical pin position is genuinely unused (NC), and BATT SENS — which does have a live trace to R48 — sits one position earlier, at pin 23.

**Conclusion:** There is no "SENS1" pin. Starting from pin 5 onward, every single pin in the old table shifts down by exactly one position. The correct board has 23 active/used pins and 1 unused (NC) pin at the very end (pin 24).

**Impact:** CN2A pinout table (old Section 4), current sensing table (old Section 5), wiring plan (old Section 10), CN2A breakout table (old Section 11), and all Phase 1/5 test/connection instructions (old Section 12) all needed pin-number updates. **No physical rework was needed** — the CN2A breakout harness (Chapter 1) had not yet been built when this was caught, so nothing needs to be re-wired. Chapter 1 restarts fresh with the corrected numbers below.

---

### v2 → v3 (earlier correction, still valid)

| Item                 | v2 said        | v3 (verified/confirmed)                                    | Source                                                        |
| -------------------- | -------------- | ---------------------------------------------------------- | ------------------------------------------------------------- |
| EG8010A package      | "DIP-16 only"  | **LQFP32 ONLY — no DIP-16 version exists**                 | Verified via EG Micro / LCSC / distributor datasheet listings |
| EG8010A qty & method | 3× bare DIP-16 | **2× LQFP32 chip + 5× QFP32-to-DIP32 0.8mm adapter board** | User's final shopping list — confirmed correct                |
| LCD                  | 20×4 I2C       | **16×2 I2C backpack — CONFIRMED in hand**                  | Direct confirmation from Jafar                                |

---

## 1. WHO I AM

- Electronics student in Bangladesh (Dhaka / Savar area)
- Intermediate level — understands concepts when explained clearly
- Goal: Build a working hybrid solar inverter system that properly protects battery
- Shopping locations: Elephant Road Dhaka, RoboticsBD online store, AliExpress
- **All parts have been purchased and are in hand as of August 2026**

---

## 2. THE ORIGINAL PROBLEM

Setup before this project:

- 40A solar MPPT charge controller
- 200Ah 12V flat tubular lead-acid battery
- IPS/UPS inverter

All three connected to battery terminals in parallel (passive bus). This causes constant battery micro-cycling because no intelligence coordinates who supplies what. Battery absorbs and releases current constantly even when solar could cover the load alone — shortens battery life significantly.

---

## 3. THE MACHINE — UTL GAMMA+ 1KVA/12V

UTL Gamma+ 1KVA/12V rMPPT Solar PCU hybrid inverter whose **brain/control board got damaged**. All other boards confirmed healthy.

---

### Board 1 — MPPT Buck Converter Board

- **Label:** GAMMA+1KVA/12V, GPPA_C_B_25194
- Has toroidal inductor (500uH), filter electrolytic capacitors, MOSFETs on heatsink
- **Terminals:** SPV+ (solar panel +), SPV- (solar panel -), BATT-, CAP-
- Converts solar panel voltage down to battery charging voltage
- Receives PWM control signal from brain via **CN2A pin 20 (MPPT DRV)**
- **Back of board:** Shunt resistor **SNT1 (R001 = 0.001Ω = 1mΩ)** for current sensing
- SNT1 two wires go to CN2A pins **A- (pin 9) and A+ (pin 10)** on main inverter board
- Shunt carries RAW millivolt signal — no amplifier between shunt and CN2A

---

### Board 2 — Main Inverter H-Bridge Board

- 7 power MOSFETs (IRLB series) on large heatsink
- 3 large electrolytic capacitors (40V, 105°C rated)
- Relay (TSD BY A.Z, 15A, 50Hz) for grid/inverter changeover
- **CN2A** — 24-pin brain connector (23 active signal pins + 1 unused/NC), fully labeled on PCB silk screen
- Own gate driver ICs (IR2110) already built in — DO NOT add another set
- Own 5V regulator — confirmed CN2A **pin 13** = 4.95V ✅
- Own 3.3V regulator — confirmed CN2A **pin 12** = 3.3V ✅
- Voltage sensing, AC grid sensing, relay driver, fan driver all built in
- **Back of board:** Second shunt near R83/R91/R92/R93 — solar negative to H-bridge path
- Second shunt wires go to CN2A **B- (pin 4) and B+ (pin 5)**
- **Board barcode:** GPPXCHU01KA027691, Date: 1/08/2021

---

### Board 3 — Small MOSFET Daughter Board

- Part numbers: MA-GU-071, SPP-BCXX-XXX112
- 6 MOSFETs total: 2 larger (battery connection) + 4 smaller
- Charging path switcher / synchronous rectifier
- Operates independently — needs NO brain signals
- Healthy and untouched

**Transformer:** Available and healthy.

---

## 4. CN2A CONNECTOR — COMPLETE VERIFIED PINOUT

24 physical pin positions. **23 are active signals, pin 24 is unused (NC) — physically confirmed via continuity test, August 2026.**

```
PIN 1:  O/P SYNC      → AC output voltage sync signal
PIN 2:  I/P SYNC      → Grid input phase sync signal
PIN 3:  MAINS SENS    → Grid AC presence (already conditioned, logic level)
PIN 4:  B-            → Shunt 2 negative (solar→H-bridge current, raw mV)
PIN 5:  B+            → Shunt 2 positive (solar→H-bridge current, raw mV)
PIN 6:  SPV S         → Solar panel voltage sense (already scaled, logic level)
PIN 7:  SHORT CKT-1   → Short circuit fault input 1
PIN 8:  SHORT CKT-2   → Short circuit fault input 2
PIN 9:  A-            → Shunt 1 negative (solar→fuse current, raw mV)
PIN 10: A+            → Shunt 1 positive (solar→fuse current, raw mV)
PIN 11: GND           → Ground
PIN 12: 3U3           → 3.3V rail (CONFIRMED: 3.3V present)
PIN 13: +5V           → 5V rail (CONFIRMED: 4.95V present)
PIN 14: H1            → High-side gate drive, H-bridge leg 1
PIN 15: L1            → Low-side gate drive, H-bridge leg 1
PIN 16: H2            → High-side gate drive, H-bridge leg 2
PIN 17: L2            → Low-side gate drive, H-bridge leg 2
PIN 18: GND           → Ground
PIN 19: RLY DRV       → Relay driver (grid/inverter changeover)
PIN 20: MPPT DRV      → PWM signal TO MPPT board (active-HIGH)
PIN 21: SP-           → Solar panel negative (signal level)
PIN 22: SP+           → Solar panel positive (signal level)
PIN 23: BATT SENS     → Battery voltage sense (has live trace to R48 — confirmed used)
PIN 24: NC            → Not Connected — physically isolated, confirmed by continuity test
```

**⚠️ There is no pin named "SENS1." This label appeared in earlier documentation drafts but does not exist on the physical board. Do not wire anything expecting to find it.**

---

## 5. CURRENT SENSING ARCHITECTURE — CRITICAL

**2 shunt resistors exist on the boards. Both feed RAW millivolt signals directly into CN2A. No amplifier exists between shunt and CN2A pins.**

| Shunt            | Location            | Measures               | CN2A Pins               | Signal |
| ---------------- | ------------------- | ---------------------- | ----------------------- | ------ |
| SNT1 (R001, 1mΩ) | MPPT board back     | Solar→fuse current     | A- (pin 9), A+ (pin 10) | Raw mV |
| Shunt 2          | Inverter board back | Solar→H-bridge current | B- (pin 4), B+ (pin 5)  | Raw mV |

At 30A through 1mΩ = only 30mV differential. ESP32 ADC cannot read this accurately. Original dsPIC had built-in differential ADC. **Solution: 2× INA219 I2C modules.**

**ACS712 is NOT needed — confirmed removed from project permanently.**

---

## 6. REPLACEMENT SOLUTION OVERVIEW

### Main Brain

ESP32-S3-WROOM-1-N16R8 UNO DevKit

### Base Firmware — AngeloCasi FUGU Arduino MPPT

- **Correct link:** https://github.com/AngeloCasi/FUGU-ARDUINO-MPPT-FIRMWARE
- Arduino IDE based — beginner friendly
- Lead-acid battery support built in ✅
- WiFi telemetry built in
- 16×2 LCD support (LiquidCrystal_I2C library) — **this build uses 16×2, confirmed**
- EEPROM settings storage
- **Plan:** use as skeleton only. Current-sensing filtering and MPPT control-loop logic will be rewritten in Chapter 9 to fl4p-level quality (proper noise filtering, tighter PID) while keeping AngeloCasi's lead-acid charging algorithm and easy Arduino IDE structure.

### WRONG firmware links — do not use these:

- ❌ `https://github.com/fl4p/Fugu2` — most complex, different hardware entirely
- ❌ `https://github.com/fl4p/fugu-mppt-firmware` — complete rewrite, lithium focused, ESP-IDF based, no lead-acid support

### Inverter SPWM Generator

**EG8010A IC — LQFP32 package (VERIFIED — this chip has never been made in DIP-16).**

- Generates H1/L1/H2/L2 pure sine SPWM signals
- 50Hz, dead time built in hardware
- Powered from **CN2A pin 13** (5V)
- Logic outputs → **CN2A pins 14, 15, 16, 17** (H1, L1, H2, L2)
- UTL's existing IR2110 gate drivers handle amplification
- Must be soldered onto a QFP32-to-DIP32 0.8mm-pitch adapter board before it can be breadboarded
- **LIMITATION:** Cannot sync to grid phase — 50-100ms break-before-make switching only. Acceptable for 1KVA home use.

---

## 7. KNOWN RISKS

| Risk                                          | Severity | Mitigation                                                                                                                                               |
| --------------------------------------------- | -------- | -------------------------------------------------------------------------------------------------------------------------------------------------------- |
| ESP32 power from 3.3V pin 12                  | HIGH     | Power from **pin 13** (5V) via VIN instead — UTL 3.3V reg only rated ~100mA                                                                              |
| FUGU needs heavy rewriting                    | HIGH     | Plan for 3-4 month project, not weekend build                                                                                                            |
| No grid phase sync                            | MEDIUM   | 50-100ms break-before-make with dead time                                                                                                                |
| MPPT PWM frequency unknown                    | HIGH     | Scope **pin 20**, start at 25kHz and monitor MOSFET temp                                                                                                 |
| Missing protection logic                      | HIGH     | Short circuit, undervoltage, overcurrent = 300-400 lines, not afterthought                                                                               |
| ADS1015 may not be needed                     | MEDIUM   | Measure pins 6, 23 voltage range first (Phase 1 Test 2)                                                                                                  |
| LQFP32 hand-soldering                         | MEDIUM   | 0.8mm pitch — use flux + fine tip iron or hot air; buy spare chips/adapters (already planned)                                                            |
| Pin-numbering errors from undocumented boards | HIGH     | **Never trust a written pinout without physically verifying against the real board first** — this exact mistake already happened once (v3→v4 correction) |

---

## 8. FINAL PARTS LIST — ALL PURCHASED AND IN HAND ✅

### RoboticsBD (ordered online)

| #   | Item                                 | Qty    | Notes                                                                                       |
| --- | ------------------------------------ | ------ | ------------------------------------------------------------------------------------------- |
| 1   | ESP32-S3-WROOM-1-N16R8 UNO DevKit    | 1      | Main brain. Must be S3, not plain ESP32/C3/C6                                               |
| 2   | INA219 I2C current sensor module     | 2      | One per shunt pair. Replaces ACS712                                                         |
| 3   | ADS1015 I2C ADC module               | 1      | For voltage sensing (pins 6, 23). Not ADS1115. May end up optional — Phase 1 Test 2 decides |
| 4   | **16×2 LCD with I2C backpack**       | 1      | CONFIRMED IN HAND. 4-pin only (VCC, GND, SDA, SCL)                                          |
| 5   | 12MHz Crystal HC-49S                 | 4      | For EG8010A oscillator circuit                                                              |
| 6   | Breadboard 830-point (full size)     | 1      |                                                                                             |
| 7   | Dupont jumper wires male-female 20cm | 1 pack | For breadboard prototyping                                                                  |
| 8   | USB Type-C cable                     | 1      | For flashing ESP32-S3                                                                       |

### Elephant Road (bought in person)

| #   | Item                                        | Qty         | Notes                                                     |
| --- | ------------------------------------------- | ----------- | --------------------------------------------------------- |
| 9   | **EG8010A LQFP32 chip**                     | 2           | VERIFIED: LQFP32 is the only package this chip exists in  |
| 10  | **QFP32-to-DIP adapter PCB** (0.8mm pitch)  | 5           | Required for breadboarding the LQFP32 chip                |
| 11  | Male pin header strip 40-pin                | 1           | For the adapter boards                                    |
| 12  | 22pF ceramic capacitor                      | 10          | For 12MHz crystal loading                                 |
| 13  | 100nF ceramic capacitor (104)               | 10          | Decoupling caps for ICs                                   |
| 14  | Resistor kit: 470Ω, 1kΩ, 4.7kΩ, 10kΩ, 100kΩ | 10 pcs each | For EG8010A config pins, pull-ups, dividers               |
| 15  | Tactile push button 6mm                     | 6           | MODE / UP / DOWN / SELECT + 2 spares                      |
| 16  | 2.54mm pin header strip male + female       | 2 sets      | For CN2A connector and general use                        |
| 17  | 24-pin female DuPont housing + crimp pins   | 1 set       | For clean CN2A connection                                 |
| 18  | 15-22Ω, 1W resistor                         | 1           | Phase 1 Test 1 load resistor — needed, was missing before |
| 19  | 10A automotive blade fuse + inline holder   | 1 + 1 spare | Battery protection — mandatory before any power-on test   |

### Permanently Removed / Not Used

- ~~ACS712~~ — boards have built-in shunts, INA219 used instead
- ~~EG8010A DIP-16~~ — does not exist
- ~~"SENS1" pin~~ — does not exist on the physical board (v4 correction)

### LCD Firmware Note (CONFIRMED)

```cpp
LiquidCrystal_I2C lcd(0x27, 16, 2);  // 16x2 CONFIRMED
```

---

## 9. HARD RULES — NEVER BREAK

- EG8010A → **LQFP32 ONLY** — never EGS002 (has built-in IR2110, conflicts with UTL)
- ACS712 → **NOT needed** — permanently removed
- ESP32 → **S3 specifically** — not plain ESP32, C3, or C6
- Power ESP32 from **CN2A pin 13 (5V) via VIN** — NOT from pin 12 (3.3V)
- INA219 → need **2 modules** — one per shunt pair
- INA219 #1 → address 0x40 (default) → reads A+/A- (**pins 10, 9**)
- INA219 #2 → address 0x41 (bridge A0 to VCC) → reads B+/B- (**pins 5, 4**)
- LCD → **16×2 confirmed in hand**
- **CN2A has 23 active pins + 1 unused (pin 24, NC).** There is no "SENS1" pin — never assume it exists.
- **Never wire from a written pinout without physically verifying against the real board first.**

---

## 10. WIRING PLAN

```
Battery (+) → 10A fuse → breadboard 12V rail
Battery (-) → breadboard GND rail
                    │
                    ↓
             UTL inverter board
                    │
             CN2A 24-pin connector (23 active + 1 NC)
                    │
         DuPont breakout wires (labeled)
                    │
      ┌─────────────┼─────────────┐
      │             │             │
  ESP32-S3      LCD 16×2      INA219 ×2
  (breadboard)  (I2C)         (I2C)

ESP32-S3
    ├── INA219 #1 (I2C) → A+ (pin 10), A- (pin 9)
    ├── INA219 #2 (I2C) → B+ (pin 5),  B- (pin 4)
    ├── ADS1015 (I2C)   → voltage sense pins
    ├── LCD 16×2 (I2C)  → display
    ├── 4 buttons       → mode selection
    ├── CN2A pin 3      → MAINS SENS (grid detection input)
    ├── CN2A pin 19     → RLY DRV (relay control output)
    ├── CN2A pin 20     → MPPT DRV (MPPT PWM output)
    ├── CN2A pin 13     → 5V power via VIN
    └── CN2A pin 11/18  → GND

All I2C devices share:
    SDA → ESP32 GPIO 8
    SCL → ESP32 GPIO 9

EG8010A (LQFP32 on QFP32-to-DIP adapter, from CN2A pin 13, 5V)
    ├── 12MHz crystal + 22pF caps
    ├── CN2A pin 14 (H1)
    ├── CN2A pin 15 (L1)
    ├── CN2A pin 16 (H2)
    └── CN2A pin 17 (L2)
```

---

## 11. CN2A BREAKOUT PIN ASSIGNMENT (FOR BREADBOARD LABELING)

| CN2A Pin | Label       | Wire Color Suggestion | Priority                          |
| -------- | ----------- | --------------------- | --------------------------------- |
| 11       | GND         | Black                 | First                             |
| 18       | GND         | Black                 | First                             |
| 13       | +5V         | Red                   | First                             |
| 12       | 3.3V        | Orange                | First                             |
| 20       | MPPT DRV    | Yellow                | High                              |
| 19       | RLY DRV     | Blue                  | High                              |
| 3        | MAINS SENS  | Green                 | High                              |
| 5        | B+          | White                 | High                              |
| 6        | SPV S       | Purple                | High                              |
| 9        | A-          | Grey                  | High                              |
| 10       | A+          | Brown                 | High                              |
| 4        | B-          | Pink                  | High                              |
| 23       | BATT SENS   | Grey/Brown stripe     | First (needed for Phase 1 Test 2) |
| 7        | SHORT CKT-1 | Red/Black             | Later                             |
| 8        | SHORT CKT-2 | Red/Black             | Later                             |
| 24       | NC          | —                     | Never — confirmed unused          |

**Batch A (build in Chapter 1 — power/sensing only, no gate/control signals yet):**
Pins 11, 18, 13, 12, 3, 5, 6, 9, 10, 4, 23 — 11 wires total.

**Batch B (build in Chapter 8, after firmware is flashed and tested standalone):**
Pins 1, 2, 7, 8, 14, 15, 16, 17, 19, 20, 21, 22.

---

## 12. BUILD SEQUENCE

### PHASE 1 — Test UTL Board First (Battery + Multimeter Only)

**Test 1 — 5V Rail Capacity:**
Connect 15-22Ω, 1W resistor between CN2A **pin 13** and **pin 11** (~300mA load).

- Stays above 4.5V → safe to power ESP32 from pin 13 ✅
- Drops below 4.5V → need external 5V buck converter from battery (LM2596 or XL4015)

**Test 2 — Sense Pin Voltage Range:**
Measure pins **6 (SPV S)** and **23 (BATT SENS)** vs GND with battery connected.

- Both read 0–3.3V → can skip ADS1015 for voltage, read direct GPIO
- Either reads above 3.3V → ADS1015 needed for protection

**Test 3 — INA219 Shunt Verification:**
Probe CN2A pins **9/10** (A-/A+) and **4/5** (B-/B+) differentially. Verify millivolt signal present.

---

### PHASE 2 — ESP32-S3 Alone (No UTL Board)

1. Install Arduino IDE from arduino.cc
2. Add ESP32 board support:
   - File → Preferences → Additional Board Manager URLs
   - Paste: `https://raw.githubusercontent.com/espressif/arduino-esp32/gh-pages/package_esp32_index.json`
   - Tools → Board → Board Manager → search ESP32 → install Espressif
3. Download FUGU from: https://github.com/AngeloCasi/FUGU-ARDUINO-MPPT-FIRMWARE
4. Open in Arduino IDE
5. Select: ESP32-S3 Dev Module
6. Connect USB-C, upload
7. Verify serial monitor starts without crashing
8. Verify LCD displays something
9. Confirm LCD line is: `LiquidCrystal_I2C lcd(0x27, 16, 2);`

---

### PHASE 3 — EG8010A Breadboard Test

1. Solder the LQFP32 EG8010A chip onto the QFP32-to-DIP32 adapter board (0.8mm pitch — flux, fine-tip iron, verify no bridges with continuity check before powering)
2. Solder 0.1" pin headers onto the adapter board
3. Wire EG8010A standalone with 5V power + 12MHz crystal + 22pF caps
4. Verify H1/L1/H2/L2 signals with multimeter BEFORE touching CN2A

---

### PHASE 4 — INA219 Test

Connect both INA219 modules to ESP32 I2C.
Write simple test sketch to read both addresses (0x40 and 0x41).
Verify readings before connecting to shunt pins.

---

### PHASE 5 — CN2A Connection

Connect in this strict order:

1. Power pins first: **11, 13, 18**
2. Sensing pins: **3, 4, 5, 9, 10**
3. Control pins last: **19, 20**
4. Gate signals last of all: **14, 15, 16, 17**

---

### PHASE 6 — Firmware Customization (Major Work)

- Calibrate INA219 scaling for UTL shunt values
- Calibrate voltage sense for UTL's existing dividers
- Find correct MPPT PWM frequency for UTL board (start 25kHz)
- Write protection logic (short circuit pins 7/8, undervoltage, overcurrent)
- Add relay logic (grid/inverter switching, break-before-make 50-100ms)
- Add mode selection (Hybrid / Solar Only / Grid Priority / Battery Saver)
- Add EEPROM storage for settings
- Hardware watchdog timer

---

## 13. OPERATING MODES TO IMPLEMENT

```
MODE 1: HYBRID (default)
→ Solar supplies load, battery fills gap only when needed
→ Grid charges battery at night

MODE 2: SOLAR ONLY
→ Solar + battery only, grid disconnected

MODE 3: GRID PRIORITY
→ Grid runs everything, solar charges battery only

MODE 4: BATTERY SAVER
→ Battery kicks in only when solar drops below threshold

EEPROM Settings:
→ Battery type (Tubular/AGM/Lithium)
→ Battery cutoff voltage (default 11.5V)
→ Float voltage (default 13.5V)
→ Absorption voltage (default 14.4V)
→ MPPT current limit
→ Grid charge ON/OFF
→ MPPT PWM frequency
```

---

## 14. CURRENT PROJECT STATUS

| Task                                                                           | Status                                                                                 |
| ------------------------------------------------------------------------------ | -------------------------------------------------------------------------------------- |
| Problem identified                                                             | ✅ Done                                                                                |
| Machine identified (UTL Gamma+ 1KVA/12V)                                       | ✅ Done                                                                                |
| Board architecture understood                                                  | ✅ Done                                                                                |
| Shunt resistors identified (R001, SNT1)                                        | ✅ Done                                                                                |
| INA219 selected over ACS712                                                    | ✅ Done                                                                                |
| Correct FUGU firmware identified (AngeloCasi)                                  | ✅ Done                                                                                |
| EG8010A package verified (LQFP32, not DIP-16)                                  | ✅ Done                                                                                |
| LCD size confirmed (16×2, not 20×4)                                            | ✅ Done                                                                                |
| All parts purchased and in hand                                                | ✅ Done                                                                                |
| **CN2A pinout physically verified — 23 active + 1 NC, "SENS1" does not exist** | ✅ Done                                                                                |
| Workbench safety setup (fuse, ESD, soldering tools)                            | ✅ Done                                                                                |
| CN2A breakout harness (Chapter 1)                                              | ✅ Done — built with premade jumper wires, continuity-checked                          |
| Phase 1 voltage tests (Chapter 2)                                              | ✅ Done — all 3 tests passed, ADS1015 and buck converter both ruled out as unnecessary |
| Arduino IDE + FUGU installed                                                   | ⏳ Pending — next step                                                                 |
| ESP32-S3 flashed and LCD working                                               | ⏳ Pending                                                                             |
| EG8010A soldered to adapter + breadboard test                                  | ⏳ Pending                                                                             |
| INA219 I2C test                                                                | ⏳ Pending                                                                             |
| CN2A full connection                                                           | ⏳ Pending                                                                             |
| Firmware customization                                                         | ⏳ Pending                                                                             |
| Protection logic                                                               | ⏳ Pending                                                                             |
| Full hybrid mode test                                                          | ⏳ Pending                                                                             |

---

## 15. KEY CONCEPTS ALREADY UNDERSTOOD — DO NOT RE-EXPLAIN

- Why passive bus causes battery cycling
- PWM and duty cycle as control mechanism
- Buck converter operation
- Battery internal EMF vs terminal voltage
- Why current not voltage is the control variable
- How MPPT chases load current to keep battery near zero net current
- Why two gate driver sets conflict
- Why EGS002 conflicts with UTL board
- Why ACS712 is not needed (built-in shunts exist)
- Why INA219 needed (raw mV signals, ESP32 ADC too noisy)
- Why power from pin 13 not pin 12
- Why EG8010A cannot do grid sync
- EG8010A is LQFP32 only, requires adapter board for breadboard use
- This is a 3-4 month development project not a weekend build
- Why AngeloCasi FUGU chosen as skeleton, fl4p-quality logic rewritten in later chapters
- **CN2A has 23 active pins + 1 NC pin — never trust an unverified pinout again**

---

## 16. NEXT IMMEDIATE ACTION

Rebuild CN2A breakout harness (Chapter 1) using the corrected pin numbers in Section 11.
Then run Phase 1 voltage tests (Chapter 2) with corrected pin numbers.
Then install Arduino IDE and download FUGU firmware (Chapter 3).

## 17. FIRMWARE / TOOLCHAIN REFERENCE (from Chapter 3)

### Verified working environment

- Arduino IDE 2.3.10, ESP32 Arduino core **3.3.11**
- Board Manager URL: https://espressif.github.io/arduino-esp32/package_esp32_index.json

### Tools menu settings (all required)

| Setting          | Value                                       |
| ---------------- | ------------------------------------------- |
| Board            | ESP32S3 Dev Module                          |
| USB CDC On Boot  | Enabled                                     |
| Flash Size       | 16MB                                        |
| PSRAM            | **OPI PSRAM** (NOT QSPI — N16R8 uses Octal) |
| Partition Scheme | 16M Flash (3MB APP/9.9MB FATFS)             |
| Upload Speed     | 921600                                      |

### Chip identity (confirmed by esptool)

ESP32-S3 QFN56 rev v0.2 · 8MB embedded PSRAM detected · MAC 84:FC:E6:59:28:AC
PSRAM detection confirms the OPI setting is correct.

### Build size baseline

949,670 bytes = 30% of app space · 48,844 bytes RAM = 14%. Ample headroom remaining.

### ⚠ UPLOAD QUIRK — board flashes on COM5, not COM4

The board changes COM port when entering download mode. Working sequence:
hold BOOT → tap RST → keep holding BOOT ~1s → release BOOT →
Tools→Port→**COM5** → click Upload.
Symptom if forgotten: "Failed to connect to ESP32-S3: No serial data received"
or "Could not open COM4, the port is busy or doesn't exist."

### Libraries installed

| Library           | Author                 | Note                                              |
| ----------------- | ---------------------- | ------------------------------------------------- |
| Blynk             | Volodymyr Shymanskyy   | modern version — needs TEMPLATE_ID defines        |
| LiquidCrystal I2C | **Frank de Brabander** | this fork has setBacklight() — confirmed compiles |
| Adafruit ADS1X15  | Adafruit               | + Adafruit BusIO dependency                       |

### FIVE CODE FIXES applied to stock AngeloCasi FUGU — all mandatory

1. **Pin remap.** Stock GPIO 27/33/32/34/35/19 collide with N16R8 internal
   flash/PSRAM/USB lines (per Espressif ESP32-S3 GPIO reference: GPIO26-32 = flash,
   GPIO33-37 = Octal PSRAM on any R8 module, GPIO19/20 = USB). Corrected:
   backflow_MOSFET 4 · buck_IN 5 · buck_EN 6 · ADC_ALERT 7 · TempSensor 1 · buttonBack 21
   (LED 2, FAN 16, buttonLeft 18, buttonRight 17, buttonSelect 23 were already safe)
2. **PWM API.** ledcSetup()+ledcAttachPin() removed in core 3.0+. Replaced with:
   `ledcAttach(buck_IN, pwmFrequency, pwmResolution);` and `ledcWrite(buck_IN, PWM);`
3. **Blynk defines.** Added above ALL includes (must precede BlynkSimpleEsp32.h):
   `#define BLYNK_TEMPLATE_ID "TMPL_PLACEHOLDER"`
   `#define BLYNK_TEMPLATE_NAME "FUGU MPPT"`
   Placeholders only — replace with real values if/when Blynk is actually set up.
4. **Real bug in stock code.** `pinMode(TS,INPUT)` → `pinMode(TempSensor,INPUT)`.
   TS is a float variable, not a pin; it resolved to GPIO 0 = the BOOT strapping pin.
5. **LCD init.** `lcd.begin()` → `lcd.begin(16,2)` — installed library version
   requires cols/rows arguments.

### Expected, ignorable

"WARNING: library LiquidCrystal I2C claims to run on avr architecture(s)" —
appears on every compile. Harmless; the library predates ESP32.

### Confirmed compatible (no change needed)

- I2C on GPIO 8 (SDA) / GPIO 9 (SCL) — these are already the ESP32-S3 Arduino
  core defaults, so Section 10's wiring plan needs no code change.
- lcd.setBacklight() exists in the installed library — 8_LCD_Menu.ino needs no edits.

---

_Project started: July 2026_
_All parts in hand: August 2026_
_Doc corrected v3 (EG8010A package + LCD size): August 2026_
_Doc corrected v4 (CN2A pinout — 23 active + 1 NC pin, physically verified): August 2026_
_Machine: UTL Gamma+ 1KVA/12V rMPPT Solar PCU_
_Brain: ESP32-S3 + AngeloCasi FUGU (heavily customized) + EG8010A (LQFP32)_
_Current sensing: 2× INA219 on-board shunts via I2C_
_Display: 16×2 LCD with I2C backpack_
_Status: Pinout verified — CN2A harness rebuild next_
