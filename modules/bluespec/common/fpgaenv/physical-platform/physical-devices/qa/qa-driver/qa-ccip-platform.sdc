##
## CCI-P reset
##
set_false_path -from inst_ccip_interface_reg|pck_cp2af_softReset_T1 -to [get_keepers *ccip_std_afu*user_rst_T1*]
