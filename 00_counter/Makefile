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
	@echo "VSCode WaveTrace で開いて確認すること"

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
