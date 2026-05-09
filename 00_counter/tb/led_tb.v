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