// Time-source arbiter + second-boundary discipline (Step 5).
//
// Sources, highest priority first (GPS slots in above PC later by adding
// one more input bundle and extending the mux):
//   1. PC over UART (pc_*)  - each load is also forwarded to the RX8900
//                             as a write-back (rtc_set)
//   2. RX8900 RTC   (rtc_*) - startup load and periodic re-read
// When neither strobes the internal counters free-run (final fallback).
//
// Discipline: the RX8900 FOUT (1Hz) rising edge marks the RTC second
// boundary; sec_sync asks the top-level counters to re-phase and count one
// second. Edges landing in the first half of the internal second are
// ignored: legitimate edges always land near sec_pos = 999 because time
// loads themselves happen at second boundaries, so an early edge is stale
// (e.g. the RTC sub-second counter was just reset by a write-back) and
// accepting it would double-count a second.
module time_arbiter #(
    parameter int CLK_HZ = 27_000_000
)(
    input  logic clk,

    input  logic        pc_strobe,
    input  logic [11:0] pc_year_full,
    input  logic [3:0]  pc_year_tens,
    input  logic [3:0]  pc_year_ones,
    input  logic [3:0]  pc_month_bin,
    input  logic [4:0]  pc_day_bin,
    input  logic [1:0]  pc_hour_tens,
    input  logic [3:0]  pc_hour_ones,
    input  logic [2:0]  pc_min_tens,
    input  logic [3:0]  pc_min_ones,
    input  logic [5:0]  pc_sec_bin,

    input  logic        rtc_strobe,
    input  logic [11:0] rtc_year_full,
    input  logic [3:0]  rtc_year_tens,
    input  logic [3:0]  rtc_year_ones,
    input  logic [3:0]  rtc_month_bin,
    input  logic [4:0]  rtc_day_bin,
    input  logic [1:0]  rtc_hour_tens,
    input  logic [3:0]  rtc_hour_ones,
    input  logic [2:0]  rtc_min_tens,
    input  logic [3:0]  rtc_min_ones,
    input  logic [5:0]  rtc_sec_bin,

    input  logic        fout_1hz,        // async pin, synchronized here
    input  logic        discipline_en,   // rx8900_ctrl.init_done
    input  logic [9:0]  sec_pos,

    output logic        fout_edge,       // raw synced rising edge
    output logic        fout_alive,
    output logic        sec_sync,        // gated discipline pulse

    output logic        load,            // 1-clock: load out_* into counters
    output logic        rtc_set,         // 1-clock: write out_* back to RTC
    output logic [11:0] out_year_full,
    output logic [3:0]  out_year_tens,
    output logic [3:0]  out_year_ones,
    output logic [3:0]  out_month_bin,
    output logic [4:0]  out_day_bin,
    output logic [1:0]  out_hour_tens,
    output logic [3:0]  out_hour_ones,
    output logic [2:0]  out_min_tens,
    output logic [3:0]  out_min_ones,
    output logic [5:0]  out_sec_bin
);
    assign load    = pc_strobe | rtc_strobe;
    assign rtc_set = pc_strobe;

    assign out_year_full = pc_strobe ? pc_year_full : rtc_year_full;
    assign out_year_tens = pc_strobe ? pc_year_tens : rtc_year_tens;
    assign out_year_ones = pc_strobe ? pc_year_ones : rtc_year_ones;
    assign out_month_bin = pc_strobe ? pc_month_bin : rtc_month_bin;
    assign out_day_bin   = pc_strobe ? pc_day_bin   : rtc_day_bin;
    assign out_hour_tens = pc_strobe ? pc_hour_tens : rtc_hour_tens;
    assign out_hour_ones = pc_strobe ? pc_hour_ones : rtc_hour_ones;
    assign out_min_tens  = pc_strobe ? pc_min_tens  : rtc_min_tens;
    assign out_min_ones  = pc_strobe ? pc_min_ones  : rtc_min_ones;
    assign out_sec_bin   = pc_strobe ? pc_sec_bin   : rtc_sec_bin;

    logic f_meta = 1'b0;
    logic f_sync = 1'b0;
    logic f_prev = 1'b0;
    always_ff @(posedge clk) begin
        f_meta <= fout_1hz;
        f_sync <= f_meta;
        f_prev <= f_sync;
    end
    assign fout_edge = f_sync & ~f_prev;

    // Watchdog: FOUT counts as alive while edges keep arriving. When the
    // RTC is absent/dead the counters silently fall back to free-run.
    localparam int ALIVE_CYC = CLK_HZ + CLK_HZ / 2;   // 1.5 s
    localparam int ALIVE_W   = $clog2(ALIVE_CYC + 1);

    logic [ALIVE_W-1:0] alive_cnt = ALIVE_W'(ALIVE_CYC);
    always_ff @(posedge clk) begin
        if (fout_edge)                             alive_cnt <= '0;
        else if (alive_cnt != ALIVE_W'(ALIVE_CYC)) alive_cnt <= alive_cnt + 1'b1;
    end
    assign fout_alive = discipline_en && (alive_cnt != ALIVE_W'(ALIVE_CYC));

    assign sec_sync = fout_edge && discipline_en && (sec_pos >= 10'd500);
endmodule
