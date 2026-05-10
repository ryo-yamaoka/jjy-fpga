module debouncer #(
    parameter int CLK_HZ         = 27_000_000,
    parameter int STABLE_TIME_MS = 10
) (
    input  logic clk,
    input  logic sig_async,
    output logic sig_sync,
    output logic pulse_neg
);
    localparam int STABLE_TICKS = (CLK_HZ / 1000) * STABLE_TIME_MS;
    localparam int CNT_W        = $clog2(STABLE_TICKS + 1);

    // 2-stage synchronizer to mitigate metastability on async input
    logic sig_meta  = 1'b1;
    logic sig_stab  = 1'b1;
    always_ff @(posedge clk) begin
        sig_meta <= sig_async;
        sig_stab <= sig_meta;
    end

    // hold the candidate level for STABLE_TICKS before committing to sig_q
    logic [CNT_W-1:0] cnt   = '0;
    logic             sig_q = 1'b1;

    always_ff @(posedge clk) begin
        if (sig_stab != sig_q) begin
            if (cnt == CNT_W'(STABLE_TICKS - 1)) begin
                sig_q <= sig_stab;
                cnt   <= '0;
            end else begin
                cnt <= cnt + 1'b1;
            end
        end else begin
            cnt <= '0;
        end
    end

    logic sig_q_prev = 1'b1;
    always_ff @(posedge clk) sig_q_prev <= sig_q;

    assign sig_sync  = sig_q;
    assign pulse_neg = sig_q_prev & ~sig_q;
endmodule
