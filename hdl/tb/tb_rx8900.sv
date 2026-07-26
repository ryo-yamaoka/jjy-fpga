// Testbench for the Step 5 RTC chain (rx8900_ctrl -> i2c_master) against a
// behavioral RX8900 I2C slave model. Checks the init writes (FSEL=1Hz,
// charge disable, flag clear), the FOUT-edge-aligned time read-out, the
// resync re-read, and the PC-sync write-back sequence (RESET hold/release).
//
// Run:
//   iverilog -g2012 -o tb_rx8900.vvp \
//     hdl/tb/tb_rx8900.sv \
//     hdl/src/i2c_master.sv hdl/src/rx8900_ctrl.sv
//   vvp tb_rx8900.vvp
`timescale 1ns/1ps

module tb_rx8900;
    logic clk = 1'b0;
    always #18 clk = ~clk;   // ~27 MHz

    // ---- I2C bus with pull-ups ----
    wire sda, scl;
    pullup (sda);
    pullup (scl);

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
    i2c_master #(.CLK_HZ(27_000_000), .SCL_HZ(100_000)) dut_i2c (
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

    logic        set_req = 1'b0;
    logic [3:0]  set_year_tens, set_year_ones;
    logic [3:0]  set_month_bin;
    logic [4:0]  set_day_bin;
    logic [1:0]  set_hour_tens;
    logic [3:0]  set_hour_ones;
    logic [2:0]  set_min_tens;
    logic [3:0]  set_min_ones;
    logic [5:0]  set_sec_bin;
    logic [2:0]  set_weekday;
    logic        fout_edge = 1'b0;

    logic        rtc_valid, rtc_strobe, init_done;
    logic [11:0] rtc_year_full;
    logic [3:0]  rtc_year_tens, rtc_year_ones, rtc_month_bin;
    logic [4:0]  rtc_day_bin;
    logic [1:0]  rtc_hour_tens;
    logic [3:0]  rtc_hour_ones;
    logic [2:0]  rtc_min_tens;
    logic [3:0]  rtc_min_ones;
    logic [5:0]  rtc_sec_bin;
    rx8900_ctrl #(
        .CLK_HZ     (27_000_000),
        .PWRUP_MS   (1),      // shortened for simulation
        .RESYNC_SEC (4)
    ) dut_ctrl (
        .clk           (clk),
        .i2c_req       (i2c_req),
        .i2c_cmd       (i2c_cmd),
        .i2c_wr_data   (i2c_wr_data),
        .i2c_rd_nack   (i2c_rd_nack),
        .i2c_rd_data   (i2c_rd_data),
        .i2c_done      (i2c_done),
        .i2c_nack      (i2c_nack),
        .set_req       (set_req),
        .set_year_tens (set_year_tens),
        .set_year_ones (set_year_ones),
        .set_month_bin (set_month_bin),
        .set_day_bin   (set_day_bin),
        .set_hour_tens (set_hour_tens),
        .set_hour_ones (set_hour_ones),
        .set_min_tens  (set_min_tens),
        .set_min_ones  (set_min_ones),
        .set_sec_bin   (set_sec_bin),
        .set_weekday   (set_weekday),
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
        .init_done     (init_done)
    );

    // ---- behavioral RX8900 I2C slave ----
    localparam [6:0] SLAVE_ADDR = 7'h32;

    localparam [2:0] PH_ADDR       = 3'd0;
    localparam [2:0] PH_WREG       = 3'd1;
    localparam [2:0] PH_WDATA      = 3'd2;
    localparam [2:0] PH_RDATA_PEND = 3'd3;
    localparam [2:0] PH_RDATA      = 3'd4;
    localparam [2:0] PH_DEAD       = 3'd5;

    reg [7:0] mem [0:255];
    reg       sl_oe   = 1'b0;
    reg       in_txn  = 1'b0;
    reg [2:0] phase   = PH_DEAD;
    integer   bitn    = 0;
    reg [7:0] sh      = 8'd0;
    reg [7:0] rd_byte = 8'd0;
    reg [7:0] ptr     = 8'd0;
    reg       mst_ack = 1'b0;

    assign sda = sl_oe ? 1'b0 : 1'bz;

    always @(negedge sda) if (scl === 1'b1) begin   // START / repeated START
        in_txn = 1'b1;
        phase  = PH_ADDR;
        bitn   = 0;
        sl_oe  = 1'b0;
    end
    always @(posedge sda) if (scl === 1'b1) begin   // STOP
        in_txn = 1'b0;
        phase  = PH_DEAD;
        sl_oe  = 1'b0;
    end

    always @(posedge scl) if (in_txn) begin
        if (bitn < 8) begin
            if (phase != PH_RDATA) sh = {sh[6:0], sda === 1'b1};
            bitn = bitn + 1;
        end else begin
            mst_ack = (sda === 1'b0);
            bitn = 9;
        end
    end

    always @(negedge scl) if (in_txn) begin
        if (bitn >= 1 && bitn <= 7) begin
            if (phase == PH_RDATA) sl_oe = ~rd_byte[7 - bitn];
        end else if (bitn == 8) begin
            if (phase == PH_RDATA) begin
                sl_oe = 1'b0;                     // master ACK slot
            end else if (phase == PH_ADDR) begin
                if (sh[7:1] == SLAVE_ADDR) begin
                    sl_oe = 1'b1;                 // ACK address
                    phase = sh[0] ? PH_RDATA_PEND : PH_WREG;
                end else begin
                    sl_oe = 1'b0;
                    phase = PH_DEAD;
                end
            end else if (phase == PH_WREG) begin
                ptr   = sh;
                phase = PH_WDATA;
                sl_oe = 1'b1;
            end else if (phase == PH_WDATA) begin
                mem[ptr] = sh;
                ptr      = ptr + 8'd1;
                sl_oe    = 1'b1;
            end else begin
                sl_oe = 1'b0;
            end
        end else if (bitn == 9) begin
            sl_oe = 1'b0;
            if (phase == PH_RDATA) begin
                if (mst_ack) begin
                    ptr     = ptr + 8'd1;
                    rd_byte = mem[ptr];
                    sl_oe   = ~rd_byte[7];
                end else begin
                    phase = PH_DEAD;
                end
            end else if (phase == PH_RDATA_PEND) begin
                phase   = PH_RDATA;
                rd_byte = mem[ptr];
                sl_oe   = ~rd_byte[7];
            end
            bitn = 0;
        end
    end else begin
        sl_oe = 1'b0;
    end

    // ---- test sequence ----
    integer errors = 0;

    task check8(input [127:0] name, input [7:0] got, input [7:0] exp);
        if (got !== exp) begin
            $display("NG %0s: got %02h expected %02h", name, got, exp);
            errors = errors + 1;
        end
    endtask

    task pulse_fout;
        begin
            @(posedge clk); #1 fout_edge = 1'b1;
            @(posedge clk); #1 fout_edge = 1'b0;
        end
    endtask

    initial begin
        // preload: 2026-07-07 (Tue) 12:34:56, VLF=0
        mem[8'h00] = 8'h56;
        mem[8'h01] = 8'h34;
        mem[8'h02] = 8'h12;
        mem[8'h03] = 8'h04;   // one-hot Tuesday
        mem[8'h04] = 8'h07;
        mem[8'h05] = 8'h07;
        mem[8'h06] = 8'h26;
        mem[8'h0D] = 8'h00;
        mem[8'h0E] = 8'h00;   // VLF=0
        mem[8'h0F] = 8'h40;
        mem[8'h18] = 8'h00;

        wait (init_done);
        #10_000;
        check8("ext FSEL",  mem[8'h0D], 8'h08);
        check8("backup",    mem[8'h18], 8'h0C);
        check8("flag clr",  mem[8'h0E], 8'h00);

        // startup read waits for the FOUT edge
        if (rtc_valid !== 1'b0) begin
            $display("NG rtc_valid before first read");
            errors = errors + 1;
        end
        pulse_fout();
        wait (rtc_strobe);
        if (rtc_sec_bin   !== 6'd56  || rtc_min_tens !== 3'd3
            || rtc_min_ones !== 4'd4 || rtc_hour_tens !== 2'd1
            || rtc_hour_ones !== 4'd2 || rtc_day_bin !== 5'd7
            || rtc_month_bin !== 4'd7 || rtc_year_full !== 12'd2026
            || rtc_year_tens !== 4'd2 || rtc_year_ones !== 4'd6) begin
            $display("NG read-out: %04d-%02d-%02d %0d%0d:%0d%0d:%02d",
                     rtc_year_full, rtc_month_bin, rtc_day_bin,
                     rtc_hour_tens, rtc_hour_ones, rtc_min_tens, rtc_min_ones,
                     rtc_sec_bin);
            errors = errors + 1;
        end
        if (rtc_valid !== 1'b1) begin
            $display("NG rtc_valid after read");
            errors = errors + 1;
        end

        // periodic resync: RESYNC_SEC(=4) FOUT edges -> another read
        mem[8'h00] = 8'h57;
        repeat (5) begin
            #400_000 pulse_fout();
        end
        wait (rtc_strobe);
        if (rtc_sec_bin !== 6'd57) begin
            $display("NG resync read: sec=%0d", rtc_sec_bin);
            errors = errors + 1;
        end

        // PC-sync write-back: 2026-12-31 (Thu) 23:59:30
        #400_000;
        set_year_tens = 4'd2;  set_year_ones = 4'd6;
        set_month_bin = 4'd12; set_day_bin   = 5'd31;
        set_hour_tens = 2'd2;  set_hour_ones = 4'd3;
        set_min_tens  = 3'd5;  set_min_ones  = 4'd9;
        set_sec_bin   = 6'd30; set_weekday   = 3'd4;
        @(posedge clk); #1 set_req = 1'b1;
        @(posedge clk); #1 set_req = 1'b0;

        #6_000_000;   // let the 4-transaction write sequence finish
        check8("set sec",   mem[8'h00], 8'h30);
        check8("set min",   mem[8'h01], 8'h59);
        check8("set hour",  mem[8'h02], 8'h23);
        check8("set week",  mem[8'h03], 8'h10);   // 1 << 4 (Thursday)
        check8("set day",   mem[8'h04], 8'h31);
        check8("set month", mem[8'h05], 8'h12);
        check8("set year",  mem[8'h06], 8'h26);
        check8("set ctrl",  mem[8'h0F], 8'h40);   // RESET released
        check8("set flag",  mem[8'h0E], 8'h00);

        if (errors == 0) $display("OK");
        else             $display("FAILED: %0d error(s)", errors);
        $finish;
    end

    initial begin
        #200_000_000;
        $display("TIMEOUT");
        $finish;
    end
endmodule
