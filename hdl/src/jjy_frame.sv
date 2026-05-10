// JJY frame generator (40kHz station tape format).
// Time fields are taken as BCD pairs from the parent module so that the
// counter logic stays simple (BCD increment instead of 10-divide hardware).
// Day-of-year, year and weekday are still passed in BCD too; the parent may
// hardcode them while only minute/hour advance.
// pulse codes: 0=Marker(M/P), 1=One, 2=Zero
module jjy_frame (
    input  logic [1:0] hour_tens,
    input  logic [3:0] hour_ones,
    input  logic [2:0] min_tens,
    input  logic [3:0] min_ones,
    input  logic [1:0] day_hund,
    input  logic [3:0] day_tens,
    input  logic [3:0] day_ones,
    input  logic [3:0] year_tens,
    input  logic [3:0] year_ones,
    input  logic [2:0] weekday,
    input  logic [5:0] sec_in_frame,
    output logic [1:0] pulse
);
    // Even parity over the bits actually transmitted for hour/minute.
    // Hour pattern: {hour_tens[1], hour_tens[0], hour_ones[3:0]} = 6 bits
    // Minute pattern: {min_tens[2:0], min_ones[3:0]} = 7 bits
    logic hour_parity;
    logic min_parity;
    assign hour_parity = ^{hour_tens, hour_ones};
    assign min_parity  = ^{min_tens,  min_ones};

    // Helper: emit a data bit as PULSE_ONE (1) or PULSE_ZERO (2).
    function automatic logic [1:0] bit_pulse(input logic b);
        return b ? 2'd1 : 2'd2;
    endfunction

    always_comb begin
        unique case (sec_in_frame)
            6'd0:  pulse = 2'd0;                          // M
            6'd1:  pulse = bit_pulse(min_tens[2]);        // min 40
            6'd2:  pulse = bit_pulse(min_tens[1]);        // min 20
            6'd3:  pulse = bit_pulse(min_tens[0]);        // min 10
            6'd4:  pulse = 2'd2;                          // 0
            6'd5:  pulse = bit_pulse(min_ones[3]);        // min 8
            6'd6:  pulse = bit_pulse(min_ones[2]);        // min 4
            6'd7:  pulse = bit_pulse(min_ones[1]);        // min 2
            6'd8:  pulse = bit_pulse(min_ones[0]);        // min 1
            6'd9:  pulse = 2'd0;                          // P1

            6'd10, 6'd11: pulse = 2'd2;                   // 0,0
            6'd12: pulse = bit_pulse(hour_tens[1]);       // hr 20
            6'd13: pulse = bit_pulse(hour_tens[0]);       // hr 10
            6'd14: pulse = 2'd2;                          // 0
            6'd15: pulse = bit_pulse(hour_ones[3]);       // hr 8
            6'd16: pulse = bit_pulse(hour_ones[2]);       // hr 4
            6'd17: pulse = bit_pulse(hour_ones[1]);       // hr 2
            6'd18: pulse = bit_pulse(hour_ones[0]);       // hr 1
            6'd19: pulse = 2'd0;                          // P2

            6'd20, 6'd21: pulse = 2'd2;                   // 0,0
            6'd22: pulse = bit_pulse(day_hund[1]);        // day 200
            6'd23: pulse = bit_pulse(day_hund[0]);        // day 100
            6'd24: pulse = 2'd2;                          // 0
            6'd25: pulse = bit_pulse(day_tens[3]);        // day 80
            6'd26: pulse = bit_pulse(day_tens[2]);        // day 40
            6'd27: pulse = bit_pulse(day_tens[1]);        // day 20
            6'd28: pulse = bit_pulse(day_tens[0]);        // day 10
            6'd29: pulse = 2'd0;                          // P3
            6'd30: pulse = bit_pulse(day_ones[3]);        // day 8
            6'd31: pulse = bit_pulse(day_ones[2]);        // day 4
            6'd32: pulse = bit_pulse(day_ones[1]);        // day 2
            6'd33: pulse = bit_pulse(day_ones[0]);        // day 1
            6'd34, 6'd35: pulse = 2'd2;                   // 0,0

            6'd36: pulse = bit_pulse(hour_parity);        // PA1
            6'd37: pulse = bit_pulse(min_parity);         // PA2
            6'd38: pulse = 2'd2;                          // SU1
            6'd39: pulse = 2'd0;                          // P4
            6'd40: pulse = 2'd2;                          // SU2

            6'd41: pulse = bit_pulse(year_tens[3]);       // year 80
            6'd42: pulse = bit_pulse(year_tens[2]);       // year 40
            6'd43: pulse = bit_pulse(year_tens[1]);       // year 20
            6'd44: pulse = bit_pulse(year_tens[0]);       // year 10
            6'd45: pulse = bit_pulse(year_ones[3]);       // year 8
            6'd46: pulse = bit_pulse(year_ones[2]);       // year 4
            6'd47: pulse = bit_pulse(year_ones[1]);       // year 2
            6'd48: pulse = bit_pulse(year_ones[0]);       // year 1
            6'd49: pulse = 2'd0;                          // P5

            6'd50: pulse = bit_pulse(weekday[2]);         // wk 4
            6'd51: pulse = bit_pulse(weekday[1]);         // wk 2
            6'd52: pulse = bit_pulse(weekday[0]);         // wk 1
            6'd53, 6'd54: pulse = 2'd2;                   // LS1, LS2
            6'd55, 6'd56, 6'd57, 6'd58: pulse = 2'd2;     // 0
            6'd59: pulse = 2'd0;                          // P0
            default: pulse = 2'd2;
        endcase
    end
endmodule
