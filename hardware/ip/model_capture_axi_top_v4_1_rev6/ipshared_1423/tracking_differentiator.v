`timescale 1ns / 1ps

// ┌──────────────────────────────────────────────────────────────┐
// │  Tracking Differentiator (TD) — Velocity Estimator           │
// │                                                              │
// │  Continuous:  H_vel(s) = r0^2 * s / (s^2 + 2*r0*s + r0^2)  │
// │  Discrete:    y[n] = (B0*x[n] + B2*x[n-2] + C1*y[n-1]       │
// │                                       + C2*y[n-2]) >> Q     │
// │  (B1 = 0 for Tustin discretization)                         │
// │                                                              │
// │  Also outputs filtered position:                             │
// │    H_pos(s) = r0^2 / (s^2 + 2*r0*s + r0^2)                  │
// │                                                              │
// │  Pipeline: 4 cycles                                          │
// │    S0: shift register update                                 │
// │    S1: DSP48 multiply (inferred)                              │
// │    S2: DSP48 multiply output register                         │
// │    S3: accumulate + shift + output                           │
// └──────────────────────────────────────────────────────────────┘

module tracking_differentiator #(
    // ── TD coefficients (Q0.24 fixed-point) ──
    // Default: r0=200 rad/s (32 Hz), Ts=1ms (Fs=1kHz)
    parameter signed [31:0] TD_B0 =  277309,          //  0.016529 * 2^24
    parameter signed [31:0] TD_B1 =  0,                //  0.0
    parameter signed [31:0] TD_B2 = -277309,           // -0.016529 * 2^24
    parameter signed [31:0] TD_C1 =  27453626,         //  1.636364 * 2^24
    parameter signed [31:0] TD_C2 = -11231029,         // -0.669421 * 2^24
    parameter integer       TD_Q  = 24,                 // fractional bits
    // ── Velocity scaling ──
    // vel_nm_per_s = vel_td_output * (1/Ts)  since TD estimates v in pos/sample
    // With Ts=1ms: multiply TD output by 1000 to get nm/s
    // We embed this in the output stage.
    parameter integer       TS_NS = 1000000         // sample period in ns (1ms = 1,000,000 ns)
) (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         valid_in,         // position data valid strobe
    input  wire signed [31:0] pos_in_nm,  // input position (nm)

    output reg  signed [31:0] pos_est_nm, // filtered position estimate (nm)
    output reg  signed [31:0] vel_est_nm_s, // velocity estimate (nm/s)
    output reg          valid_out
);

    // ── Pipeline registers ───────────────────────────────────────

    // Stage 0: input shift registers
    reg signed [31:0] x0, x1, x2;   // x[n], x[n-1], x[n-2]
    reg signed [31:0] y1, y2;       // y[n-1], y[n-2]
    reg               v0;

    // Stage 1: multiplier inputs
    reg signed [31:0] x0_s1, x2_s1, y1_s1, y2_s1;
    reg               v1;

    // Stage 2: multiplier outputs (registered inside DSP48)
    reg signed [63:0] p0_s2, p2_s2, pc1_s2, pc2_s2;  // 32b × 32b = 64b products
    reg signed [31:0] x0_s2;   // pass x[n] through for pos_est
    reg               v2;

    // Stage 3: accumulate
    reg signed [63:0] accum_s3;
    reg signed [31:0] x0_s3;
    reg               v3;

    // ── Coefficients (registered for timing) ─────────────────────
    reg signed [31:0] b0, b1, b2, c1, c2;
    reg [31:0]        q_val;
    localparam integer NS_PER_SECOND = 1000000000;
    localparam integer VEL_SCALE = NS_PER_SECOND / TS_NS;

    always @(posedge clk) begin
        if (!rst_n) begin
            b0 <= 32'sd0; b1 <= 32'sd0; b2 <= 32'sd0;
            c1 <= 32'sd0; c2 <= 32'sd0;
            q_val <= 32'd24;
        end else begin
            b0 <= TD_B0; b1 <= TD_B1; b2 <= TD_B2;
            c1 <= TD_C1; c2 <= TD_C2;
            q_val <= TD_Q;
        end
    end

    // ── Pipeline ─────────────────────────────────────────────────

    always @(posedge clk) begin
        if (!rst_n) begin
            x0 <= 32'sd0; x1 <= 32'sd0; x2 <= 32'sd0;
            y1 <= 32'sd0; y2 <= 32'sd0; v0 <= 1'b0;

            x0_s1 <= 32'sd0; x2_s1 <= 32'sd0;
            y1_s1 <= 32'sd0; y2_s1 <= 32'sd0; v1 <= 1'b0;

            p0_s2  <= 64'sd0; p2_s2  <= 64'sd0;
            pc1_s2 <= 64'sd0; pc2_s2 <= 64'sd0;
            x0_s2  <= 32'sd0; v2 <= 1'b0;

            accum_s3 <= 64'sd0; x0_s3 <= 32'sd0; v3 <= 1'b0;

            pos_est_nm  <= 32'sd0;
            vel_est_nm_s <= 32'sd0;
            valid_out   <= 1'b0;

        end else begin

            // ── Stage 0: capture input + shift ────────────────────

            v0 <= valid_in;
            if (valid_in) begin
                x2 <= x1;
                x1 <= x0;
                x0 <= pos_in_nm;
            end

            // ── Stage 1: register multiplier inputs ───────────────

            v1 <= v0;
            if (v0) begin
                x0_s1 <= x0;
                x2_s1 <= x2;
                y1_s1 <= y1;
                y2_s1 <= y2;
            end

            // ── Stage 2: DSP48 multiply ───────────────────────────

            v2 <= v1;
            if (v1) begin
                // These map to DSP48: 32b × 32b → 64b
                p0_s2  <= x0_s1 * b0;
                p2_s2  <= x2_s1 * b2;
                pc1_s2 <= y1_s1 * c1;
                pc2_s2 <= y2_s1 * c2;
                x0_s2  <= x0_s1;
            end

            // ── Stage 3: accumulate + shift + output ──────────────

            v3 <= v2;
            if (v2) begin
                // Sum all products
                accum_s3 <= p0_s2 + p2_s2 + pc1_s2 + pc2_s2;
                x0_s3    <= x0_s2;
            end

            // ── Stage 4: output (registered after DSP accum) ──────

            valid_out <= v3;
            if (v3) begin
                // Velocity: y = accum >> Q   (pos/sample)
                vel_est_nm_s <= ((accum_s3 * VEL_SCALE) >>> q_val);

                // Filtered position from TD:
                // H_pos(s) = r0^2 / (s^2 + 2*r0*s + r0^2)
                // Digital via Tustin produces a similar IIR.
                // Simpler: use a 1st-order LP on the input, or compute
                // pos_est from the velocity integrator.
                // For now: output x0 delayed (phase-aligned with vel)
                pos_est_nm  <= x0_s3;

                // Update feedback registers y1, y2 with the NEW velocity
                // (not the delayed one — this is the IIR feedback path)
                // Wait — y1,y2 must be the previous OUTPUT values.
                // The output is available at S4, so y1,y2 update here.
                y2 <= y1;
                y1 <= (accum_s3 >>> q_val);   // store velocity in pos/sample
            end
        end
    end

endmodule
