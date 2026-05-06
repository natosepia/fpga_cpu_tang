# FPGA/RISC-V 自作CPU 開発環境構築手順書

Tang Nano 9K（Gowin GW1NR-9）を用いた RISC-V 自作 CPU 開発環境の構築手順。
VPS（Ubuntu 22.04）上でシミュレーション・合成を行い、Win11 実機で焼き込み・UART 確認を行う 2 層構成。

## 目次

1. [全体構成](#1-全体構成)
2. [VPS 側環境構築](#2-vps-側環境構築)
3. [Win11 側環境構築](#3-win11-側環境構築)
4. [VSCode 拡張設定](#4-vscode-拡張設定)
5. [プロジェクト構造の作成](#5-プロジェクト構造の作成)
6. [動作確認 — LED Lチカ](#6-動作確認--led-lチカ)
7. [ファイル転送（Syncthing）](#7-ファイル転送syncthing)
8. [TM1638 接続・検証](#8-tm1638-接続検証)
9. [トラブルシューティング](#9-トラブルシューティング)
10. [リファレンス](#10-リファレンス)

---

## 1. 全体構成

```
┌──────────────────────────────────────────────────────┐
│  VPS (Ubuntu 22.04)                                  │
│                                                      │
│  ┌─────────────────┐   ┌──────────────────────────┐  │
│  │ Icarus Verilog   │   │ OSS CAD Suite            │  │
│  │ (iverilog/vvp)   │   │ yosys → nextpnr → pack  │  │
│  │ シミュレーション │   │ 合成 → 配置配線 → .fs   │  │
│  └────────┬────────┘   └────────────┬─────────────┘  │
│           │ dump.vcd                │ pack.fs         │
│           ▼                         │                 │
│  VSCode WaveTrace                   │ Syncthing       │
│  (波形確認)                         ▼                 │
├─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─│
│  Win11                                               │
│  ┌──────────────────┐  ┌──────────────────────────┐  │
│  │ openFPGALoader   │  │ TeraTerm                 │  │
│  │ .fs → Tang Nano  │  │ UART 115200bps 確認      │  │
│  └──────────────────┘  └──────────────────────────┘  │
└──────────────────────────────────────────────────────┘
```

### ハードウェア構成

| 品目 | 用途 |
|------|------|
| Tang Nano 9K（GW1NR-9, 8640 LUT4） | FPGA本体 |
| 2.54mm ピンヘッダ 1x40 x2 | 自分でハンダ付け |
| ブレッドボード 830穴（SAD-101 / EIC-801等） | 外部回路 |
| TM1638 モジュール | 7セグ+LED+ボタン（デバッグ主力） |
| ジャンパ線 オス-メス 10本 | TM1638 接続 |
| ジャンパ線 オス-オス 10本 | ブレッドボード内配線 |

### Tang Nano 9K 主要ピンマップ

| 信号 | ピン番号 | 備考 |
|------|----------|------|
| クロック (27MHz) | 52 | PULL_MODE=UP |
| LED[0] - LED[5] | 10, 11, 13, 14, 15, 16 | オンボード6個、Low=点灯 |
| ボタン S1 | 3 | IO_TYPE=LVCMOS18（1.8V BANK） |
| ボタン S2 | 4 | IO_TYPE=LVCMOS18（JTAG兼用） |
| UART TX | 17 | BL702 経由で USB シリアル |
| UART RX | 18 | BL702 経由で USB シリアル |

### 合成パラメータ

| パラメータ | 値 |
|------------|-----|
| device | GW1NR-LV9QN88PC6/I5 |
| family | GW1N-9C |

---

## 2. VPS 側環境構築

### 2.1 Icarus Verilog のインストール

シミュレーション（論理検証）に使用する。

```bash
sudo apt update
sudo apt install -y iverilog
```

動作確認:

```bash
iverilog -V
```

`Icarus Verilog version 1x.x` のようなバージョンが表示されれば OK。

### 2.2 OSS CAD Suite のインストール

合成（yosys）・配置配線（nextpnr-himbaechel）・ビットストリーム生成（gowin_pack）に使用する。
Gowin EDA ではなく OSS CAD Suite を採用する理由: ライセンス申請不要、CLI 完結で VSCode Remote SSH と相性が良い、CI 自動化可能。Tang Nano 9K + RV32I/M 規模なら合成品質差は誤差。

#### 2.2.1 tarball のダウンロード

最新リリースを [GitHub Releases](https://github.com/YosysHQ/oss-cad-suite-build/releases) から取得する。
ファイル名パターン: `oss-cad-suite-linux-x64-YYYYMMDD.tgz`

```bash
# 最新リリースのダウンロード（日付部分は最新に読み替えること）
wget https://github.com/YosysHQ/oss-cad-suite-build/releases/download/2026-04-07/oss-cad-suite-linux-x64-20260407.tgz
```

> **NOTE**: リリース日は頻繁に更新される（ほぼ nightly）。
> https://github.com/YosysHQ/oss-cad-suite-build/releases/latest で最新を確認すること。

#### 2.2.2 展開

```bash
tar xzf oss-cad-suite-linux-x64-20260407.tgz -C ~/
```

`~/oss-cad-suite/` 配下にツール群が展開される。

#### 2.2.3 環境変数の設定

```bash
source ~/oss-cad-suite/environment
```

毎回 source するのが面倒な場合は `.bashrc` に追記する:

```bash
echo 'source ~/oss-cad-suite/environment' >> ~/.bashrc
```

#### 2.2.4 動作確認

```bash
yosys -V
```

```bash
nextpnr-himbaechel --version
```

```bash
gowin_pack --help
```

それぞれバージョンやヘルプが表示されれば OK。

---

## 3. Win11 側環境構築

### 3.1 openFPGALoader のインストール（MSYS2 経由）

生成した .fs ビットストリームを Tang Nano 9K に焼き込むために使用する。

#### 3.1.1 MSYS2 のインストール

1. [MSYS2 公式サイト](https://www.msys2.org/) からインストーラをダウンロード
2. インストーラを実行し、全てデフォルト設定で進める
3. インストール完了後、**UCRT64** 環境（`MSYS2 UCRT64` のショートカット）を起動

#### 3.1.2 openFPGALoader のインストール

UCRT64 ターミナルで以下を実行:

```bash
pacman -S mingw-w64-ucrt-x86_64-openFPGALoader
```

動作確認:

```bash
openFPGALoader --detect
```

（Tang Nano 9K を接続していない場合はエラーになるが、コマンド自体が認識されれば OK）

### 3.2 Zadig によるドライバ設定

openFPGALoader が Tang Nano 9K と通信するために、JTAG インターフェースのドライバを WinUSB に変更する必要がある。

> ### !!!!!!! 最重要注意事項 !!!!!!!
>
> **Interface 0（JTAG）のみ** WinUSB 化すること。
>
> **Interface 1（UART）は絶対に触らないこと。**
>
> Interface 1 のドライバを変更すると TeraTerm 等でシリアル通信ができなくなる。
> 復旧にはデバイスマネージャからの手動ドライバ再インストールが必要になり、非常に面倒。

#### 3.2.1 手順

1. [Zadig 公式サイト](https://zadig.akeo.ie/) から最新版をダウンロード
2. Tang Nano 9K を USB で接続
3. Zadig を起動
4. メニュー → **Options** → **List All Devices** にチェック
5. ドロップダウンから **JTAG Debugger (Interface 0)** を選択
6. ドライバを **WinUSB** に設定（矢印ボタンで選択）
7. **Replace Driver** をクリック
8. 1〜2分待つ

> **再確認**: ドロップダウンに「Interface 1」が見える場合があるが、**絶対に選択しない**。
> Interface 1 = UART = TeraTerm で使うシリアルポート。

### 3.3 TeraTerm のインストール

UART 経由の通信確認に使用する。Tang Nano 9K はオンボードの BL702 デバッガを経由して USB シリアル通信が可能。

1. [TeraTerm 公式](https://github.com/TeraTermProject/teraterm/releases) から最新版をダウンロード・インストール
2. 接続設定:
   - ポート: COM ポート（デバイスマネージャで確認）
   - ボーレート: **115200**
   - データビット: 8
   - パリティ: なし
   - ストップビット: 1
   - フロー制御: なし

---

## 4. VSCode 拡張設定

VPS に VSCode Remote SSH で接続して開発する。以下の拡張をインストール:

| 拡張名 | 用途 |
|--------|------|
| **WaveTrace** | .vcd 波形ファイルの可視化。シミュレーション結果を視覚的に確認 |
| **SystemVerilog - Language Support** | Verilog/SystemVerilog のシンタックスハイライト・補完 |

### インストール手順

1. VSCode の拡張機能パネル（Ctrl+Shift+X）を開く
2. 「WaveTrace」で検索 → インストール
3. 「SystemVerilog Language Support」で検索 → インストール

### WaveTrace の使い方

シミュレーション後に生成される `.vcd` ファイルをエクスプローラからクリックすると波形ビューアが開く。

---

## 5. プロジェクト構造の作成

```bash
mkdir -p /home/natosepia/project/fpga_cpu_tang/00_counter/src
mkdir -p /home/natosepia/project/fpga_cpu_tang/00_counter/tb
mkdir -p /home/natosepia/project/fpga_cpu_tang/00_counter/constraints
mkdir -p /home/natosepia/project/fpga_cpu_tang/01_uart/src
mkdir -p /home/natosepia/project/fpga_cpu_tang/01_uart/tb
mkdir -p /home/natosepia/project/fpga_cpu_tang/01_uart/constraints
mkdir -p /home/natosepia/project/fpga_cpu_tang/02_rv32i_core/src
mkdir -p /home/natosepia/project/fpga_cpu_tang/02_rv32i_core/tb
mkdir -p /home/natosepia/project/fpga_cpu_tang/02_rv32i_core/constraints
mkdir -p /home/natosepia/project/fpga_cpu_tang/03_rv32m_core/src
mkdir -p /home/natosepia/project/fpga_cpu_tang/03_rv32m_core/tb
mkdir -p /home/natosepia/project/fpga_cpu_tang/03_rv32m_core/constraints
```

完成後の構造:

```
fpga_cpu_tang/
├── docs/
│   └── 01_setup_guide.md      ← 本ドキュメント
├── 00_counter/                 ← 環境確認用（LED Lチカ）
│   ├── src/                    ← RTL ソース
│   ├── tb/                     ← テストベンチ
│   ├── constraints/
│   │   └── tangnano9k.cst     ← ピン制約
│   └── Makefile                ← sim / synth ターゲット
├── 01_uart/                    ← UART Hello World
│   ├── src/
│   ├── tb/
│   ├── constraints/
│   │   └── tangnano9k.cst
│   └── Makefile
├── 02_rv32i_core/              ← RV32I 本体
│   ├── src/
│   ├── tb/
│   ├── constraints/
│   │   └── tangnano9k.cst
│   └── Makefile
└── 03_rv32m_core/              ← M 拡張
    ├── src/
    ├── tb/
    ├── constraints/
    │   └── tangnano9k.cst
    └── Makefile
```

各サブプロジェクトの Makefile は `sim`（シミュレーション）と `synth`（合成〜ビットストリーム生成）の 2 ターゲットを持つ。

---

## 6. 動作確認 — LED Lチカ

`00_counter` プロジェクトで環境構築の完了を検証する。

### 6.1 RTL ソース

`00_counter/src/led.v`:

```verilog
module led (
    input  wire       sys_clk,    // 27MHz オンボードクロック
    input  wire       sys_rst_n,  // リセット（S1ボタン、Low=リセット）
    output reg  [5:0] led         // オンボード LED x6（Low=点灯）
);

    reg [23:0] counter;

    // 27MHz / 13,500,000 = 0.5秒周期
    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n)
            counter <= 24'd0;
        else if (counter < 24'd13_499_999)
            counter <= counter + 1'b1;
        else
            counter <= 24'd0;
    end

    // 0.5秒ごとに LED パターンをローテーション
    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n)
            led <= 6'b111110;
        else if (counter == 24'd13_499_999)
            led[5:0] <= {led[4:0], led[5]};
        else
            led <= led;
    end

endmodule
```

### 6.2 テストベンチ

`00_counter/tb/led_tb.v`:

```verilog
`timescale 1ns / 1ps

module led_tb;

    reg        sys_clk;
    reg        sys_rst_n;
    wire [5:0] led;

    led uut (
        .sys_clk(sys_clk),
        .sys_rst_n(sys_rst_n),
        .led(led)
    );

    // 27MHz クロック生成（周期 ≈ 37ns）
    initial sys_clk = 0;
    always #18.5 sys_clk = ~sys_clk;

    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, led_tb);

        // リセット
        sys_rst_n = 0;
        #100;
        sys_rst_n = 1;

        // 適当な時間シミュレーション（全 LED 回転を見るには長時間必要）
        #1_000_000;

        $display("Simulation finished.");
        $finish;
    end

endmodule
```

### 6.3 ピン制約ファイル

`00_counter/constraints/tangnano9k.cst`:

```
// Tang Nano 9K ピン制約
// デバイス: GW1NR-LV9QN88PC6/I5

// クロック（27MHz オンボード水晶）
IO_LOC  "sys_clk" 52;
IO_PORT "sys_clk" PULL_MODE=UP;

// リセットボタン（S1）
// S1 は BANK0（1.8V）に接続されている
IO_LOC  "sys_rst_n" 3;
IO_PORT "sys_rst_n" PULL_MODE=UP IO_TYPE=LVCMOS18;

// オンボード LED x6（active low: Low で点灯）
IO_LOC  "led[0]" 10;
IO_LOC  "led[1]" 11;
IO_LOC  "led[2]" 13;
IO_LOC  "led[3]" 14;
IO_LOC  "led[4]" 15;
IO_LOC  "led[5]" 16;
```

### 6.4 Makefile

`00_counter/Makefile`:

```makefile
# Tang Nano 9K — LED Lチカ
# デバイス: GW1NR-LV9QN88PC6/I5 / family: GW1N-9C

DEVICE   = GW1NR-LV9QN88PC6/I5
FAMILY   = GW1N-9C
TOP      = led
SRC      = src/led.v
TB       = tb/led_tb.v
CST      = constraints/tangnano9k.cst
BUILD    = build

# ─── シミュレーション ───
.PHONY: sim
sim:
	mkdir -p $(BUILD)
	iverilog -o $(BUILD)/sim.out $(TB) $(SRC)
	cd $(BUILD) && vvp sim.out
	@echo "波形ファイル: $(BUILD)/dump.vcd"
	@echo "VSCode WaveTrace で開いて確認すること"

# ─── 合成 → 配置配線 → ビットストリーム生成 ───
.PHONY: synth
synth:
	mkdir -p $(BUILD)
	yosys -p "read_verilog $(SRC); synth_gowin -top $(TOP) -json $(BUILD)/$(TOP).json"
	nextpnr-himbaechel --json $(BUILD)/$(TOP).json \
		--write $(BUILD)/$(TOP)_pnr.json \
		--device $(DEVICE) \
		--vopt family=$(FAMILY) \
		--vopt cst=$(CST)
	gowin_pack -d $(FAMILY) -o $(BUILD)/$(TOP).fs $(BUILD)/$(TOP)_pnr.json
	@echo "ビットストリーム生成完了: $(BUILD)/$(TOP).fs"
	@echo "Win11 に転送して openFPGALoader で焼き込むこと"

# ─── クリーン ───
.PHONY: clean
clean:
	rm -r $(BUILD) 2>/dev/null || true

.PHONY: help
help:
	@echo "make sim   — Icarus Verilog でシミュレーション実行"
	@echo "make synth — yosys + nextpnr + gowin_pack で .fs 生成"
	@echo "make clean — ビルド成果物を削除"
```

### 6.5 動作確認手順

#### Step 1: VPS でシミュレーション

```bash
cd /home/natosepia/project/fpga_cpu_tang/00_counter
make sim
```

`build/dump.vcd` が生成される。VSCode で開いて波形を確認。

#### Step 2: VPS で合成

```bash
cd /home/natosepia/project/fpga_cpu_tang/00_counter
make synth
```

`build/led.fs` が生成される。

#### Step 3: .fs を Win11 に転送

Syncthing で自動同期（後述）、または手動で scp:

```bash
scp user@vps:/home/natosepia/project/fpga_cpu_tang/00_counter/build/led.fs C:\fpga\
```

#### Step 4: Win11 で焼き込み

MSYS2 UCRT64 ターミナルで:

```bash
openFPGALoader -b tangnano9k led.fs
```

#### Step 5: 確認

Tang Nano 9K の LED が順番に点灯（ローテーション）すれば環境構築完了。
S1 ボタンを押すとリセットされ、LED パターンが初期状態に戻る。

---

## 7. ファイル転送（Syncthing）

VPS → Win11 の .fs ファイル転送に Syncthing を使用する。
合成のたびに手動で scp するのは非効率なため、ビルド成果物を自動同期させる。

### 7.1 VPS 側

```bash
sudo apt install -y syncthing
```

起動:

```bash
syncthing
```

Web UI（デフォルト: `http://127.0.0.1:8384`）にアクセスし、同期フォルダとして `fpga_cpu_tang` を追加する。

### 7.2 Win11 側

1. [Syncthing 公式](https://syncthing.net/) から Windows 版をダウンロード
   - または [SyncthingWindowsSetup](https://github.com/Bill-Stewart/SyncthingWindowsSetup) を使用
2. インストール後、Web UI（`http://127.0.0.1:8384`）を開く
3. VPS のデバイス ID を追加（**Add Remote Device**）
4. 共有フォルダを設定

> **TIPS**: Syncthing はフォルダ全体を同期するため、.vcd ファイル等の大きな中間成果物を
> `.stignore` で除外しておくと転送量を抑えられる。

`.stignore` の例:

```
// シミュレーション成果物（大きいため除外）
*.vcd
// Python キャッシュ
__pycache__
// 中間ファイル（.fs のみ同期したい場合）
*.out
*.json
!constraints/**
```

---

## 8. TM1638 接続・検証

TM1638 モジュールは RISC-V 自作 CPU のデバッグ主力として使用する。

### 8.1 TM1638 モジュールの概要

| 機能 | 数量 | CPU デバッグでの用途 |
|------|------|----------------------|
| 7セグメントディスプレイ | 8桁 | ALU 演算結果・PC 値の 16 進表示 |
| 個別 LED | 8個 | レジスタ値や PC のビット表示 |
| プッシュボタン | 8個 | シングルステップ実行、リセット、レジスタ選択 等 |

### 8.2 通信仕様

TM1638 は SPI ライクな 3 線式インターフェース:

| 信号 | 方向 | 説明 |
|------|------|------|
| STB | FPGA → TM1638 | チップセレクト（Low=アクティブ） |
| CLK | FPGA → TM1638 | クロック |
| DIO | 双方向 | データ入出力 |

電源は VCC（5V）と GND の 2 本。合計 5 本の接続が必要。

### 8.3 電圧レベルに関する注意

| 項目 | 電圧 |
|------|------|
| TM1638 公称動作電圧 | 5V ±10% |
| Tang Nano 9K GPIO（BANK 1/2） | 3.3V（LVCMOS33） |
| Tang Nano 9K GPIO（BANK 0/3） | 1.8V |

> **重要**: TM1638 は公称 5V だが、赤/緑 LED モジュールであれば 3.3V でも動作する実績がある。
> ただし公式仕様外のため、以下に留意すること:
>
> - 青色 LED モジュールの場合は LED の順方向電圧（≈3V）との余裕がなく、表示が暗い or 点灯しない可能性がある
> - 安定動作を求める場合は VCC に 5V を供給し、信号線（STB/CLK/DIO）にレベルシフタ（例: 74AHCT125）を挟む
> - まずは 3.3V 直結で試し、問題があればレベルシフタを追加する方針で OK

### 8.4 配線

ジャンパ線（オス-メス）で Tang Nano 9K のピンヘッダと TM1638 モジュールを接続する。
使用するピンは BANK 1/2 の 3.3V GPIO から任意に選択可能。

配線例（ピン番号は自由に変更可能）:

| TM1638 側 | Tang Nano 9K ピン | 信号 |
|-----------|-------------------|------|
| STB       | 25                | チップセレクト |
| CLK       | 26                | クロック |
| DIO       | 27                | データ I/O |
| VCC       | 5V（USBから供給） | 電源 |
| GND       | GND               | グランド |

> **NOTE**: Tang Nano 9K の 5V 出力は USB バスパワーから取得可能。
> ピンヘッダの VCC/5V ピンを使用すること。

### 8.5 制約ファイルへの追記

```
// TM1638 接続（ピン番号は配線に合わせて変更）
IO_LOC  "tm1638_stb" 25;
IO_PORT "tm1638_stb" IO_TYPE=LVCMOS33;
IO_LOC  "tm1638_clk" 26;
IO_PORT "tm1638_clk" IO_TYPE=LVCMOS33;
IO_LOC  "tm1638_dio" 27;
IO_PORT "tm1638_dio" IO_TYPE=LVCMOS33 PULL_MODE=UP;
```

### 8.6 参考リソース

TM1638 の Verilog ドライバ実装は以下のリポジトリが参考になる:

- [alangarf/tm1638-verilog](https://github.com/alangarf/tm1638-verilog) — 基本的な Verilog ドライバ
- [mangakoji/TM1638_LED_KEY_DRV](https://github.com/mangakoji/TM1638_LED_KEY_DRV) — LED/キー両対応ドライバ

---

## 9. トラブルシューティング

### yosys で `synth_gowin` が見つからない

OSS CAD Suite の environment を source していない可能性がある。

```bash
source ~/oss-cad-suite/environment
```

### nextpnr で `ERROR: Unconstrained IO` が出る

トップモジュールの全てのポートに対して `.cst` ファイルでピン割り当てが必要。
未使用ポートがある場合は RTL 側から削除するか、制約ファイルに追記する。

### openFPGALoader で `No cable found` が出る

1. Zadig で Interface 0 を WinUSB に変更したか確認
2. USB ケーブルがデータ通信対応か確認（充電専用ケーブルでは認識しない）
3. MSYS2 UCRT64 ターミナルから実行しているか確認（通常の cmd.exe では PATH が通っていない）

### TeraTerm でシリアルポートが見つからない

Zadig で **Interface 1 を変更してしまった** 可能性がある。
デバイスマネージャで「ユニバーサル シリアル バス デバイス」→ 該当デバイスを右クリック → ドライバの更新 → 「コンピューターを参照してドライバーを検索」→ 「コンピューター上の利用可能なドライバーの一覧から選択」→ USB シリアルデバイス を選択して復旧する。

### LED が全く光らない

1. Tang Nano 9K の LED は **active low**（Low 出力で点灯）。初期値が全 High だと消灯状態
2. ビットストリーム(.fs)の書き込みが正常に完了したか確認
3. 制約ファイルのピン番号が正しいか確認

---

## 10. リファレンス

### 公式ドキュメント

- [Tang Nano 9K — Sipeed Wiki](https://wiki.sipeed.com/hardware/en/tang/Tang-Nano-9K/Nano-9K.html)
- [OSS CAD Suite — GitHub](https://github.com/YosysHQ/oss-cad-suite-build)
- [Project Apicula（Gowin FPGA bitstream docs）](https://github.com/YosysHQ/apicula)
- [nextpnr-himbaechel Gowin Wiki](https://github.com/YosysHQ/apicula/wiki/Nextpnr%E2%80%90Himbaechel-Gowin)
- [openFPGALoader](https://github.com/trabucayre/openFPGALoader)
- [openFPGALoader インストールガイド](https://trabucayre.github.io/openFPGALoader/guide/install.html)

### チュートリアル

- [Lushay Labs — Tang Nano 9K Getting Setup](https://learn.lushaylabs.com/getting-setup-with-the-tang-nano-9k/)
- [Lushay Labs — Tang Nano 9K Debugging & UART](https://learn.lushaylabs.com/tang-nano-9k-debugging/)

### ツール

- [Zadig — USB ドライバインストーラ](https://zadig.akeo.ie/)
- [TeraTerm](https://github.com/TeraTermProject/teraterm/releases)
- [Syncthing](https://syncthing.net/)
- [MSYS2](https://www.msys2.org/)
