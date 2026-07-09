`timescale 1ns / 1ps

// ┌──────────────────────────────────────────────────────────────┐
// │  Feedforward LUT — BRAM-based with linear interpolation      │
// │                                                              │
// │  4 tables: M1_UP, M1_DN, M2_UP, M2_DN                       │
// │  Each: 4096 × 16-bit DAC codes                               │
// │                                                              │
// │  Input:  pos_nm (signed, 32-bit), branch (up=1/down=0)       │
// │  Output: dac_code (16-bit), via linear interpolation         │
// │                                                              │
// │  Position to index:                                          │
// │    idx = (pos_nm - POS_MIN) * SCALE >> SCALE_Q               │
// │    where SCALE = 4096 * 2^SCALE_Q / (POS_MAX - POS_MIN)      │
// │                                                              │
// │  Latency: 5 cycles (v2 — added pipeline registers after      │
// │    DSP48 multiply and before BRAM address to meet 100 MHz)    │
// │                                                              │
// │  Pipeline stages:                                            │
// │    S0: input register + branch mux (scale/pos_min/pos_max)   │
// │    S1: offset = pos - pos_min  →  product = offset * scale   │
// │         (DSP48, registered here — splits 21-level path)      │
// │    S2: product >> Q  →  addr, addr_next (clamped)            │
// │    S3: BRAM read (addr → dac0, dac1)                         │
// │    S4: frac from recomputed product (DSP48) + delta           │
// │    Out: dac = dac0 + (delta * frac) >> Q  (DSP48)            │
// └──────────────────────────────────────────────────────────────┘

module pzt_ff_lut #(
    // ── LUT depth ──
    parameter integer LUT_DEPTH = 4096,
    parameter integer ADDR_W    = 12,
    // ── M1 UP (from 6.16 data, adc_a spike-cleaned) ──
    parameter signed [31:0] M1_UP_POS_MIN = 32'sd42,
    parameter signed [31:0] M1_UP_POS_MAX = 32'sd657086,
    parameter [31:0]        M1_UP_SCALE  = 32'd104589,
    // ── M1 DN ──
    parameter signed [31:0] M1_DN_POS_MIN = 32'sd208,
    parameter signed [31:0] M1_DN_POS_MAX = 32'sd657144,
    parameter [31:0]        M1_DN_SCALE  = 32'd104606,
    // ── M2 UP ──
    parameter signed [31:0] M2_UP_POS_MIN = -32'sd28,
    parameter signed [31:0] M2_UP_POS_MAX = 32'sd629143,
    parameter [31:0]        M2_UP_SCALE  = 32'd109222,
    // ── M2 DN ──
    parameter signed [31:0] M2_DN_POS_MIN = 32'sd193,
    parameter signed [31:0] M2_DN_POS_MAX = 32'sd629254,
    parameter [31:0]        M2_DN_SCALE  = 32'd109241,
    // ── Scaling ──
    parameter integer SCALE_Q = 24
) (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         valid_in,

    // Motor 1
    input  wire signed [31:0] pos_m1_nm,
    input  wire               branch_m1,       // 1=up, 0=down
    output reg  [15:0]        dac_ff_m1,
    output reg                dac_ff_m1_valid,

    // Motor 2
    input  wire signed [31:0] pos_m2_nm,
    input  wire               branch_m2,
    output reg  [15:0]        dac_ff_m2,
    output reg                dac_ff_m2_valid
);

    // ── BRAM LUT tables ──────────────────────────────────────────

    (* ram_style = "block" *) reg [15:0] lut_m1_up [0:4095];
    (* ram_style = "block" *) reg [15:0] lut_m1_dn [0:4095];
    (* ram_style = "block" *) reg [15:0] lut_m2_up [0:4095];
    (* ram_style = "block" *) reg [15:0] lut_m2_dn [0:4095];
    localparam [ADDR_W-1:0] LUT_LAST_ADDR = {ADDR_W{1'b1}};

    initial begin
        $readmemh("lut_m1_up.mem",   lut_m1_up);
        $readmemh("lut_m1_dn.mem",   lut_m1_dn);
        $readmemh("lut_m2_up.mem",   lut_m2_up);
        $readmemh("lut_m2_dn.mem",   lut_m2_dn);
    end

    // ── Pipeline registers ───────────────────────────────────────

    // Stage 0: input latch + branch-based parameter select
    reg signed [31:0] pos_s0_m1, pos_s0_m2;
    reg               branch_s0_m1, branch_s0_m2;
    reg [31:0]        scale_s0_m1,  scale_s0_m2;
    reg signed [31:0] pos_min_s0_m1, pos_min_s0_m2;
    reg signed [31:0] pos_max_s0_m1, pos_max_s0_m2;
    reg               v0;

    // Stage 1: offset * scale product (DSP48, registered here)
    reg signed [63:0] prod_s1_m1, prod_s1_m2;
    reg signed [31:0] pos_s1_m1, pos_s1_m2;
    reg [31:0]        scale_s1_m1,  scale_s1_m2;
    reg signed [31:0] pos_min_s1_m1, pos_min_s1_m2;
    reg signed [31:0] pos_max_s1_m1, pos_max_s1_m2;
    reg               branch_s1_m1, branch_s1_m2;
    reg               v1;

    // Stage 2: BRAM address (shifted + clamped product)
    reg [ADDR_W-1:0]  addr_s2_m1,  addr_next_s2_m1;
    reg [ADDR_W-1:0]  addr_s2_m2,  addr_next_s2_m2;
    reg signed [31:0] pos_s2_m1, pos_s2_m2;
    reg [31:0]        scale_s2_m1,  scale_s2_m2;
    reg signed [31:0] pos_min_s2_m1, pos_min_s2_m2;
    reg signed [31:0] pos_max_s2_m1, pos_max_s2_m2;
    reg               branch_s2_m1, branch_s2_m2;
    reg               v2;

    // Stage 3: BRAM output registers
    reg [15:0]        dac0_s3_m1, dac1_s3_m1;
    reg [15:0]        dac0_s3_m2, dac1_s3_m2;
    reg signed [31:0] pos_s3_m1, pos_s3_m2;
    reg [31:0]        scale_s3_m1,  scale_s3_m2;
    reg signed [31:0] pos_min_s3_m1, pos_min_s3_m2;
    reg signed [31:0] pos_max_s3_m1, pos_max_s3_m2;
    reg               v3;

    // Stage 4: fractional part (from recomputed product via DSP48) + delta
    reg [SCALE_Q-1:0] frac_s4_m1, frac_s4_m2;
    reg signed [16:0] delta_s4_m1, delta_s4_m2;   // 17-bit signed: [-65535, 65535]
    reg [15:0]        dac0_s4_m1, dac0_s4_m2;
    reg               v4;

    // Intermediate wires for S3→S4 recompute product
    // (split from inline to avoid Vivado part-select-on-expression error)
    wire signed [63:0] reprod_s4_m1;
    wire signed [63:0] reprod_s4_m2;
    assign reprod_s4_m1 = ($signed(pos_s3_m1) - pos_min_s3_m1) *
                          $signed({1'b0, scale_s3_m1});
    assign reprod_s4_m2 = ($signed(pos_s3_m2) - pos_min_s3_m2) *
                          $signed({1'b0, scale_s3_m2});

    // ── Pipeline ─────────────────────────────────────────────────

    always @(posedge clk) begin
        if (!rst_n) begin
            // Stage 0
            pos_s0_m1 <= 0; pos_s0_m2 <= 0;
            branch_s0_m1 <= 0; branch_s0_m2 <= 0;
            scale_s0_m1  <= 0; scale_s0_m2  <= 0;
            pos_min_s0_m1 <= 0; pos_min_s0_m2 <= 0;
            pos_max_s0_m1 <= 0; pos_max_s0_m2 <= 0;
            v0 <= 0;

            // Stage 1
            prod_s1_m1 <= 0; prod_s1_m2 <= 0;
            pos_s1_m1  <= 0; pos_s1_m2  <= 0;
            scale_s1_m1 <= 0; scale_s1_m2 <= 0;
            pos_min_s1_m1 <= 0; pos_min_s1_m2 <= 0;
            pos_max_s1_m1 <= 0; pos_max_s1_m2 <= 0;
            branch_s1_m1 <= 0; branch_s1_m2 <= 0;
            v1 <= 0;

            // Stage 2
            addr_s2_m1 <= 0; addr_next_s2_m1 <= 0;
            addr_s2_m2 <= 0; addr_next_s2_m2 <= 0;
            pos_s2_m1  <= 0; pos_s2_m2  <= 0;
            scale_s2_m1 <= 0; scale_s2_m2 <= 0;
            pos_min_s2_m1 <= 0; pos_min_s2_m2 <= 0;
            pos_max_s2_m1 <= 0; pos_max_s2_m2 <= 0;
            branch_s2_m1 <= 0; branch_s2_m2 <= 0;
            v2 <= 0;

            // Stage 3
            dac0_s3_m1 <= 0; dac1_s3_m1 <= 0;
            dac0_s3_m2 <= 0; dac1_s3_m2 <= 0;
            pos_s3_m1  <= 0; pos_s3_m2  <= 0;
            scale_s3_m1 <= 0; scale_s3_m2 <= 0;
            pos_min_s3_m1 <= 0; pos_min_s3_m2 <= 0;
            pos_max_s3_m1 <= 0; pos_max_s3_m2 <= 0;
            v3 <= 0;

            // Stage 4
            frac_s4_m1 <= 0; frac_s4_m2 <= 0;
            delta_s4_m1 <= 0; delta_s4_m2 <= 0;
            dac0_s4_m1 <= 0; dac0_s4_m2 <= 0;
            v4 <= 0;

            // Output
            dac_ff_m1 <= 0; dac_ff_m2 <= 0;
            dac_ff_m1_valid <= 0; dac_ff_m2_valid <= 0;

        end else begin

            // ── Stage 0: input latch + branch-based parameter mux ──

            v0 <= valid_in;
            pos_s0_m1    <= pos_m1_nm;
            pos_s0_m2    <= pos_m2_nm;
            branch_s0_m1 <= branch_m1;
            branch_s0_m2 <= branch_m2;

            // Select scale / pos_min / pos_max based on branch direction
            // (fast LUT mux, negligible timing cost)
            if (branch_m1) begin
                scale_s0_m1   <= M1_UP_SCALE;
                pos_min_s0_m1 <= M1_UP_POS_MIN;
                pos_max_s0_m1 <= M1_UP_POS_MAX;
            end else begin
                scale_s0_m1   <= M1_DN_SCALE;
                pos_min_s0_m1 <= M1_DN_POS_MIN;
                pos_max_s0_m1 <= M1_DN_POS_MAX;
            end

            if (branch_m2) begin
                scale_s0_m2   <= M2_UP_SCALE;
                pos_min_s0_m2 <= M2_UP_POS_MIN;
                pos_max_s0_m2 <= M2_UP_POS_MAX;
            end else begin
                scale_s0_m2   <= M2_DN_SCALE;
                pos_min_s0_m2 <= M2_DN_POS_MIN;
                pos_max_s0_m2 <= M2_DN_POS_MAX;
            end

            // ── Stage 1: offset * scale → product (DSP48 multiply) ──
            // Combinatorial: 5 CARRY4 (subtraction) + 1 DSP48 (multiply)
            // Registered here to split the 21-level critical path.

            v1 <= v0;
            if (v0) begin
                // M1: (pos - pos_min) * scale
                prod_s1_m1   <= ($signed(pos_s0_m1) - pos_min_s0_m1) *
                                $signed({1'b0, scale_s0_m1});
                // M2: (pos - pos_min) * scale
                prod_s1_m2   <= ($signed(pos_s0_m2) - pos_min_s0_m2) *
                                $signed({1'b0, scale_s0_m2});

                pos_s1_m1    <= pos_s0_m1;
                pos_s1_m2    <= pos_s0_m2;
                scale_s1_m1  <= scale_s0_m1;
                scale_s1_m2  <= scale_s0_m2;
                pos_min_s1_m1 <= pos_min_s0_m1;
                pos_min_s1_m2 <= pos_min_s0_m2;
                pos_max_s1_m1 <= pos_max_s0_m1;
                pos_max_s1_m2 <= pos_max_s0_m2;
                branch_s1_m1 <= branch_s0_m1;
                branch_s1_m2 <= branch_s0_m2;
            end

            // ── Stage 2: address generation (shift + clamp) ──
            // Combinatorial: shift = wire-select (free),
            //   clamp = 2 comparisons + mux (~2 LUT levels),
            //   addr+1 = 1 CARRY4 if not at max

            v2 <= v1;
            if (v1) begin
                // ── M1 address ──
                if (pos_s1_m1 <= pos_min_s1_m1) begin
                    addr_s2_m1      <= {ADDR_W{1'b0}};
                    addr_next_s2_m1 <= {{(ADDR_W-1){1'b0}}, 1'b1};   // = 1
                end else if (pos_s1_m1 >= pos_max_s1_m1) begin
                    addr_s2_m1      <= LUT_LAST_ADDR;
                    addr_next_s2_m1 <= LUT_LAST_ADDR;
                end else begin
                    // integer part of product after shift
                    addr_s2_m1 <= prod_s1_m1[SCALE_Q+ADDR_W-1:SCALE_Q];
                    // next address for interpolation (clamped to 4095)
                    if (prod_s1_m1[SCALE_Q+ADDR_W-1:SCALE_Q] >= LUT_LAST_ADDR)
                        addr_next_s2_m1 <= LUT_LAST_ADDR;
                    else
                        addr_next_s2_m1 <= prod_s1_m1[SCALE_Q+ADDR_W-1:SCALE_Q] + 1'b1;
                end

                // ── M2 address ──
                if (pos_s1_m2 <= pos_min_s1_m2) begin
                    addr_s2_m2      <= {ADDR_W{1'b0}};
                    addr_next_s2_m2 <= {{(ADDR_W-1){1'b0}}, 1'b1};
                end else if (pos_s1_m2 >= pos_max_s1_m2) begin
                    addr_s2_m2      <= LUT_LAST_ADDR;
                    addr_next_s2_m2 <= LUT_LAST_ADDR;
                end else begin
                    addr_s2_m2 <= prod_s1_m2[SCALE_Q+ADDR_W-1:SCALE_Q];
                    if (prod_s1_m2[SCALE_Q+ADDR_W-1:SCALE_Q] >= LUT_LAST_ADDR)
                        addr_next_s2_m2 <= LUT_LAST_ADDR;
                    else
                        addr_next_s2_m2 <= prod_s1_m2[SCALE_Q+ADDR_W-1:SCALE_Q] + 1'b1;
                end

                pos_s2_m1    <= pos_s1_m1;
                pos_s2_m2    <= pos_s1_m2;
                scale_s2_m1  <= scale_s1_m1;
                scale_s2_m2  <= scale_s1_m2;
                pos_min_s2_m1 <= pos_min_s1_m1;
                pos_min_s2_m2 <= pos_min_s1_m2;
                pos_max_s2_m1 <= pos_max_s1_m1;
                pos_max_s2_m2 <= pos_max_s1_m2;
                branch_s2_m1 <= branch_s1_m1;
                branch_s2_m2 <= branch_s1_m2;
            end

            // ── Stage 3: BRAM read ────────────────────────────────
            // Combinatorial: BRAM address → data out (registered here)

            v3 <= v2;
            if (v2) begin
                // M1 BRAM read
                if (branch_s2_m1) begin
                    dac0_s3_m1 <= lut_m1_up[addr_s2_m1];
                    dac1_s3_m1 <= lut_m1_up[addr_next_s2_m1];
                end else begin
                    dac0_s3_m1 <= lut_m1_dn[addr_s2_m1];
                    dac1_s3_m1 <= lut_m1_dn[addr_next_s2_m1];
                end

                // M2 BRAM read
                if (branch_s2_m2) begin
                    dac0_s3_m2 <= lut_m2_up[addr_s2_m2];
                    dac1_s3_m2 <= lut_m2_up[addr_next_s2_m2];
                end else begin
                    dac0_s3_m2 <= lut_m2_dn[addr_s2_m2];
                    dac1_s3_m2 <= lut_m2_dn[addr_next_s2_m2];
                end

                pos_s3_m1    <= pos_s2_m1;
                pos_s3_m2    <= pos_s2_m2;
                scale_s3_m1  <= scale_s2_m1;
                scale_s3_m2  <= scale_s2_m2;
                pos_min_s3_m1 <= pos_min_s2_m1;
                pos_min_s3_m2 <= pos_min_s2_m2;
                pos_max_s3_m1 <= pos_max_s2_m1;
                pos_max_s3_m2 <= pos_max_s2_m2;
            end

            // ── Stage 4: fractional part + delta ───────────────────
            // Combinatorial: pos clamp + offset + product via DSP48
            //   (for frac); delta = dac1 - dac0 (fast LUT subtract)
            // Registered here so the next stage's DSP multiply for
            //   (delta * frac) starts from a clean register.

            v4 <= v3;
            if (v3) begin
                // ── M1 frac ──
                if (pos_s3_m1 <= pos_min_s3_m1) begin
                    frac_s4_m1 <= {SCALE_Q{1'b0}};   // force frac = 0
                end else begin
                    // Recompute (pos - pos_min) * scale for frac extraction.
                    // pos >= pos_max case: delta = 0 (addr = addr_next = 4095,
                    // dac0 = dac1), so frac value is irrelevant.
                    // Use pre-computed wire to avoid Vivado syntax error
                    // on inline part-select.
                    frac_s4_m1 <= reprod_s4_m1[SCALE_Q-1:0];
                end

                delta_s4_m1 <= $signed({1'b0, dac1_s3_m1}) -
                               $signed({1'b0, dac0_s3_m1});
                dac0_s4_m1  <= dac0_s3_m1;

                // ── M2 frac ──
                if (pos_s3_m2 <= pos_min_s3_m2) begin
                    frac_s4_m2 <= {SCALE_Q{1'b0}};
                end else begin
                    frac_s4_m2 <= reprod_s4_m2[SCALE_Q-1:0];
                end

                delta_s4_m2 <= $signed({1'b0, dac1_s3_m2}) -
                               $signed({1'b0, dac0_s3_m2});
                dac0_s4_m2  <= dac0_s3_m2;
            end

            // ── Output: linear interpolation ───────────────────────
            // Combinatorial: (delta * frac) >>> Q via DSP48 + add dac0
            //
            //  dac_ff = dac0 + (delta * frac) >> SCALE_Q
            //
            //  delta: 17-bit signed,  frac: 24-bit unsigned
            //  DSP48 infers: signed × unsigned → shift → add

            dac_ff_m1_valid <= v4;
            dac_ff_m2_valid <= v4;

            if (v4) begin
                dac_ff_m1 <= $signed({1'b0, dac0_s4_m1}) +
                             ((delta_s4_m1 * $signed({1'b0, frac_s4_m1})) >>> SCALE_Q);
                dac_ff_m2 <= $signed({1'b0, dac0_s4_m2}) +
                             ((delta_s4_m2 * $signed({1'b0, frac_s4_m2})) >>> SCALE_Q);
            end
        end
    end

endmodule
