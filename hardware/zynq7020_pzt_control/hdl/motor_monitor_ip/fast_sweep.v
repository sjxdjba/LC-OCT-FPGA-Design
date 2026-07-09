`timescale 1ns / 1ps

// Bidirectional fast DAC sweep with ADC capture.
//
// Forward:  DAC 0→full-scale, synced ADC at 625 kHz.
//           (half_period=2, SPI=64 + pad=19 + ADC≈75 = 160 cycles)
// Reverse:  DAC full-scale→0 at 3.125 MHz, ADC free-runs at ~1 MHz
//           (async spot-sampling: DAC pumps at half_period=1, 32 cyc/step;
//            ADC runs continuously; records are sparse snapshots of DAC position)
// Repeats for sweep_cycles iterations, then stops at code 0.
//
// rev_mode output selects SPI speed: 0=forward, 1=reverse.
module fast_sweep #(
    parameter integer DAC_BITS          = 16,
    parameter integer NUM_CYCLES        = 10,
    parameter integer ZERO_HOLD_CYCLES  = 1000000,
    parameter integer FWD_PAD_CYCLES    = 19
) (
    input  wire                clk,
    input  wire                rst_n,

    input  wire                start,
    input  wire [DAC_BITS-1:0] target_code,
    input  wire [31:0]         sweep_cycles,
    input  wire [31:0]         zero_hold_cycles,
    input  wire [31:0]         fwd_pad_cycles,

    // SPI interface (to spi_for_8830)
    input  wire                spi_done,
    output reg                 spi_start,
    output reg  [DAC_BITS-1:0] spi_data,

    // ADC interface (from ad7616)
    input  wire                adc_valid,
    input  wire signed [31:0]  adc_a_uv,
    input  wire signed [31:0]  adc_b_uv,
    output reg                 adc_start,

    // Record output (one per ADC sample)
    output reg                 record_valid,
    output reg                 record_last,
    output reg                 record_ramp_up,
    output reg  [DAC_BITS-1:0] record_dac_code,
    output reg  signed [31:0]  record_adc_a_uv,
    output reg  signed [31:0]  record_adc_b_uv,

    // Speed control
    output reg                 rev_mode,

    output reg                 busy,
    output reg                 done
);

    localparam [3:0] IDLE          = 4'd0,
                     FWD_WAIT_SPI  = 4'd1,
                     FWD_PAD       = 4'd2,
                     FWD_WAIT_ADC  = 4'd3,
                     FWD_RECORD    = 4'd4,
                     REV_RUN       = 4'd5,
                     HOLD_ZERO     = 4'd6,
                     DONE_ST       = 4'd7;

    localparam [DAC_BITS-1:0] LAST_CODE = {DAC_BITS{1'b1}};

    reg [3:0]           state;
    reg [DAC_BITS-1:0]  current_code;
    reg [31:0]          cycle_count;
    reg [31:0]          zero_hold_count;
    reg [31:0]          zero_hold_cycles_latched;
    reg [31:0]          fwd_pad_cnt;
    reg [31:0]          fwd_pad_target;

    // Reverse async state
    reg                 rev_dac_active;
    reg                 rev_dac_done;
    reg                 rev_first_spi;

    wire [DAC_BITS-1:0] unused_target_code = target_code;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state           <= IDLE;
            spi_start       <= 1'b0;
            spi_data        <= {DAC_BITS{1'b0}};
            adc_start       <= 1'b0;
            record_valid    <= 1'b0;
            record_last     <= 1'b0;
            record_ramp_up  <= 1'b1;
            record_dac_code <= {DAC_BITS{1'b0}};
            record_adc_a_uv <= 32'sd0;
            record_adc_b_uv <= 32'sd0;
            rev_mode        <= 1'b0;
            busy            <= 1'b0;
            done            <= 1'b0;
            current_code    <= {DAC_BITS{1'b0}};
            cycle_count     <= 32'd0;
            zero_hold_count <= 32'd0;
            zero_hold_cycles_latched <= ZERO_HOLD_CYCLES;
            rev_dac_active  <= 1'b0;
            rev_dac_done    <= 1'b0;
            rev_first_spi   <= 1'b0;
        end else begin
            spi_start    <= 1'b0;
            record_valid <= 1'b0;
            record_last  <= 1'b0;
            done         <= 1'b0;

            case (state)
                IDLE: begin
                    adc_start       <= 1'b0;
                    rev_mode        <= 1'b0;
                    zero_hold_count <= 32'd0;
                    rev_dac_active  <= 1'b0;
                    rev_dac_done    <= 1'b0;
                    rev_first_spi   <= 1'b0;
                    if (start) begin
                        busy         <= 1'b1;
                        current_code <= {DAC_BITS{1'b0}};
                        spi_data     <= {DAC_BITS{1'b0}};
                        spi_start    <= 1'b1;
                        cycle_count  <= (sweep_cycles != 32'd0) ? sweep_cycles : NUM_CYCLES;
                        zero_hold_cycles_latched <=
                            (zero_hold_cycles != 32'd0) ? zero_hold_cycles : ZERO_HOLD_CYCLES;
                        fwd_pad_target <= (fwd_pad_cycles != 32'd0) ? fwd_pad_cycles : FWD_PAD_CYCLES;
                        state        <= FWD_WAIT_SPI;
                    end
                end

                // ─── Forward sweep (0 → MAX) ─────────────────────────────

                FWD_WAIT_SPI: begin
                    rev_mode  <= 1'b0;
                    adc_start <= 1'b0;
                    if (spi_done) begin
                        fwd_pad_cnt <= 32'd0;
                        state       <= FWD_PAD;
                    end
                end

                FWD_PAD: begin
                    rev_mode  <= 1'b0;
                    adc_start <= 1'b0;
                    if (fwd_pad_cnt >= fwd_pad_target - 1'b1) begin
                        adc_start <= 1'b1;
                        state     <= FWD_WAIT_ADC;
                    end else begin
                        fwd_pad_cnt <= fwd_pad_cnt + 1'b1;
                    end
                end

                FWD_WAIT_ADC: begin
                    rev_mode  <= 1'b0;
                    adc_start <= 1'b1;
                    if (adc_valid) begin
                        adc_start       <= 1'b0;
                        record_valid    <= 1'b1;
                        record_ramp_up  <= 1'b1;
                        // Fast-sweep mode should terminate the AXIS packet only
                        // after the final reverse-sweep sample is emitted.
                        record_last     <= 1'b0;
                        record_dac_code <= current_code;
                        record_adc_a_uv <= adc_a_uv;
                        record_adc_b_uv <= adc_b_uv;
                        state           <= FWD_RECORD;
                    end
                end

                FWD_RECORD: begin
                    rev_mode  <= 1'b0;
                    adc_start <= 1'b0;
                    if (current_code == LAST_CODE) begin
                        // Transition to reverse sweep
                        current_code   <= LAST_CODE;
                        rev_dac_active <= 1'b1;
                        rev_dac_done   <= 1'b0;
                        rev_first_spi  <= 1'b1;
                        rev_mode       <= 1'b1;
                        state          <= REV_RUN;
                    end else begin
                        current_code <= current_code + 1'b1;
                        spi_data     <= current_code + 1'b1;
                        spi_start    <= 1'b1;
                        state        <= FWD_WAIT_SPI;
                    end
                end

                // ─── Reverse sweep (MAX → 0)  async DAC + ADC ───────────

                // DAC pumps at 3.125 MHz (half_period=1, 32 cyc/step).
                // ADC free-runs at ~1 MHz; records are spot-samples of DAC position.
                REV_RUN: begin
                    rev_mode  <= 1'b1;
                    adc_start <= 1'b1;  // continuous ADC

                    // --- DAC pump ---
                    // Start very first SPI on entry, then pump on each spi_done.
                    if (rev_first_spi) begin
                        spi_data      <= LAST_CODE;
                        spi_start     <= 1'b1;
                        rev_first_spi <= 1'b0;
                    end else if (spi_done && rev_dac_active) begin
                        if (current_code == 0) begin
                            rev_dac_active <= 1'b0;
                            rev_dac_done   <= 1'b1;
                        end else begin
                            current_code <= current_code - 1'b1;
                            spi_data     <= current_code - 1'b1;
                            spi_start    <= 1'b1;
                        end
                    end

                    // --- ADC capture (spot-sample at whatever ADC gives us) ---
                    if (adc_valid) begin
                        record_valid    <= 1'b1;
                        record_ramp_up  <= 1'b0;
                        record_dac_code <= current_code;
                        record_adc_a_uv <= adc_a_uv;
                        record_adc_b_uv <= adc_b_uv;
                        if (rev_dac_done) begin
                            // DAC already stopped; this is the last ADC sample
                            record_last     <= (cycle_count <= 1);
                            adc_start       <= 1'b0;
                            rev_mode        <= 1'b0;
                            if (cycle_count > 1) begin
                                cycle_count    <= cycle_count - 1'b1;
                                current_code   <= {DAC_BITS{1'b0}};
                                zero_hold_count <= 32'd0;
                                state          <= HOLD_ZERO;
                            end else begin
                                busy  <= 1'b0;
                                done  <= 1'b1;
                                state <= DONE_ST;
                            end
                        end
                    end
                end

                // ─── Inter-cycle hold at zero ──────────────────────────────

                HOLD_ZERO: begin
                    rev_mode  <= 1'b0;
                    adc_start <= 1'b0;
                    if (zero_hold_cycles_latched == 32'd0 ||
                        zero_hold_count >= zero_hold_cycles_latched - 1'b1) begin
                        current_code <= {DAC_BITS{1'b0}};
                        spi_data     <= {DAC_BITS{1'b0}};
                        spi_start    <= 1'b1;
                        state        <= FWD_WAIT_SPI;
                    end else begin
                        zero_hold_count <= zero_hold_count + 1'b1;
                    end
                end

                // ─── Done ─────────────────────────────────────────────────

                DONE_ST: begin
                    rev_mode  <= 1'b0;
                    adc_start <= 1'b0;
                    if (!start) begin
                        state <= IDLE;
                    end
                end

                default: begin
                    state <= IDLE;
                end
            endcase
        end
    end

endmodule
