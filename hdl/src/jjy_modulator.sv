module jjy_modulator #(
    parameter int CLK_HZ = 27_000_000
) (
    input  logic       clk,
    input  logic [9:0] sec_pos,    // 0..999 (ms position within current second)
    input  logic [1:0] pulse_type, // 0=Marker, 1=One, 2=Zero
    output logic       carrier
);
    logic carrier_40k;
    carrier_40khz #(.CLK_HZ(CLK_HZ)) carrier_inst (
        .clk     (clk),
        .carrier (carrier_40k)
    );

    // JJY official spec (NICT): each second starts at amplitude 100% (RF on)
    // and drops to 10% (RF off) after the pulse width. Pulse widths are:
    //   Marker: 200 ms ON, then 800 ms OFF
    //   One:    500 ms ON, then 500 ms OFF
    //   Zero:   800 ms ON, then 200 ms OFF
    logic [9:0] on_ms;
    always_comb begin
        unique case (pulse_type)
            2'd0:    on_ms = 10'd200; // Marker
            2'd1:    on_ms = 10'd500; // One
            2'd2:    on_ms = 10'd800; // Zero
            default: on_ms = 10'd0;
        endcase
    end

    // OOK: pass through 40kHz carrier (LED half-bright, RF on) during the
    // leading on_ms window, then drive carrier high (LED off, RF off).
    logic carrier_on;
    assign carrier_on = (sec_pos < on_ms);
    assign carrier    = carrier_on ? carrier_40k : 1'b1;
endmodule
