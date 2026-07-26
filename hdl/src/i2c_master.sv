// Byte-level I2C bus master. Open-drain SDA/SCL (drive low or release);
// no clock stretching support, single-master only. The parent FSM issues
// one command per req pulse: START (also serves as repeated start),
// WRITE (8 bits + slave ACK sample), READ (8 bits + master ACK/NACK), STOP.
// SDA only changes one quarter-bit after the SCL falling edge, giving
// 2.5 us hold/setup margins at 100kHz.
module i2c_master #(
    parameter int CLK_HZ = 27_000_000,
    parameter int SCL_HZ = 100_000
) (
    input  logic       clk,
    input  logic       req,
    input  logic [1:0] cmd,
    input  logic [7:0] wr_data,
    input  logic       rd_nack,   // 1: answer NACK to the byte being read
    output logic [7:0] rd_data,
    output logic       done,      // 1-clock pulse at command completion
    output logic       nack,      // WRITE: slave answered NACK
    input  logic       sda_in,
    output logic       sda_oe,    // 1: drive SDA low
    output logic       scl_oe     // 1: drive SCL low
);
    localparam logic [1:0] CMD_START = 2'd0;
    localparam logic [1:0] CMD_WRITE = 2'd1;
    localparam logic [1:0] CMD_READ  = 2'd2;
    localparam logic [1:0] CMD_STOP  = 2'd3;

    localparam int QDIV = CLK_HZ / (SCL_HZ * 4);
    localparam int QDW  = $clog2(QDIV);

    logic sda_meta = 1'b1;
    logic sda_s    = 1'b1;
    always_ff @(posedge clk) begin
        sda_meta <= sda_in;
        sda_s    <= sda_meta;
    end

    logic           run   = 1'b0;
    logic [1:0]     c     = 2'd0;
    logic [7:0]     wdata = 8'd0;
    logic           rnack = 1'b0;
    logic [QDW-1:0] qcnt  = '0;
    logic [1:0]     phase = 2'd0;
    logic [3:0]     bitn  = 4'd0;   // 0..7 data bits, 8 = ACK slot

    logic qtick;
    assign qtick = run && (qcnt == QDW'(QDIV - 1));

    logic sda_oe_r = 1'b0;
    logic scl_oe_r = 1'b0;
    logic done_r   = 1'b0;
    logic nack_r   = 1'b0;
    assign sda_oe = sda_oe_r;
    assign scl_oe = scl_oe_r;
    assign done   = done_r;
    assign nack   = nack_r;

    always_ff @(posedge clk) begin
        done_r <= 1'b0;
        if (!run) begin
            if (req) begin
                run   <= 1'b1;
                c     <= cmd;
                wdata <= wr_data;
                rnack <= rd_nack;
                qcnt  <= '0;
                phase <= 2'd0;
                bitn  <= 4'd0;
            end
        end else if (!qtick) begin
            qcnt <= qcnt + 1'b1;
        end else begin
            qcnt <= '0;
            unique case (c)
                CMD_START: begin
                    unique case (phase)
                        2'd0: begin sda_oe_r <= 1'b0; scl_oe_r <= 1'b1; phase <= 2'd1; end
                        2'd1: begin scl_oe_r <= 1'b0; phase <= 2'd2; end
                        2'd2: begin sda_oe_r <= 1'b1; phase <= 2'd3; end
                        2'd3: begin scl_oe_r <= 1'b1; run <= 1'b0; done_r   <= 1'b1; end
                    endcase
                end
                CMD_WRITE: begin
                    unique case (phase)
                        2'd0: begin
                            scl_oe_r <= 1'b1;
                            sda_oe_r <= (bitn == 4'd8) ? 1'b0 : ~wdata[7];
                            phase  <= 2'd1;
                        end
                        2'd1: begin scl_oe_r <= 1'b0; phase <= 2'd2; end
                        2'd2: begin
                            if (bitn == 4'd8) nack_r <= sda_s;
                            phase <= 2'd3;
                        end
                        2'd3: begin
                            scl_oe_r <= 1'b1;
                            wdata  <= {wdata[6:0], 1'b0};
                            phase  <= 2'd0;
                            if (bitn == 4'd8) begin
                                sda_oe_r <= 1'b0;
                                run    <= 1'b0;
                                done_r   <= 1'b1;
                            end else begin
                                bitn <= bitn + 4'd1;
                            end
                        end
                    endcase
                end
                CMD_READ: begin
                    unique case (phase)
                        2'd0: begin
                            scl_oe_r <= 1'b1;
                            sda_oe_r <= (bitn == 4'd8) ? ~rnack : 1'b0;
                            phase  <= 2'd1;
                        end
                        2'd1: begin scl_oe_r <= 1'b0; phase <= 2'd2; end
                        2'd2: begin
                            if (bitn != 4'd8) rd_data <= {rd_data[6:0], sda_s};
                            phase <= 2'd3;
                        end
                        2'd3: begin
                            scl_oe_r <= 1'b1;
                            phase  <= 2'd0;
                            if (bitn == 4'd8) begin
                                sda_oe_r <= 1'b0;
                                run    <= 1'b0;
                                done_r   <= 1'b1;
                            end else begin
                                bitn <= bitn + 4'd1;
                            end
                        end
                    endcase
                end
                CMD_STOP: begin
                    unique case (phase)
                        2'd0: begin sda_oe_r <= 1'b1; scl_oe_r <= 1'b1; phase <= 2'd1; end
                        2'd1: begin scl_oe_r <= 1'b0; phase <= 2'd2; end
                        2'd2: begin sda_oe_r <= 1'b0; phase <= 2'd3; end
                        2'd3: begin run <= 1'b0; done_r   <= 1'b1; end
                    endcase
                end
            endcase
        end
    end
endmodule
