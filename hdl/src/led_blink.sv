module led_blink #(
    parameter int CLK_HZ   = 27_000_000,
    parameter int BLINK_HZ = 1
) (
    input  logic       clk,
    output logic [5:0] led
);
    localparam int               HALF_TICKS = CLK_HZ / (BLINK_HZ * 2);
    localparam int               CNT_W      = $clog2(HALF_TICKS);
    localparam logic [CNT_W-1:0] HALF_LIMIT = HALF_TICKS - 1;

    logic [CNT_W-1:0] cnt    = '0;
    logic             toggle = 1'b0;

    always_ff @(posedge clk) begin
        if (cnt == HALF_LIMIT) begin
            cnt    <= '0;
            toggle <= ~toggle;
        end else begin
            cnt <= cnt + 1'b1;
        end
    end

    // active-low: invert and broadcast to all 6 LEDs
    assign led = {toggle, ~toggle, toggle, ~toggle, toggle, ~toggle};
endmodule
