// RX8900 (AE-RX8900) controller: one-shot init, startup / periodic time
// read-out aligned to the FOUT 1Hz edge, and time write-back on PC sync.
// Drives i2c_master one command at a time through a small burst engine.
//
// Register assumptions (Epson RX8900 application manual, ETM45J):
//   0x0D Extension : FSEL[1:0] = bits[3:2], "10" -> FOUT 1Hz
//   0x0E Flag      : VLF = bit1 (oscillation stop / data lost)
//   0x0F Control   : CSEL[1:0] = bits[7:6] (keep default "01"), RESET = bit0
//   0x18 Backup    : VDETOFF = bit3, SWOFF = bit2 -> 0x0C disables charging
//                    (primary battery + external protection diode)
//   0x03 WEEK      : one-hot, bit0 = Sunday .. bit6 = Saturday
module rx8900_ctrl #(
    parameter int CLK_HZ     = 27_000_000,
    parameter int PWRUP_MS   = 500,
    parameter int RESYNC_SEC = 3600
)(
    input  logic clk,

    output logic       i2c_req,
    output logic [1:0] i2c_cmd,
    output logic [7:0] i2c_wr_data,
    output logic       i2c_rd_nack,
    input  logic [7:0] i2c_rd_data,
    input  logic       i2c_done,
    input  logic       i2c_nack,

    // Write-back request (PC sync). Fields sampled on the set_req pulse.
    input  logic       set_req,
    input  logic [3:0] set_year_tens,
    input  logic [3:0] set_year_ones,
    input  logic [3:0] set_month_bin,
    input  logic [4:0] set_day_bin,
    input  logic [1:0] set_hour_tens,
    input  logic [3:0] set_hour_ones,
    input  logic [2:0] set_min_tens,
    input  logic [3:0] set_min_ones,
    input  logic [5:0] set_sec_bin,
    input  logic [2:0] set_weekday,

    input  logic       fout_edge,

    // Time source towards time_arbiter. rtc_strobe pulses right after an
    // FOUT edge, so the value marks a fresh second boundary.
    output logic        rtc_valid,
    output logic        rtc_strobe,
    output logic [11:0] rtc_year_full,
    output logic [3:0]  rtc_year_tens,
    output logic [3:0]  rtc_year_ones,
    output logic [3:0]  rtc_month_bin,
    output logic [4:0]  rtc_day_bin,
    output logic [1:0]  rtc_hour_tens,
    output logic [3:0]  rtc_hour_ones,
    output logic [2:0]  rtc_min_tens,
    output logic [3:0]  rtc_min_ones,
    output logic [5:0]  rtc_sec_bin,

    output logic        init_done   // FSEL=1Hz active: FOUT discipline usable
);
    localparam logic [1:0] CMD_START = 2'd0;
    localparam logic [1:0] CMD_WRITE = 2'd1;
    localparam logic [1:0] CMD_READ  = 2'd2;
    localparam logic [1:0] CMD_STOP  = 2'd3;

    localparam logic [7:0] ADDR_WR = 8'h64;   // 0x32 << 1
    localparam logic [7:0] ADDR_RD = 8'h65;

    // ---- burst engine: one register-addressed read/write per t_go ----
    logic       t_go   = 1'b0;
    logic       t_read = 1'b0;
    logic [7:0] t_reg  = 8'd0;
    logic [2:0] t_len  = 3'd1;
    logic [7:0] wbuf [0:6];
    logic [7:0] rbuf [0:6];
    logic       t_done = 1'b0;
    logic       t_err  = 1'b0;

    localparam logic [3:0] E_IDLE   = 4'd0;
    localparam logic [3:0] E_START  = 4'd1;
    localparam logic [3:0] E_ADDR   = 4'd2;
    localparam logic [3:0] E_REG    = 4'd3;
    localparam logic [3:0] E_RSTART = 4'd4;
    localparam logic [3:0] E_ADDRR  = 4'd5;
    localparam logic [3:0] E_WDATA  = 4'd6;
    localparam logic [3:0] E_RDATA  = 4'd7;
    localparam logic [3:0] E_STOP   = 4'd8;
    localparam logic [3:0] E_ABORT  = 4'd9;

    logic [3:0] eng = E_IDLE;
    logic [2:0] idx = 3'd0;

    always_ff @(posedge clk) begin
        i2c_req <= 1'b0;
        t_done  <= 1'b0;
        t_err   <= 1'b0;
        unique case (eng)
            E_IDLE: if (t_go) begin
                idx     <= 3'd0;
                i2c_req <= 1'b1;
                i2c_cmd <= CMD_START;
                eng     <= E_START;
            end
            E_START: if (i2c_done) begin
                i2c_req     <= 1'b1;
                i2c_cmd     <= CMD_WRITE;
                i2c_wr_data <= ADDR_WR;
                eng         <= E_ADDR;
            end
            E_ADDR: if (i2c_done) begin
                i2c_req <= 1'b1;
                if (i2c_nack) begin
                    i2c_cmd <= CMD_STOP;
                    eng     <= E_ABORT;
                end else begin
                    i2c_cmd     <= CMD_WRITE;
                    i2c_wr_data <= t_reg;
                    eng         <= E_REG;
                end
            end
            E_REG: if (i2c_done) begin
                i2c_req <= 1'b1;
                if (i2c_nack) begin
                    i2c_cmd <= CMD_STOP;
                    eng     <= E_ABORT;
                end else if (t_read) begin
                    i2c_cmd <= CMD_START;
                    eng     <= E_RSTART;
                end else begin
                    i2c_cmd     <= CMD_WRITE;
                    i2c_wr_data <= wbuf[0];
                    eng         <= E_WDATA;
                end
            end
            E_RSTART: if (i2c_done) begin
                i2c_req     <= 1'b1;
                i2c_cmd     <= CMD_WRITE;
                i2c_wr_data <= ADDR_RD;
                eng         <= E_ADDRR;
            end
            E_ADDRR: if (i2c_done) begin
                i2c_req <= 1'b1;
                if (i2c_nack) begin
                    i2c_cmd <= CMD_STOP;
                    eng     <= E_ABORT;
                end else begin
                    i2c_cmd     <= CMD_READ;
                    i2c_rd_nack <= (t_len == 3'd1);
                    eng         <= E_RDATA;
                end
            end
            E_RDATA: if (i2c_done) begin
                rbuf[idx] <= i2c_rd_data;
                i2c_req   <= 1'b1;
                if (idx == t_len - 3'd1) begin
                    i2c_cmd <= CMD_STOP;
                    eng     <= E_STOP;
                end else begin
                    idx         <= idx + 3'd1;
                    i2c_cmd     <= CMD_READ;
                    i2c_rd_nack <= (idx == t_len - 3'd2);
                end
            end
            E_WDATA: if (i2c_done) begin
                i2c_req <= 1'b1;
                if (i2c_nack) begin
                    i2c_cmd <= CMD_STOP;
                    eng     <= E_ABORT;
                end else if (idx == t_len - 3'd1) begin
                    i2c_cmd <= CMD_STOP;
                    eng     <= E_STOP;
                end else begin
                    idx         <= idx + 3'd1;
                    i2c_cmd     <= CMD_WRITE;
                    i2c_wr_data <= wbuf[idx + 3'd1];
                end
            end
            E_STOP: if (i2c_done) begin
                t_done <= 1'b1;
                eng    <= E_IDLE;
            end
            E_ABORT: if (i2c_done) begin
                t_err <= 1'b1;
                eng   <= E_IDLE;
            end
            default: eng <= E_IDLE;
        endcase
    end

    // ---- binary -> RX8900 BCD conversions for write-back ----
    function automatic logic [7:0] bcd6(input logic [5:0] b);
        logic [2:0] t;
        t = (b >= 6'd50) ? 3'd5 : (b >= 6'd40) ? 3'd4 : (b >= 6'd30) ? 3'd3
          : (b >= 6'd20) ? 3'd2 : (b >= 6'd10) ? 3'd1 : 3'd0;
        bcd6 = {1'b0, t, 4'(b - 6'(t) * 6'd10)};
    endfunction

    function automatic logic [7:0] bcd5(input logic [4:0] b);
        logic [1:0] t;
        t = (b >= 5'd30) ? 2'd3 : (b >= 5'd20) ? 2'd2 : (b >= 5'd10) ? 2'd1 : 2'd0;
        bcd5 = {2'b00, t, 4'(b - 5'(t) * 5'd10)};
    endfunction

    function automatic logic [7:0] bcd_month(input logic [3:0] m);
        bcd_month = (m >= 4'd10) ? {3'b000, 1'b1, 4'(m - 4'd10)} : {4'b0000, m};
    endfunction

    // ---- read-out parse + sanity check ----
    logic [5:0] p_sec_bin;
    logic [3:0] p_mon_bin;
    logic [5:0] p_day_bin;
    logic parse_ok;

    assign p_sec_bin = 6'(rbuf[0][6:4]) * 6'd10 + 6'(rbuf[0][3:0]);
    assign p_mon_bin = rbuf[5][4] ? (4'd10 + rbuf[5][3:0]) : rbuf[5][3:0];
    assign p_day_bin = 6'(rbuf[4][5:4]) * 6'd10 + 6'(rbuf[4][3:0]);

    assign parse_ok =
           (rbuf[0][3:0] <= 4'd9) && (rbuf[0][6:4] <= 3'd5)
        && (rbuf[1][3:0] <= 4'd9) && (rbuf[1][6:4] <= 3'd5)
        && (rbuf[2][3:0] <= 4'd9)
        && ((rbuf[2][5:4] <= 2'd1) || (rbuf[2][5:4] == 2'd2 && rbuf[2][3:0] <= 4'd3))
        && (rbuf[4][3:0] <= 4'd9)
        && (p_day_bin >= 6'd1) && (p_day_bin <= 6'd31)
        && (rbuf[5][3:0] <= 4'd9)
        && (p_mon_bin >= 4'd1) && (p_mon_bin <= 4'd12)
        && (rbuf[6][7:4] <= 4'd9) && (rbuf[6][3:0] <= 4'd9);

    // ---- main FSM ----
    localparam int PWRUP_CYC = (CLK_HZ / 1000) * PWRUP_MS;
    localparam int ERR_CYC   = CLK_HZ / 10;

    localparam logic [3:0] M_PWRUP     = 4'd0;
    localparam logic [3:0] M_FLAG_RD   = 4'd1;
    localparam logic [3:0] M_INIT_EXT  = 4'd2;
    localparam logic [3:0] M_INIT_BKUP = 4'd3;
    localparam logic [3:0] M_INIT_FCLR = 4'd4;
    localparam logic [3:0] M_IDLE      = 4'd5;
    localparam logic [3:0] M_RD_EDGE   = 4'd6;
    localparam logic [3:0] M_RD        = 4'd7;
    localparam logic [3:0] M_SET_HOLD  = 4'd8;
    localparam logic [3:0] M_SET_TIME  = 4'd9;
    localparam logic [3:0] M_SET_REL   = 4'd10;
    localparam logic [3:0] M_SET_FCLR  = 4'd11;
    localparam logic [3:0] M_ERR       = 4'd12;

    logic [3:0]  m           = M_PWRUP;
    logic [3:0]  retry_st    = M_PWRUP;
    logic [24:0] wait_cnt    = 25'd0;
    logic [15:0] resync_cnt  = 16'd0;
    logic        vlf         = 1'b0;
    logic        set_pending = 1'b0;
    logic        rd_request  = 1'b0;
    logic [7:0]  s_buf [0:6];

    logic rtc_valid_r  = 1'b0;
    logic rtc_strobe_r = 1'b0;
    logic init_done_r  = 1'b0;
    assign rtc_valid  = rtc_valid_r;
    assign rtc_strobe = rtc_strobe_r;
    assign init_done  = init_done_r;

    always_ff @(posedge clk) begin
        t_go         <= 1'b0;
        rtc_strobe_r <= 1'b0;

        if (set_req) begin
            s_buf[0]    <= bcd6(set_sec_bin);
            s_buf[1]    <= {1'b0, set_min_tens, set_min_ones};
            s_buf[2]    <= {2'b00, set_hour_tens, set_hour_ones};
            s_buf[3]    <= 8'(8'h01 << set_weekday);
            s_buf[4]    <= bcd5(set_day_bin);
            s_buf[5]    <= bcd_month(set_month_bin);
            s_buf[6]    <= {set_year_tens, set_year_ones};
            set_pending <= 1'b1;
        end

        if (init_done_r && rtc_valid_r && fout_edge) begin
            if (resync_cnt >= 16'(RESYNC_SEC - 1)) begin
                resync_cnt <= 16'd0;
                rd_request <= 1'b1;
            end else begin
                resync_cnt <= resync_cnt + 16'd1;
            end
        end

        unique case (m)
            M_PWRUP: begin
                if (wait_cnt == 25'(PWRUP_CYC - 1)) begin
                    wait_cnt <= 25'd0;
                    t_read   <= 1'b1;
                    t_reg    <= 8'h0E;
                    t_len    <= 3'd1;
                    t_go     <= 1'b1;
                    m        <= M_FLAG_RD;
                end else begin
                    wait_cnt <= wait_cnt + 25'd1;
                end
            end
            M_FLAG_RD: begin
                if (t_done) begin
                    vlf     <= rbuf[0][1];
                    t_read  <= 1'b0;
                    t_reg   <= 8'h0D;
                    t_len   <= 3'd1;
                    wbuf[0] <= 8'h08;      // FSEL = 1Hz
                    t_go    <= 1'b1;
                    m       <= M_INIT_EXT;
                end else if (t_err) begin
                    retry_st <= M_FLAG_RD;
                    m        <= M_ERR;
                end
            end
            M_INIT_EXT: begin
                if (t_done) begin
                    t_reg   <= 8'h18;
                    wbuf[0] <= 8'h0C;      // VDETOFF + SWOFF: no charging
                    t_go    <= 1'b1;
                    m       <= M_INIT_BKUP;
                end else if (t_err) begin
                    retry_st <= M_INIT_EXT;
                    m        <= M_ERR;
                end
            end
            M_INIT_BKUP: begin
                if (t_done) begin
                    t_reg   <= 8'h0E;
                    wbuf[0] <= 8'h00;      // clear VLF/VDET etc.
                    t_go    <= 1'b1;
                    m       <= M_INIT_FCLR;
                end else if (t_err) begin
                    retry_st <= M_INIT_BKUP;
                    m        <= M_ERR;
                end
            end
            M_INIT_FCLR: begin
                if (t_done) begin
                    init_done_r  <= 1'b1;
                    rd_request <= ~vlf;    // VLF=1: time lost, wait for PC sync
                    m          <= M_IDLE;
                end else if (t_err) begin
                    retry_st <= M_INIT_FCLR;
                    m        <= M_ERR;
                end
            end
            M_IDLE: begin
                if (set_pending) begin
                    set_pending <= 1'b0;
                    t_read      <= 1'b0;
                    t_reg       <= 8'h0F;
                    t_len       <= 3'd1;
                    wbuf[0]     <= 8'h41;  // CSEL=01 kept, RESET=1
                    t_go        <= 1'b1;
                    m           <= M_SET_HOLD;
                end else if (rd_request) begin
                    m <= M_RD_EDGE;
                end
            end
            M_RD_EDGE: begin
                if (set_pending) begin
                    m <= M_IDLE;
                end else if (fout_edge) begin
                    rd_request <= 1'b0;
                    t_read     <= 1'b1;
                    t_reg      <= 8'h00;
                    t_len      <= 3'd7;
                    t_go       <= 1'b1;
                    m          <= M_RD;
                end
            end
            M_RD: begin
                if (t_done) begin
                    if (parse_ok) begin
                        rtc_sec_bin   <= p_sec_bin;
                        rtc_min_tens  <= rbuf[1][6:4];
                        rtc_min_ones  <= rbuf[1][3:0];
                        rtc_hour_tens <= rbuf[2][5:4];
                        rtc_hour_ones <= rbuf[2][3:0];
                        rtc_day_bin   <= p_day_bin[4:0];
                        rtc_month_bin <= p_mon_bin;
                        rtc_year_tens <= rbuf[6][7:4];
                        rtc_year_ones <= rbuf[6][3:0];
                        rtc_year_full <= 12'd2000 + 12'(rbuf[6][7:4]) * 12'd10
                                       + 12'(rbuf[6][3:0]);
                        rtc_strobe_r <= 1'b1;
                        rtc_valid_r  <= 1'b1;
                    end else begin
                        rd_request <= 1'b1;   // retry at the next edge
                    end
                    m <= M_IDLE;
                end else if (t_err) begin
                    rd_request <= 1'b1;
                    m          <= M_IDLE;
                end
            end
            M_SET_HOLD: begin
                if (t_done) begin
                    wbuf[0] <= s_buf[0];
                    wbuf[1] <= s_buf[1];
                    wbuf[2] <= s_buf[2];
                    wbuf[3] <= s_buf[3];
                    wbuf[4] <= s_buf[4];
                    wbuf[5] <= s_buf[5];
                    wbuf[6] <= s_buf[6];
                    t_reg   <= 8'h00;
                    t_len   <= 3'd7;
                    t_go    <= 1'b1;
                    m       <= M_SET_TIME;
                end else if (t_err) begin
                    retry_st <= M_SET_HOLD;
                    m        <= M_ERR;
                end
            end
            M_SET_TIME: begin
                if (t_done) begin
                    t_reg   <= 8'h0F;
                    t_len   <= 3'd1;
                    wbuf[0] <= 8'h40;      // release RESET, sub-second restarts
                    t_go    <= 1'b1;
                    m       <= M_SET_REL;
                end else if (t_err) begin
                    retry_st <= M_SET_TIME;
                    m        <= M_ERR;
                end
            end
            M_SET_REL: begin
                if (t_done) begin
                    t_reg   <= 8'h0E;
                    wbuf[0] <= 8'h00;
                    t_go    <= 1'b1;
                    m       <= M_SET_FCLR;
                end else if (t_err) begin
                    retry_st <= M_SET_REL;
                    m        <= M_ERR;
                end
            end
            M_SET_FCLR: begin
                if (t_done) begin
                    rtc_valid_r  <= 1'b1;
                    m         <= M_IDLE;
                end else if (t_err) begin
                    retry_st <= M_SET_FCLR;
                    m        <= M_ERR;
                end
            end
            M_ERR: begin
                if (wait_cnt == 25'(ERR_CYC - 1)) begin
                    wait_cnt <= 25'd0;
                    t_go     <= 1'b1;
                    m        <= retry_st;
                end else begin
                    wait_cnt <= wait_cnt + 25'd1;
                end
            end
            default: m <= M_IDLE;
        endcase
    end
endmodule
