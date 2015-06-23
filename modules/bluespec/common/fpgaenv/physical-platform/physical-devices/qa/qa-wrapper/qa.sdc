#**************************************************************
# Quick Assist clock declaration
#   We pull in a generated, 200MHz clock from the quick assist 
#   device. 
#**************************************************************

create_clock -name {vl_clk_LPdomain_32ui} -period 5 [get_ports {cci_std_afu|model_wrapper|vl_clk_LPdomain_32ui}]

annotateSafeClockCrossing [get_clocks cci_std_afu|model_wrapper|vl_clk_LPdomain_32ui] [get_clocks "cci_std_afu|model_wrapper|m_sys_sys_vp_m_mod|llpi_phys_plat_clocks_userClockPackage_m_clk|altpll_component|auto_generated|generic_pll1~PLL_OUTPUT_COUNTER|divclk"]


