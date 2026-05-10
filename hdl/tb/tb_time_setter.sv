// Testbench for the Step 4 receive chain (uart_rx -> time_setter -> date_calc).
// Drives UART bytes at 115200 baud, then checks the parsed/derived fields.
//
// Run:
//   iverilog -g2012 -o tb_time_setter.vvp \
//     hdl/tb/tb_time_setter.sv \
//     hdl/src/uart_rx.sv hdl/src/time_setter.sv hdl/src/date_calc.sv
//   vvp tb_time_setter.vvp
`timescale 1ns/1ps

module tb_time_setter;
    logic clk = 1'b0;
    // 27 MHz period = 37.037 ns. Use a 19/18 ns alternation as a close
    // approximation; exact half-period not critical here.
    always #18 clk = ~clk;

    logic rx = 1'b1;

    logic [7:0] uart_byte;
    logic       uart_byte_valid;
    uart_rx #(.CLK_HZ(27_000_000), .BAUD(115_200)) dut_uart (
        .clk        (clk),
        .rx         (rx),
        .byte_data  (uart_byte),
        .byte_valid (uart_byte_valid)
    );

    logic        time_valid;
    logic [11:0] year_full;
    logic [3:0]  year_tens;
    logic [3:0]  year_ones;
    logic [3:0]  month_bin;
    logic [4:0]  day_bin;
    logic [1:0]  hour_tens;
    logic [3:0]  hour_ones;
    logic [2:0]  min_tens;
    logic [3:0]  min_ones;
    logic [5:0]  sec_bin;
    time_setter dut_ts (
        .clk        (clk),
        .byte_data  (uart_byte),
        .byte_valid (uart_byte_valid),
        .time_valid (time_valid),
        .year_full  (year_full),
        .year_tens  (year_tens),
        .year_ones  (year_ones),
        .month_bin  (month_bin),
        .day_bin    (day_bin),
        .hour_tens  (hour_tens),
        .hour_ones  (hour_ones),
        .min_tens   (min_tens),
        .min_ones   (min_ones),
        .sec_bin    (sec_bin)
    );

    logic [8:0] doy;
    logic [2:0] weekday_v;
    date_calc dut_dc (
        .year    (year_full),
        .month   (month_bin),
        .day     (day_bin),
        .doy     (doy),
        .weekday (weekday_v)
    );

    // 115200 bps -> 1 bit = 1e9 / 115200 ≈ 8680.555 ns
    localparam real BIT_TIME = 8680.555;

    integer pass_count = 0;
    integer fail_count = 0;
    int     valid_seen = 0;

    always @(posedge clk) if (time_valid) valid_seen++;

    task send_byte(input [7:0] data);
        integer i;
        begin
            rx = 1'b0;
            #(BIT_TIME);
            for (i = 0; i < 8; i = i + 1) begin
                rx = data[i];
                #(BIT_TIME);
            end
            rx = 1'b1;
            #(BIT_TIME);
        end
    endtask

    // Send a 21-byte fixed-length frame. msg is packed MSB-first.
    task send_frame(input [167:0] msg);
        integer i;
        begin
            for (i = 0; i < 21; i = i + 1)
                send_byte(msg[(20 - i) * 8 +: 8]);
        end
    endtask

    task expect_eq(input [31:0] got, input [31:0] exp, input string label);
        begin
            if (got === exp) begin
                $display("[PASS] %s = %0d", label, got);
                pass_count = pass_count + 1;
            end else begin
                $display("[FAIL] %s : got %0d, expected %0d", label, got, exp);
                fail_count = fail_count + 1;
            end
        end
    endtask

    initial begin
        rx = 1'b1;
        #200;

        $display("--- case 1: valid 2026-04-13T12:00:30 ---");
        valid_seen = 0;
        send_frame("T2026-04-13T12:00:30\n");
        #5000;
        expect_eq(valid_seen, 1, "valid pulses (case 1)");
        expect_eq(year_full, 12'd2026, "year_full");
        expect_eq(year_tens, 4'd2,     "year_tens");
        expect_eq(year_ones, 4'd6,     "year_ones");
        expect_eq(month_bin, 4'd4,     "month_bin");
        expect_eq(day_bin,   5'd13,    "day_bin");
        expect_eq(hour_tens, 2'd1,     "hour_tens");
        expect_eq(hour_ones, 4'd2,     "hour_ones");
        expect_eq(min_tens,  3'd0,     "min_tens");
        expect_eq(min_ones,  4'd0,     "min_ones");
        expect_eq(sec_bin,   6'd30,    "sec_bin");
        expect_eq(doy,       9'd103,   "doy (2026-04-13)");
        expect_eq(weekday_v, 3'd1,     "weekday (Mon)");

        $display("--- case 2: valid 2024-02-29T23:59:59 (leap day) ---");
        valid_seen = 0;
        send_frame("T2024-02-29T23:59:59\n");
        #5000;
        expect_eq(valid_seen, 1, "valid pulses (case 2)");
        expect_eq(doy,       9'd60,    "doy (2024-02-29 leap)");
        // 2024-02-29 was a Thursday (weekday=4).
        expect_eq(weekday_v, 3'd4,     "weekday (Thu)");

        $display("--- case 3: invalid month (2026-13-01) ---");
        valid_seen = 0;
        send_frame("T2026-13-01T12:00:00\n");
        #5000;
        expect_eq(valid_seen, 0, "valid pulses (rejected case)");

        $display("--- case 4: invalid hour (2026-04-13T24) ---");
        valid_seen = 0;
        send_frame("T2026-04-13T24:00:00\n");
        #5000;
        expect_eq(valid_seen, 0, "valid pulses (hour rejected)");

        $display("--- case 5: leading garbage then valid frame ---");
        valid_seen = 0;
        send_byte("X");
        send_byte("X");
        send_frame("T2026-12-31T23:59:59\n");
        #5000;
        expect_eq(valid_seen, 1,    "valid pulses (recovered)");
        expect_eq(month_bin,  4'd12, "month_bin (case 5)");
        expect_eq(day_bin,    5'd31, "day_bin (case 5)");
        expect_eq(doy,        9'd365, "doy (2026-12-31 non-leap)");

        $display("=== summary: %0d pass, %0d fail ===", pass_count, fail_count);
        if (fail_count == 0) $display("OK");
        else                 $display("NG");
        $finish;
    end
endmodule
