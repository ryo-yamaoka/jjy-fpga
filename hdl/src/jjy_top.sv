module jjy_top #(
    parameter int CLK_HZ         = 27_000_000,
    parameter int RTC_PWRUP_MS   = 500,
    parameter int RTC_RESYNC_SEC = 3600
) (
    input  logic clk,
    input  logic uart_rx,
    input  logic fout_1hz,      // RX8900 FOUT (1Hz, FOE=H fixed)
    inout  wire  sda,           // open-drain, external 10k pull-up
    inout  wire  scl,           // open-drain, external 10k pull-up
    output logic carrier_led,   // active-low (on-board LED1)
    output logic carrier_ant,   // active-high, idles low (NPN tank driver)
    output logic led_marker,
    output logic led_one,
    output logic led_zero,
    output logic led_frame_sync,
    output logic led_rtc        // lit (low) while RTC time is not established
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

    logic time_valid;
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

    // ----- RX8900 RTC (Step 5) -----
    logic sda_oe, scl_oe;
    assign sda = sda_oe ? 1'b0 : 1'bz;
    assign scl = scl_oe ? 1'b0 : 1'bz;

    logic       i2c_req;
    logic [1:0] i2c_cmd;
    logic [7:0] i2c_wr_data;
    logic       i2c_rd_nack;
    logic [7:0] i2c_rd_data;
    logic       i2c_done;
    logic       i2c_nack;
    i2c_master #(.CLK_HZ(CLK_HZ)) i2c_inst (
        .clk     (clk),
        .req     (i2c_req),
        .cmd     (i2c_cmd),
        .wr_data (i2c_wr_data),
        .rd_nack (i2c_rd_nack),
        .rd_data (i2c_rd_data),
        .done    (i2c_done),
        .nack    (i2c_nack),
        .sda_in  (sda),
        .sda_oe  (sda_oe),
        .scl_oe  (scl_oe)
    );

    logic        rtc_valid;
    logic        rtc_strobe;
    logic [11:0] rtc_year_full;
    logic [3:0]  rtc_year_tens;
    logic [3:0]  rtc_year_ones;
    logic [3:0]  rtc_month_bin;
    logic [4:0]  rtc_day_bin;
    logic [1:0]  rtc_hour_tens;
    logic [3:0]  rtc_hour_ones;
    logic [2:0]  rtc_min_tens;
    logic [3:0]  rtc_min_ones;
    logic [5:0]  rtc_sec_bin;
    logic        rtc_init_done;
    logic        fout_edge;
    logic        fout_alive;
    logic        sec_sync;
    logic        rtc_set;

    // syn_keep / syn_preserve below are precautionary. The load net has
    // high fanout (drives load enables of every BCD register) so GOWIN
    // P&R may promote it onto an LW (Long Wire) low-skew net. That
    // promotion is benign for clock-enable use, but the attributes lock
    // the netlist shape so future re-synthesis cannot accidentally absorb
    // the load path into a constant.
    (* syn_keep = "true" *) logic arb_load;
    logic [11:0] arb_year_full;
    logic [3:0]  arb_year_tens;
    logic [3:0]  arb_year_ones;
    logic [3:0]  arb_month_bin;
    logic [4:0]  arb_day_bin;
    logic [1:0]  arb_hour_tens;
    logic [3:0]  arb_hour_ones;
    logic [2:0]  arb_min_tens;
    logic [3:0]  arb_min_ones;
    logic [5:0]  arb_sec_bin;

    logic [9:0] sec_pos = 10'd0;

    time_arbiter #(.CLK_HZ(CLK_HZ)) arbiter_inst (
        .clk           (clk),
        .pc_strobe     (time_valid),
        .pc_year_full  (ts_year_full),
        .pc_year_tens  (ts_year_tens),
        .pc_year_ones  (ts_year_ones),
        .pc_month_bin  (ts_month_bin),
        .pc_day_bin    (ts_day_bin),
        .pc_hour_tens  (ts_hour_tens),
        .pc_hour_ones  (ts_hour_ones),
        .pc_min_tens   (ts_min_tens),
        .pc_min_ones   (ts_min_ones),
        .pc_sec_bin    (ts_sec_bin),
        .rtc_strobe    (rtc_strobe),
        .rtc_year_full (rtc_year_full),
        .rtc_year_tens (rtc_year_tens),
        .rtc_year_ones (rtc_year_ones),
        .rtc_month_bin (rtc_month_bin),
        .rtc_day_bin   (rtc_day_bin),
        .rtc_hour_tens (rtc_hour_tens),
        .rtc_hour_ones (rtc_hour_ones),
        .rtc_min_tens  (rtc_min_tens),
        .rtc_min_ones  (rtc_min_ones),
        .rtc_sec_bin   (rtc_sec_bin),
        .fout_1hz      (fout_1hz),
        .discipline_en (rtc_init_done),
        .sec_pos       (sec_pos),
        .fout_edge     (fout_edge),
        .fout_alive    (fout_alive),
        .sec_sync      (sec_sync),
        .load          (arb_load),
        .rtc_set       (rtc_set),
        .out_year_full (arb_year_full),
        .out_year_tens (arb_year_tens),
        .out_year_ones (arb_year_ones),
        .out_month_bin (arb_month_bin),
        .out_day_bin   (arb_day_bin),
        .out_hour_tens (arb_hour_tens),
        .out_hour_ones (arb_hour_ones),
        .out_min_tens  (arb_min_tens),
        .out_min_ones  (arb_min_ones),
        .out_sec_bin   (arb_sec_bin)
    );

    logic [8:0] dc_doy;
    logic [2:0] dc_weekday;
    date_calc date_calc_inst (
        .year    (arb_year_full),
        .month   (arb_month_bin),
        .day     (arb_day_bin),
        .doy     (dc_doy),
        .weekday (dc_weekday)
    );

    rx8900_ctrl #(
        .CLK_HZ     (CLK_HZ),
        .PWRUP_MS   (RTC_PWRUP_MS),
        .RESYNC_SEC (RTC_RESYNC_SEC)
    ) rx8900_inst (
        .clk           (clk),
        .i2c_req       (i2c_req),
        .i2c_cmd       (i2c_cmd),
        .i2c_wr_data   (i2c_wr_data),
        .i2c_rd_nack   (i2c_rd_nack),
        .i2c_rd_data   (i2c_rd_data),
        .i2c_done      (i2c_done),
        .i2c_nack      (i2c_nack),
        .set_req       (rtc_set),
        .set_year_tens (arb_year_tens),
        .set_year_ones (arb_year_ones),
        .set_month_bin (arb_month_bin),
        .set_day_bin   (arb_day_bin),
        .set_hour_tens (arb_hour_tens),
        .set_hour_ones (arb_hour_ones),
        .set_min_tens  (arb_min_tens),
        .set_min_ones  (arb_min_ones),
        .set_sec_bin   (arb_sec_bin),
        .set_weekday   (dc_weekday),
        .fout_edge     (fout_edge),
        .rtc_valid     (rtc_valid),
        .rtc_strobe    (rtc_strobe),
        .rtc_year_full (rtc_year_full),
        .rtc_year_tens (rtc_year_tens),
        .rtc_year_ones (rtc_year_ones),
        .rtc_month_bin (rtc_month_bin),
        .rtc_day_bin   (rtc_day_bin),
        .rtc_hour_tens (rtc_hour_tens),
        .rtc_hour_ones (rtc_hour_ones),
        .rtc_min_tens  (rtc_min_tens),
        .rtc_min_ones  (rtc_min_ones),
        .rtc_sec_bin   (rtc_sec_bin),
        .init_done     (rtc_init_done)
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

    // ----- internal time counters -----
    // sec_sync re-phases the millisecond/second counters to the RTC second
    // boundary. While FOUT is alive the free-run wrap is suppressed
    // (sec_pos parks at 999 until the edge arrives), so every second is
    // paced by the RTC; free-run resumes transparently if FOUT dies.
    logic [MS_W-1:0] ms_cnt  = '0;
    logic            ms_tick = 1'b0;
    always_ff @(posedge clk) begin
        if (arb_load || sec_sync) begin
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

    logic sec_tick;
    assign sec_tick = sec_sync
                    || (ms_tick && (sec_pos == 10'd999) && !fout_alive);

    always_ff @(posedge clk) begin
        if (arb_load || sec_sync) begin
            sec_pos <= 10'd0;
        end else if (ms_tick) begin
            if (sec_pos == 10'd999) begin
                if (!fout_alive) sec_pos <= 10'd0;
            end else begin
                sec_pos <= sec_pos + 10'd1;
            end
        end
    end

    logic [5:0] sec_in_frame = 6'd0;
    always_ff @(posedge clk) begin
        if (arb_load) begin
            sec_in_frame <= arb_sec_bin;
        end else if (sec_tick) begin
            if (sec_in_frame == 6'd59) sec_in_frame <= 6'd0;
            else                       sec_in_frame <= sec_in_frame + 6'd1;
        end
    end

    // BCD time registers. Initial value: 2000-01-01 (DOY 1) Sat, 00:00:00.
    // Deliberately implausible so that a failed time load (RTC VLF set and no
    // PC sync yet) is obvious on any clock that picks up the broadcast; it
    // pairs with LED6 as the "time not established" indicator.
    // Overwritten by the arbiter on every PC time-set or RTC read-out.
    // syn_preserve prevents the synthesizer from absorbing/optimising any of
    // these registers when the load path looks like a constant assignment.
    (* syn_preserve = "true" *) logic [3:0] min_ones  = 4'd0;
    (* syn_preserve = "true" *) logic [2:0] min_tens  = 3'd0;
    (* syn_preserve = "true" *) logic [3:0] hour_ones = 4'd0;
    (* syn_preserve = "true" *) logic [1:0] hour_tens = 2'd0;
    (* syn_preserve = "true" *) logic [1:0] day_hund  = 2'd0;
    (* syn_preserve = "true" *) logic [3:0] day_tens  = 4'd0;
    (* syn_preserve = "true" *) logic [3:0] day_ones  = 4'd1;
    (* syn_preserve = "true" *) logic [3:0] year_tens = 4'd0;
    (* syn_preserve = "true" *) logic [3:0] year_ones = 4'd0;
    (* syn_preserve = "true" *) logic [2:0] weekday   = 3'd6;

    logic minute_tick;
    assign minute_tick = sec_tick && (sec_in_frame == 6'd59);

    always_ff @(posedge clk) begin
        if (arb_load) begin
            hour_tens <= arb_hour_tens;
            hour_ones <= arb_hour_ones;
            min_tens  <= arb_min_tens;
            min_ones  <= arb_min_ones;
            day_hund  <= doy_h[1:0];
            day_tens  <= doy_t;
            day_ones  <= doy_o;
            year_tens <= arb_year_tens;
            year_ones <= arb_year_ones;
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
        .carrier    (carrier_ant),
        .carrier_n  (carrier_led)
    );

    // ----- status indicators -----
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
    //   LED6 (led_rtc)     : rtc_valid == 0    -> solid while the RX8900
    //                                             holds no trusted time
    //                                             (VLF set, absent, or bus
    //                                             failure at init)
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
    assign led_rtc        = rtc_valid;
endmodule
