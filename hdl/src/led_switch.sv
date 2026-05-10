module led_switch #(
    parameter int CLK_HZ = 27_000_000
) (
    input  logic       clk,
    input  logic [1:0] btn,
    output logic [5:0] led
);
    logic btn0_press, btn1_press;

    debouncer #(.CLK_HZ(CLK_HZ)) deb_btn0 (
        .clk       (clk),
        .sig_async (btn[0]),
        .sig_sync  (),
        .pulse_neg (btn0_press)
    );
    debouncer #(.CLK_HZ(CLK_HZ)) deb_btn1 (
        .clk       (clk),
        .sig_async (btn[1]),
        .sig_sync  (),
        .pulse_neg (btn1_press)
    );

    typedef enum logic [1:0] {
        MODE_ALL_ON  = 2'd0,
        MODE_KNIGHT  = 2'd1,
        MODE_ALL_OFF = 2'd2
    } led_mode_t;

    led_mode_t mode = MODE_ALL_ON;
    always_ff @(posedge clk) begin
        if (btn0_press) begin
            unique case (mode)
                MODE_ALL_ON:  mode <= MODE_KNIGHT;
                MODE_KNIGHT:  mode <= MODE_ALL_OFF;
                MODE_ALL_OFF: mode <= MODE_ALL_ON;
                default:      mode <= MODE_ALL_ON;
            endcase
        end
    end

    typedef enum logic [1:0] {
        FREQ_STOP = 2'd0,
        FREQ_1HZ  = 2'd1,
        FREQ_2HZ  = 2'd2,
        FREQ_4HZ  = 2'd3
    } freq_t;

    freq_t freq = FREQ_STOP;
    always_ff @(posedge clk) begin
        if (btn1_press) begin
            unique case (freq)
                FREQ_STOP: freq <= FREQ_1HZ;
                FREQ_1HZ:  freq <= FREQ_2HZ;
                FREQ_2HZ:  freq <= FREQ_4HZ;
                FREQ_4HZ:  freq <= FREQ_STOP;
            endcase
        end
    end

    // tick threshold per blink half-period
    localparam int TICK_W = $clog2(CLK_HZ);
    logic [TICK_W-1:0] tick_threshold;
    always_comb begin
        unique case (freq)
            FREQ_1HZ: tick_threshold = TICK_W'(CLK_HZ / 2  - 1);
            FREQ_2HZ: tick_threshold = TICK_W'(CLK_HZ / 4  - 1);
            FREQ_4HZ: tick_threshold = TICK_W'(CLK_HZ / 8  - 1);
            default:  tick_threshold = '1;
        endcase
    end

    logic [TICK_W-1:0] tick_cnt = '0;
    logic              tick     = 1'b0;
    always_ff @(posedge clk) begin
        if (freq == FREQ_STOP) begin
            tick_cnt <= '0;
            tick     <= 1'b0;
        end else if (tick_cnt == tick_threshold) begin
            tick_cnt <= '0;
            tick     <= 1'b1;
        end else begin
            tick_cnt <= tick_cnt + 1'b1;
            tick     <= 1'b0;
        end
    end

    logic blink_toggle = 1'b0;
    always_ff @(posedge clk) begin
        if (tick) blink_toggle <= ~blink_toggle;
    end

    // knight rider position: 0..5 with bouncing direction
    logic [2:0] pos = 3'd0;
    logic       dir = 1'b0;
    always_ff @(posedge clk) begin
        if (tick) begin
            if (dir == 1'b0) begin
                if (pos == 3'd5) begin
                    dir <= 1'b1;
                    pos <= 3'd4;
                end else begin
                    pos <= pos + 3'd1;
                end
            end else begin
                if (pos == 3'd0) begin
                    dir <= 1'b0;
                    pos <= 3'd1;
                end else begin
                    pos <= pos - 3'd1;
                end
            end
        end
    end

    logic [5:0] pattern;
    always_comb begin
        unique case (mode)
            MODE_ALL_ON:  pattern = (freq == FREQ_STOP) ? 6'b111111 : {6{blink_toggle}};
            MODE_KNIGHT:  pattern = 6'b1 << pos;
            MODE_ALL_OFF: pattern = 6'b0;
            default:      pattern = 6'b0;
        endcase
    end

    // active-low: invert internal pattern to drive LEDs
    assign led = ~pattern;
endmodule
