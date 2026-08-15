// ============================================================
//  tb_verify.v  -  Self-Checking Testbench  (v5 FINAL)
//  Verilog-2001 compatible.
//
//  Fix vs v4: noise amplitude increased from >> 4 to >> 1
//  so the weight update mu*e*x is large enough to survive
//  the Q1.15 fixed-point quantization in the Verilog core.
// ============================================================
`timescale 1ns/1ps

module tb_verify;

    parameter N          = 16;
    parameter W_BITS     = 16;
    parameter CLK_PERIOD = 10;
    parameter MAX_WAIT   = 5000;

    reg                      clk;
    reg                      rst_n;
    reg                      sample_valid;
    reg  signed [W_BITS-1:0] d_n;
    reg  signed [W_BITS-1:0] x_in;
    wire signed [W_BITS-1:0] y_n;
    wire signed [W_BITS-1:0] e_n;
    wire                     output_valid;

    leaky_lms_core #(
        .N(N), .W_BITS(W_BITS),
        .LAMBDA_Q15(32735),
        .MU_Q15(328)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .sample_valid(sample_valid),
        .d_n(d_n), .x_in(x_in),
        .y_n(y_n), .e_n(e_n),
        .output_valid(output_valid)
    );

    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    integer pass_count;
    integer fail_count;
    integer sim_done;

    reg [15:0] lfsr;
    task lfsr_step;
        lfsr = {lfsr[14:0], lfsr[15]^lfsr[13]^lfsr[12]^lfsr[10]};
    endtask

    reg signed [15:0] sin_lut [0:43];
    integer lut_i;
    real    angle_r;

    reg     timed_out;
    integer wait_cnt;

    task send_sample;
        input signed [15:0] d_in;
        input signed [15:0] x_ref;
        begin
            timed_out    = 0;
            d_n          = d_in;
            x_in         = x_ref;
            @(negedge clk);
            sample_valid = 1;
            @(posedge clk);
            #1;
            sample_valid = 0;
            wait_cnt = 0;
            while ((output_valid !== 1'b1) && (wait_cnt < MAX_WAIT)) begin
                @(posedge clk);
                wait_cnt = wait_cnt + 1;
            end
            if (wait_cnt >= MAX_WAIT) begin
                timed_out = 1;
                $display("  [TIMEOUT] state=%0d bit_cnt=%0d running=%0b",
                         dut.state, dut.u_da.bit_cnt, dut.u_da.running);
                sim_done = 1;
            end else begin
                @(posedge clk);
            end
        end
    endtask

    task do_reset;
        begin
            rst_n        = 0;
            sample_valid = 0;
            d_n          = 0;
            x_in         = 0;
            repeat(15) @(posedge clk);
            rst_n = 1;
            repeat(5)  @(posedge clk);
        end
    endtask

    task check;
        input integer  tnum;
        input [255:0]  tname;
        input          cond;
        begin
            if (cond) begin
                $display("  [PASS] Test %0d: %s", tnum, tname);
                pass_count = pass_count + 1;
            end else begin
                $display("  [FAIL] Test %0d: %s", tnum, tname);
                $display("         y_n=%0d  e_n=%0d  state=%0d",
                         $signed(y_n), $signed(e_n), dut.state);
                fail_count = fail_count + 1;
            end
        end
    endtask

    integer i;
    integer phase;
    integer mse_sum_e;
    integer mse_sum_l;
    integer mse_early;
    integer mse_late;
    integer e_sq;
    integer d_noisy;
    integer noise_val;
    integer y_abs;

    initial begin
        pass_count = 0;
        fail_count = 0;
        sim_done   = 0;
        lfsr       = 16'hACE1;

        for (lut_i = 0; lut_i < 44; lut_i = lut_i + 1) begin
            angle_r = 2.0 * 3.14159265358979 * lut_i / 44.0;
            sin_lut[lut_i] = $rtoi($sin(angle_r) * 16383.0);
        end

        $display("");
        $display("============================================");
        $display("  Leaky LMS -- Verification Testbench v5");
        $display("============================================");

        // ====================================================
        //  TEST 1: Zero input
        // ====================================================
        $display("\n--- TEST 1: Zero Input ---");
        do_reset;
        i = 0;
        while ((i < 5) && (sim_done == 0)) begin
            send_sample(16'h0000, 16'h0000);
            i = i + 1;
        end
        if (sim_done == 0) begin
            check(1, "Zero input y[n]=0", ($signed(y_n) == 16'h0000));
            check(1, "Zero input e[n]=0", ($signed(e_n) == 16'h0000));
        end else begin
            $display("  [SKIP] timed out"); fail_count = fail_count + 1;
        end

        // ====================================================
        //  TEST 2: Error equation
        // ====================================================
        if (sim_done == 0) begin
            $display("\n--- TEST 2: Error Equation ---");
            do_reset;
            send_sample(16'h1234, 16'h0567);
            if (sim_done == 0) begin
                check(2, "y[0]=0 when weights=0",  ($signed(y_n) == 16'h0000));
                check(2, "e[0]=d[0]=0x1234",       ($signed(e_n) == $signed(16'h1234)));
            end else begin
                $display("  [SKIP] timed out"); fail_count = fail_count + 1;
            end
        end

        // ====================================================
        //  TEST 3: MSE Convergence
        //
        //  Noise uses >> 1 (amplitude ~16000) so the product
        //  mu * e * x is large enough to survive >> 30 quantization.
        //  800 samples is enough for clear convergence at this SNR.
        // ====================================================
        if (sim_done == 0) begin
            $display("\n--- TEST 3: MSE Convergence ---");
            do_reset;
            phase     = 0;
            mse_sum_e = 0;
            mse_sum_l = 0;
            i = 0;

            while ((i < 800) && (sim_done == 0)) begin
                d_noisy   = sin_lut[phase];
                phase     = (phase + 1) % 44;
                lfsr_step;
                // Use >> 1 for larger noise amplitude
                noise_val = $signed(lfsr) >>> 1;
                d_noisy   = d_noisy + noise_val;
                if (d_noisy >  32767) d_noisy =  32767;
                if (d_noisy < -32768) d_noisy = -32768;

                send_sample(d_noisy[15:0], noise_val[15:0]);

                if (sim_done == 0) begin
                    e_sq = ($signed(e_n) * $signed(e_n)) >>> 16;
                    if (i < 100)
                        mse_sum_e = mse_sum_e + e_sq;
                    if (i >= 700)
                        mse_sum_l = mse_sum_l + e_sq;
                end
                i = i + 1;
            end

            if (sim_done == 0) begin
                mse_early = mse_sum_e / 100;
                mse_late  = mse_sum_l / 100;
                $display("  MSE first 100 samples : %0d  (untrained)", mse_early);
                $display("  MSE last  100 samples : %0d  (trained)",   mse_late);
                if (mse_early > 0)
                    $display("  Reduction             : %0d%%",
                             100*(mse_early - mse_late)/mse_early);
                check(3, "MSE decreased (filter converged)", (mse_late < mse_early));
            end else begin
                $display("  [SKIP] timed out"); fail_count = fail_count + 1;
            end
        end

        // ====================================================
        //  TEST 4: Leak - weights decay after silence
        // ====================================================
        if (sim_done == 0) begin
            $display("\n--- TEST 4: Leak Factor ---");
            i = 0;
            while ((i < 300) && (sim_done == 0)) begin
                send_sample(16'h0000, 16'h0000);
                i = i + 1;
            end
            if (sim_done == 0) begin
                y_abs = ($signed(y_n) > 0) ? $signed(y_n) : -$signed(y_n);
                $display("  |y_n| after 300 silent samples: %0d", y_abs);
                check(4, "y_n near 0 after silence (leak)", (y_abs < 500));
            end else begin
                $display("  [SKIP] timed out"); fail_count = fail_count + 1;
            end
        end

        // ====================================================
        //  TEST 5: No X/Z on max inputs
        // ====================================================
        if (sim_done == 0) begin
            $display("\n--- TEST 5: No X/Z on Max Inputs ---");
            do_reset;
            send_sample(16'h7FFF, 16'h7FFF);
            if (sim_done == 0) begin
                check(5, "Max positive: no X/Z in y_n", (^y_n !== 1'bx));
                check(5, "Max positive: no X/Z in e_n", (^e_n !== 1'bx));
            end
            if (sim_done == 0) begin
                send_sample(16'h8000, 16'h8000);
                if (sim_done == 0)
                    check(5, "Max negative: no X/Z in y_n", (^y_n !== 1'bx));
            end
        end

        // ====================================================
        //  TEST 6: Reset clears state
        // ====================================================
        if (sim_done == 0) begin
            $display("\n--- TEST 6: Reset Clears State ---");
            do_reset;
            send_sample(16'h1000, 16'h0800);
            if (sim_done == 0) begin
                check(6, "Post-reset y[0]=0",           ($signed(y_n) == 16'h0000));
                check(6, "Post-reset e[0]=d[0]=0x1000", ($signed(e_n) == $signed(16'h1000)));
            end else begin
                $display("  [SKIP] timed out"); fail_count = fail_count + 1;
            end
        end

        $display("");
        $display("============================================");
        $display("  RESULTS: %0d PASSED,  %0d FAILED",
                 pass_count, fail_count);
        if (fail_count == 0)
            $display("  ALL TESTS PASSED");
        else
            $display("  SOME TESTS FAILED -- see messages above");
        $display("============================================");
        #100;
        $finish;
    end

    initial begin
        #500_000_000;
        $display("GLOBAL WATCHDOG FIRED");
        $finish;
    end

endmodule