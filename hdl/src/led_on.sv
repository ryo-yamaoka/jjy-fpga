module led_on (
    output logic led
);
    // active-low: 0 to light up
    assign led = 1'b0;
endmodule
