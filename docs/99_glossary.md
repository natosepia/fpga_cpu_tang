# 99_glossary — 用語解説シート

FPGA 開発・RISC-V 自作 CPU プロジェクトでよく出てくる用語の解説。
Phase 進行に応じて随時追記する。各セクション内は ABC 順。

略号の意味だけでなく、**ソフトウェア工学側の類推**があれば併記する（なとせのバックグラウンドに合わせる）。

---

## 目次

- [1. FPGA 基礎](#1-fpga-基礎)
- [2. ハードウェア記述言語（HDL）](#2-ハードウェア記述言語hdl)
- [3. ツールチェーン](#3-ツールチェーン)
- [4. RISC-V ISA](#4-risc-v-isa)
- [5. CPU アーキテクチャ](#5-cpu-アーキテクチャ)
- [6. メモリ・MMU](#6-メモリmmu)
- [7. 割り込み・周辺](#7-割り込み周辺)
- [8. 通信・I/O プロトコル](#8-通信io-プロトコル)
- [9. シミュレーション・検証](#9-シミュレーション検証)
- [10. ボード固有（Tang Nano 9K / Arty A7）](#10-ボード固有tang-nano-9k--arty-a7)

---

## 1. FPGA 基礎

### BRAM (Block RAM)
FPGA に内蔵された専用の SRAM ブロック。LUT 群を使って RAM を構成するより高速・省リソース。
キャッシュやレジスタファイル、命令メモリ・データメモリに使う。
**ソフトウェア類推**: ヒープから取らずに専用プールから割り当てるイメージ。

### CST (Constraint file)
Gowin FPGA 向けのピン制約ファイル（拡張子 `.cst`）。RTL 上のポート名と物理ピン番号、IO 規格（LVCMOS33 等）の対応を定義する。
コメントは `#`（`//` は不可、Phase 1 で実機検証予定）。

### DSP slice
乗算器・累算器を専用回路化した FPGA 内ブロック。LUT で構成するより高速で、電力効率も良い。
RV32M（M 拡張、乗除算）や FFT、信号処理で活躍。

### FF (Flip-Flop)
1 ビットの記憶素子。クロックエッジで入力値を取り込んで保持する。CPU レジスタの基本構成要素。
レジスタ 32 本×32bit = 1024 個の FF が必要（最低限）。

### Fabric
FPGA 内部の LUT・FF・配線リソースの総称。「Fabric を使い切る」= ロジック容量上限に到達。

### LUT (Look-Up Table)
FPGA の最小論理ユニット。N 入力の真理値表を SRAM で実装したもの。Tang Nano 9K の LUT4 は 4 入力 1 出力。
組合せ論理（AND/OR/NOT を組み合わせた式）はすべて LUT で実装される。

### PLL (Phase-Locked Loop)
クロック逓倍／分周回路。27 MHz 入力から 100 MHz や 50 MHz を生成する用途。
Tang Nano 9K の Gowin GW1NR-9 にも内蔵。

### Place & Route (PnR / 配置配線)
合成済みネットリストを「物理的にどの LUT/FF/BRAM にマップして、どう配線するか」を決める工程。
nextpnr-himbaechel が担当。タイミング制約を満たすことが目的。
**ソフトウェア類推**: 「コードを書く」のではなく「コンパイル後の実行ファイルをメモリにレイアウトする」工程。

### RTL (Register Transfer Level)
レジスタ間の値の流れで回路を記述する抽象度。Verilog/SystemVerilog/VHDL で書くコードのレベル。
ゲートレベル（NAND/NOR の網）より高位、振る舞いレベル（C ライク）より低位。

### Slack（タイミングスラック）
クロック周期からクリティカルパス遅延を引いた余裕値。負だとタイミング違反（動作不能）。
**ソフトウェア類推**: 締切までの猶予時間。

### Synthesis（合成）
RTL コードから論理回路（ネットリスト）を生成する工程。Yosys が担当。
RTL → ネットリスト（LUT/FF の組合せ） → PnR（物理配置）の流れ。
**ソフトウェア類推**: コンパイラが C コードからアセンブリを生成する工程に相当。

### Timing closure
全パスがタイミング制約（目標クロック周波数）を満たした状態。
未達なら「クリティカルパス削減」「パイプライン段数増」「動作周波数下げる」のいずれかで対処。

---

## 2. ハードウェア記述言語（HDL）

### HDL (Hardware Description Language)
ハードウェア記述言語の総称。Verilog / SystemVerilog / VHDL / Chisel / SpinalHDL などが該当。

### SystemVerilog
Verilog 2001 の拡張言語。`logic` 型・`always_ff`／`always_comb` などの記述が安全。
本プロジェクトでは Phase 2 以降で SystemVerilog を採用予定。Phase 1 の Lチカは Verilog で十分。

### Verilog
最古参の HDL。本プロジェクトの Phase 1（00_counter, 01_uart）で使用。
シンプルだが `always @(*)` の記述漏れで latch を作りやすい等、罠が多い。

### `always` / `always_ff` / `always_comb`
- `always @(posedge clk)` — 順序回路（クロック駆動）
- `always_comb` — 組合せ回路（SystemVerilog、latch 防止）
- `always_ff` — 順序回路（SystemVerilog、明示的に FF 推論）

### `wire` / `reg` / `logic`
- `wire` — 配線（連続代入）
- `reg` — 「procedural assignment が可能」の意。FF とは限らない
- `logic` — SystemVerilog で `wire`/`reg` の用途両対応の万能型

---

## 3. ツールチェーン

### gowin_pack
Project Apicula の一部。配置配線済みネットリスト（JSON）を Gowin FPGA のビットストリーム（`.fs`）に変換する。

### Icarus Verilog (iverilog)
オープンソースの Verilog/SystemVerilog シミュレータ。`iverilog` でコンパイル、`vvp` で実行、VCD ダンプ生成。
本プロジェクトのシミュレーションはこれで実施。

### nextpnr / nextpnr-himbaechel
オープンソースの汎用 PnR ツール。`nextpnr-himbaechel` が Gowin FPGA 対応バックエンド。
入力: yosys が出した JSON ネットリスト＋CST 制約。出力: 配置配線済み JSON。

### openFPGALoader
オープンソースの FPGA ビットストリーム書き込みツール。Tang Nano 9K の JTAG 経由で `.fs` を焼く。
Win11 側で MSYS2 UCRT64 から実行する想定。

### OSS CAD Suite
Yosys / nextpnr / gowin_pack / GHDL / SymbiYosys 等を統合したオープンソース EDA バンドル。
`source ~/oss-cad-suite/environment` で全ツールが PATH に通る。

### Project Apicula
Gowin FPGA のビットストリーム形式・bel/wire 情報をリバースエンジニアリングしたデータベース。
nextpnr-himbaechel + gowin_pack の Gowin 対応はこれが土台。

### SymbiYosys (sby)
Yosys ベースのフォーマル検証フロントエンド。アサーション付き RTL を入力に「反例 trace」or「全状態安全性」を出す。
Phase 2 以降で導入候補。

### Synth
合成ツール一般を指す略語。本プロジェクトでは yosys を指す。

### Verilator
高速 Verilog シミュレータ。RTL を C++ に変換してネイティブ実行するため、iverilog より桁違いに速い。
大規模 testbench（Linux ブートシミュレーション等）では必須。Phase 4-5 で導入予定。

### vvp
iverilog が生成した中間ファイル（`.out`）を実行するランタイム。`iverilog -o sim.out tb.v src.v && vvp sim.out` の流れ。

### WaveTrace
VSCode 拡張。`.vcd` 波形ファイルを GUI で閲覧できる。GTKWave の代替。

### Yosys
オープンソース論理合成ツール。RTL → ネットリスト変換を担う。
`yosys -p "read_verilog x.v; synth_gowin -top top -json out.json"` の流れで使う。

---

## 4. RISC-V ISA

### ABI (Application Binary Interface)
コンパイル済みコードと OS／ライブラリの呼出規約。レジスタ用途（caller-saved/callee-saved）、引数渡し方等。
RV32 系 ABI: ilp32（整数）、ilp32f（単精度浮動）、ilp32d（倍精度）。

### CSR (Control and Status Register)
特権命令でアクセスする制御／状態レジスタ。`mstatus`、`mtvec`、`mepc` 等。
12bit のアドレス空間で、用途・特権レベルでマップされる。Phase 3（特権モード）で大量に登場。

### Decoder（命令デコーダ）
32bit 命令を「opcode・rd・rs1・rs2・funct3・funct7・immediate」に切り分ける論理回路。
RISC-V は 6 種類の命令フォーマット（R/I/S/B/U/J）を持ち、即値の組み立て方が形式ごとに違う。

### GPR (General Purpose Register)
汎用レジスタ。RV32 では 32 本（x0-x31）、各 32bit。x0 は常に 0。
ABI 呼び名: `zero`, `ra`, `sp`, `gp`, `tp`, `t0-t6`, `s0-s11`, `a0-a7`。

### Hart (Hardware thread)
RISC-V 仕様での「実行コンテキスト」単位。1 コアでも SMT すれば複数 hart。
プロジェクトの Phase 1-7 は単一 hart（シングルコア）想定。

### Privileged Architecture (M/S/U-mode)
特権レベル：
- M-mode（Machine）— 最上位、ファームウェア / SBI 層
- S-mode（Supervisor）— Linux カーネルが乗る層
- U-mode（User）— ユーザーランド
Linux 起動には M+S+U の 3 モード実装が必要。

### RV32I / RV32IM / RV32IMA / RV64GC
ISA 拡張の積み重ね：
- I — 整数基本（必須）
- M — 乗除算
- A — アトミック命令（マルチタスク必須）
- F/D — 浮動小数（単/倍精度）
- C — 圧縮命令（16bit 命令、コードサイズ削減）
- G — IMAFD 一括（"General"）
- 64 — 64bit 化
**RV64GC = Linux ブートの最小公倍数**。本プロジェクトの最終目標 ISA。

### SBI (Supervisor Binary Interface)
M-mode → S-mode（Linux）への ABI 規約。OpenSBI が標準実装。
Phase 8（Linux ブート）で必須。

### Trap
例外（exception）と割り込み（interrupt）の総称。M-mode/S-mode の `mtvec`/`stvec` で示されたハンドラに飛ぶ。

---

## 5. CPU アーキテクチャ

### Branch prediction（分岐予測）
分岐命令の結果（taken/not-taken）を事前予測してパイプラインを止めない手法。
シンプルな BTB（Branch Target Buffer）から、tournament predictor、TAGE まで段階あり。
Phase 5-6 で導入候補。

### Cache (L1 / L2)
DRAM アクセス遅延を隠蔽する高速バッファ。
- L1 命令キャッシュ（I-cache）/ L1 データキャッシュ（D-cache）
- L2 統合キャッシュ
Phase 7 で導入予定。

### Hazard（ハザード）
パイプライン処理を阻害する依存関係：
- **Data hazard** — 後続命令が前の結果を待つ（forwarding/stall で対処）
- **Control hazard** — 分岐で次命令がまだ確定しない（分岐予測 / flush）
- **Structural hazard** — リソース競合（FF/メモリポート不足）

### IPC (Instructions Per Cycle)
1 サイクルあたり完了する命令数。CPU 性能の主指標の 1 つ。
シングルサイクル CPU = 1.0、5 段パイプライン理想 = 1.0、スーパースカラ = 1.0 超。

### ISA（命令セットアーキテクチャ）
プログラマから見えるハードウェアの抽象（命令・レジスタ・例外モデル）。
RISC-V / x86 / ARM / MIPS など。マイクロアーキ（実装方法）と独立。

### Microarchitecture（マイクロアーキテクチャ）
ISA を実装する具体的な内部構造（パイプライン段数・分岐予測器・キャッシュ構成等）。
同じ RV32I でも実装は無数（PicoRV32 / VexRiscv / Rocket 等）。

### Out-of-order execution（アウトオブオーダ実行）
命令を投入順序ではなく依存関係解決順に実行する手法。Tomasulo アルゴリズム等。
Phase 7+ で導入候補だが、本プロジェクトでは In-order 実装で十分（Linux 起動目的のため）。

### Pipeline（パイプライン）
命令を複数段階に分けて並行処理する手法。古典 RISC は 5 段：
1. IF (Instruction Fetch)
2. ID (Instruction Decode)
3. EX (Execute)
4. MEM (Memory access)
5. WB (Write Back)
Phase 1-3 では単段 / 5 段から始め、Phase 5+ で増段検討。

### Single-cycle / Multi-cycle CPU
- **シングルサイクル** — 1 命令を 1 クロックで完遂。最も単純、性能低
- **マルチサイクル** — 1 命令を複数クロックで実行（ハードウェア節約）
- **パイプライン** — 命令重ね合わせで 1 クロックあたり実効 1 命令
教育的にはシングルサイクル → マルチ → パイプラインの順で学ぶ。

---

## 6. メモリ・MMU

### MMU (Memory Management Unit)
仮想アドレス → 物理アドレス変換を行うユニット。プロセス分離・メモリ保護の根幹。
**Linux 起動には MMU 必須**。Phase 5 が最大の山。

### Page Table（ページテーブル）
仮想ページ番号 → 物理ページ番号の対応表。階層化（multi-level）が一般的。
Sv39 = 3 段、Sv48 = 4 段。

### PMP (Physical Memory Protection)
物理メモリ領域のアクセス権制御（M-mode 設定）。MMU と独立した保護機構。

### PTE (Page Table Entry)
ページテーブルの 1 エントリ。物理ページ番号＋アクセス権限ビット（V/R/W/X/U/G/A/D）。

### Sv32 / Sv39 / Sv48 / Sv57
RISC-V 仮想化方式：
- Sv32 — 32bit 仮想空間、2 段ページテーブル（RV32 用）
- Sv39 — 39bit 仮想空間、3 段（RV64 Linux 標準）
- Sv48 — 48bit 仮想空間、4 段（大規模システム）
- Sv57 — 57bit 仮想空間、5 段（最新サーバ）

### TLB (Translation Lookaside Buffer)
ページテーブルのキャッシュ。仮想→物理変換を高速化。
TLB miss 時はハードウェア（ページテーブルウォーカ）が階層を辿る。

### Virtual / Physical Address
- 仮想アドレス — ソフトウェアが見る論理空間
- 物理アドレス — DRAM の実際の番地
MMU が両者を変換する。

---

## 7. 割り込み・周辺

### CLINT (Core Local Interruptor)
コアローカル割り込みコントローラ。タイマ割り込み（mtime / mtimecmp）とソフトウェア割り込み（msip）を担当。
Phase 6 で実装。

### Interrupt（割り込み）
外部イベント（タイマ満了・I/O 完了等）で実行中命令を中断してハンドラに飛ばす機構。
Trap の一種（同期例外と区別される非同期 trap）。

### MTIME / MTIMECMP
- mtime — マシンタイマ（実時間カウンタ）
- mtimecmp — 比較値、mtime ≧ mtimecmp で割り込み発生
Linux のスケジューリングタイマの基盤。

### PLIC (Platform-Level Interrupt Controller)
プラットフォーム共通の割り込みコントローラ。複数外部デバイスからの割り込みを優先度順に hart に配信。
Phase 6 で CLINT と一緒に実装。

---

## 8. 通信・I/O プロトコル

### I2C
2 線式シリアル通信（SDA / SCL）。低速（〜400kHz）、複数デバイス対応。
センサ／EEPROM 接続でよく使う。

### JTAG
FPGA や CPU の境界スキャン／デバッグ用標準インタフェース。4 線（TCK / TMS / TDI / TDO）。
Tang Nano 9K のビットストリーム書き込み経路。

### SPI
高速同期シリアル通信（CLK / MOSI / MISO / CS）。1MHz〜数十 MHz。
SPI Flash、SD カード、TM1638 などのデバッグモジュールで使う。

### UART
非同期シリアル通信（TX / RX、クロック共有なし）。1 bit ずつボーレート同期で送る。
本プロジェクトの初期デバッグ手段（Phase 1 / 01_uart）。Tang Nano 9K の BL702 経由 USB シリアルで PC と接続。

### USB-CDC
USB クラスの 1 つ、シリアル通信エミュレーション。Tang Nano 9K の BL702 が UART → USB-CDC 変換を担う。

---

## 9. シミュレーション・検証

### Cocotb
Python で書ける testbench フレームワーク。Verilog/VHDL の DUT を Python から駆動・検証できる。
Phase 2 以降で複雑な testbench に導入候補。

### Coverage（カバレッジ）
testbench がどれだけ RTL の状態空間を網羅したかの指標。line / branch / FSM state coverage 等。

### DUT (Design Under Test)
testbench の中で検証対象となる回路モジュール。

### Formal verification（形式検証）
testbench でなく数学的に「全入力で性質が成り立つ」ことを証明する検証手法。SymbiYosys 等。
Phase 5（MMU）で導入価値高い（バグの取りこぼしが致命的なため）。

### Testbench
RTL を駆動・観測する検証用コード。Verilog で書ける。
入力刺激 → 期待値比較 → pass/fail 判定。

### VCD (Value Change Dump)
シミュレータが出力する波形ダンプフォーマット。テキスト形式、汎用性高い。
WaveTrace / GTKWave で可視化。

### Waveform（波形）
信号値の時間変化グラフ。デバッグの主力ツール。
**ソフトウェア類推**: `printf` デバッグの代わりに「全変数の時系列ログ」を取る感覚。

---

## 10. ボード固有（Tang Nano 9K / Arty A7）

### Arty A7-100T
Digilent 製の Xilinx Artix-7 評価ボード。本プロジェクトの Phase 4-8 で使用予定。
- FPGA: XC7A100T（101,440 LUT）
- DDR3 256MB
- 用途: RV64 + MMU + Linux ブート

### BL702
Tang Nano 9K に搭載される Bouffalo Lab 製の SoC（RISC-V ベース）。
役割: USB-JTAG / USB-UART 変換。書き込みも UART デバッグもこの 1 チップ経由。

### Gowin GW1NR-9
Tang Nano 9K のメイン FPGA。
- 8,640 LUT4
- 6,480 FF
- 17 KB BRAM
- 2 PLL
- 64Mbit SDRAM 内蔵パッケージ（GW1NR は SDRAM 統合版）

### Sipeed Tang Nano 9K
Sipeed 製の小型 FPGA 評価ボード。Gowin GW1NR-9 搭載、USB-C 給電・BL702 デバッガ統合。
本プロジェクトの Phase 1-3 で使用。

---

## 追記方針

- **Phase 進行に応じて随時追記**する。机上で全部書こうとしない
- 用語が増えたら同セクション内に ABC 順で挿入
- 「ソフトウェア類推」が思いつく場合は積極的に記載（なとせのバックグラウンドに合わせる）
- 不確実な記述は「要検証」マーク付きで残す（後で潰す）
