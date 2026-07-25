`timescale 1ps/1ps

// Verifies the OOK output polarity required by the Step 6 NPN tank driver:
// carrier (antenna, pin 25) must idle LOW so the transistor is off during the
// amplitude-10% window, and carrier_n (on-board LED, pin 10) must be its
// exact inverse.
module tb_jjy_modulator;
    localparam int CLK_HZ  = 27_000_000;
    localparam int HALF_PS = 18_518;

    int errors = 0;

    task automatic check(input bit cond, input string msg);
        if (cond) $display("[PASS] %s", msg);
        else begin
            $display("[FAIL] %s", msg);
            errors++;
        end
    endtask

    // ---------------- unit level ----------------
    logic       clk = 1'b0;
    logic [9:0] sec_pos = 10'd0;
    logic [1:0] pulse_type = 2'd0;
    logic       carrier, carrier_n;

    always #HALF_PS clk = ~clk;

    jjy_modulator #(.CLK_HZ(CLK_HZ)) dut (
        .clk        (clk),
        .sec_pos    (sec_pos),
        .pulse_type (pulse_type),
        .carrier    (carrier),
        .carrier_n  (carrier_n)
    );

    int inv_err = 0;
    always @(posedge clk) if (carrier_n !== ~carrier) inv_err++;

    // Samples one full 40kHz period (675 clocks) and reports the levels seen.
    task automatic observe(output bit saw_hi, output bit saw_lo);
        saw_hi = 1'b0;
        saw_lo = 1'b0;
        repeat (700) begin
            @(posedge clk);
            if (carrier) saw_hi = 1'b1;
            else         saw_lo = 1'b1;
        end
    endtask

    task automatic check_pulse(input logic [1:0] pt, input int on_ms, input string name);
        bit hi, lo;
        pulse_type = pt;

        sec_pos = 10'd0;
        observe(hi, lo);
        check(hi && lo, $sformatf("%s: carrier toggles at sec_pos=0", name));

        sec_pos = 10'(on_ms - 1);
        observe(hi, lo);
        check(hi && lo, $sformatf("%s: carrier toggles at sec_pos=%0d (last ON ms)", name, on_ms - 1));

        sec_pos = 10'(on_ms);
        observe(hi, lo);
        check(!hi, $sformatf("%s: carrier idles LOW at sec_pos=%0d (first OFF ms)", name, on_ms));

        sec_pos = 10'd999;
        observe(hi, lo);
        check(!hi, $sformatf("%s: carrier idles LOW at sec_pos=999", name));
    endtask

    // ---------------- top level ----------------
    logic       t_clk = 1'b0;
    wire        t_sda, t_scl;
    logic       t_carrier_led, t_carrier_ant;
    logic       t_m, t_o, t_z, t_f, t_r;

    always #HALF_PS t_clk = ~t_clk;
    pullup (t_sda);
    pullup (t_scl);

    jjy_top #(.CLK_HZ(CLK_HZ), .RTC_PWRUP_MS(1), .RTC_RESYNC_SEC(3600)) top (
        .clk            (t_clk),
        .uart_rx        (1'b1),
        .fout_1hz       (1'b0),
        .sda            (t_sda),
        .scl            (t_scl),
        .carrier_led    (t_carrier_led),
        .carrier_ant    (t_carrier_ant),
        .led_marker     (t_m),
        .led_one        (t_o),
        .led_zero       (t_z),
        .led_frame_sync (t_f),
        .led_rtc        (t_r)
    );

    // Expected ON width for the pulse the frame generator is emitting.
    function automatic int exp_on_ms(input logic [1:0] pt);
        case (pt)
            2'd0:    exp_on_ms = 200;
            2'd1:    exp_on_ms = 500;
            2'd2:    exp_on_ms = 800;
            default: exp_on_ms = 0;
        endcase
    endfunction

    int wire_err = 0;   // carrier_led must be the inverse of carrier_ant
    int dc_err   = 0;   // antenna must never sit high outside the ON window
    int on_seen  = 0;   // carrier activity observed inside the ON window

    always @(posedge t_clk) begin
        if (t_carrier_led !== ~t_carrier_ant) wire_err++;
        if (top.sec_pos >= 10'(exp_on_ms(top.pulse_type))) begin
            if (t_carrier_ant !== 1'b0) dc_err++;
        end else if (t_carrier_ant === 1'b1) begin
            on_seen++;
        end
    end

    initial begin
        $display("--- jjy_modulator: OOK polarity ---");
        check_pulse(2'd0, 200, "Marker");
        check_pulse(2'd1, 500, "One");
        check_pulse(2'd2, 800, "Zero");
        check(inv_err == 0, $sformatf("carrier_n is the inverse of carrier (%0d mismatches)", inv_err));

        $display("--- jjy_top: antenna / LED wiring over second 0 (marker) ---");
        #260_000_000_000;   // 260 ms: covers the 200 ms ON window and the OFF transition
        check(wire_err == 0, $sformatf("carrier_led === ~carrier_ant (%0d mismatches)", wire_err));
        check(dc_err == 0, $sformatf("carrier_ant LOW throughout the amplitude-10%% window (%0d violations)", dc_err));
        check(on_seen > 0, $sformatf("carrier_ant active during the ON window (%0d high samples)", on_seen));

        $display("=== summary: %0d error(s) ===", errors);
        if (errors == 0) $display("OK");
        else             $display("NG");
        $finish;
    end
endmodule
