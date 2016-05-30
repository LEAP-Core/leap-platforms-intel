set current_exe $::TimeQuestInfo(nameofexecutable)
if { $current_exe == "quartus_fit" } {

    set_clock_uncertainty -from {pClk} -to {pClk} \
                          -hold 0.045  -add -enable_same_physical_edge

    set_clock_uncertainty -from {pClkDiv2}  -to {pClkDiv2} \
                          -hold 0.045  -add -enable_same_physical_edge

    set_clock_uncertainty -from {pClkDiv4}  -to {pClkDiv4} \
                          -hold 0.045  -add -enable_same_physical_edge

    set_clock_uncertainty -from {uClk_usr}  -to {uClk_usr} \
                          -hold 0.045  -add -enable_same_physical_edge

    set_clock_uncertainty -from {uClk_usrDiv2}  -to {uClk_usrDiv2} \
                          -hold 0.045  -add -enable_same_physical_edge

}
