#
# Altera Timing Tcl Library
#   Various tcl functions for annotating timing constraints
#

##
## Discover the clock feeding a pin.  Source from:
##   https://www.altera.com/support/support-resources/design-examples/design-software/timequest/exm-tq-clocks-feeding-register.html
##
proc get_clocks_feeding_pin { pin_name } {

    # Before step 1, perform an error check to ensure that pin_name
    # passed in to the procedure matches one and only one pin.
    # Return an error if it does not match one and only one pin.
    set pin_col [get_pins -no_duplicates -compatibility_mode $pin_name]
    if { 0 == [get_collection_size $pin_col] } {
        return -code error "No pins match $pin_name"
    } elseif { 1 < [get_collection_size $pin_col] } {
        return -code error "$pin_name matches [get_collection_size $pin_col]\
            pins but must match only one"
    }

    # Initialize variables used in the procedure
    catch { array unset nodes_with_clocks }
    catch { array unset node_types }
    array set nodes_with_clocks [list]
    array set node_types [list]
    set pin_drivers [list]

    # Step 1. Get all clocks in the design and create a mapping from
    # the target nodes to the clocks on the target nodes

    # Iterate over each clock in the design
    foreach_in_collection clock_id [all_clocks] {

        set clock_name [get_clock_info -name $clock_id]
        set clock_target_col [get_clock_info -targets $clock_id]

        # Each clock is applied to nodes. Get the collection of target nodes
        foreach_in_collection target_id [get_clock_info -targets $clock_id] {

            # Associate the clock name with its target node
            set target_name [get_node_info -name $target_id]
            lappend nodes_with_clocks($target_name) $clock_name

            # Save the type of the target node for later use
            set target_type [get_node_info -type $target_id]
            set node_types($target_name) $target_type
        }
    }

    # Step 2. Get a list of nodes with clocks on them that are on the
    # fanin path to the specified pin

    # Iterate over all nodes in the mapping created in step 1
    foreach node_with_clocks [array names nodes_with_clocks] {

        # Use the type of the target node to create a type-specific
        # collection for the -through value in the get_fanins command.
        switch -exact -- $node_types($node_with_clocks) {
            "pin" {  set through_col [get_pins $node_with_clocks] }
            "port" { set through_col [get_ports $node_with_clocks] }
            "cell" { set through_col [get_cells $node_with_clocks] }
            "reg" {  set through_col [get_registers $node_with_clocks] }
            default { return -code error "$node_types($node_with_clocks) is not handled\
                as a fanin type by the script" }
        }

        # Get any fanins to the specified pin through the current node
        set fanin_col [get_fanins -clock -through $through_col $pin_name]

        # If there is at least one fanin node, the current node is on the
        # fanin path to the specified pin, so save it.
        if { 0 < [get_collection_size $fanin_col] } {
            lappend pin_drivers $node_with_clocks
        }
    }

    # Before step 3, perform an error check to ensure that at least one
    # of the nodes with clocks in the design is on the fanin path to
    # the specified pin.
    if { 0 == [llength $pin_drivers] } {
        return -code error "Can not find any node with clocks that drives $pin_name"
    }

    # Step 3. From the list of nodes created in step 2, find the node
    # closest to the specified pin and return the clocks on that node.

    while { 1 < [llength $pin_drivers] } {

        # Get the first two nodes in the pin_drivers list
        set node_a [lindex $pin_drivers 0]
        set node_b [lindex $pin_drivers 1]

        # Use the type of the target node to create a type-specific
        # collection for the -through value in the get_fanins command.
        switch -exact -- $node_types($node_b) {
            "pin" {  set through_col [get_pins $node_b] }
            "port" { set through_col [get_ports $node_b] }
            "cell" { set through_col [get_cells $node_b] }
            "reg" {  set through_col [get_registers $node_b] }
            default { return -code error "$node_types($node_b) is not handled\
                as a fanin type by the script" }
        }

        # Check whether node_b is on the fanin path of node_a
        set fanin_col [get_fanins -clock -through $through_col $node_a]

        # If there is at least one fanin node, node_b must be further
        # away from the specified pin than node_a is.
        # If there is no fanin node, node_b must be closer to the
        # specified pin than node_a is.
        if { 0 < [get_collection_size $fanin_col] } {

            # node_a is closer to the pin.
            # Remove node_b from the pin_drivers list
            set pin_drivers [lreplace $pin_drivers 1 1]

        } else {

            # node_b is closer to the pin
            # Remove node_a from the pin_drivers list
            set pin_drivers [lrange $pin_drivers 1 end]
        }
    }

    # The one node left in pin_drivers is the node driving the specified pin
    set node_driving_pin [lindex $pin_drivers 0]

    # Look up the clocks on the node in the mapping from step 1 and return them
    return $nodes_with_clocks($node_driving_pin)
}


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
