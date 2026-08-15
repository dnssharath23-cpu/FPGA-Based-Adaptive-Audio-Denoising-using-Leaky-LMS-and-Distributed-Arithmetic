`timescale 1ns / 1ps
// ============================================================
//  tb_leaky_lms.v  -  Testbench  (Verilog-2001 compatible)
//  Works with Vivado xvlog without -sv flag
// ============================================================
`timescale 1ns/1ps

module tb_leaky_lms;

    parameter N          = 16;
    parameter W_BITS     = 16;
    parameter CLK_PERIOD = 10;   // 100 MHz

    reg                      clk;
    reg                      rst_n;
    reg                      sample_valid;
    reg  signed [W_BITS-1:0] d_n;
    reg  signed [W_BITS-1:0] x_in;
    wire signed [W_BITS-1:0] y_n;
    wire signed [W_BITS-1:0] e_n;
    wire                     output_valid;

    // ---- DUT ----
    leaky_lms_core #(
        .N(N), .W_BITS(W_BITS),
        .LAMBDA_Q15(32735), .MU_Q15(328)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .sample_valid(sample_valid),
        .d_n(d_n), .x_in(x_in),
        .y_n(y_n), .e_n(e_n),
        .output_valid(output_valid)
    );

    // ---- Clock ----
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // ---- 16-bit LFSR for pseudo-random noise ----
    reg [15:0] lfsr;
    task lfsr_step;
        lfsr = {lfsr[14:0], lfsr[15]^lfsr[13]^lfsr[12]^lfsr[10]};
    endtask

    // ---- sin ROM (pre-computed 1 kHz @ 44100 Hz, Q1.15) ----
    // We approximate sin with a simple cordic-free integer table
    // 44 samples = one period of ~1 kHz at 44100 Hz
    reg signed [15:0] sin_lut [0:43];
    integer lut_i;
    real    angle_r;

    initial begin
        for (lut_i = 0; lut_i < 44; lut_i = lut_i + 1) begin
            angle_r = 2.0 * 3.14159265358979 * lut_i / 44.0;
            sin_lut[lut_i] = $rtoi($sin(angle_r) * 16383.0);
        end
    end

    // ---- Stimulus ----
    integer i;
    integer phase;
    integer mse_sum;
    integer mse_count;
    integer d_noisy;

    initial begin
        $dumpfile("tb_leaky_lms.vcd");
        $dumpvars(0, tb_leaky_lms);

        clk          = 0;
        rst_n        = 0;
        sample_valid = 0;
        d_n          = 0;
        x_in         = 0;
        lfsr         = 16'hACE1;
        phase        = 0;

        repeat(10) @(posedge clk);
        rst_n = 1;
        repeat(5)  @(posedge clk);

        $display("=== Leaky LMS Testbench Start ===");
        mse_sum   = 0;
        mse_count = 0;

        for (i = 0; i < 2000; i = i + 1) begin

            // Clean 1 kHz sine from LUT
            d_noisy = sin_lut[phase];
            phase   = (phase + 1) % 44;

            // Noise from LFSR (scaled to ~10% amplitude)
            lfsr_step;
            d_noisy = d_noisy + ($signed(lfsr) >>> 4);

            // Saturate to 16-bit
            if (d_noisy >  32767) d_noisy =  32767;
            if (d_noisy < -32768) d_noisy = -32768;

            d_n  = d_noisy[15:0];
            x_in = $signed(lfsr) >>> 4;   // Correlated reference

            // One-cycle pulse
            sample_valid = 1;
            @(posedge clk);
            sample_valid = 0;

            // Wait for filter to finish processing
            @(posedge output_valid);
            @(posedge clk);

            // Accumulate MSE in last 500 samples
            if (i > 1500) begin
                mse_sum   = mse_sum + (($signed(e_n) * $signed(e_n)) >>> 16);
                mse_count = mse_count + 1;
            end
        end

        if (mse_count > 0)
            $display("Avg MSE (last 500): %0d  (lower = better convergence)",
                     mse_sum / mse_count);

        $display("=== Testbench Complete ===");
        #200;
        $finish;
    end

    // ---- Timeout watchdog ----
    initial begin
        #5_000_000;
        $display("TIMEOUT - simulation took too long");
        $finish;
    end

endmodule
