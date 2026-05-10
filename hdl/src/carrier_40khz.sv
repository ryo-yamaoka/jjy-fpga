module carrier_40khz #(
    parameter int CLK_HZ     = 27_000_000,
    parameter int CARRIER_HZ = 40_000
) (
    input  logic clk,
    output logic carrier
);
    // 27_000_000 / (40_000 * 2) = 337.5, round down to 337.
    // Resulting carrier frequency: 27_000_000 / (337 * 2) ≈ 40_059 Hz (+0.15%),
    // well within the receive bandwidth of typical JJY-compatible clocks.
    localparam int HALF_PERIOD = CLK_HZ / (CARRIER_HZ * 2);
    localparam int CNT_W       = $clog2(HALF_PERIOD);

    logic [CNT_W-1:0] cnt       = '0;
    logic             carrier_q = 1'b0;

    always_ff @(posedge clk) begin
        if (cnt == CNT_W'(HALF_PERIOD - 1)) begin
            cnt       <= '0;
            carrier_q <= ~carrier_q;
        end else begin
            cnt <= cnt + 1'b1;
        end
    end

    assign carrier = carrier_q;
endmodule
