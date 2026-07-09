`timescale 1ns / 1ps

// DAC ramp generator: ramps DAC code from 0 to target_code, then jumps
// straight back to 0 (one SPI to code 0), repeating for TOTAL_CYCLES times.
// Runs at maximum SPI transfer rate.
//
// Sequence: 0,1,2,...,target, 0,1,2,...,target, 0  (× TOTAL_CYCLES, ends at 0)
//
// At SPI_HALF_PERIOD_CYCLES=5 and 100 MHz clk, each step takes ~161 cycles
// = 1.61 us → ~621 kHz.
module dac_ramp #(
    parameter integer DAC_BITS     = 16,
    parameter integer TOTAL_CYCLES = 10
) (
    input  wire                clk,
    input  wire                rst_n,

    input  wire                start,
    input  wire [DAC_BITS-1:0] target_code,
    input  wire                spi_done,
    output reg                 spi_start,
    output reg  [DAC_BITS-1:0] spi_data,
    output reg                 busy,
    output reg                 done
);

    localparam [1:0] IDLE = 2'd0,
                     RAMP = 2'd1,
                     DONE = 2'd2;

    reg [1:0]           state;
    reg [DAC_BITS-1:0]  current_code;
    reg [3:0]           cycle_count;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= IDLE;
            spi_start     <= 1'b0;
            spi_data      <= {DAC_BITS{1'b0}};
            busy          <= 1'b0;
            done          <= 1'b0;
            current_code  <= {DAC_BITS{1'b0}};
            cycle_count   <= {4{1'b0}};
        end else begin
            spi_start <= 1'b0;
            done      <= 1'b0;

            case (state)
                IDLE: begin
                    if (start) begin
                        busy         <= 1'b1;
                        current_code <= {DAC_BITS{1'b0}};
                        spi_data     <= {DAC_BITS{1'b0}};
                        spi_start    <= 1'b1;
                        cycle_count  <= TOTAL_CYCLES[3:0];
                        state        <= RAMP;
                    end
                end

                RAMP: begin
                    if (spi_done) begin
                        if (current_code >= target_code) begin
                            // Reached peak — jump back to 0
                            if (cycle_count > 1) begin
                                cycle_count  <= cycle_count - 1'b1;
                                current_code <= {DAC_BITS{1'b0}};
                                spi_data     <= {DAC_BITS{1'b0}};
                                spi_start    <= 1'b1;
                            end else begin
                                // Last cycle: also home to 0, then done
                                current_code <= {DAC_BITS{1'b0}};
                                spi_data     <= {DAC_BITS{1'b0}};
                                spi_start    <= 1'b1;
                                busy         <= 1'b0;
                                done         <= 1'b1;
                                state        <= DONE;
                            end
                        end else begin
                            current_code <= current_code + 1'b1;
                            spi_data     <= current_code + 1'b1;
                            spi_start    <= 1'b1;
                        end
                    end
                end

                DONE: begin
                    if (!start) begin
                        state <= IDLE;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
