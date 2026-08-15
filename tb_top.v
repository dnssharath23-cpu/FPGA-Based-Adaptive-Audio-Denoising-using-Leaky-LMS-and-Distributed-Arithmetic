// ============================================================
//  tb_top.v  -  Top-Level Testbench
//  Tests the complete system: UART RX -> LMS -> UART TX
//
//  What this tests:
//    1. UART byte reception (8N1 framing)
//    2. 4-byte frame assembly (d[n] + x_ref[n])
//    3. LMS processing (calls leaky_lms_core internally)
//    4. 4-byte TX response (y[n] + e[n])
//    5. End-to-end: send noisy audio, verify response arrives
//
//  NOTE: tb_verify.v already proves the LMS algorithm is correct.
//        This testbench proves the UART wrapper works correctly.
//
//  Clock: 100 MHz  (CLK_HZ = 100_000_000)
//  Baud:  115200
//  CLKS_PER_BIT = 100_000_000 / 115_200 = 868
// ============================================================
`timescale 1ns/1ps

module tb_top;

    // ---- Timing parameters ----
    parameter CLK_PERIOD   = 10;          // 10 ns = 100 MHz
    parameter CLK_HZ       = 100_000_000;
    parameter BAUD         = 115_200;
    parameter CLKS_PER_BIT = CLK_HZ / BAUD;  // 868
    parameter BIT_PERIOD   = CLK_PERIOD * CLKS_PER_BIT;  // 8680 ns

    // ---- DUT ports ----
    reg  clk;
    reg  rst_n;
    reg  uart_rx_pin;
    wire uart_tx_pin;
    wire led_active;

    // ---- DUT ----
    top #(
        .CLK_HZ     (CLK_HZ),
        .BAUD       (BAUD),
        .N          (16),
        .LAMBDA_Q15 (32735),
        .MU_Q15     (328)
    ) dut (
        .clk         (clk),
        .rst_n       (rst_n),
        .uart_rx_pin (uart_rx_pin),
        .uart_tx_pin (uart_tx_pin),
        .led_active  (led_active)
    );

    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // ---- Pass/fail counters ----
    integer pass_count;
    integer fail_count;

    // ---- Received bytes from UART TX ----
    reg [7:0] rx_bytes [0:15];   // store up to 16 received bytes
    integer   rx_count;

    // ---- Check helper ----
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
                fail_count = fail_count + 1;
            end
        end
    endtask

    // ============================================================
    //  Task: send one UART byte (8N1) on uart_rx_pin
    //  Bit order: LSB first
    // ============================================================
    task uart_send_byte;
        input [7:0] data;
        integer b;
        begin
            // Start bit (LOW)
            uart_rx_pin = 0;
            #(BIT_PERIOD);
            // 8 data bits, LSB first
            for (b = 0; b < 8; b = b + 1) begin
                uart_rx_pin = data[b];
                #(BIT_PERIOD);
            end
            // Stop bit (HIGH)
            uart_rx_pin = 1;
            #(BIT_PERIOD);
        end
    endtask

    // ============================================================
    //  Task: send one sample pair (4 bytes)
    //  Format: [D_HIGH][D_LOW][X_HIGH][X_LOW]
    // ============================================================
    task send_sample_pair;
        input signed [15:0] d_val;
        input signed [15:0] x_val;
        begin
            uart_send_byte(d_val[15:8]);
            uart_send_byte(d_val[7:0]);
            uart_send_byte(x_val[15:8]);
            uart_send_byte(x_val[7:0]);
        end
    endtask

    // ============================================================
    //  Task: receive one UART byte from uart_tx_pin
    //  Waits for start bit, samples at mid-bit
    // ============================================================
    task uart_recv_byte;
        output [7:0] data;
        integer b;
        integer timeout;
        begin
            data    = 8'hFF;
            timeout = 0;
            // Wait for start bit (falling edge on TX)
            while (uart_tx_pin !== 0 && timeout < 10_000_000) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            if (timeout >= 10_000_000) begin
                $display("  [UART_RX_TIMEOUT] No start bit detected");
                data = 8'hFF;
            end else begin
                // Move to middle of start bit
                #(BIT_PERIOD / 2);
                // Sample 8 data bits
                for (b = 0; b < 8; b = b + 1) begin
                    #(BIT_PERIOD);
                    data[b] = uart_tx_pin;
                end
                // Wait through stop bit
                #(BIT_PERIOD);
            end
        end
    endtask

    // ============================================================
    //  Task: receive 4-byte response from FPGA
    //  Returns y[n] and e[n] as signed 16-bit
    // ============================================================
    reg [7:0] rb0, rb1, rb2, rb3;
    task recv_response;
        output signed [15:0] y_out;
        output signed [15:0] e_out;
        begin
            uart_recv_byte(rb0);
            uart_recv_byte(rb1);
            uart_recv_byte(rb2);
            uart_recv_byte(rb3);
            y_out = {rb0, rb1};
            e_out = {rb2, rb3};
        end
    endtask

    // ============================================================
    //  Main stimulus
    // ============================================================
    integer i;
    reg signed [15:0] y_resp, e_resp;
    reg signed [15:0] y_prev;
    integer got_response;
    integer mse_sum_early, mse_sum_late;
    integer e_sq;

    initial begin
        $dumpfile("tb_top.vcd");
        $dumpvars(0, tb_top);

        pass_count   = 0;
        fail_count   = 0;
        uart_rx_pin  = 1;   // UART idle = HIGH

        rst_n = 0;
        repeat(20) @(posedge clk);
        rst_n = 1;
        repeat(10) @(posedge clk);

        $display("");
        $display("============================================");
        $display("  tb_top.v -- Top-Level UART Integration");
        $display("============================================");

        // ====================================================
        //  TEST 1: LED heartbeat toggles (clock is running)
        // ====================================================
        $display("\n--- TEST 1: Heartbeat LED ---");
        // LED toggles every 2^27 clocks ~ 1.3 seconds
        // We just check it's driven (not X/Z)
        #100;
        check(1, "led_active has no X/Z", (^led_active !== 1'bx));
        check(1, "uart_tx_pin idle HIGH",  (uart_tx_pin === 1'b1));

        // ====================================================
        //  TEST 2: Send one zero sample, get zero response
        //  d[n]=0, x[n]=0 -> y[n]=0, e[n]=0
        // ====================================================
        $display("\n--- TEST 2: Zero Sample -> Zero Response ---");
        send_sample_pair(16'h0000, 16'h0000);
        recv_response(y_resp, e_resp);
        $display("  Sent  d=0 x=0  Got y=%0d e=%0d",
                 $signed(y_resp), $signed(e_resp));
        check(2, "Zero input: y=0", ($signed(y_resp) == 16'h0000));
        check(2, "Zero input: e=0", ($signed(e_resp) == 16'h0000));

        // ====================================================
        //  TEST 3: First nonzero sample: y must be 0, e must = d
        //  Because weights are still zero after reset
        // ====================================================
        $display("\n--- TEST 3: First Sample Error Equation ---");
        // Reset first so weights are guaranteed 0
        rst_n = 0;
        repeat(20) @(posedge clk);
        rst_n = 1;
        repeat(10) @(posedge clk);
        uart_rx_pin = 1;

        send_sample_pair(16'h1000, 16'h0800);
        recv_response(y_resp, e_resp);
        $display("  Sent  d=0x1000 x=0x0800");
        $display("  Got   y=%0d (0x%04h)  e=%0d (0x%04h)",
                 $signed(y_resp), y_resp,
                 $signed(e_resp), e_resp);
        check(3, "First sample y=0 (weights=0)",      ($signed(y_resp) == 16'h0000));
        check(3, "First sample e=d=0x1000",            ($signed(e_resp) == $signed(16'h1000)));

        // ====================================================
        //  TEST 4: UART framing - byte ordering is correct
        //  Send known pattern, verify bytes are assembled right
        // ====================================================
        $display("\n--- TEST 4: UART Byte Order ---");
        // Send d=0x1234, x=0x5678
        // Expected: d_high=0x12, d_low=0x34, x_high=0x56, x_low=0x78
        rst_n = 0; repeat(20) @(posedge clk); rst_n = 1;
        repeat(10) @(posedge clk); uart_rx_pin = 1;

        send_sample_pair(16'h1234, 16'h5678);
        recv_response(y_resp, e_resp);
        $display("  Sent  d=0x1234 x=0x5678");
        $display("  Got   y=0x%04h  e=0x%04h", y_resp, e_resp);
        // y should be 0 (weights=0), e should be 0x1234
        check(4, "Byte order: y=0",          ($signed(y_resp) == 16'h0000));
        check(4, "Byte order: e=d=0x1234",   ($signed(e_resp) == $signed(16'h1234)));

        // ====================================================
        //  TEST 5: Multiple samples - TX responds to every RX
        //  Send 10 samples, count responses
        // ====================================================
        $display("\n--- TEST 5: Multiple Samples Processed ---");
        rst_n = 0; repeat(20) @(posedge clk); rst_n = 1;
        repeat(10) @(posedge clk); uart_rx_pin = 1;

        got_response = 0;
        for (i = 0; i < 10; i = i + 1) begin
            send_sample_pair(16'h0400, 16'h0200);
            recv_response(y_resp, e_resp);
            if (e_resp !== 16'hFFFF)   // hFFFF = timeout sentinel
                got_response = got_response + 1;
        end
        $display("  Sent 10 samples, got %0d responses", got_response);
        check(5, "All 10 samples got responses", (got_response == 10));

        // ====================================================
        //  TEST 6: Convergence visible across 200 samples
        //  Use large noise so weight updates are non-zero
        // ====================================================
        $display("\n--- TEST 6: End-to-End Convergence ---");
        rst_n = 0; repeat(20) @(posedge clk); rst_n = 1;
        repeat(10) @(posedge clk); uart_rx_pin = 1;

        mse_sum_early = 0;
        mse_sum_late  = 0;

        for (i = 0; i < 200; i = i + 1) begin
            // Large amplitude noise for clear convergence
            send_sample_pair($signed(16'h3000) + i[15:0],
                             $signed(16'h1800) + i[15:0]);
            recv_response(y_resp, e_resp);

            e_sq = ($signed(e_resp) * $signed(e_resp)) >>> 16;
            if (i < 40)
                mse_sum_early = mse_sum_early + e_sq;
            if (i >= 160)
                mse_sum_late = mse_sum_late + e_sq;
        end

        $display("  MSE first 40 samples : %0d", mse_sum_early / 40);
        $display("  MSE last  40 samples : %0d", mse_sum_late  / 40);
        check(6, "MSE decreased end-to-end",
              (mse_sum_late / 40) < (mse_sum_early / 40));

        // ====================================================
        //  SUMMARY
        // ====================================================
        $display("");
        $display("============================================");
        $display("  RESULTS: %0d PASSED,  %0d FAILED",
                 pass_count, fail_count);
        if (fail_count == 0)
            $display("  ALL TESTS PASSED");
        else
            $display("  SOME TESTS FAILED");
        $display("============================================");
        $display("");
        $display("NOTE: tb_verify.v already proves LMS algorithm.");
        $display("      This testbench proves UART wrapper is correct.");

        #1000;
        $finish;
    end

    // Global watchdog (UART tests take longer due to bit-period timing)
    initial begin
        #2_000_000_000;
        $display("WATCHDOG FIRED");
        $finish;
    end

endmodule