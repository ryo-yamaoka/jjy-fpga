// Combinational year/month/day -> day-of-year + weekday converter.
// Year range is restricted to 2020..2099 (Step 4 spec). Outside this range
// the leap-year and Zeller divisor approximations break down.
//
// weekday encoding follows JJY/NICT convention: 0=Sun, 1=Mon, ..., 6=Sat.
module date_calc (
    input  logic [11:0] year,
    input  logic [3:0]  month,
    input  logic [4:0]  day,
    output logic [8:0]  doy,
    output logic [2:0]  weekday
);
    // Within 2020..2099 the century rule is irrelevant: every year divisible
    // by 4 is a leap year.
    logic is_leap;
    assign is_leap = (year[1:0] == 2'b00);

    logic [8:0] cum_days;
    always_comb begin
        unique case (month)
            4'd1:  cum_days = 9'd0;
            4'd2:  cum_days = 9'd31;
            4'd3:  cum_days = is_leap ? 9'd60  : 9'd59;
            4'd4:  cum_days = is_leap ? 9'd91  : 9'd90;
            4'd5:  cum_days = is_leap ? 9'd121 : 9'd120;
            4'd6:  cum_days = is_leap ? 9'd152 : 9'd151;
            4'd7:  cum_days = is_leap ? 9'd182 : 9'd181;
            4'd8:  cum_days = is_leap ? 9'd213 : 9'd212;
            4'd9:  cum_days = is_leap ? 9'd244 : 9'd243;
            4'd10: cum_days = is_leap ? 9'd274 : 9'd273;
            4'd11: cum_days = is_leap ? 9'd305 : 9'd304;
            4'd12: cum_days = is_leap ? 9'd335 : 9'd334;
            default: cum_days = 9'd0;
        endcase
    end
    assign doy = cum_days + {4'd0, day};

    // Zeller's congruence with Jan/Feb folded into the previous year as
    // months 13/14. Year range 2020..2099 means J = floor(Y_eff/100) is
    // always 20 (even when Y_eff = 2019 for Jan/Feb 2020), so 5*J = 100 and
    // floor(J/4) = 5 are constants.
    logic [3:0]  m_z;
    logic [11:0] year_eff;
    assign m_z      = (month <= 4'd2) ? (month + 4'd12) : month;
    assign year_eff = (month <= 4'd2) ? (year - 12'd1) : year;

    logic [6:0] k_term;
    assign k_term = 7'(year_eff - 12'd2000);

    logic [5:0] m_term;
    always_comb begin
        unique case (m_z)
            4'd3:  m_term = 6'd10;
            4'd4:  m_term = 6'd13;
            4'd5:  m_term = 6'd15;
            4'd6:  m_term = 6'd18;
            4'd7:  m_term = 6'd20;
            4'd8:  m_term = 6'd23;
            4'd9:  m_term = 6'd26;
            4'd10: m_term = 6'd28;
            4'd11: m_term = 6'd31;
            4'd12: m_term = 6'd33;
            4'd13: m_term = 6'd36;
            4'd14: m_term = 6'd39;
            default: m_term = 6'd0;
        endcase
    end

    logic [9:0] zeller_sum;
    assign zeller_sum = 10'(day) + 10'(m_term)
                      + 10'(k_term) + 10'(k_term >> 2)
                      + 10'd5 + 10'd100;

    logic [2:0] zeller_h;
    assign zeller_h = 3'(zeller_sum % 10'd7);

    // Zeller: 0=Sat, 1=Sun, ..., 6=Fri. Remap to JJY (0=Sun..6=Sat).
    assign weekday = (zeller_h == 3'd0) ? 3'd6 : (zeller_h - 3'd1);
endmodule
