##
## Annotate the system clock and model clock as independent.  There are
## synchronizers between the two.  Finding the clocks in QA can be challenging
## because wire names are optimized away.  We find the clocks from the
## two sides of one of the syncFIFOs.
##

set pin_col [get_pins -compatibility_mode {cci_std_afu|*|*|llpi_phys_plat_qa_device|syncChannelReadQ|sNotFullReg|clk}]

if {0 == [get_collection_size $pin_col]} {
    puts "WARNING: LEAP model clock not found!"
} else {
    puts "Analyzing LEAP model clock..."

    set clk_sys_name   [get_clocks_feeding_pin {cci_std_afu|*|*|llpi_phys_plat_qa_device|syncChannelReadQ|sNotFullReg|clk}]
    set clk_sys        [get_clocks $clk_sys_name]

    foreach_in_collection clk $clk_sys {
        set clk_sys_period [get_clock_info -period $clk]
        puts "SYS Clock $clk_sys_name: $clk_sys_period"
    }

    set clk_model_name [get_clocks_feeding_pin {cci_std_afu|*|*|llpi_phys_plat_qa_device|syncChannelReadQ|dNotEmptyReg|clk}]
    set clk_model      [get_clocks $clk_model_name]

    foreach_in_collection clk $clk_model {
        set clk_model_period [get_clock_info -period $clk]
        puts "MODEL Clock $clk_model_name: $clk_model_period"
    }

    if { $clk_sys_name != $clk_model_name } {
        annotateSafeClockCrossing $clk_sys $clk_model
    }
}
