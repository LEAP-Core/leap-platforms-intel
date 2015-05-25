
#---------------------------------------------------------------------------------------------------
# set 5ns paths through raddr (32UI) to embedded address registers in 2x clocked ram (16UI clocking)
#---------------------------------------------------------------------------------------------------
  set_max_delay  -through  *tag*raddr*                                          5.0
  set_max_delay  -through  *quad_ram*raddr*                                     5.0
  set_max_delay  -through  *re*_q*raddr*                                        5.0  
  set_max_delay  -through  *mem_req_fifo*raddr*                                 5.0
  set_max_delay  -through  *4Byteram*raddr*                                     5.0
  
  set_max_delay  -to  [get_registers {*qlp_top*tag*wxe*}]                       5.0
  set_max_delay  -to  [get_registers {*qlp_top*quad_ram*wxe*}]                  5.0
  set_max_delay  -to  [get_registers {*qlp_top*re*_q*wxe*}]                     5.0
  set_max_delay  -to  [get_registers {*mem_top*quad_*wxe*}]                     5.0
  set_max_delay  -to  [get_registers {*qlp_top*4Byteram*wxe*}]                  5.0

  set_max_delay  -to  [get_registers {*qlp_top*quad_ram*wxaddr*}]               5.0
  set_max_delay  -to  [get_registers {*qlp_top*re*_q*wxaddr*}]                  5.0
  set_max_delay  -to  [get_registers {*qlp_top*tag*wxaddr*}]                    5.0
  set_max_delay  -to  [get_registers {*mem_top*quad_*wxaddr*}]                  5.0
  set_max_delay  -to  [get_registers {*qlp_top*4Byteram*wxaddr*}]               5.0
  set_max_delay  -from                *clk_align*                               2.5
  set_max_delay  -from                *4Byteram*wxe*                            2.5
  
  set_max_delay  -to  [get_registers {*reset_sync*reset_reg*}]                  5.0
  set_multicycle_path -end -hold  -to [get_registers {*reset_sync*reset_reg*}]  1


create_generated_clock -name {Clk_128UI} -source [get_pins {bot_ome|top_qph|s45_reset_qph|s45_fab_pll_reset_qph|qph_reset_pll_fab_s45_inst|altera_pll_i|general[1].gpll~PLL_OUTPUT_COUNTER|divclk}] -divide_by 4 -master_clock {bot_ome|top_qph|s45_reset_qph|s45_fab_pll_reset_qph|qph_reset_pll_fab_s45_inst|altera_pll_i|general[1].gpll~PLL_OUTPUT_COUNTER|divclk} 
set_false_path  -from  [get_clocks {Clk_128UI}]  -to  [get_clocks {bot_ome|top_qph|s45_reset_qph|s45_fab_pll_reset_qph|qph_reset_pll_fab_s45_inst|altera_pll_i|general[1].gpll~PLL_OUTPUT_COUNTER|divclk}]
set_false_path  -to    [get_clocks {Clk_128UI}]  -from  [get_clocks {bot_ome|top_qph|s45_reset_qph|s45_fab_pll_reset_qph|qph_reset_pll_fab_s45_inst|altera_pll_i|general[1].gpll~PLL_OUTPUT_COUNTER|divclk}]
#-----------------------------------------------------------------------------------------
# Stephen's comments- use with 8G timing, since 8G is 4ns period.  They are there so the synthesis
# is not bogged down by the phy timing, because Altera would have to meet 4ns timing, and not us.
# over constrain due to large clk skews for clk domain crossing
#-----------------------------------------------------------------------------------------
#
#  if {$::quartus(nameofexecutable) == "quartus_sta"} {
# set_max_delay                             -to  *top_nlb*                      5.0
#  set_max_delay  -from *qph_xcvr_*          -to  *qph_mach*                     5.0
#  set_max_delay  -from *qph_mach*           -to  *qph_xcvr_*                    5.0
#  set_max_delay  -from *qph_mach*           -to  *qph_mach*                     5.0
#  }
