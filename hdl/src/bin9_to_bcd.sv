// 9-bit binary (0..511) -> 3-digit BCD via subtraction ladders.
// Used to convert day-of-year (1..366) into JJY-frame BCD digits without
// depending on the synthesizer's runtime divide support.
module bin9_to_bcd (
    input  logic [8:0] bin,
    output logic [3:0] hundreds,
    output logic [3:0] tens,
    output logic [3:0] ones
);
    logic [8:0] step1;
    logic [8:0] step2;

    always_comb begin
        if      (bin >= 9'd400) begin hundreds = 4'd4; step1 = bin - 9'd400; end
        else if (bin >= 9'd300) begin hundreds = 4'd3; step1 = bin - 9'd300; end
        else if (bin >= 9'd200) begin hundreds = 4'd2; step1 = bin - 9'd200; end
        else if (bin >= 9'd100) begin hundreds = 4'd1; step1 = bin - 9'd100; end
        else                    begin hundreds = 4'd0; step1 = bin;          end
    end

    always_comb begin
        if      (step1 >= 9'd90) begin tens = 4'd9; step2 = step1 - 9'd90; end
        else if (step1 >= 9'd80) begin tens = 4'd8; step2 = step1 - 9'd80; end
        else if (step1 >= 9'd70) begin tens = 4'd7; step2 = step1 - 9'd70; end
        else if (step1 >= 9'd60) begin tens = 4'd6; step2 = step1 - 9'd60; end
        else if (step1 >= 9'd50) begin tens = 4'd5; step2 = step1 - 9'd50; end
        else if (step1 >= 9'd40) begin tens = 4'd4; step2 = step1 - 9'd40; end
        else if (step1 >= 9'd30) begin tens = 4'd3; step2 = step1 - 9'd30; end
        else if (step1 >= 9'd20) begin tens = 4'd2; step2 = step1 - 9'd20; end
        else if (step1 >= 9'd10) begin tens = 4'd1; step2 = step1 - 9'd10; end
        else                     begin tens = 4'd0; step2 = step1;         end
    end

    assign ones = step2[3:0];
endmodule
