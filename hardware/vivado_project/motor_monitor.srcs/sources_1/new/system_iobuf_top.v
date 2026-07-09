`timescale 1 ps / 1 ps

module system_iobuf_top
   (DDR_addr,
    DDR_ba,
    DDR_cas_n,
    DDR_ck_n,
    DDR_ck_p,
    DDR_cke,
    DDR_cs_n,
    DDR_dm,
    DDR_dq,
    DDR_dqs_n,
    DDR_dqs_p,
    DDR_odt,
    DDR_ras_n,
    DDR_reset_n,
    DDR_we_n,
    FIXED_IO_ddr_vrn,
    FIXED_IO_ddr_vrp,
    FIXED_IO_mio,
    FIXED_IO_ps_clk,
    FIXED_IO_ps_porb,
    FIXED_IO_ps_srstb,
    adc_burst_0,
    adc_busy_0,
    adc_chsel_0,
    adc_convst_0,
    adc_cs_n_0,
    adc_data_bus_0,
    adc_hw_rngsel_0,
    adc_rd_n_0,
    adc_reset_n_0,
    adc_ser_par_0,
    dac_cam_cs_0,
    dac_cam_sclk_0,
    dac_cam_sdi_0,
    dac_m1_cs_0,
    dac_m1_sclk_0,
    dac_m1_sdi_0,
    dac_m2_cs_0,
    dac_m2_sclk_0,
    dac_m2_sdi_0,
    uart_rtl_0_rxd,
    uart_rtl_0_txd);

  inout [14:0]DDR_addr;
  inout [2:0]DDR_ba;
  inout DDR_cas_n;
  inout DDR_ck_n;
  inout DDR_ck_p;
  inout DDR_cke;
  inout DDR_cs_n;
  inout [3:0]DDR_dm;
  inout [31:0]DDR_dq;
  inout [3:0]DDR_dqs_n;
  inout [3:0]DDR_dqs_p;
  inout DDR_odt;
  inout DDR_ras_n;
  inout DDR_reset_n;
  inout DDR_we_n;
  inout FIXED_IO_ddr_vrn;
  inout FIXED_IO_ddr_vrp;
  inout [53:0]FIXED_IO_mio;
  inout FIXED_IO_ps_clk;
  inout FIXED_IO_ps_porb;
  inout FIXED_IO_ps_srstb;
  output adc_burst_0;
  input adc_busy_0;
  output [2:0]adc_chsel_0;
  output adc_convst_0;
  output adc_cs_n_0;
  inout [15:0]adc_data_bus_0;
  output [1:0]adc_hw_rngsel_0;
  output adc_rd_n_0;
  output adc_reset_n_0;
  output adc_ser_par_0;
  output dac_cam_cs_0;
  output dac_cam_sclk_0;
  output dac_cam_sdi_0;
  output dac_m1_cs_0;
  output dac_m1_sclk_0;
  output dac_m1_sdi_0;
  output dac_m2_cs_0;
  output dac_m2_sclk_0;
  output dac_m2_sdi_0;
  input  uart_rtl_0_rxd;
  output uart_rtl_0_txd;

  wire [15:0] adc_data_bus_i_0;
  wire [15:0] adc_data_bus_o_0;
  wire        adc_data_bus_t_0;

  genvar adc_data_idx;
  generate
    for (adc_data_idx = 0; adc_data_idx < 16; adc_data_idx = adc_data_idx + 1) begin : gen_adc_iobuf
      IOBUF u_adc_data_iobuf (
        .I(adc_data_bus_o_0[adc_data_idx]),
        .O(adc_data_bus_i_0[adc_data_idx]),
        .IO(adc_data_bus_0[adc_data_idx]),
        .T(adc_data_bus_t_0)
      );
    end
  endgenerate

  system_wrapper system_wrapper_i
       (.DDR_addr(DDR_addr),
        .DDR_ba(DDR_ba),
        .DDR_cas_n(DDR_cas_n),
        .DDR_ck_n(DDR_ck_n),
        .DDR_ck_p(DDR_ck_p),
        .DDR_cke(DDR_cke),
        .DDR_cs_n(DDR_cs_n),
        .DDR_dm(DDR_dm),
        .DDR_dq(DDR_dq),
        .DDR_dqs_n(DDR_dqs_n),
        .DDR_dqs_p(DDR_dqs_p),
        .DDR_odt(DDR_odt),
        .DDR_ras_n(DDR_ras_n),
        .DDR_reset_n(DDR_reset_n),
        .DDR_we_n(DDR_we_n),
        .FIXED_IO_ddr_vrn(FIXED_IO_ddr_vrn),
        .FIXED_IO_ddr_vrp(FIXED_IO_ddr_vrp),
        .FIXED_IO_mio(FIXED_IO_mio),
        .FIXED_IO_ps_clk(FIXED_IO_ps_clk),
        .FIXED_IO_ps_porb(FIXED_IO_ps_porb),
        .FIXED_IO_ps_srstb(FIXED_IO_ps_srstb),
        .adc_burst_0(adc_burst_0),
        .adc_busy_0(adc_busy_0),
        .adc_chsel_0(adc_chsel_0),
        .adc_convst_0(adc_convst_0),
        .adc_cs_n_0(adc_cs_n_0),
        .adc_data_bus_i_0(adc_data_bus_i_0),
        .adc_data_bus_o_0(adc_data_bus_o_0),
        .adc_data_bus_t_0(adc_data_bus_t_0),
        .adc_hw_rngsel_0(adc_hw_rngsel_0),
        .adc_rd_n_0(adc_rd_n_0),
        .adc_reset_n_0(adc_reset_n_0),
        .adc_ser_par_0(adc_ser_par_0),
        .dac_cam_cs_0(dac_cam_cs_0),
        .dac_cam_sclk_0(dac_cam_sclk_0),
        .dac_cam_sdi_0(dac_cam_sdi_0),
        .dac_m1_cs_0(dac_m1_cs_0),
        .dac_m1_sclk_0(dac_m1_sclk_0),
        .dac_m1_sdi_0(dac_m1_sdi_0),
        .dac_m2_cs_0(dac_m2_cs_0),
        .dac_m2_sclk_0(dac_m2_sclk_0),
        .dac_m2_sdi_0(dac_m2_sdi_0),
        .uart_rtl_0_rxd(uart_rtl_0_rxd),
        .uart_rtl_0_txd(uart_rtl_0_txd));

endmodule
