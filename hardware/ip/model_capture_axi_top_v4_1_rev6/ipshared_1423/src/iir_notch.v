`timescale 1ns / 1ps

// ┌──────────────────────────────────────────────────────────────┐
// │  IIR Notch Filter — 2nd-order, configurable frequency        │
// │                                                              │
// │  H(z) = (1 - 2*cos(w0)*z^-1 + z^-2) /                       │
// │         (1 - 2*r*cos(w0)*z^-1 + r^2*z^-2)                   │
// │                                                              │
// │  w0 = 2*pi*f0/Fs     (notch frequency)                      │
// │  r  = 1 - pi*BW/Fs   (pole radius, controls notch width)     │
// │                                                              │
// │  Pipeline: 3 cycles                                          │
// └──────────────────────────────────────────────────────────────┘

module iir_notch #(
    // ── Notch coefficients (Q0.24 fixed-point) ──
    // Default: f0=79.2 Hz, BW=3 Hz, Fs=4 kHz
    parameter signed [31:0] N_B0  = 16777216,    //  1.0     * 2^24
    parameter signed [31:0] N_B1  = -32903660,   // -2*cos(w0) * 2^24
    parameter signed [31:0] N_B2  = 16777216,    //  1.0     * 2^24
    parameter signed [31:0] N_A1  = -32811026,   // -2*r*cos(w0) * 2^24
    parameter signed [31:0] N_A2  = 16662668,    //  r^2    * 2^24
    parameter integer       N_Q   = 24
) (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         valid_in,
    input  wire signed [31:0] data_in,

    output reg  signed [31:0] data_out,
    output reg          valid_out
);

    // ── Pipeline registers ───────────────────────────────────────

    // Stage 0: shift register
    reg signed [31:0] x0, x1, x2;   // x[n], x[n-1], x[n-2]
    reg signed [31:0] y1, y2;       // y[n-1], y[n-2]
    reg               v0, v1;

    // Stage 1: multiplier inputs
    reg signed [31:0] x0_s1, x1_s1, x2_s1, y1_s1, y2_s1;
    reg               v1_s;

    // Stage 2: products (DSP48 output registers)
    reg signed [63:0] px0, px1, px2, py1, py2;
    reg               v2;

    always @(posedge clk) begin
        if (!rst_n) begin
            x0 <= 0; x1 <= 0; x2 <= 0; y1 <= 0; y2 <= 0;
            v0 <= 0; v1 <= 0;
            x0_s1 <= 0; x1_s1 <= 0; x2_s1 <= 0;
            y1_s1 <= 0; y2_s1 <= 0; v1_s <= 0;
            px0 <= 0; px1 <= 0; px2 <= 0; py1 <= 0; py2 <= 0; v2 <= 0;
            data_out  <= 0;
            valid_out <= 0;
        end else begin

            // ── Stage 0: shift ────────────────────────────────────

            v0 <= valid_in;
            if (valid_in) begin
                x2 <= x1; x1 <= x0; x0 <= data_in;
            end
            v1 <= v0;

            // ── Stage 1: latch multiplier inputs ──────────────────

            v1_s <= v0;
            if (v0) begin
                x0_s1 <= x0; x1_s1 <= x1; x2_s1 <= x2;
                y1_s1 <= y1; y2_s1 <= y2;
            end

            // ── Stage 2: DSP48 multiply ───────────────────────────

            v2 <= v1_s;
            if (v1_s) begin
                px0 <= x0_s1 * N_B0;
                px1 <= x1_s1 * N_B1;
                px2 <= x2_s1 * N_B2;
                py1 <= y1_s1 * N_A1;
                py2 <= y2_s1 * N_A2;
            end

            // ── Stage 3: accumulate + output ──────────────────────

            valid_out <= v2;
            if (v2) begin
                // y[n] = (B0*x0 + B1*x1 + B2*x2 + A1*y1 + A2*y2) >> Q
                // Note: A1, A2 already store (-a1), (-a2) so we ADD them
                data_out <= (px0 + px1 + px2 + py1 + py2) >>> N_Q;

                // Update feedback
                y2 <= y1;
                y1 <= (px0 + px1 + px2 + py1 + py2) >>> N_Q;
            end
        end
    end

endmodule
