# FPGA-Based Adaptive Audio Denoising using Leaky LMS and Distributed Arithmetic

## Overview

This project explores the implementation of an **adaptive audio denoising system on FPGA** using a **Leaky Least Mean Squares (Leaky LMS) adaptive filter**.

The filtering operation is implemented using **Distributed Arithmetic (DA)** to investigate a hardware-efficient approach for performing the multiply-accumulate operations required by digital filtering.

The project combines:

* Digital Signal Processing
* Adaptive Filtering
* FIR Filtering
* Leaky LMS
* Distributed Arithmetic
* Verilog HDL
* FPGA-based hardware implementation

> **Current Status:** The FPGA implementation is functional at the architectural/simulation level, but the current output still contains significant noise and does not yet achieve the expected denoising performance. Debugging and optimization are ongoing.

---

## Objective

The objective of this project is to implement an adaptive noise-cancellation/denoising filter on an FPGA.

The system uses the **Leaky LMS algorithm** to continuously update the filter coefficients based on the error between the desired signal and the filter output.

Distributed Arithmetic is explored as a hardware-efficient alternative to conventional multiplier-based FIR filter implementation.

---

## System Architecture

```text
Input / Noisy Audio
        │
        ▼
   Audio Samples
        │
        ▼
   FIR Adaptive Filter
        │
        ├──────────────┐
        │              │
        ▼              │
   Filter Output       │
        │              │
        ▼              │
   Error Calculation ◄─┘
        │
        ▼
  Leaky LMS Coefficient
       Update
        │
        ▼
  Updated Filter Weights
        │
        └──────► Adaptive Filter
```

The filtering computation is implemented using **Distributed Arithmetic** for FPGA-oriented hardware optimization.

---

## Adaptive Filtering

An adaptive filter adjusts its coefficients according to the input signal and error signal.

For a conventional LMS filter:

[
y(n)=\mathbf{w}^T(n)\mathbf{x}(n)
]

where:

* (x(n)) = input signal
* (w(n)) = adaptive filter coefficients
* (y(n)) = filter output

The error is calculated as:

[
e(n)=d(n)-y(n)
]

where (d(n)) is the desired signal.

The conventional LMS coefficient update is:

[
\mathbf{w}(n+1)
===============

\mathbf{w}(n)
+
\mu e(n)\mathbf{x}(n)
]

where (\mu) is the step-size parameter.

---

## Leaky LMS

The project uses the **Leaky LMS** algorithm.

The leakage term prevents excessive growth of the adaptive filter coefficients and can improve stability in practical implementations.

A commonly used update equation is:

[
\mathbf{w}(n+1)
===============

(1-\mu\gamma)\mathbf{w}(n)
+
\mu e(n)\mathbf{x}(n)
]

where:

* (\mu) = LMS step size
* (\gamma) = leakage factor
* (e(n)) = error signal
* (\mathbf{x}(n)) = input vector
* (\mathbf{w}(n)) = filter coefficient vector

The leakage factor introduces a small decay in the filter coefficients.

---

## Distributed Arithmetic

Digital FIR filters normally require multiple multiplication and accumulation operations.

For FPGA implementation, **Distributed Arithmetic (DA)** can be used to replace conventional multipliers with LUT-based and shift-and-add operations.

For a fixed coefficient FIR filter, DA decomposes the multiplication operation based on the individual bits of the input samples.

Conceptually:

```text
Input Bits
    │
    ▼
Bit Decomposition
    │
    ▼
LUT / Partial Product Generation
    │
    ▼
Shift and Accumulate
    │
    ▼
Filter Output
```

This approach can reduce the need for dedicated hardware multipliers and can be useful for FPGA-based DSP implementations.

---

## FPGA Implementation

The design is developed using **Verilog HDL**.

The implementation involves:

* Input sample processing
* FIR filtering
* Error computation
* Leaky LMS coefficient update
* Distributed Arithmetic-based computation
* Fixed-point signal processing
* Sequential/control logic
* Simulation and output analysis

---

## Current Results

The current implementation produces an output signal, but the output still contains considerable noise and does not yet match the expected denoised signal.

This is currently being investigated through:

* Filter coefficient analysis
* Step-size selection
* Leakage-factor selection
* Fixed-point precision
* Input/output scaling
* DA implementation
* LMS convergence behavior
* Verilog timing and control logic

The current limitation is treated as part of the ongoing development of the FPGA implementation.

---

## Challenges

Some of the key challenges in FPGA-based adaptive filtering include:

### 1. Fixed-Point Precision

Unlike floating-point MATLAB simulations, FPGA implementations typically use fixed-point arithmetic. Insufficient precision can affect filter convergence and output quality.

### 2. Step-Size Selection

The LMS step size directly affects convergence.

A very large step size can cause instability, while a very small step size can result in slow convergence.

### 3. Leakage Factor

The leakage parameter must be selected carefully because excessive leakage can prevent the filter coefficients from converging to useful values.

### 4. Hardware Timing

The adaptive filter requires sequential coefficient updates and signal processing operations, which must be correctly synchronized in the FPGA implementation.

### 5. Distributed Arithmetic

The DA architecture requires careful handling of bit widths, LUT/partial-product generation, shifting, and accumulation.

---

## Tools and Technologies

* **Verilog HDL**
* **FPGA**
* **MATLAB**
* **Digital Signal Processing**
* **Adaptive Filtering**
* **Leaky LMS**
* **FIR Filters**
* **Distributed Arithmetic**
* **Fixed-Point Arithmetic**

---

## Project Status

**Status: Work in Progress**

The Leaky LMS adaptive-filter architecture and FPGA-oriented Distributed Arithmetic implementation are under development.

The current implementation produces a noisy output, and further work is being carried out to improve convergence and denoising performance.

Future improvements include:

1. Optimize LMS step-size and leakage parameters.
2. Improve fixed-point precision and scaling.
3. Verify the DA implementation against a MATLAB reference model.
4. Analyze filter convergence.
5. Compare input and output SNR.
6. Validate the design through FPGA hardware testing.
7. Improve real-time audio processing performance.

---

## Learning Outcomes

Through this project, the following concepts are being explored:

* Adaptive digital filtering
* LMS and Leaky LMS algorithms
* FIR filter implementation
* Distributed Arithmetic
* FPGA-based DSP
* Fixed-point arithmetic
* Verilog RTL design
* Hardware/software algorithm comparison
* Signal-to-noise analysis
* FPGA debugging and optimization

---

## Author

**DSP / FPGA Project**

Developed as part of an FPGA-based Digital Signal Processing project.
