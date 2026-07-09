`timescale 1ns / 1ps

// Fast DAC sweep with simultaneous ADC capture.
// Steps DAC code from 0 to target_code, triggers one ADC conversion per step,
// outputs (dac_code, adc_a_uv, adc_b_uv) records at maximum possible rate.
//
// No settling wait, no averaging — designed to capture the motor trajectory
// at the DAC LSB change rate.
//
// Sequence: SPI(code 0) → ADC → record → SPI(code 1) → ADC → record → ...
//           repeats for NUM_CYCLES, ends at code 0.
module fast_sweep #(
    parameter integer DAC_BITS    = 16,
    parameter integer NUM_CYCLES  = 10
) (
    input  wire                clk,
    input  wire                rst_n,

    input  wire                start,
    input  wire [DAC_BITS-1:0] target_code,

    // SPI interface (to spi_for_8830)
    input  wire                spi_done,
    output reg                 spi_start,
    output reg  [DAC_BITS-1:0] spi_data,

    // ADC interface (from ad7616)
    input  wire                adc_valid,
    input  wire signed [31:0]  adc_a_uv,
    input  wire signed [31:0]  adc_b_uv,
    output reg                 adc_start,

    // Record output (one per DAC step)
    output reg                 record_valid,
    output reg  [DAC_BITS-1:0] record_dac_code,
    output reg  signed [31:0]  record_adc_a_uv,
    output reg  signed [31:0]  record_adc_b_uv,

    output reg                 busy,
    output reg                 done
);

    localparam [2:0] IDLE     = 3'd0,
                     WAIT_SPI = 3'd1,
                     WAIT_ADC = 3'd2,
                     RECORD   = 3'd3,
                     DONE_ST  = 3'd4;

    reg [2:0]           state;
    reg [DAC_BITS-1:0]  current_code;
    reg [3:0]           cycle_count;
    reg                 adc_started;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= IDLE;
            spi_start     <= 1'b0;
            spi_data      <= {DAC_BITS{1'b0}};
            adc_start     <= 1'b0;
            adc_started   <= 1'b0;
            record_valid  <= 1'b0;
            record_dac_code <= {DAC_BITS{1'b0}};
            record_adc_a_uv <= 32'sd0;
            record_adc_b_uv <= 32'sd0;
            busy          <= 1'b0;
            done          <= 1'b0;
            current_code  <= {DAC_BITS{1'b0}};
            cycle_count   <= {4{1'b0}};
        end else begin
            spi_start    <= 1'b0;
            record_valid <= 1'b0;
            done         <= 1'b0;

            case (state)
                IDLE: begin
                    adc_start   <= 1'b0;
                    adc_started <= 1'b0;
                    if (start) begin
                        busy         <= 1'b1;
                        current_code <= {DAC_BITS{1'b0}};
                        spi_data     <= {DAC_BITS{1'b0}};
                        spi_start    <= 1'b1;
                        cycle_count  <= NUM_CYCLES[3:0];
                        state        <= WAIT_SPI;
                    end
                end

                WAIT_SPI: begin
                    if (spi_done) begin
                        adc_start   <= 1'b1;
                        adc_started <= 1'b1;
                        state       <= WAIT_ADC;
                    end
                end

                WAIT_ADC: begin
                    adc_start <= 1'b1;
                    if (adc_valid) begin
                        adc_start        <= 1'b0;
                        adc_started      <= 1'b0;
                        record_valid     <= 1'b1;
                        record_dac_code  <= current_code;
                        record_adc_a_uv  <= adc_a_uv;
                        record_adc_b_uv  <= adc_b_uv;
                        state            <= RECORD;
                    end
                end

                RECORD: begin
                    adc_start   <= 1'b0;
                    adc_started <= 1'b0;
                    if (current_code >= target_code) begin
                        // Reached peak — jump back to 0
                        if (cycle_count > 1) begin
                            cycle_count  <= cycle_count - 1'b1;
                            current_code <= {DAC_BITS{1'b0}};
                            spi_data     <= {DAC_BITS{1'b0}};
                            spi_start    <= 1'b1;
                            state        <= WAIT_SPI;
                        end else begin
                            // Last cycle: home to 0, then done
                            current_code <= {DAC_BITS{1'b0}};
                            spi_data     <= {DAC_BITS{1'b0}};
                            spi_start    <= 1'b1;
                            busy         <= 1'b0;
                            done         <= 1'b1;
                            state        <= DONE_ST;
                        end
                    end else begin
                        current_code <= current_code + 1'b1;
                        spi_data     <= current_code + 1'b1;
                        spi_start    <= 1'b1;
                        state        <= WAIT_SPI;
                    end
                end

                DONE_ST: begin
                    adc_start <= 1'b0;
                    if (!start) begin
                        state <= IDLE;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
