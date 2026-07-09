`timescale 1ns / 1ps

// SPI driver for DAC8830 modules with shared SDI/SCLK and two chip selects.
// Supported external pins:
// - cs1
// - cs2
// - sdi
// - sclk
//
// Usage:
// - Assert start for one clk with a valid 16-bit data word.
// - Select the target DAC with target_sel:
//     2'b01 -> cs1 active
//     2'b10 -> cs2 active
// - busy stays high during the transfer.
// - done pulses high for one clk after the frame completes.
module spi_for_8830 #(
    parameter integer DATA_BITS              = 16,
    parameter integer SPI_HALF_PERIOD_CYCLES = 5,
    parameter integer COUNTER_WIDTH          = 16,
    parameter integer SHIFT_WIDTH            = 5
) (
    input  wire                 clk,
    input  wire                 rst_n,
    input  wire                 start,
    input  wire [DATA_BITS-1:0] data_in,
    input  wire [1:0]           target_sel,
    input  wire [15:0]          half_period_cycles,

    output reg                  busy,
    output reg                  done,
    output reg                  cs1,
    output reg                  cs2,
    output reg                  sclk,
    output reg                  sdi
);

    localparam [SHIFT_WIDTH-1:0] DATA_BITS_U = DATA_BITS;

    reg [DATA_BITS-1:0]      shift_reg;
    reg [COUNTER_WIDTH-1:0]  clk_count;
    reg [SHIFT_WIDTH-1:0]    bit_count;
    reg [1:0]                active_target;
    reg [COUNTER_WIDTH-1:0]  active_half_period_cycles;

    always @(posedge clk) begin
        if (!rst_n) begin
            busy          <= 1'b0;
            done          <= 1'b0;
            cs1           <= 1'b1;
            cs2           <= 1'b1;
            sclk          <= 1'b0;
            sdi           <= 1'b0;
            shift_reg     <= {DATA_BITS{1'b0}};
            clk_count     <= {COUNTER_WIDTH{1'b0}};
            bit_count     <= {SHIFT_WIDTH{1'b0}};
            active_target <= 2'b00;
            active_half_period_cycles <= SPI_HALF_PERIOD_CYCLES;
        end else begin
            done <= 1'b0;

            if (!busy) begin
                cs1       <= 1'b1;
                cs2       <= 1'b1;
                sclk      <= 1'b0;
                clk_count <= {COUNTER_WIDTH{1'b0}};
                bit_count <= {SHIFT_WIDTH{1'b0}};

                if (start && (target_sel != 2'b00)) begin
                    busy          <= 1'b1;
                    active_target <= target_sel;
                    shift_reg     <= data_in;
                    sdi           <= data_in[DATA_BITS-1];
                    bit_count     <= DATA_BITS_U;
                    if (half_period_cycles != 16'd0) begin
                        active_half_period_cycles <= half_period_cycles[COUNTER_WIDTH-1:0];
                    end else begin
                        active_half_period_cycles <= SPI_HALF_PERIOD_CYCLES;
                    end

                    case (target_sel)
                        2'b01: begin
                            cs1 <= 1'b0;
                            cs2 <= 1'b1;
                        end
                        2'b10: begin
                            cs1 <= 1'b1;
                            cs2 <= 1'b0;
                        end
                        default: begin
                            cs1 <= 1'b1;
                            cs2 <= 1'b1;
                        end
                    endcase
                end
            end else begin
                case (active_target)
                    2'b01: begin
                        cs1 <= 1'b0;
                        cs2 <= 1'b1;
                    end
                    2'b10: begin
                        cs1 <= 1'b1;
                        cs2 <= 1'b0;
                    end
                    default: begin
                        cs1 <= 1'b1;
                        cs2 <= 1'b1;
                    end
                endcase

                if (clk_count == active_half_period_cycles - 1'b1) begin
                    clk_count <= {COUNTER_WIDTH{1'b0}};
                    sclk      <= ~sclk;

                    if (sclk) begin
                        if (bit_count > 0) begin
                            bit_count <= bit_count - 1'b1;
                            if (bit_count > 1) begin
                                shift_reg <= {shift_reg[DATA_BITS-2:0], 1'b0};
                                sdi       <= shift_reg[DATA_BITS-2];
                            end else begin
                                sdi <= 1'b0;
                            end
                        end

                        if (bit_count == 1) begin
                            busy          <= 1'b0;
                            done          <= 1'b1;
                            cs1           <= 1'b1;
                            cs2           <= 1'b1;
                            sclk          <= 1'b0;
                            active_target <= 2'b00;
                        end
                    end
                end else begin
                    clk_count <= clk_count + 1'b1;
                end
            end
        end
    end

endmodule
