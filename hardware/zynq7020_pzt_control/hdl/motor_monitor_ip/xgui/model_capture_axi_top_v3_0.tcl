# Definitional proc to organize widgets for parameters.
proc init_gui { IPINST } {
  ipgui::add_param $IPINST -name "Component_Name"
  #Adding Page
  set Page_0 [ipgui::add_page $IPINST -name "Page 0"]
  ipgui::add_param $IPINST -name "AXIS_DATA_WIDTH" -parent ${Page_0}
  ipgui::add_param $IPINST -name "AXI_ADDR_WIDTH" -parent ${Page_0}
  ipgui::add_param $IPINST -name "AXI_DATA_WIDTH" -parent ${Page_0}
  ipgui::add_param $IPINST -name "DAC_BITS" -parent ${Page_0}
  ipgui::add_param $IPINST -name "DAC_TARGET_SEL" -parent ${Page_0}
  ipgui::add_param $IPINST -name "DEFAULT_SAMPLES_PER_CODE" -parent ${Page_0}
  ipgui::add_param $IPINST -name "DEFAULT_SETTLE_CYCLES" -parent ${Page_0}
  ipgui::add_param $IPINST -name "DEFAULT_STEP_SIZE" -parent ${Page_0}
  ipgui::add_param $IPINST -name "SPI_HALF_PERIOD_CYCLES" -parent ${Page_0}


}

proc update_PARAM_VALUE.AXIS_DATA_WIDTH { PARAM_VALUE.AXIS_DATA_WIDTH } {
	# Procedure called to update AXIS_DATA_WIDTH when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.AXIS_DATA_WIDTH { PARAM_VALUE.AXIS_DATA_WIDTH } {
	# Procedure called to validate AXIS_DATA_WIDTH
	return true
}

proc update_PARAM_VALUE.AXI_ADDR_WIDTH { PARAM_VALUE.AXI_ADDR_WIDTH } {
	# Procedure called to update AXI_ADDR_WIDTH when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.AXI_ADDR_WIDTH { PARAM_VALUE.AXI_ADDR_WIDTH } {
	# Procedure called to validate AXI_ADDR_WIDTH
	return true
}

proc update_PARAM_VALUE.AXI_DATA_WIDTH { PARAM_VALUE.AXI_DATA_WIDTH } {
	# Procedure called to update AXI_DATA_WIDTH when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.AXI_DATA_WIDTH { PARAM_VALUE.AXI_DATA_WIDTH } {
	# Procedure called to validate AXI_DATA_WIDTH
	return true
}

proc update_PARAM_VALUE.DAC_BITS { PARAM_VALUE.DAC_BITS } {
	# Procedure called to update DAC_BITS when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.DAC_BITS { PARAM_VALUE.DAC_BITS } {
	# Procedure called to validate DAC_BITS
	return true
}

proc update_PARAM_VALUE.DAC_TARGET_SEL { PARAM_VALUE.DAC_TARGET_SEL } {
	# Procedure called to update DAC_TARGET_SEL when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.DAC_TARGET_SEL { PARAM_VALUE.DAC_TARGET_SEL } {
	# Procedure called to validate DAC_TARGET_SEL
	return true
}

proc update_PARAM_VALUE.DEFAULT_SAMPLES_PER_CODE { PARAM_VALUE.DEFAULT_SAMPLES_PER_CODE } {
	# Procedure called to update DEFAULT_SAMPLES_PER_CODE when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.DEFAULT_SAMPLES_PER_CODE { PARAM_VALUE.DEFAULT_SAMPLES_PER_CODE } {
	# Procedure called to validate DEFAULT_SAMPLES_PER_CODE
	return true
}

proc update_PARAM_VALUE.DEFAULT_SETTLE_CYCLES { PARAM_VALUE.DEFAULT_SETTLE_CYCLES } {
	# Procedure called to update DEFAULT_SETTLE_CYCLES when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.DEFAULT_SETTLE_CYCLES { PARAM_VALUE.DEFAULT_SETTLE_CYCLES } {
	# Procedure called to validate DEFAULT_SETTLE_CYCLES
	return true
}

