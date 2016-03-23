## Quartus constraints for MPF.

# CSR read from LUTRAM is held for two cycles to relax timing
set_multicycle_path -setup -end -through [get_nets {*cciMpfCSRMemRdVal*} ] 2
set_multicycle_path -hold  -end -through [get_nets {*cciMpfCSRMemRdVal*} ] 1
