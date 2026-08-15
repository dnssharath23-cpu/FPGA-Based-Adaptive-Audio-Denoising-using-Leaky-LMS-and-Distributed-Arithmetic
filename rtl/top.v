`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 19.04.2026 13:27:01
// Design Name: 
// Module Name: top
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


// ============================================================
//  uart_rx.v  —  Simple 8N1 UART Receiver
//  Baud rate set by CLKS_PER_BIT parameter.
//  For 100 MHz clock, 115200 baud: CLKS_PER_BIT = 868
// ============================================================
module uart_rx #(
    parameter CLKS_PER_BIT = 868
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       rx,
    output reg  [7:0] rx_byte,
    output reg        rx_done     // 1-cycle pulse when byte ready
);
    localparam IDLE        = 2'd0;
    localparam START_BIT   = 2'd1;
    localparam DATA_BITS   = 2'd2;
    localparam STOP_BIT    = 2'd3;

    reg [1:0]  state;
    reg [15:0] clk_cnt;
    reg [2:0]  bit_idx;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state   <= IDLE;
            rx_done <= 0;
            rx_byte <= 0;
            clk_cnt <= 0;
            bit_idx <= 0;
        end else begin
            rx_done <= 0;
            case (state)
                IDLE: begin
                    if (rx == 0) begin         // Start bit detected
                        clk_cnt <= 0;
                        state   <= START_BIT;
                    end
                end
                START_BIT: begin
                    if (clk_cnt == CLKS_PER_BIT/2) begin
                        if (rx == 0) begin
                            clk_cnt <= 0;
                            state   <= DATA_BITS;
                            bit_idx <= 0;
                        end else
                            state <= IDLE;
                    end else
                        clk_cnt <= clk_cnt + 1;
                end
                DATA_BITS: begin
                    if (clk_cnt == CLKS_PER_BIT - 1) begin
                        clk_cnt        <= 0;
                        rx_byte[bit_idx] <= rx;
                        if (bit_idx == 7) begin
                            bit_idx <= 0;
                            state   <= STOP_BIT;
                        end else
                            bit_idx <= bit_idx + 1;
                    end else
                        clk_cnt <= clk_cnt + 1;
                end
                STOP_BIT: begin
                    if (clk_cnt == CLKS_PER_BIT - 1) begin
                        rx_done <= 1;
                        clk_cnt <= 0;
                        state   <= IDLE;
                    end else
                        clk_cnt <= clk_cnt + 1;
                end
            endcase
        end
    end
endmodule

// ============================================================
//  uart_tx.v  —  Simple 8N1 UART Transmitter
// ============================================================
module uart_tx #(
    parameter CLKS_PER_BIT = 868
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       tx_start,
    input  wire [7:0] tx_byte,
    output reg        tx,
    output reg        tx_busy
);
    localparam IDLE      = 2'd0;
    localparam START_BIT = 2'd1;
    localparam DATA_BITS = 2'd2;
    localparam STOP_BIT  = 2'd3;

    reg [1:0]  state;
    reg [15:0] clk_cnt;
    reg [2:0]  bit_idx;
    reg [7:0]  tx_data;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state   <= IDLE;
            tx      <= 1;
            tx_busy <= 0;
            clk_cnt <= 0;
            bit_idx <= 0;
        end else begin
            case (state)
                IDLE: begin
                    tx      <= 1;
                    tx_busy <= 0;
                    if (tx_start) begin
                        tx_data <= tx_byte;
                        tx_busy <= 1;
                        clk_cnt <= 0;
                        state   <= START_BIT;
                    end
                end
                START_BIT: begin
                    tx <= 0;
                    if (clk_cnt == CLKS_PER_BIT - 1) begin
                        clk_cnt <= 0;
                        bit_idx <= 0;
                        state   <= DATA_BITS;
                    end else
                        clk_cnt <= clk_cnt + 1;
                end
                DATA_BITS: begin
                    tx <= tx_data[bit_idx];
                    if (clk_cnt == CLKS_PER_BIT - 1) begin
                        clk_cnt <= 0;
                        if (bit_idx == 7)
                            state <= STOP_BIT;
                        else
                            bit_idx <= bit_idx + 1;
                    end else
                        clk_cnt <= clk_cnt + 1;
                end
                STOP_BIT: begin
                    tx <= 1;
                    if (clk_cnt == CLKS_PER_BIT - 1) begin
                        state <= IDLE;
                    end else
                        clk_cnt <= clk_cnt + 1;
                end
            endcase
        end
    end
endmodule

// ============================================================
//  top.v  —  Top-Level FPGA Module
//
//  Protocol (PC -> FPGA):
//    Send 2 bytes: [HIGH_BYTE][LOW_BYTE] of 16-bit d[n]
//    then          [HIGH_BYTE][LOW_BYTE] of 16-bit x_ref[n]
//    4 bytes total per sample pair.
//
//  Protocol (FPGA -> PC):
//    Send 2 bytes: [HIGH][LOW] of y[n]   (denoised output)
//    then          [HIGH][LOW] of e[n]   (error signal)
//    4 bytes total per processed sample.
// ============================================================
module top #(
    parameter CLK_HZ       = 50_000_000,   // Your FPGA clock
    parameter BAUD         = 115_200,
    parameter N            = 16,
    parameter W_BITS       = 16,
    parameter LAMBDA_Q15   = 32735,          // 0.999
    parameter MU_Q15       = 328             // 0.01
)(
    input  wire clk,
    input  wire rst_n,
    input  wire uart_rx_pin,
    output wire uart_tx_pin,
    output wire led_active               // Heartbeat LED
);
    localparam CLKS_PER_BIT = CLK_HZ / BAUD;

    // ---- UART RX ----
    wire [7:0] rx_byte;
    wire       rx_done;
    uart_rx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_rx (
        .clk(clk), .rst_n(rst_n),
        .rx(uart_rx_pin), .rx_byte(rx_byte), .rx_done(rx_done)
    );

    // ---- Frame assembler: 4 bytes -> d[n] + x_ref[n] ----
    reg [7:0]  frame_buf [0:3];
    reg [1:0]  byte_cnt;
    reg signed [W_BITS-1:0] d_n_reg, x_ref_reg;
    reg                      sample_valid;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            byte_cnt     <= 0;
            sample_valid <= 0;
        end else begin
            sample_valid <= 0;
            if (rx_done) begin
                frame_buf[byte_cnt] <= rx_byte;
                if (byte_cnt == 3) begin
                    d_n_reg      <= {frame_buf[0], frame_buf[1]};  // Signed Q1.15
                    x_ref_reg    <= {frame_buf[2], frame_buf[3]};
                    sample_valid <= 1;
                    byte_cnt     <= 0;
                end else
                    byte_cnt <= byte_cnt + 1;
            end
        end
    end

    // ---- Leaky LMS Core ----
    wire signed [W_BITS-1:0] y_n, e_n;
    wire                      output_valid;

    leaky_lms_core #(
        .N(N), .W_BITS(W_BITS),
        .LAMBDA_Q15(LAMBDA_Q15), .MU_Q15(MU_Q15)
    ) u_lms (
        .clk(clk), .rst_n(rst_n),
        .sample_valid(sample_valid),
        .d_n(d_n_reg), .x_in(x_ref_reg),
        .y_n(y_n), .e_n(e_n),
        .output_valid(output_valid)
    );

    // ---- TX serialiser: y[n] and e[n] -> 4 bytes ----
    wire [7:0] tx_byte;
    wire       tx_start, tx_busy;
    uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_tx (
        .clk(clk), .rst_n(rst_n),
        .tx_start(tx_start), .tx_byte(tx_byte),
        .tx(uart_tx_pin), .tx_busy(tx_busy)
    );

    reg [7:0]  tx_buf [0:3];
    reg [1:0]  tx_cnt;
    reg        tx_pending;
    reg        tx_start_r;

    assign tx_byte  = tx_buf[tx_cnt];
    assign tx_start = tx_start_r;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_cnt     <= 0;
            tx_pending <= 0;
            tx_start_r <= 0;
        end else begin
            tx_start_r <= 0;

            if (output_valid) begin
                tx_buf[0]  <= y_n[15:8];
                tx_buf[1]  <= y_n[7:0];
                tx_buf[2]  <= e_n[15:8];
                tx_buf[3]  <= e_n[7:0];
                tx_cnt     <= 0;
                tx_pending <= 1;
            end

            if (tx_pending && !tx_busy && !tx_start_r) begin
                tx_start_r <= 1;
                if (tx_cnt == 3)
                    tx_pending <= 0;
                else
                    tx_cnt <= tx_cnt + 1;
            end
        end
    end

    // ---- Heartbeat LED ----
    reg [26:0] led_cnt;
    assign led_active = led_cnt[26];
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) led_cnt <= 0;
        else        led_cnt <= led_cnt + 1;
    end

endmodule