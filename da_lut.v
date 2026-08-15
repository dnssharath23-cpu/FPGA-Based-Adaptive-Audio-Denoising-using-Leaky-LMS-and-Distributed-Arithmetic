
//  da_lut.v  -  Distributed Arithmetic Inner Product  (v2)
//  Updated: ACC_BITS default raised to 48 to match leaky_lms_core.
//  Computes y = sum_{k=0}^{N-1}  w[k] * x[k]
// ============================================================

module da_lut #(
    parameter N        = 16,
    parameter W_BITS   = 16,
    parameter C_BITS   = 16,
    parameter ACC_BITS = 48        // raised from 36 to 48
)(
    input  wire                        clk,
    input  wire                        rst_n,
    input  wire                        start,
    input  wire [N*W_BITS-1:0]        x_flat,
    input  wire [N*C_BITS-1:0]        w_flat,
    output reg  signed [ACC_BITS-1:0] y_out,
    output reg                         valid
);

    wire signed [W_BITS-1:0] x [0:N-1];
    wire signed [C_BITS-1:0] w [0:N-1];

    genvar gi;
    generate
        for (gi = 0; gi < N; gi = gi + 1) begin : unpack
            assign x[gi] = $signed(x_flat[gi*W_BITS +: W_BITS]);
            assign w[gi] = $signed(w_flat[gi*C_BITS +: C_BITS]);
        end
    endgenerate

    integer k;
    reg signed [ACC_BITS-1:0] partial;
    reg signed [ACC_BITS-1:0] accumulator;
    reg signed [ACC_BITS-1:0] acc_next;
    reg [4:0]  bit_cnt;
    reg        running;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            accumulator <= 0;
            y_out       <= 0;
            valid       <= 0;
            bit_cnt     <= 0;
            running     <= 0;
        end else begin
            valid <= 0;

            if (start && !running) begin
                accumulator <= 0;
                bit_cnt     <= 0;
                running     <= 1;
            end

            if (running) begin
                partial = 0;
                for (k = 0; k < N; k = k + 1) begin
                    if (w[k][bit_cnt])
                        partial = partial +
                                  {{(ACC_BITS-W_BITS){x[k][W_BITS-1]}}, x[k]};
                end

                if (bit_cnt == C_BITS - 1)
                    acc_next = accumulator - (partial <<< bit_cnt);
                else
                    acc_next = accumulator + (partial <<< bit_cnt);

                accumulator <= acc_next;

                if (bit_cnt == C_BITS - 1) begin
                    running <= 0;
                    valid   <= 1;
                    y_out   <= acc_next;
                end else begin
                    bit_cnt <= bit_cnt + 1;
                end
            end
        end
    end

endmodule