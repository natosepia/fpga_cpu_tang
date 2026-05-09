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