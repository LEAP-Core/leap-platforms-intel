#
# Altera Timing Tcl Library
#   Various tcl functions for annotating timing constraints
#

## This function annotates pairs of clocks as a safe (managed)
## clock crossing.
proc annotateSafeClockCrossing {src_clock dst_clock} {
    # check inputs -- sometimes things may have been optimized away.
    if {[llength $src_clock] && [llength $dst_clock]} {
        puts "Separating clocks ${src_clock} and ${dst_clock}"
        set_clock_groups -asynchronous -group $src_clock -group $dst_clock
    }
}

# Derive PLL-based user clock. 
# Why this doesn't happen automatically is beyond me. 
derive_pll_clocks


