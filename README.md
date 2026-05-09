# fpga_cpu_tang

Tang Nano 9K から始める **RISC-V 自作 CPU プロジェクト**。
最終目標は実シリコン（Arty A7-100T）に焼いた自作 CPU 上で **Linux カーネルをブートさせること**。

---

## プロジェクト目的

- 自作 RISC-V CPU を SystemVerilog で実装し、シリコンに焼いて実 Linux を起動する
- 動機：純粋な好奇心。せいぜいコンピュータサイエンスをハードウェア層から少し深く理解したい程度
- それ以上の崇高な目的は掲げない

---

## ロードマップ（全体）

| Phase | 内容 | 想定工数 | デバイス |
|-------|------|---------|---------|
| 1 | **RV32I 基本実装**（環境構築・Lチカ・UART・整数命令） | 100-150h | Tang Nano 9K |
| 2 | M/A 拡張（乗除算・アトミック命令） | 50-100h | Tang Nano 9K |
| 3 | 特権モード（M/S/U-mode、CSR） | 100-150h | Tang Nano 9K → Arty A7 |
| 4 | 64bit 化（RV64） | 100-150h | Arty A7-100T |
| 5 | **MMU 実装**（Sv39/Sv48 ページテーブル・TLB）  ← 最大の山 | 150-250h | Arty A7-100T |
| 6 | 割り込み（PLIC + CLINT） | 50-100h | Arty A7-100T |
| 7 | ペリフェラル（UART・DDR3 256MB・ストレージ） | 100-150h | Arty A7-100T |
| 8 | **Linux ブート**（RV64GC 達成） | 50-150h | Arty A7-100T |

合計工数見積：**700-1200h**（一般的な目安）

> **NOTE**: なとせの実工数は **2,100〜6,000h 程度を想定**。
> Factorio K2SO（一般目安 100h）を 500h で完走した実績から、3〜5 倍の係数を掛けた値。
> 焦らない、急がない、複雑なタスクは落ち着いて完遂させること。

### 現在のステータス

- **Phase 1 入口（環境構築フェーズ）**
- 設計フェーズ完了、実装着手準備中
- セットアップ手順書 `docs/01_setup_guide.md` 整備済み
- 00_counter（LED Lチカ）／01_uart までが直近のターゲット

---

## ハードウェア構成

### Phase 1〜3：Tang Nano 9K

| 項目 | 内容 |
|------|------|
| FPGA | Gowin GW1NR-9（8,640 LUT4） |
| クロック | 27 MHz オンボード水晶 |
| 用途 | RV32I コア・M/A 拡張・特権モード基本実装 |
| デバッグ | TM1638 モジュール（7セグ×8 + LED×8 + ボタン×8） |

### Phase 4〜8：Arty A7-100T

| 項目 | 内容 |
|------|------|
| FPGA | Xilinx Artix-7 XC7A100T（101,440 LUT） |
| メモリ | DDR3 256 MB |
| 用途 | RV64・MMU・Linux ブート |
| 移行理由 | Tang Nano 9K では MMU + 64bit + ペリフェラルが容量的に厳しい |

---

## 開発フロー

VPS（Ubuntu 22.04）と Win11 の **2 層構成**:

```
┌──────────────────────────────────────────────────────┐
│  VPS (Ubuntu 22.04)                                  │
│  - Icarus Verilog（シミュレーション）                │
│  - OSS CAD Suite（yosys → nextpnr → gowin_pack）     │
│  - VSCode VaporView で .vcd 波形確認                 │
└────────────┬─────────────────────────────────────────┘
             │ Syncthing（.fs ビットストリーム自動同期）
             ▼
┌──────────────────────────────────────────────────────┐
│  Win11                                               │
│  - openFPGALoader（.fs を Tang Nano 9K に焼き込み）  │
│  - TeraTerm（UART 115200bps 確認）                   │
└──────────────────────────────────────────────────────┘
```

**設計判断**:
- VPS 集中で重い処理を回す（合成・シミュレーション）
- Win11 は実機との物理境界（USB/UART）に専念
- VPS リソースを活かすため WSL2 一本化案は採用せず（外部レビュー検討済み）

---

## ディレクトリ構成

```
fpga_cpu_tang/
├── README.md                   ← 本ファイル（プロジェクト羅針盤）
├── docs/
│   └── 01_setup_guide.md       ← 開発環境構築手順
├── 00_counter/                 ← 環境確認用（LED Lチカ）
│   ├── src/                    ← RTL
│   ├── tb/                     ← テストベンチ
│   ├── constraints/
│   └── Makefile
├── 01_uart/                    ← UART Hello World
│   └── （00_counter と同構造）
├── 02_rv32i_core/              ← Phase 1 本体（必要時に作成）
├── 03_rv32m_core/              ← Phase 2（必要時に作成）
└── ...                         ← Phase 進行に応じて段階的に追加
```

各サブプロジェクトの Makefile は `sim`（シミュレーション）／ `synth`（合成→ビットストリーム生成）の 2 ターゲットを持つ。

---

## ドキュメント

| ファイル | 内容 |
|---------|------|
| [docs/01_setup_guide.md](docs/01_setup_guide.md) | 開発環境構築手順（VPS 側ツール・Win11 側ツール・Tang Nano 9K ピンマップ・LED Lチカ動作確認） |
| [docs/02_vaporview_guide.md](docs/02_vaporview_guide.md) | VaporView 波形ビューア操作ガイド（基本操作・ナビゲーション・Phase 1 RV32I 波形デバッグ実践パターン・トラブルシューティング） |
| [docs/99_glossary.md](docs/99_glossary.md) | 用語集（FPGA・RISC-V・周辺ツール用語の解説） |

Phase 進行に応じて `docs/` 配下にアーキテクチャ設計書・命令デコーダ仕様書・MMU 設計書などを順次追加予定。

---

## 参考リソース

### RISC-V 仕様
- [RISC-V ISA Manual](https://riscv.org/technical/specifications/) — 公式仕様（Unprivileged / Privileged）

### 先行実装
- [VexRiscv（SpinalHDL）](https://github.com/SpinalHDL/VexRiscv) — Linux booting 実例、Arty A7 動作確認済み
- [Rocket Chip（Chisel）](https://github.com/chipsalliance/rocket-chip) — SiFive 商用元、業務級
- [PicoRV32](https://github.com/YosysHQ/picorv32) — MMU 無しシンプル実装
- [neorv32（VHDL）](https://github.com/stnolting/neorv32) — SoC 構成の参考

### ツールチェーン
- [OSS CAD Suite](https://github.com/YosysHQ/oss-cad-suite-build) — yosys + nextpnr + gowin_pack の統合ディストリ
- [Project Apicula](https://github.com/YosysHQ/apicula) — Gowin FPGA bitstream 仕様（OSS）

### Tang Nano 9K
- [Sipeed 公式 Wiki](https://wiki.sipeed.com/hardware/en/tang/Tang-Nano-9K/Nano-9K.html)
- [Lushay Labs チュートリアル](https://learn.lushaylabs.com/getting-setup-with-the-tang-nano-9k/)
