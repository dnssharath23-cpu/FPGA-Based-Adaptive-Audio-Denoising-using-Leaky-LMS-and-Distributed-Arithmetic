
//  leaky_lms_core.v  -  Leaky LMS Adaptive Filter  (v3 FIXED)
//
//  Bug fix in UPDATE_WEIGHTS:
//  Old (broken): ((MU * e) >> 15) * x >> 15
//    Problem: (MU * e) >> 15 truncates to ~14 for typical values,
//             then 14 * x >> 15 = 0 always. Weights never update.
//
//  New (correct): (MU * e * x) >> 30
//    Uses a 48-bit intermediate register so no precision is lost
//    before the single final right-shift by 30.
//
//  ACC_BITS extended to 48 to hold MU(16) * e(16) * x(16) = 48-bit product.
// ============================================================

module leaky_lms_core #(
    parameter N          = 16,
    parameter W_BITS     = 16,
    parameter ACC_BITS   = 48,        // MUST be >= 48 for mu*e*x product
    parameter LAMBDA_Q15 = 32735,
    parameter MU_Q15     = 328
)(
    input  wire                      clk,
    input  wire                      rst_n,
    input  wire                      sample_valid,
    input  wire signed [W_BITS-1:0]  d_n,
    input  wire signed [W_BITS-1:0]  x_in,
    output reg  signed [W_BITS-1:0]  y_n,
    output reg  signed [W_BITS-1:0]  e_n,
    output reg                        output_valid
);

    reg signed [W_BITS-1:0] x_tap [0:N-1];
    reg signed [W_BITS-1:0] w     [0:N-1];

    // ---- Pack arrays into flat buses for da_lut ----
    reg [N*W_BITS-1:0] x_flat;
    reg [N*W_BITS-1:0] w_flat;

    integer pi;
    always @(*) begin
        for (pi = 0; pi < N; pi = pi + 1) begin
            x_flat[pi*W_BITS +: W_BITS] = x_tap[pi];
            w_flat[pi*W_BITS +: W_BITS] = w[pi];
        end
    end

    // ---- DA instance (inner product) ----
    wire signed [ACC_BITS-1:0] y_da;
    wire                        da_valid_wire;
    reg                         da_start;
    reg                         da_valid_latch;

    da_lut #(
        .N(N), .W_BITS(W_BITS), .C_BITS(W_BITS), .ACC_BITS(ACC_BITS)
    ) u_da (
        .clk(clk), .rst_n(rst_n),
        .start(da_start),
        .x_flat(x_flat),
        .w_flat(w_flat),
        .y_out(y_da),
        .valid(da_valid_wire)
    );

    // ---- FSM states ----
    localparam WAIT_SAMPLE    = 3'd0;
    localparam SHIFT_TAPS     = 3'd1;
    localparam START_DA       = 3'd2;
    localparam WAIT_DA        = 3'd3;
    localparam COMPUTE_ERROR  = 3'd4;
    localparam UPDATE_WEIGHTS = 3'd5;
    localparam OUTPUT_STATE   = 3'd6;

    reg [2:0]  state;
    reg [4:0]  upd_cnt;
    reg signed [W_BITS-1:0]   d_reg;
    reg signed [W_BITS-1:0]   e_reg;

    // Wide intermediate for weight update: MU(16) * e(16) * x(16) = 48-bit
    reg signed [ACC_BITS-1:0] tmp;
    reg signed [ACC_BITS-1:0] mu_e_x;   // holds mu * e * x before shift

    integer k;

    // ---- Saturation ----
    function signed [W_BITS-1:0] saturate;
        input signed [ACC_BITS-1:0] val;
        begin
            if      (val > $signed(32767))  saturate = 16'h7FFF;
            else if (val < $signed(-32768)) saturate = 16'h8000;
            else                            saturate = val[W_BITS-1:0];
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state          <= WAIT_SAMPLE;
            da_start       <= 1'b0;
            da_valid_latch <= 1'b0;
            output_valid   <= 1'b0;
            y_n            <= 0;
            e_n            <= 0;
            e_reg          <= 0;
            d_reg          <= 0;
            upd_cnt        <= 0;
            for (k = 0; k < N; k = k + 1) begin
                x_tap[k] <= 0;
                w[k]     <= 0;
            end
        end else begin
            da_start     <= 1'b0;
            output_valid <= 1'b0;

            if (da_valid_wire)
                da_valid_latch <= 1'b1;

            case (state)

                WAIT_SAMPLE: begin
                    if (sample_valid) begin
                        d_reg <= d_n;
                        state <= SHIFT_TAPS;
                    end
                end

                SHIFT_TAPS: begin
                    for (k = N-1; k > 0; k = k - 1)
                        x_tap[k] <= x_tap[k-1];
                    x_tap[0] <= x_in;
                    state <= START_DA;
                end

                START_DA: begin
                    da_valid_latch <= 1'b0;
                    da_start       <= 1'b1;
                    state          <= WAIT_DA;
                end

                WAIT_DA: begin
                    if (da_valid_latch || da_valid_wire) begin
                        da_valid_latch <= 1'b0;
                        // DA result is Q(W+C)=Q32, shift right 15 -> Q1.15
                        y_n   <= saturate(y_da >>> 15);
                        state <= COMPUTE_ERROR;
                    end
                end

                COMPUTE_ERROR: begin
                    tmp   = $signed(d_reg) - $signed(y_n);
                    e_reg <= saturate(tmp);
                    e_n   <= saturate(tmp);
                    upd_cnt <= 0;
                    state   <= UPDATE_WEIGHTS;
                end

                // ---- KEY FIX HERE ----
                // Old broken code did two separate >> 15 shifts which
                // quantised the intermediate result to near-zero.
                //
                // Correct: multiply all three terms together into a 
                // 48-bit register, then shift right 30 once at the end.
                //   MU_Q15 (16-bit) * e_reg (16-bit) * x_tap (16-bit)
                //   = up to 48-bit product
                //   >> 30 = Q1.15 result
                UPDATE_WEIGHTS: begin
                    // lambda * w[k]  (Q15 multiply -> Q15)
                    tmp = ($signed({{(ACC_BITS-16){1'b0}}, LAMBDA_Q15[15:0]}) *
                           $signed({{(ACC_BITS-W_BITS){w[upd_cnt][W_BITS-1]}},
                                     w[upd_cnt]})) >>> 15;

                    // mu * e[n] * x[k]  (three terms, single >> 30)
                    mu_e_x = $signed({{(ACC_BITS-16){1'b0}}, MU_Q15[15:0]}) *
                             $signed({{(ACC_BITS-W_BITS){e_reg[W_BITS-1]}}, e_reg}) *
                             $signed({{(ACC_BITS-W_BITS){x_tap[upd_cnt][W_BITS-1]}},
                                       x_tap[upd_cnt]});
                    tmp = tmp + (mu_e_x >>> 30);

                    w[upd_cnt] <= saturate(tmp);

                    if (upd_cnt == N - 1)
                        state <= OUTPUT_STATE;
                    else
                        upd_cnt <= upd_cnt + 1;
                end

                OUTPUT_STATE: begin
                    output_valid <= 1'b1;
                    state        <= WAIT_SAMPLE;
                end

            endcase
        end
    end

endmodule