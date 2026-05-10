// Asynchronous UART receiver. 8 data bits, no parity, 1 stop bit.
// Sampling is at mid-bit. Start bit is re-checked at its center to filter
// out short glitches.
module uart_rx #(
    parameter int CLK_HZ = 27_000_000,
    parameter int BAUD   = 115_200
) (
    input  logic       clk,
    input  logic       rx,
    output logic [7:0] byte_data,
    output logic       byte_valid
);
    localparam int CYCLES_PER_BIT = CLK_HZ / BAUD;
    localparam int HALF_CYCLES    = CYCLES_PER_BIT / 2;
    localparam int CNT_W          = $clog2(CYCLES_PER_BIT);

    localparam logic [1:0] S_IDLE  = 2'd0;
    localparam logic [1:0] S_START = 2'd1;
    localparam logic [1:0] S_DATA  = 2'd2;
    localparam logic [1:0] S_STOP  = 2'd3;

    logic rx_meta = 1'b1;
    logic rx_sync = 1'b1;
    always_ff @(posedge clk) begin
        rx_meta <= rx;
        rx_sync <= rx_meta;
    end

    logic [1:0]       state   = S_IDLE;
    logic [CNT_W-1:0] cnt     = '0;
    logic [2:0]       bit_idx = 3'd0;
    logic [7:0]       shift   = 8'd0;

    always_ff @(posedge clk) begin
        byte_valid <= 1'b0;
        unique case (state)
            S_IDLE: begin
                bit_idx <= 3'd0;
                if (rx_sync == 1'b0) begin
                    state <= S_START;
                    cnt   <= CNT_W'(HALF_CYCLES - 1);
                end
            end
            S_START: begin
                if (cnt == '0) begin
                    if (rx_sync == 1'b0) begin
                        state <= S_DATA;
                        cnt   <= CNT_W'(CYCLES_PER_BIT - 1);
                    end else begin
                        state <= S_IDLE;
                    end
                end else begin
                    cnt <= cnt - 1'b1;
                end
            end
            S_DATA: begin
                if (cnt == '0) begin
                    shift <= {rx_sync, shift[7:1]};
                    cnt   <= CNT_W'(CYCLES_PER_BIT - 1);
                    if (bit_idx == 3'd7) begin
                        state <= S_STOP;
                    end else begin
                        bit_idx <= bit_idx + 3'd1;
                    end
                end else begin
                    cnt <= cnt - 1'b1;
                end
            end
            S_STOP: begin
                if (cnt == '0) begin
                    if (rx_sync == 1'b1) begin
                        byte_data  <= shift;
                        byte_valid <= 1'b1;
                    end
                    state <= S_IDLE;
                end else begin
                    cnt <= cnt - 1'b1;
                end
            end
            default: state <= S_IDLE;
        endcase
    end
endmodule