proc update_PARAM_VALUE.DEFAULT_STEP_SIZE { PARAM_VALUE.DEFAULT_STEP_SIZE } {
	# Procedure called to update DEFAULT_STEP_SIZE when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.DEFAULT_STEP_SIZE { PARAM_VALUE.DEFAULT_STEP_SIZE } {
	# Procedure called to validate DEFAULT_STEP_SIZE
	return true
}

proc update_PARAM_VALUE.SPI_HALF_PERIOD_CYCLES { PARAM_VALUE.SPI_HALF_PERIOD_CYCLES } {
	# Procedure called to update SPI_HALF_PERIOD_CYCLES when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.SPI_HALF_PERIOD_CYCLES { PARAM_VALUE.SPI_HALF_PERIOD_CYCLES } {
	# Procedure called to validate SPI_HALF_PERIOD_CYCLES
	return true
}


proc update_MODELPARAM_VALUE.AXI_ADDR_WIDTH { MODELPARAM_VALUE.AXI_ADDR_WIDTH PARAM_VALUE.AXI_ADDR_WIDTH } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.AXI_ADDR_WIDTH}] ${MODELPARAM_VALUE.AXI_ADDR_WIDTH}
}

proc update_MODELPARAM_VALUE.AXI_DATA_WIDTH { MODELPARAM_VALUE.AXI_DATA_WIDTH PARAM_VALUE.AXI_DATA_WIDTH } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.AXI_DATA_WIDTH}] ${MODELPARAM_VALUE.AXI_DATA_WIDTH}
}

proc update_MODELPARAM_VALUE.AXIS_DATA_WIDTH { MODELPARAM_VALUE.AXIS_DATA_WIDTH PARAM_VALUE.AXIS_DATA_WIDTH } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.AXIS_DATA_WIDTH}] ${MODELPARAM_VALUE.AXIS_DATA_WIDTH}
}

proc update_MODELPARAM_VALUE.DAC_BITS { MODELPARAM_VALUE.DAC_BITS PARAM_VALUE.DAC_BITS } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.DAC_BITS}] ${MODELPARAM_VALUE.DAC_BITS}
}

proc update_MODELPARAM_VALUE.DEFAULT_SETTLE_CYCLES { MODELPARAM_VALUE.DEFAULT_SETTLE_CYCLES PARAM_VALUE.DEFAULT_SETTLE_CYCLES } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.DEFAULT_SETTLE_CYCLES}] ${MODELPARAM_VALUE.DEFAULT_SETTLE_CYCLES}
}

proc update_MODELPARAM_VALUE.DEFAULT_SAMPLES_PER_CODE { MODELPARAM_VALUE.DEFAULT_SAMPLES_PER_CODE PARAM_VALUE.DEFAULT_SAMPLES_PER_CODE } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.DEFAULT_SAMPLES_PER_CODE}] ${MODELPARAM_VALUE.DEFAULT_SAMPLES_PER_CODE}
}

proc update_MODELPARAM_VALUE.DEFAULT_STEP_SIZE { MODELPARAM_VALUE.DEFAULT_STEP_SIZE PARAM_VALUE.DEFAULT_STEP_SIZE } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.DEFAULT_STEP_SIZE}] ${MODELPARAM_VALUE.DEFAULT_STEP_SIZE}
}

proc update_MODELPARAM_VALUE.SPI_HALF_PERIOD_CYCLES { MODELPARAM_VALUE.SPI_HALF_PERIOD_CYCLES PARAM_VALUE.SPI_HALF_PERIOD_CYCLES } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.SPI_HALF_PERIOD_CYCLES}] ${MODELPARAM_VALUE.SPI_HALF_PERIOD_CYCLES}
}

proc update_MODELPARAM_VALUE.DAC_TARGET_SEL { MODELPARAM_VALUE.DAC_TARGET_SEL PARAM_VALUE.DAC_TARGET_SEL } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.DAC_TARGET_SEL}] ${MODELPARAM_VALUE.DAC_TARGET_SEL}
}

