module jjy_top #(
    parameter int CLK_HZ = 27_000_000
) (
    input  logic clk,
    output logic carrier_led,
    output logic carrier_ant,
    output logic led_marker,
    output logic led_one,
    output logic led_zero,
    output logic led_frame_sync
);
    localparam int MS_TICKS = CLK_HZ / 1000;
    localparam int MS_W     = $clog2(MS_TICKS);

    logic [MS_W-1:0] ms_cnt  = '0;
    logic            ms_tick = 1'b0;
    always_ff @(posedge clk) begin
        if (ms_cnt == MS_W'(MS_TICKS - 1)) begin
            ms_cnt  <= '0;
            ms_tick <= 1'b1;
        end else begin
            ms_cnt  <= ms_cnt + 1'b1;
            ms_tick <= 1'b0;
        end
    end

    logic [9:0] sec_pos = 10'd0;
    logic       sec_tick;
    assign sec_tick = ms_tick && (sec_pos == 10'd999);

    always_ff @(posedge clk) begin
        if (ms_tick) begin
            if (sec_pos == 10'd999) sec_pos <= 10'd0;
            else                    sec_pos <= sec_pos + 10'd1;
        end
    end

    logic [5:0] sec_in_frame = 6'd0;
    always_ff @(posedge clk) begin
        if (sec_tick) begin
            if (sec_in_frame == 6'd59) sec_in_frame <= 6'd0;
            else                       sec_in_frame <= sec_in_frame + 6'd1;
        end
    end

    // BCD time counter. Initial value: 12:00. Minute advances every 60s,
    // hour advances every 60min, both wrap (24h -> 0h, no day rollover).
    // Day/year/weekday are kept fixed because the receiver only needs frame
    // -to-frame minute progression to declare lock.
    logic [3:0] min_ones  = 4'd0;
    logic [2:0] min_tens  = 3'd0;
    logic [3:0] hour_ones = 4'd2;
    logic [1:0] hour_tens = 2'd1;

    // 1-clock pulse fired right after sec_in_frame increments past 59 -> 0.
    logic minute_tick;
    assign minute_tick = sec_tick && (sec_in_frame == 6'd59);

    always_ff @(posedge clk) begin
        if (minute_tick) begin
            if (min_ones == 4'd9) begin
                min_ones <= 4'd0;
                if (min_tens == 3'd5) begin
                    // 60 min -> hour rollover
                    min_tens <= 3'd0;
                    if ((hour_tens == 2'd2 && hour_ones == 4'd3)
                        || (hour_tens != 2'd2 && hour_ones == 4'd9)) begin
                        hour_ones <= 4'd0;
                        if (hour_tens == 2'd2) hour_tens <= 2'd0;
                        else                   hour_tens <= hour_tens + 2'd1;
                    end else begin
                        hour_ones <= hour_ones + 4'd1;
                    end
                end else begin
                    min_tens <= min_tens + 3'd1;
                end
            end else begin
                min_ones <= min_ones + 4'd1;
            end
        end
    end

    // Hardcoded calendar (2026-04-13 Mon, day 103, year 26).
    // No rollover handling here because Step 3 only needs short-term sync.
    localparam logic [1:0] DAY_HUND_C  = 2'd1;
    localparam logic [3:0] DAY_TENS_C  = 4'd0;
    localparam logic [3:0] DAY_ONES_C  = 4'd3;
    localparam logic [3:0] YEAR_TENS_C = 4'd2;
    localparam logic [3:0] YEAR_ONES_C = 4'd6;
    localparam logic [2:0] WEEKDAY_C   = 3'd1;

    logic [1:0] pulse_type;
    jjy_frame frame_inst (
        .hour_tens    (hour_tens),
        .hour_ones    (hour_ones),
        .min_tens     (min_tens),
        .min_ones     (min_ones),
        .day_hund     (DAY_HUND_C),
        .day_tens     (DAY_TENS_C),
        .day_ones     (DAY_ONES_C),
        .year_tens    (YEAR_TENS_C),
        .year_ones    (YEAR_ONES_C),
        .weekday      (WEEKDAY_C),
        .sec_in_frame (sec_in_frame),
        .pulse        (pulse_type)
    );

    jjy_modulator #(.CLK_HZ(CLK_HZ)) mod_inst (
        .clk        (clk),
        .sec_pos    (sec_pos),
        .pulse_type (pulse_type),
        .carrier    (carrier_led)
    );

    // mirror the same OOK waveform to the external antenna pin
    assign carrier_ant = carrier_led;

    // active-low indicators
    assign led_marker     = ~(pulse_type == 2'd0);
    assign led_one        = ~(pulse_type == 2'd1);
    assign led_zero       = ~(pulse_type == 2'd2);
    assign led_frame_sync = ~(sec_in_frame == 6'd0);
endmodule
