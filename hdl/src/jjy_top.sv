module jjy_top #(
    parameter int CLK_HZ = 27_000_000
) (
    input  logic clk,
    input  logic uart_rx,
    output logic carrier_led,
    output logic carrier_ant,
    output logic led_marker,
    output logic led_one,
    output logic led_zero,
    output logic led_frame_sync
);
    localparam int MS_TICKS = CLK_HZ / 1000;
    localparam int MS_W     = $clog2(MS_TICKS);

    logic [7:0] uart_byte;
    logic       uart_byte_valid;
    uart_rx #(.CLK_HZ(CLK_HZ)) uart_rx_inst (
        .clk        (clk),
        .rx         (uart_rx),
        .byte_data  (uart_byte),
        .byte_valid (uart_byte_valid)
    );

    // syn_keep / syn_preserve below are precautionary. The time_valid net
    // has high fanout (drives load enables of every BCD register) so GOWIN
    // P&R may promote it onto an LW (Long Wire) low-skew net. That promotion
    // is benign for clock-enable use, but the attributes lock the netlist
    // shape so future re-synthesis cannot accidentally absorb the load
    // path into a constant.
    (* syn_keep = "true" *) logic time_valid;
    logic [11:0] ts_year_full;
    logic [3:0]  ts_year_tens;
    logic [3:0]  ts_year_ones;
    logic [3:0]  ts_month_bin;
    logic [4:0]  ts_day_bin;
    logic [1:0]  ts_hour_tens;
    logic [3:0]  ts_hour_ones;
    logic [2:0]  ts_min_tens;
    logic [3:0]  ts_min_ones;
    logic [5:0]  ts_sec_bin;
    logic ts_proc_busy;
    time_setter time_setter_inst (
        .clk        (clk),
        .byte_data  (uart_byte),
        .byte_valid (uart_byte_valid),
        .time_valid (time_valid),
        .proc_busy  (ts_proc_busy),
        .year_full  (ts_year_full),
        .year_tens  (ts_year_tens),
        .year_ones  (ts_year_ones),
        .month_bin  (ts_month_bin),
        .day_bin    (ts_day_bin),
        .hour_tens  (ts_hour_tens),
        .hour_ones  (ts_hour_ones),
        .min_tens   (ts_min_tens),
        .min_ones   (ts_min_ones),
        .sec_bin    (ts_sec_bin)
    );

    logic [8:0] dc_doy;
    logic [2:0] dc_weekday;
    date_calc date_calc_inst (
        .year    (ts_year_full),
        .month   (ts_month_bin),
        .day     (ts_day_bin),
        .doy     (dc_doy),
        .weekday (dc_weekday)
    );

    logic [3:0] doy_h;
    logic [3:0] doy_t;
    logic [3:0] doy_o;
    bin9_to_bcd doy_bcd_inst (
        .bin      (dc_doy),
        .hundreds (doy_h),
        .tens     (doy_t),
        .ones     (doy_o)
    );

    logic [MS_W-1:0] ms_cnt  = '0;
    logic            ms_tick = 1'b0;
    always_ff @(posedge clk) begin
        if (time_valid) begin
            ms_cnt  <= '0;
            ms_tick <= 1'b0;
        end else if (ms_cnt == MS_W'(MS_TICKS - 1)) begin
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
        if (time_valid) begin
            sec_pos <= 10'd0;
        end else if (ms_tick) begin
            if (sec_pos == 10'd999) sec_pos <= 10'd0;
            else                    sec_pos <= sec_pos + 10'd1;
        end
    end

    logic [5:0] sec_in_frame = 6'd0;
    always_ff @(posedge clk) begin
        if (time_valid) begin
            sec_in_frame <= ts_sec_bin;
        end else if (sec_tick) begin
            if (sec_in_frame == 6'd59) sec_in_frame <= 6'd0;
            else                       sec_in_frame <= sec_in_frame + 6'd1;
        end
    end

    // BCD time registers. Initial value: 2026-04-13 (DOY 103) Mon, 12:00.
    // These get overwritten on every successful UART time-set.
    // syn_preserve prevents the synthesizer from absorbing/optimising any of
    // these registers when the load path looks like a constant assignment.
    (* syn_preserve = "true" *) logic [3:0] min_ones  = 4'd0;
    (* syn_preserve = "true" *) logic [2:0] min_tens  = 3'd0;
    (* syn_preserve = "true" *) logic [3:0] hour_ones = 4'd2;
    (* syn_preserve = "true" *) logic [1:0] hour_tens = 2'd1;
    (* syn_preserve = "true" *) logic [1:0] day_hund  = 2'd1;
    (* syn_preserve = "true" *) logic [3:0] day_tens  = 4'd0;
    (* syn_preserve = "true" *) logic [3:0] day_ones  = 4'd3;
    (* syn_preserve = "true" *) logic [3:0] year_tens = 4'd2;
    (* syn_preserve = "true" *) logic [3:0] year_ones = 4'd6;
    (* syn_preserve = "true" *) logic [2:0] weekday   = 3'd1;

    logic minute_tick;
    assign minute_tick = sec_tick && (sec_in_frame == 6'd59);

    always_ff @(posedge clk) begin
        if (time_valid) begin
            hour_tens <= ts_hour_tens;
            hour_ones <= ts_hour_ones;
            min_tens  <= ts_min_tens;
            min_ones  <= ts_min_ones;
            day_hund  <= doy_h[1:0];
            day_tens  <= doy_t;
            day_ones  <= doy_o;
            year_tens <= ts_year_tens;
            year_ones <= ts_year_ones;
            weekday   <= dc_weekday;
        end else if (minute_tick) begin
            if (min_ones == 4'd9) begin
                min_ones <= 4'd0;
                if (min_tens == 3'd5) begin
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

    logic [1:0] pulse_type;
    jjy_frame frame_inst (
        .hour_tens    (hour_tens),
        .hour_ones    (hour_ones),
        .min_tens     (min_tens),
        .min_ones     (min_ones),
        .day_hund     (day_hund),
        .day_tens     (day_tens),
        .day_ones     (day_ones),
        .year_tens    (year_tens),
        .year_ones    (year_ones),
        .weekday      (weekday),
        .sec_in_frame (sec_in_frame),
        .pulse        (pulse_type)
    );

    jjy_modulator #(.CLK_HZ(CLK_HZ)) mod_inst (
        .clk        (clk),
        .sec_pos    (sec_pos),
        .pulse_type (pulse_type),
        .carrier    (carrier_led)
    );

    assign carrier_ant = carrier_led;

    // ----- Step 4 status indicators -----
    // Each pulse-stretched signal lights its LED long enough to be visible.
    // These doubled as debug aids during bring-up and stay in place to give
    // an at-a-glance view of the receive path during normal operation.
    //   LED2 (led_marker)  : time_valid        -> ~0.5 s after a successful
    //                                             time-set frame (full match)
    //   LED3 (led_one)     : uart_byte_valid   -> ~62 ms per UART byte; a
    //                                             21-byte frame appears as
    //                                             a quick burst
    //   LED4 (led_zero)    : ts_proc_busy      -> ~0.5 s while parser is
    //                                             mid-frame (after 'T')
    //   LED5 (led_frame_sync) : sec_in_frame==0 -> 1 s flash at every minute
    //                                              boundary (frame head)
    logic [24:0] tv_stretch = 25'd0;
    logic [22:0] rx_stretch = 23'd0;
    logic [24:0] busy_stretch = 25'd0;

    always_ff @(posedge clk) begin
        if (time_valid)           tv_stretch <= 25'(CLK_HZ / 2);
        else if (tv_stretch != 0) tv_stretch <= tv_stretch - 25'd1;

        if (uart_byte_valid)      rx_stretch <= 23'(CLK_HZ / 16);
        else if (rx_stretch != 0) rx_stretch <= rx_stretch - 23'd1;

        if (ts_proc_busy)            busy_stretch <= 25'(CLK_HZ / 2);
        else if (busy_stretch != 0)  busy_stretch <= busy_stretch - 25'd1;
    end

    assign led_marker     = ~(tv_stretch    != 25'd0);
    assign led_one        = ~(rx_stretch    != 23'd0);
    assign led_zero       = ~(busy_stretch  != 25'd0);
    assign led_frame_sync = ~(sec_in_frame == 6'd0);
endmodule
