// Parses the 21-byte ASCII time-set protocol "T2026-04-13T12:00:00\n"
// streamed from uart_rx. On success time_valid is pulsed for one clock and
// the binary/BCD outputs hold the parsed value. On format/range error the
// receiver simply rearms and waits for the next 'T'. There is no timeout:
// any stray bytes preceding 'T' are dropped, any in-frame mismatch resets
// the state.
//
// Year is restricted to 2020..2099, mirroring date_calc.sv assumptions.
module time_setter (
    input  logic       clk,
    input  logic [7:0] byte_data,
    input  logic       byte_valid,

    (* syn_preserve = "true" *)
    output logic        time_valid,
    output logic        proc_busy,   // debug: high while idx > 0 (after 'T')
    output logic [11:0] year_full,   // 2020..2099
    output logic [3:0]  year_tens,   // BCD digit for JJY frame
    output logic [3:0]  year_ones,   // BCD digit for JJY frame
    output logic [3:0]  month_bin,   // 1..12
    output logic [4:0]  day_bin,     // 1..31
    output logic [1:0]  hour_tens,
    output logic [3:0]  hour_ones,
    output logic [2:0]  min_tens,
    output logic [3:0]  min_ones,
    output logic [5:0]  sec_bin      // 0..59
);
    function automatic logic is_digit(input logic [7:0] b);
        is_digit = (b >= 8'h30) && (b <= 8'h39);
    endfunction
    function automatic logic [3:0] to_digit(input logic [7:0] b);
        to_digit = b[3:0];
    endfunction

    // idx = number of bytes successfully consumed since 'T'. 0 means waiting
    // for 'T'. Once idx reaches 20 and '\n' is received with all checks ok,
    // we pulse time_valid and return to idx=0.
    logic [4:0] idx = 5'd0;

    logic [3:0] y_t = 4'd0;
    logic [3:0] y_o = 4'd0;
    logic [3:0] mo_t = 4'd0;
    logic [3:0] mo_o = 4'd0;
    logic [3:0] da_t = 4'd0;
    logic [3:0] da_o = 4'd0;
    logic [3:0] ho_t = 4'd0;
    logic [3:0] ho_o = 4'd0;
    logic [3:0] mi_t = 4'd0;
    logic [3:0] mi_o = 4'd0;
    logic [3:0] se_t = 4'd0;
    logic [3:0] se_o = 4'd0;

    // Cross-field range checks performed on the trailing '\n':
    //   - month must be 01..12
    //   - day   must be 01..31 (calendar-month strict check is skipped)
    //   - hour  must be 00..23 (HH<=23)
    //   - min/sec already constrained per-byte to 00..59
    //   - year_tens already constrained to >= 2 per-byte (2020..2099)
    logic month_valid;
    logic day_valid;
    logic hour_valid;
    assign month_valid = (mo_t == 4'd0 && mo_o >= 4'd1)
                       || (mo_t == 4'd1 && mo_o <= 4'd2);
    assign day_valid   = (da_t == 4'd0 && da_o >= 4'd1)
                       || (da_t == 4'd1)
                       || (da_t == 4'd2)
                       || (da_t == 4'd3 && da_o <= 4'd1);
    assign hour_valid  = (ho_t <= 4'd1)
                       || (ho_t == 4'd2 && ho_o <= 4'd3);

    always_ff @(posedge clk) begin
        time_valid <= 1'b0;
        if (byte_valid) begin
            unique case (idx)
                5'd0: begin
                    if (byte_data == 8'h54) idx <= 5'd1; // 'T'
                end
                5'd1: begin
                    if (byte_data == 8'h32) idx <= 5'd2; // year thousands '2'
                    else                    idx <= 5'd0;
                end
                5'd2: begin
                    if (byte_data == 8'h30) idx <= 5'd3; // year hundreds '0'
                    else                    idx <= 5'd0;
                end
                5'd3: begin
                    if (is_digit(byte_data) && byte_data >= 8'h32) begin
                        y_t <= to_digit(byte_data);
                        idx <= 5'd4;
                    end else idx <= 5'd0;
                end
                5'd4: begin
                    if (is_digit(byte_data)) begin
                        y_o <= to_digit(byte_data);
                        idx <= 5'd5;
                    end else idx <= 5'd0;
                end
                5'd5: begin
                    if (byte_data == 8'h2D) idx <= 5'd6; // '-'
                    else                    idx <= 5'd0;
                end
                5'd6: begin
                    if (is_digit(byte_data) && byte_data <= 8'h31) begin
                        mo_t <= to_digit(byte_data);
                        idx  <= 5'd7;
                    end else idx <= 5'd0;
                end
                5'd7: begin
                    if (is_digit(byte_data)) begin
                        mo_o <= to_digit(byte_data);
                        idx  <= 5'd8;
                    end else idx <= 5'd0;
                end
                5'd8: begin
                    if (byte_data == 8'h2D) idx <= 5'd9;
                    else                    idx <= 5'd0;
                end
                5'd9: begin
                    if (is_digit(byte_data) && byte_data <= 8'h33) begin
                        da_t <= to_digit(byte_data);
                        idx  <= 5'd10;
                    end else idx <= 5'd0;
                end
                5'd10: begin
                    if (is_digit(byte_data)) begin
                        da_o <= to_digit(byte_data);
                        idx  <= 5'd11;
                    end else idx <= 5'd0;
                end
                5'd11: begin
                    if (byte_data == 8'h54) idx <= 5'd12; // 'T'
                    else                    idx <= 5'd0;
                end
                5'd12: begin
                    if (is_digit(byte_data) && byte_data <= 8'h32) begin
                        ho_t <= to_digit(byte_data);
                        idx  <= 5'd13;
                    end else idx <= 5'd0;
                end
                5'd13: begin
                    if (is_digit(byte_data)) begin
                        ho_o <= to_digit(byte_data);
                        idx  <= 5'd14;
                    end else idx <= 5'd0;
                end
                5'd14: begin
                    if (byte_data == 8'h3A) idx <= 5'd15; // ':'
                    else                    idx <= 5'd0;
                end
                5'd15: begin
                    if (is_digit(byte_data) && byte_data <= 8'h35) begin
                        mi_t <= to_digit(byte_data);
                        idx  <= 5'd16;
                    end else idx <= 5'd0;
                end
                5'd16: begin
                    if (is_digit(byte_data)) begin
                        mi_o <= to_digit(byte_data);
                        idx  <= 5'd17;
                    end else idx <= 5'd0;
                end
                5'd17: begin
                    if (byte_data == 8'h3A) idx <= 5'd18;
                    else                    idx <= 5'd0;
                end
                5'd18: begin
                    if (is_digit(byte_data) && byte_data <= 8'h35) begin
                        se_t <= to_digit(byte_data);
                        idx  <= 5'd19;
                    end else idx <= 5'd0;
                end
                5'd19: begin
                    if (is_digit(byte_data)) begin
                        se_o <= to_digit(byte_data);
                        idx  <= 5'd20;
                    end else idx <= 5'd0;
                end
                5'd20: begin
                    if (byte_data == 8'h0A
                        && month_valid && day_valid && hour_valid) begin
                        time_valid <= 1'b1;
                    end
                    idx <= 5'd0;
                end
                default: idx <= 5'd0;
            endcase
        end
    end

    // Combinational outputs derived from the latched BCD digits. They are
    // valid the same cycle time_valid is asserted (digits were latched on
    // earlier byte_valid pulses).
    assign year_full = 12'd2000
                     + 12'(y_t) * 12'd10
                     + 12'(y_o);
    assign year_tens = y_t;
    assign year_ones = y_o;
    assign month_bin = 4'(mo_t * 4'd10 + mo_o);
    assign day_bin   = 5'(da_t * 4'd10 + da_o);
    assign hour_tens = ho_t[1:0];
    assign hour_ones = ho_o;
    assign min_tens  = mi_t[2:0];
    assign min_ones  = mi_o;
    assign sec_bin   = 6'(se_t * 4'd10 + se_o);
    assign proc_busy = (idx != 5'd0);
endmodule
