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
│  VSCode VaporView                   │ Syncthing       │
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

公式 Schematic `Tang_Nano_9K_3672_Schematic.pdf` で確認済み（[Sipeed Wiki](https://wiki.sipeed.com/hardware/en/tang/Tang-Nano-9K/Nano-9K.html) からリンク）。

| 信号 | ピン番号 | Schematic ラベル | 備考 |
|------|----------|-----------------|------|
| クロック (27MHz) | 52 | `PIN52_XTAL_IN` | PULL_MODE=UP |
| LED[0] - LED[5] | 10, 11, 13, 14, 15, 16 | `PIN10_IOL15A_LED1` 〜 | オンボード6個、Low=点灯 |
| ボタン S1 | 3 | `PIN3_IOT2A_BUTTON_S1_1V8` | IO_TYPE=LVCMOS18（BANK3 / 1.8V） |
| ボタン S2 | 4 | `PIN4_IOL5A_JTAG_SEL_S2_1V8` | IO_TYPE=LVCMOS18（JTAG_SEL 兼用） |
| UART TX | 17 | `PIN17_IOB2A_FPGA_TX` | デバッガ経由で USB シリアル（FTDI FT2232 または BL702、rev依存） |
| UART RX | 18 | `PIN18_IOB2B_FPGA_RX` | デバッガ経由で USB シリアル（FTDI FT2232 または BL702、rev依存） |

> **NOTE**: 公式 Schematic 上の左下「LED x 7」セクションラベルと回路実体（LED 6個）に食い違いがあるが、
> 回路を辿ると LED は **6個**（Schematic のラベル誤記の可能性が高い）。
> 本表の `LED[0]-LED[5]` 6個構成で問題ない想定。実機で焼いて 6個 全点灯することを最初の Lチカで確認する。

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

リリースは ほぼ nightly で更新されるため、日付決め打ちではなく最新タグを取得して落とす。
ダウンロード先は `~/tmp/` 等の作業ディレクトリ推奨（ホーム直下を散らかさない）:

```bash
mkdir -p ~/tmp && cd ~/tmp

# 最新リリースのタグ名を取得（例: "2026-05-09"）
LATEST=$(curl -s https://api.github.com/repos/YosysHQ/oss-cad-suite-build/releases/latest \
  | grep -oP '"tag_name":\s*"\K[^"]+')
# ファイル名側のフォーマット（例: "20260509"）
DATE_PACKED=$(echo "$LATEST" | tr -d '-')
echo "Downloading oss-cad-suite ${LATEST}"

wget "https://github.com/YosysHQ/oss-cad-suite-build/releases/download/${LATEST}/oss-cad-suite-linux-x64-${DATE_PACKED}.tgz"
```

サイズは ~680MB、回線次第で 1〜3 分。

> **NOTE**: 自動取得スクリプトが何らかの理由で動かない場合は、ブラウザで
> https://github.com/YosysHQ/oss-cad-suite-build/releases/latest を開いて手動でDLすること。

#### 2.2.2 展開

```bash
# 上記の DATE_PACKED が同じシェルで生きていない場合は、ファイル名を直接指定する
tar xzf oss-cad-suite-linux-x64-${DATE_PACKED}.tgz -C ~/
```

`-C ~/` で展開先をホームに固定するため、cwd が `~/tmp/` でも `~/oss-cad-suite/` 配下にツール群が展開される。展開後 ~2GB に膨らむため、ディスク残量に注意。

展開完了後、元の `.tgz`（679MB）は不要になるため削除可:

```bash
rm ~/tmp/oss-cad-suite-linux-x64-${DATE_PACKED}.tgz
```

#### 2.2.3 環境変数の設定

OSS CAD Suite は `environment` スクリプトを source することで yosys / nextpnr-himbaechel / gowin_pack を PATH に通す。動作確認のため、まず手動で source する:

```bash
source ~/oss-cad-suite/environment
```

> **重要**: `.bashrc` に `source ~/oss-cad-suite/environment` を追記することは **推奨しない**。理由:
>
> 1. 全シェル起動時にプロンプトに `⦗OSS CAD Suite⦘` プレフィックスが付き、常時表示される
> 2. PATH が常時上書きされ、普段使いのシェルが OSS CAD Suite 環境に汚染される
> 3. システム標準 Python と OSS CAD Suite 同梱 Python（3.11）の取り違え事故リスク
>
> 本書では **Makefile 内で必要時のみ一時 source する方式** を採用する（[6.4 Makefile](#64-makefile) 参照）。
> 2.2.4 / 2.2.5 の動作確認・依存追加は手動 source した状態で実施し、確認後 `exec bash` で抜けるか SSH を切断・再接続して、PATH をクリーンに戻す運用とする。

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

#### 2.2.5 apycula 依存ライブラリの追加（推奨）

`gowin_pack --help` 実行時に以下の警告が出る場合がある:

```
UserWarning: Numpy is not available, performance will be degraded.
UserWarning: Msgspec is not available, performance will be degraded.
```

これは apycula（gowin_pack の本体）が依存する Python パッケージ（numpy / msgspec / fastcrc）が OSS CAD Suite 同梱 Python に未インストールのため発生する。**警告のままでも動作する**が、合成パフォーマンスが低下するため、Phase 5 MMU 規模以降を見越して事前にインストールしておくと良い。

```bash
# OSS CAD Suite を一時 source した状態で（2.2.3 で source 済の前提）
python3 -m pip install numpy msgspec fastcrc

# pip 自体も古い場合（23.x → 26.x）アップグレードしておくと、egg DEPRECATION 警告も消える
python3 -m pip install --upgrade pip
```

`fastcrc` は apycula が `requires fastcrc, which is not installed` の依存解決エラーを出すため事前に追加する。

> **NOTE**: ここでのインストール先は `~/oss-cad-suite/lib/python3.11/site-packages/` で、OSS CAD Suite 同梱 Python 専用領域。
> プロジェクト側 `.venv` には入らない（gowin_pack はそちらを読みに行かないため、入れても意味がない）。
>
> インストール後、再度 `gowin_pack --help` を実行して警告が出ないことを確認する。
>
> OSS CAD Suite 自体を再展開した場合これらのパッケージは消えるため、再インストールが必要。上記スニペットを再現用として残しておくこと。

---

## 3. Win11 側環境構築

### 3.1 openFPGALoader のインストール（MSYS2 経由）

生成した .fs ビットストリームを Tang Nano 9K に焼き込むために使用する。

#### 3.1.1 MSYS2 のインストール

1. [MSYS2 公式サイト](https://www.msys2.org/) からインストーラをダウンロード
2. インストーラを実行し、全てデフォルト設定で進める
3. インストール完了後、**UCRT64** 環境（`MSYS2 UCRT64` のショートカット）を起動

> **NOTE（シェル識別の罠）**: MSYS2 のショートカットは 5 つあり、`MSYS2 UCRT64` と `MSYS2 MSYS` は
> **同じ濃い紫色のアイコンで紛らわしい**。**ファイル名末尾の "UCRT64"** を必ず確認すること。
> 起動後はターミナル左上のプロンプトに以下のように表示される:
>
> - `[user@host UCRT64 ~]` ← **正解**（緑色で `UCRT64` と表示）
> - `[user@host MSYS ~]` ← 誤起動（`pacman -S mingw-w64-ucrt-x86_64-...` でインストールしたコマンドの PATH が通らず `command not found` になる）
>
> | アイコン色 | シェル | 用途 |
> |----------|--------|------|
> | 赤 M | CLANG64 | Clang/LLVM ベース |
> | 緑 M | MINGW32 | 32bit |
> | 青 M | MINGW64 | GCC + msvcrt |
> | 紫 M | MSYS | UNIX 互換（PATH 別） |
> | 紫 M | **UCRT64** | GCC + UCRT（**本書で使用**） |

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

1. [Zadig 公式サイト](https://zadig.akeo.ie/) から最新版をダウンロード（執筆時点では Zadig 2.9）
   - ダウンロードした `.exe` を実行する際、SmartScreen が「認識されないアプリ」と警告するが、
     発行元欄が `Akeo Consulting`（Zadig 作者 Pete Batard の会社）であれば正規署名済みで安全。「実行」で進む。
2. Tang Nano 9K を USB で接続（Tang Nano 9K の電源 LED が点灯しているか先に確認）
3. Zadig を起動（初回はオンライン更新確認のダイアログが出るが、`No` で十分）
4. メニュー → **Options** → **List All Devices** にチェック
5. ドロップダウンから **`JTAG Debugger (Interface 0)`** を選択
   - **USB ID 表示欄が `0403 6010 00` であることを必ず確認**（VID=FTDI、PID=FT2232、末尾 `00`=Interface 0）
   - 別 rev で BL702 デバッガの場合は VID/PID が異なるため、ドロップダウンの表記名「JTAG Debugger (Interface 0)」と Interface 番号で識別する
6. 中央の矢印ボタンで右側ドライバを **WinUSB** に設定
7. **Replace Driver** をクリック
8. 「Installing Driver...」表示 → 通常 30秒〜2分、最大 5分待機
9. 「The driver was installed successfully.」ダイアログで完了

> **再確認**: ドロップダウンには `USB Receiver (Interface 0)` 等の **Logicool 製マウス/キーボードのレシーバ**が
> 紛れ込んで見えることがある。**`JTAG Debugger` と表記されている項目以外は絶対に選択しない**。
> 入力デバイスを誤って WinUSB 化するとマウス/キーボードが反応しなくなる事故になる。

#### 3.2.2 失敗時の復旧（Restore Original Driver）

Zadig には書き換え前のドライバへ戻す機能がある。誤って違うデバイスを WinUSB 化した場合の保険として覚えておく。

1. Zadig 画面の **Replace Driver / Reinstall Driver ボタンの右の `▼`** をクリック
2. メニューから **`Restore Original Driver`** を選択
3. ドロップダウンで対象デバイスを再選択 → Restore Original Driver 実行
4. 元のドライバ（FTDIBUS や標準 HID 等）に自動復旧

万一 Zadig で自力復旧できないケースの一般手順:

- **デバイスマネージャ → 該当デバイス右クリック → デバイスのアンインストール**（「ドライバを削除」にチェック）
  → 操作 → ハードウェア変更のスキャン で Windows 標準ドライバが自動再インストール
- **Windows のシステム復元ポイント**: 不安なら Replace Driver 前に手動作成（スタート → 「復元ポイント」検索）

#### 3.2.3 VCP（Virtual COM Port）有効化

FTDI デバッガ搭載の Tang Nano 9K の場合、**Interface 1（UART）は WinUSB 化しないが、COM ポートとして昇格させるための追加設定**が必要なことがある。

##### 症状
- Zadig で Interface 0 を WinUSB 化完了
- デバイスマネージャの「ユニバーサル シリアル バス コントローラー」配下に **`USB Serial Converter B`** が見える
- ただし「ポート (COM と LPT)」セクションに **`USB Serial Port (COMn)` が出現しない**

##### 原因
FTDI のドライバには `D2XX`（FTDIBUS、低レベルアクセス用）と `VCP`（Virtual COM Port、仮想シリアル）の2層がある。
`USB Serial Converter B` だけが見えて COM ポートが出ない場合、VCP レイヤーが無効化されている。

##### 対処
1. デバイスマネージャ → **`USB Serial Converter B`** を右クリック → **プロパティ**
2. **「詳細設定」タブ**（Advanced）を開く
3. **「VCP をロード」（Load VCP）** チェックボックスを **ON**
4. OK で閉じる
5. Tang Nano 9K の USB ケーブル抜き差し（or PC 再起動）
6. デバイスマネージャに **「ポート (COM と LPT)」** セクションが新規出現
7. 配下の **`USB Serial Port (COMn)`** の `n` の数字をメモ → TeraTerm で使用

BL702 デバッガ搭載 rev では VCP 設定不要で COM ポートが直接出る場合もある。COM ポートが既に見えている場合はこのステップは不要。

### 3.3 TeraTerm のインストール

UART 経由の通信確認に使用する。Tang Nano 9K はオンボードのデバッガ（FTDI FT2232 または BL702、ボード rev により異なる）を経由して USB シリアル通信が可能。

1. [TeraTerm 公式](https://github.com/TeraTermProject/teraterm/releases) から最新版をダウンロード・インストール
2. 接続設定:
   - ポート: COM ポート（デバイスマネージャで確認、3.2.3 で確認した COMn）
   - ボーレート: **115200**
   - データビット: 8
   - パリティ: なし
   - ストップビット: 1
   - フロー制御: なし

### 3.4 接続確認（Tang Nano 9K の生死確認）

Lチカ実装に進む前に、**Tang Nano 9K と Win11 の疎通**をここで確認しておくと、後で問題の切り分けが楽になる。

#### 3.4.1 Tang Nano 9K 接続時の動作確認

Tang Nano 9K を USB で Win11 に接続した時点で、**工場出荷時 demo bitstream が動作する** はず。観察ポイント:

- オンボードの LED 6個 のいずれかが点灯/点滅（最低限の生死確認）
- 電源 LED の点灯（給電 OK）

何も光らない場合の疑い:

- USB ケーブルが充電専用（データ通信非対応）
- USB ポート不良 / KVM スイッチ／USB ハブ経由の相性問題（[9. トラブルシューティング](#9-トラブルシューティング) 参照）
- ボード初期不良

#### 3.4.2 openFPGALoader で JTAG 疎通確認

MSYS2 UCRT64 ターミナルで以下を実行:

```bash
openFPGALoader --detect
```

**期待される出力**:

```
empty
No cable or board specified: using direct ft2232 interface
Jtag frequency : requested 6.00MHz   -> real 6.00MHz
index 0:
        idcode 0x100481b
        manufacturer Gowin
        family GW1N
        model  GW1N(R)-9C
        irlength 8
```

冒頭の `empty` と `No cable or board specified` は **正常な情報メッセージ**（cable 名を `--cable ft2232` 等で明示しない場合の通知）。重要なのは下部の `manufacturer Gowin` / `family GW1N` / `model GW1N(R)-9C` が出ていること。
これが出れば **JTAG 経路（Interface 0 / WinUSB）疎通 OK**。

エラーが出る場合（`No cable found` 等）は [9. トラブルシューティング](#9-トラブルシューティング) を参照。

#### 3.4.3 TeraTerm で UART 疎通確認

3.3 の設定通り **COMn / 115200 / 8N1 / フロー制御なし** で TeraTerm を接続。

- 接続成功 → 画面が無音でも OK（出荷時 demo が UART 出力を持っていなければ何も表示されない、それで正常）
- 文字化け → ボーレート不一致を疑う（再確認）

接続が完了すれば **UART 経路（Interface 1 / VCP）疎通 OK**。

これで Win11 側の関門 3 つ（USB 認識・JTAG 接続・UART 接続）すべてクリア。Lチカ実装に進める状態。

---

## 4. VSCode 拡張設定

VPS に VSCode Remote SSH で接続して開発する。以下の拡張をインストール:

| 拡張名 | 用途 |
|--------|------|
| **VaporView** | .vcd / .fst / .ghw 波形ファイルの可視化。シミュレーション結果を視覚的に確認 |
| **SystemVerilog - Language Support** | Verilog/SystemVerilog のシンタックスハイライト・補完 |

> **NOTE（VaporView 採用理由）**: 当初は WaveTrace を採用していたが、以下の理由で VaporView に切り替えた:
>
> 1. WaveTrace は信号値表示の文字が信号行の高さに対して上部見切れる問題があり、行高調整の設定が公式に存在しない
> 2. WaveTrace 公式サイト（wavetrace.io）は 2026年5月時点で 404 で、メンテナンス停滞の兆候
> 3. VaporView は **AGPL-3.0 OSS**、活発に更新（v1.5.2 / 2026年4月、631 commits）、行高調整・多彩な数値フォーマット・主副マーカー・FST/GHW 対応など機能豊富
>
> Phase 5 MMU 規模で VCD が肥大化した場合は FST 形式（バイナリ圧縮）に切り替え可能で、長期的にも VaporView が有利。

### 4.1 インストール手順

1. **VSCode を VPS に Remote SSH 接続した状態** で拡張機能パネル（`Ctrl+Shift+X`）を開く
2. 検索バーで `VaporView` を検索（拡張ID: `lramseyer.vaporview`）
3. 拡張機能ページ右上の「**Install in SSH: <ホスト名>**」ボタンをクリック（**ローカル側ではなくリモート側**にインストール）
4. 同様に `SystemVerilog Language Support` をリモート側にインストール

> **Remote SSH の罠**: VSCode 拡張は **ローカル / リモート別管理**。Remote SSH 接続中の拡張パネルには「Local」「SSH: <ホスト>」のセクションが分かれて表示される。
> `.vcd` は VPS 側に生成されるため、リモート側に VaporView をインストール必須。ローカル側だけでは `.vcd` を開けない。
>
> 必要要件: **VSCode 1.102.0 以上**。

### 4.2 動作確認

VSCode のエクスプローラから `00_counter/build/dump.vcd` をクリックして波形ビューアが開けば動作確認 OK。

NETLIST ペインに `led_tb / uut` のスコープ階層が表示されること、信号を選んで波形ペインに追加できることを確認。

> **詳細な操作方法**: VaporView の各種操作（信号追加・行高調整・数値フォーマット・マーカー・ズーム・WaveDrom コピー等）と Phase 1 RV32I 波形デバッグでの実践パターンは [02_vaporview_guide.md](02_vaporview_guide.md) を参照。

---

## 5. プロジェクト構造の作成

Phase 1 着手時点では `00_counter`（環境確認用 Lチカ）と `01_uart`（UART Hello World）のみ作成する。
RV32I／RV32M のディレクトリは Rule of Three の観点から、必要になった時点で同じパターンで掘る。

```bash
mkdir -p /home/natosepia/project/fpga_cpu_tang/00_counter/src
mkdir -p /home/natosepia/project/fpga_cpu_tang/00_counter/tb
mkdir -p /home/natosepia/project/fpga_cpu_tang/00_counter/constraints
mkdir -p /home/natosepia/project/fpga_cpu_tang/01_uart/src
mkdir -p /home/natosepia/project/fpga_cpu_tang/01_uart/tb
mkdir -p /home/natosepia/project/fpga_cpu_tang/01_uart/constraints
```

最終的な構造（参考、Phase 進行に応じて段階的に追加）:

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
// timescale は 1ps 精度。`#18.5`（1ns単位の小数遅延）は実装依存で丸められる
// ことがあるため、ピコ秒単位で記述して半周期 18500ps = 18.5ns を表現する。
`timescale 1ps / 1ps

module led_tb;

    reg        sys_clk;
    reg        sys_rst_n;
    wire [5:0] led;

    led uut (
        .sys_clk(sys_clk),
        .sys_rst_n(sys_rst_n),
        .led(led)
    );

    // 27MHz クロック生成（半周期 18500ps = 18.5ns）
    initial sys_clk = 0;
    always #18500 sys_clk = ~sys_clk;

    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, led_tb);

        // リセット（100,000ps = 100ns 保持）
        sys_rst_n = 0;
        #100_000;
        sys_rst_n = 1;

        // 1ms 相当（1,000,000,000ps）シミュレーション
        // 全 LED ローテーションは 0.5秒×6 = 3秒 必要なため、
        // 波形では「カウンタが進んでいること」までを確認する想定
        #1_000_000_000;

        $display("Simulation finished.");
        $finish;
    end

endmodule
```

### 6.3 ピン制約ファイル

`00_counter/constraints/tangnano9k.cst`:

```
# Tang Nano 9K ピン制約
# デバイス: GW1NR-LV9QN88PC6/I5

# クロック（27MHz オンボード水晶）
IO_LOC  "sys_clk" 52;
IO_PORT "sys_clk" PULL_MODE=UP;

# リセットボタン（S1）
# S1 は BANK0（1.8V）に接続されている
IO_LOC  "sys_rst_n" 3;
IO_PORT "sys_rst_n" PULL_MODE=UP IO_TYPE=LVCMOS18;

# オンボード LED x6（active low: Low で点灯）
IO_LOC  "led[0]" 10;
IO_LOC  "led[1]" 11;
IO_LOC  "led[2]" 13;
IO_LOC  "led[3]" 14;
IO_LOC  "led[4]" 15;
IO_LOC  "led[5]" 16;
```

> **NOTE（要実機検証）**: Gowin CST のコメントは `#` を使う（`//` は Apicula/nextpnr-himbaechel のパーサで未対応の可能性）。
> もし `//` で動作した場合は注釈を更新すること。
>
> **NOTE**: S1（pin 3 / IOT2A）／S2（pin 4 / IOL5A）は公式 Schematic `Tang_Nano_9K_3672` で確認済み。
> S1 は BANK3（1.8V）に接続されているため `IO_TYPE=LVCMOS18` 指定が必須。S2 は JTAG_SEL 兼用。

### 6.4 Makefile

`00_counter/Makefile`:

```makefile
# Tang Nano 9K — LED Lチカ
# デバイス: GW1NR-LV9QN88PC6/I5 / family: GW1N-9C

SHELL    := /bin/bash
OSS_ENV  := source $(HOME)/oss-cad-suite/environment

DEVICE   = GW1NR-LV9QN88PC6/I5
FAMILY   = GW1N-9C
TOP      = led
SRC      = src/led.v
TB       = tb/led_tb.v
CST      = constraints/tangnano9k.cst
BUILD    = build

# ─── シミュレーション（iverilog は apt 版、source 不要） ───
.PHONY: sim
sim:
	mkdir -p $(BUILD)
	iverilog -o $(BUILD)/sim.out $(TB) $(SRC)
	cd $(BUILD) && vvp sim.out
	@echo "波形ファイル: $(BUILD)/dump.vcd"
	@echo "VSCode VaporView で開いて確認すること"

# ─── 合成 → 配置配線 → ビットストリーム生成（OSS CAD Suite 一時起動） ───
.PHONY: synth
synth:
	mkdir -p $(BUILD)
	$(OSS_ENV) && yosys -p "read_verilog $(SRC); synth_gowin -top $(TOP) -json $(BUILD)/$(TOP).json"
	$(OSS_ENV) && nextpnr-himbaechel --json $(BUILD)/$(TOP).json \
		--write $(BUILD)/$(TOP)_pnr.json \
		--device $(DEVICE) \
		--vopt family=$(FAMILY) \
		--vopt cst=$(CST)
	$(OSS_ENV) && gowin_pack -d $(FAMILY) -o $(BUILD)/$(TOP).fs $(BUILD)/$(TOP)_pnr.json
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

> **設計意図（OSS CAD Suite を Makefile 内で一時起動する理由）**:
>
> OSS CAD Suite の `environment` を `.bashrc` に常駐 source すると、全シェル起動時にプロンプトに `⦗OSS CAD Suite⦘` プレフィックスが付き、PATH も常時上書きされる。普段使いのシェルが汚染されるのを避けるため、本書では **`.bashrc` には source を書かず、`make synth` ターゲット内でのみ一時的に source する方式** を採用する。
>
> - `sim:` ターゲットは apt 版 iverilog（標準PATH）を使うため source 不要
> - `synth:` ターゲットは yosys / nextpnr-himbaechel / gowin_pack を使うため、各コマンド前に `$(OSS_ENV) && ` を付けて一時起動
> - `Makefile` 経由のため、サブシェル内に閉じた起動になり、親シェルの環境は汚染されない

> **NOTE（要実機検証）**: nextpnr-himbaechel の引数仕様について
>
> - `--device` に渡すデバイス文字列 `GW1NR-LV9QN88PC6/I5` には `/` が含まれる。Make 変数経由で展開した際にシェル/Make の解釈で事故る場合は、Makefile 上で**ダブルクォートで囲む**か、必要に応じて `\/` でエスケープすること。
> - `--vopt family=...` / `--vopt cst=...` の渡し方は OSS CAD Suite のリリースバージョンで揺れがあった（過去には `--write` 周辺の引数も含めて差異あり）。実機で `make synth` 通らない場合は `nextpnr-himbaechel --help` で現バージョンの正規構文を確認すること。
> - 1回実機で通ったら、本書の Makefile を確定版に書き換える。

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

VPS↔Win11 の同期は Syncthing に一本化する（[7. ファイル転送（Syncthing）](#7-ファイル転送syncthing) 参照）。
合成完了後、`build/led.fs` が Win11 側の同期フォルダに自動配信される。

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
# TM1638 接続（ピン番号は配線に合わせて変更）
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

### VPS 側

#### yosys で `synth_gowin` が見つからない

OSS CAD Suite の environment を source していない可能性がある。

```bash
source ~/oss-cad-suite/environment
```

#### nextpnr で `ERROR: Unconstrained IO` が出る

トップモジュールの全てのポートに対して `.cst` ファイルでピン割り当てが必要。
未使用ポートがある場合は RTL 側から削除するか、制約ファイルに追記する。

### Win11 側 — USB 認識まわり

#### Tang Nano 9K が「不明な USB デバイス（アドレスの設定の失敗）」になる

LED は光って給電されているのに、デバイスマネージャで認識失敗するケース。
USB 初期化の「アドレス設定」フェーズで失敗している状態。

**主な原因と対処**:

1. **USB ケーブルの相性問題**
   - 充電専用ケーブル → データ通信対応のものに交換
   - **USB-C アクティブケーブル**（Power Delivery 対応・代替モード対応の高機能ケーブル、ハードウェアウォレット用等）は Tang Nano 9K の単純な USB 2.0 デバイス相手だと **「USB 2.0 BILLBOARD」だけ現れて本体認識に失敗** することがある
   - 解決策: **シンプルな USB-A → USB-C ケーブル**（スマホ充電用、Tang Nano 9K 同梱品、100均ケーブル等）を試す

2. **KVM スイッチ / USB ハブ経由の問題**
   - 直接接続で動くか確認 → 動いたらハブ側の問題
   - USB ハブの給電不足の可能性（セルフパワー型に変更 or 給電ハブを使う）

3. **USB ポート相性**
   - USB 3.0 ポート → USB 2.0 ポートに変える（あれば）
   - 別ポートで試す

`USB 2.0 BILLBOARD` が見えている場合は、ケーブルが過剰仕様の可能性が高い。

#### MSYS2 で `command not found` が出る（誤シェル起動）

シェル選択ミスの可能性。プロンプト左の表記を確認:

- `[user@host UCRT64 ~]` ← 正解
- `[user@host MSYS ~]` ← 誤起動。`MSYS2 UCRT64` ショートカット（紫アイコンの下側）を起動し直す

UCRT64 と MSYS は **同じ濃い紫アイコン**で見分けにくい。ショートカット名末尾の「UCRT64」を確認。

#### openFPGALoader で `No cable found` が出る

1. Zadig で Interface 0 を WinUSB に変更したか確認
2. USB ケーブルがデータ通信対応か確認（充電専用ケーブルでは認識しない）
3. MSYS2 UCRT64 ターミナルから実行しているか確認（cmd.exe や MSYS シェルでは PATH が通っていない）

#### COM ポートがデバイスマネージャに出現しない

`USB Serial Converter B` は見えるが「ポート (COM と LPT)」セクションが無い場合、
FTDI の VCP（Virtual COM Port）レイヤーが無効化されている。

→ [3.2.3 VCP（Virtual COM Port）有効化](#323-vcpvirtual-com-port有効化) を参照。

#### TeraTerm でシリアルポートが見つからない

Zadig で **Interface 1 を変更してしまった** 可能性がある。
デバイスマネージャで「ユニバーサル シリアル バス デバイス」→ 該当デバイスを右クリック → ドライバの更新 → 「コンピューターを参照してドライバーを検索」→ 「コンピューター上の利用可能なドライバーの一覧から選択」→ USB シリアルデバイス を選択して復旧する。

または Zadig 画面で **Replace Driver の `▼` → Restore Original Driver** で書き換え前のドライバに戻せる。

### Win11 側 — 焼き込みまわり

#### Tang Nano 9K の JTAG アダプタの正体（BL702 vs FTDI）

物理チップは **BL702（Bouffalo Lab RISC-V MCU）**。FT2232D を **ファームウェアでエミュレート** しているだけで、本物の FTDI ではない。

- Win11 デバマネで `USB Serial Converter A/B` 表示は BL702 の擬装によるもの
- ftd2xx 系ツール（Gowin Programmer など）と細かい挙動が完全互換ではない
- Sipeed 公式 Wiki でも「IDE 同梱の Programmer は Tang Nano に合わない、推奨版に差し替えろ」と明記

→ **openFPGALoader（libusb / WinUSB 経由）に一本化が正解**。

#### apicula の GW1NR 非対応

apicula（gowin_pack）は **GW1N-9C のみサポート、GW1NR-9C 用 idcode を生成不可**（[apicula Issue #206](https://github.com/YosysHQ/apicula/issues/206)）。

| 項目 | 値 |
|---|---|
| apicula 出力の bitstream 埋め込み idcode | `0x1100481B`（GW1N-9C用） |
| Tang Nano 9K 実機 idcode | `0x0100481B`（bit28 違い） |
| openFPGALoader 判定 | 通る（下位16bitで識別） |
| Gowin Programmer 判定 | 弾く（厳密 id-code チェック） |

Lチカ程度なら GW1NR-9C と GW1N-9C は内部論理がほぼ同一なので **動作はする**（実証済み）。SDRAM 機能を使わなければ問題なし。

#### Gowin Programmer の `VLD Down` エラー（Tang Nano 9K では構造的に不適合）

Tang Nano 9K で Gowin Programmer を使うと `Error: VLD Down!` で全 Operation が失敗する：

- 原因: BL702 のFTDIエミュレーション層と Gowin の ftd2xx 経路の細かい挙動差
- Frequency 変更しても Operation 変更しても VLD Down 継続
- `exFlash Bulk Erase in bscan` も `thru GAO-Bridge` も同様に失敗

**対処:** Gowin Programmer を使わない。Sipeed 配布の推奨 Programmer に差し替えるか、openFPGALoader 一本化。

#### openFPGALoader Flash 焼きで `CRC check : FAIL` が出る

openFPGALoader v1.0.0（MSYS2 同梱版）の既知問題（[openFPGALoader Issue #251](https://github.com/trabucayre/openFPGALoader/issues/251), [#259](https://github.com/trabucayre/openFPGALoader/issues/259), [apicula Issue #262](https://github.com/YosysHQ/apicula/issues/262)）。

**Read 値で実害判定:**

| Read 値 | 判定 | 解釈 |
|---|---|---|
| `0x0000xxxx` (bitstream CRC近傍) | 偽陽性 | 焼けてる可能性あり、抜き差し後Lチカ動けばOK |
| `0x80fa00fa` (完全に化けた値) | **実害あり** | JTAG 読み戻し失敗、Flash 内容が壊れている |
| `0x00000000` (全0) | **実害あり** | 書込パスの問題、書き込み自体が成立してない |

**対処（v1.0.0 で詰む場合）:**
- 周波数下限に注意（`--freq` を 1.3MHz 未満にしない）
- v1.1.1 へアップグレード（OSS CAD Suite Windows版に同梱）
- v1.0.0 では `--bulk-erase` `--unprotect-flash` が Tang Nano 9K で `not supported`

⚠️ **2026-05-10 追検証結果**: openFPGALoader v1.1.1 へアップグレード後も CRC FAIL は再現（`Read: 0x00010000` パターン）。v1.1.0 changelog の「Gowin: 9K 用 CRC delay 増加」「未文書化シーケンス追加」修正でも解決せず。

⚠️ **2026-05-10 最終切り分け結果**: Gowin EDA Education V1.9.11.03 で同じ Verilog から正規 GW1NR-9C 用 bitstream を生成して焼いても、**完全に同じ CRC FAIL 症状**（`Read: 0x00000000`）が再現。これにより以下が確定：

- **apicula 起因ではない**（bitstream を変えても同じ症状）
- **openFPGALoader バージョン起因ではない**（v1.0.0 / v1.1.1 両方で同じ）
- **USB 通信品質問題でもない**（PC直挿しで pollFlag 化け値消滅、最終試行は化け値ゼロでも CRC FAIL）
- 残る原因は **物理層**（BL702 エミュレーション / Puya P25Q32U とのSPI配線 / USB信号品質）

**Status Register 比較で最終確証:**

| タイミング | Status Reg | フラグ |
|---|---|---|
| SRAM焼き Write後 | `0001e020` | **Done Final, Security Final**（正常起動） |
| Flash焼き Write後 | `00018020` | Done Final/Security Final **無し**（リロード未完了） |

**ベンダー公式の見解**: GowinSemi 公式サポートが「**Tang Nano 9K の eFlash プログラミングには BL702 を除去して外部 JTAG を接続するのが推奨**」と回答（Hackaday.io / svofski 氏記事より）。**ベンダー自身が9K Flash焼きを保証外と認めている**。

**apicula 共同開発者 yrabbit 証言**: 「4枚の Tang Nano 9K すべて USB コネクタの半田不良（外見正常・実際フリー）。優しく扱い、息も吹きかけない方がいい」（apicula Issue #262）。

→ **Phase 1 では SRAM 焼き運用で確定**（Phase 3 で USB絶縁器 ADuM3160 / 別ボード移行検討、Issue #1, #4 参照）。

#### SRAM 焼きで `CRC check: Success` が出るのに L チカ動かない

**原因仮説**: External Flash 内のゴミデータで FPGA 起動時にハング。Flash 焼き失敗を繰り返した直後に発生しやすい。

Tang Nano 9K は電源投入時に external SPI Flash (Puya P25Q32U) から bitstream を自動ロードする。ここに半端なデータが残っていると、FPGA が「有効っぽいが壊れてる」ヘッダを読みに行ってフリーズ → SRAM 焼きしても出力が正しく駆動されない。

**対処（Flash を 0xFF で埋めて消去状態にする）:**

```bash
# 4MB の 0xFF blob を生成
python -c "open('blank.bin','wb').write(b'\xFF'*4194304)"

# Flash に焼く（実質的な消去）
openFPGALoader -b tangnano9k -f --external-flash blank.bin
```

`--external-flash` を**必ず付ける**（Tang Nano 9K の bitstream Flash は外部 Puya P25Q32U で確定）。`Erasing 100%` まで完走すれば消去成功（Writing は途中 Ctrl+C で止めても問題なし）。

#### idcode が変化する／化ける（bit12 フリップ現象）

**現象**: 通常 `0x0100481B` の idcode が `0x0100581B`（bit12=1）に化け、3回連続 `--detect` でも安定して別の値を返す。

**原因仮説**（[ありす分析](https://github.com/YosysHQ/apicula/issues/262) と整合）: Flash erase 中断で IDCODE 管理セルの閾値が中途半端化（読み出し閾値ギリギリの状態）。

**復旧手順（実証済み）:**

1. USB ケーブル抜く
2. ボード電源 LED 消灯確認
3. **5 分以上放置**（残留電荷と Flash セルの閾値再安定化を待つ）
4. USB 再接続
5. `openFPGALoader --detect -b tangnano9k` を 3 回連続実行
6. 3 回とも `idcode 0x100481b` に戻れば復活

**5 分放置で Flash セル閾値が再安定化、idcode 復活する**事例あり。idcode 安定値を返している間は TAP 健全 = 物理破損ではない。

**追加観察（2026-05-10）**: idcode 化けの直接トリガは **「SRAM 焼きの `CRC check : FAIL`」** が有力。Flash erase 中断だけでなく、SRAM bridge bitstream の中途半端ロードでも FPGA 内部状態が汚染され、IDCODE 読み取りまで影響する模様。SRAM 焼きで FAIL が出た直後に `--detect` すると idcode 化けを観測しやすい。

#### ドライバ運用（Zadig WinUSB / FTDIBUS の使い分け）

| ツール | 必要ドライバ | 用途 |
|---|---|---|
| openFPGALoader | **WinUSB** | SRAM/Flash 焼き、推奨 |
| Gowin Programmer | **FTDIBUS** (FTDI 公式 ftd2xx) | ただし Tang Nano 9K では不適合 |

**両立不可**: 同じ USB I/F に WinUSB と ftd2xx は同時バインドできない（Windows ドライバスタック仕様）。

**Tang Nano 9K の正解:** WinUSB + openFPGALoader 一本化。Gowin Programmer ルートは VLD Down で詰むので、保険として Sipeed 配布の推奨 Programmer を入手しておく程度に留める。

**Interface 1 (UART) は絶対触らない**（[3.2.4 Zadig 操作](#324-zadig-操作) 既出）。

#### 開発フェーズ中の推奨運用（Phase 1〜2 段階）

Phase 1 〜 2 では **SRAM 焼き運用** に統一する。

```bash
# 焼き込み: -f なしで SRAM 焼き
openFPGALoader -b tangnano9k led.fs
```

| 項目 | SRAM 焼き | Flash 焼き |
|---|---|---|
| 速度 | 高速（数秒） | 遅い（数十秒〜分） |
| 永続性 | 電源 OFF で消える | 永続 |
| 開発サイクル | 適合 | 過剰 |
| 現状の安定性 | 安定 | CRC FAIL 多発 |

**Flash 永続化は Phase 3（完成・実機展示フェーズ）で本気で対処**。Issue 起票済み（リポジトリ Issues 参照）。

### ハードウェア側

#### LED が全く光らない（Lチカ書き込み後）

1. Tang Nano 9K の LED は **active low**（Low 出力で点灯）。初期値が全 High だと消灯状態
2. ビットストリーム(.fs)の書き込みが正常に完了したか確認
3. 制約ファイルのピン番号が正しいか確認
4. **Flash 内ゴミデータによる起動ハング**の可能性 → 上記「SRAM 焼きで CRC Success が出るのに L チカ動かない」項目を参照

#### 接続直後に LED が全く光らない（出荷時 demo すら動かない）

1. USB 給電不足（ハブ経由なら直接接続を試す）
2. 「不明な USB デバイス」になっていないか確認 → 上記のケーブル相性問題を参照
3. ボード初期不良（別 PC で試して切り分け）

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

### 既知の罠・トラブル参照（2026-05-10 セッション知見）

- [apicula Issue #206 — GW1NR vs GW1N idcode](https://github.com/YosysHQ/apicula/issues/206)
- [apicula Issue #262 — Tang Nano 9K bad checksum when flashing](https://github.com/YosysHQ/apicula/issues/262)
- [openFPGALoader Issue #251 — Tang Nano 9k: cable issues](https://github.com/trabucayre/openFPGALoader/issues/251)
- [openFPGALoader Issue #259 — GW1N-9C: flash CRC error](https://github.com/trabucayre/openFPGALoader/issues/259)
- [Sipeed Wiki — Tang common questions（VLD Down 等の解決策）](https://wiki.sipeed.com/hardware/en/tang/Tang-Nano-Doc/questions.html)
- [Gowin Programmer User Guide SUG502E（PDF）](https://cdn.gowinsemi.com.cn/SUG502E.pdf)
