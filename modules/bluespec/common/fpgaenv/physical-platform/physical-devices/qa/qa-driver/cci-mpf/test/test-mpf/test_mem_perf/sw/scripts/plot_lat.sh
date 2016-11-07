#!/bin/sh

##
## This script expects that run_lat.sh has been completed in two configurations:
## one with a ROB enabled and one without, using:
##
##   scripts/run_lat.sh
##   scripts/run_lat.sh ord
##

gnuplot scripts/plot_latency.gp
gnuplot scripts/plot_offered_load.gp

# Merge into a single PDF
gs -dBATCH -dNOPAUSE -q -sDEVICE=pdfwrite -sOutputFile=bw-lat.pdf read_*.pdf write_*.pdf
rm read_*.pdf write_*.pdf
