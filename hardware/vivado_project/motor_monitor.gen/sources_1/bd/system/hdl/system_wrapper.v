//Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
//Copyright 2022-2025 Advanced Micro Devices, Inc. All Rights Reserved.
//--------------------------------------------------------------------------------
//Tool Version: Vivado v.2025.2 (win64) Build 6299465 Fri Nov 14 19:35:11 GMT 2025
//Date        : Fri Jun 19 17:35:39 2026
//Host        : DESKTOP-TPTN2DE running 64-bit major release  (build 9200)
//Command     : generate_target system_wrapper.bd
//Design      : system_wrapper
//Purpose     : IP block netlist
//--------------------------------------------------------------------------------
`timescale 1 ps / 1 ps

module system_wrapper
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
    adc_data_bus_i_0,
    adc_data_bus_o_0,
    adc_data_bus_t_0,
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
  input [15:0]adc_data_bus_i_0;
  output [15:0]adc_data_bus_o_0;
  output adc_data_bus_t_0;
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
  input uart_rtl_0_rxd;
  output uart_rtl_0_txd;

  wire [14:0]DDR_addr;
  wire [2:0]DDR_ba;
  wire DDR_cas_n;
  wire DDR_ck_n;
  wire DDR_ck_p;
  wire DDR_cke;
  wire DDR_cs_n;
  wire [3:0]DDR_dm;
  wire [31:0]DDR_dq;
  wire [3:0]DDR_dqs_n;
  wire [3:0]DDR_dqs_p;
  wire DDR_odt;
  wire DDR_ras_n;
  wire DDR_reset_n;
  wire DDR_we_n;
  wire FIXED_IO_ddr_vrn;
  wire FIXED_IO_ddr_vrp;
  wire [53:0]FIXED_IO_mio;
  wire FIXED_IO_ps_clk;
  wire FIXED_IO_ps_porb;
  wire FIXED_IO_ps_srstb;
  wire adc_burst_0;
  wire adc_busy_0;
  wire [2:0]adc_chsel_0;
  wire adc_convst_0;
  wire adc_cs_n_0;
  wire [15:0]adc_data_bus_i_0;
  wire [15:0]adc_data_bus_o_0;
  wire adc_data_bus_t_0;
  wire [1:0]adc_hw_rngsel_0;
  wire adc_rd_n_0;
  wire adc_reset_n_0;
  wire adc_ser_par_0;
  wire dac_cam_cs_0;
  wire dac_cam_sclk_0;
  wire dac_cam_sdi_0;
  wire dac_m1_cs_0;
  wire dac_m1_sclk_0;
  wire dac_m1_sdi_0;
  wire dac_m2_cs_0;
  wire dac_m2_sclk_0;
  wire dac_m2_sdi_0;
  wire uart_rtl_0_rxd;
  wire uart_rtl_0_txd;

  system system_i
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
