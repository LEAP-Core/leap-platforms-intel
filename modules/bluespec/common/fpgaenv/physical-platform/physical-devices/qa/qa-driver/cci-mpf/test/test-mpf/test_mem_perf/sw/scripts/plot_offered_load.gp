if (! exists("platform")) platform = "SKX"

set term postscript color enhanced font "Helvetica" 17 butt dashed

set ylabel "Bandwidth (GB/s)" offset 1,0 font ",15"
set y2label "Latency (400 MHz Cycles)" offset -1.75,0 font ",15"
set xlabel "Offered Load Ratio" font ",15"

set mxtics 3
set boxwidth 0.8
set xtics out font ",12"

set ytics out nomirror font ",12"
set y2tics out font ",12"

set yrange [0:]
set y2range [0:]
#set size square
set bmargin 0.5
set tmargin 0.5
set lmargin 1.5
set rmargin 6.25

set key on inside bottom right width 2 samplen 4 spacing 1.5 font ",14"
set style fill pattern
set style data histograms

set style line 1 lc rgb "red" lw 3
set style line 2 lc rgb "red" lw 3 dashtype "-"
set style line 3 lc rgb "blue" lw 3
set style line 4 lc rgb "blue" lw 3 dashtype "-"
set style line 5 lc rgb "green" lw 3
set style line 6 lc rgb "green" lw 3 dashtype "-"


set output "| ps2pdf - read_offer_mcl1.pdf"
set title platform . " Xeon+FPGA Uncached READ Varying Offered Load  (MCL=1)" offset 0,1 font ",18"
set auto x

plot 'stats/lat_mcl1_vc0.dat' index 2 using (1/($1+1)):($2) with lines ls 1 title "VA Bandwidth", \
     'stats/lat_mcl1_vc0.dat' index 2 using (1/($1+1)):($10) axes x1y2 with lines ls 2 title "VA Latency", \
     'stats/lat_map_mcl1_vc0.dat' index 2 using (1/($1+1)):($2) with lines ls 3 title "VC Map Bandwidth", \
     'stats/lat_map_mcl1_vc0.dat' index 2 using (1/($1+1)):($10) axes x1y2 with lines ls 4 title "VC Map Latency", \
     'stats/lat_ord_map_mcl1_vc0.dat' index 2 using (1/($1+1)):($2) with lines ls 5 title "ROB VC Map Bandwidth", \
     'stats/lat_ord_map_mcl1_vc0.dat' index 2 using (1/($1+1)):($10) axes x1y2 with lines ls 6 title "ROB VC Map Latency"


set output "| ps2pdf - read_offer_mcl4.pdf"
set title platform . " Xeon+FPGA Uncached READ Varying Offered Load  (MCL=4)" offset 0,1 font ",18"
set xrange [0:.5]

plot 'stats/lat_mcl4_vc0.dat' index 2 using (1/($1+1)):($2) with lines ls 1 title "VA Bandwidth", \
     'stats/lat_mcl4_vc0.dat' index 2 using (1/($1+1)):($10) axes x1y2 with lines ls 2 title "VA Latency", \
     'stats/lat_map_mcl4_vc0.dat' index 2 using (1/($1+1)):($2) with lines ls 3 title "VC Map Bandwidth", \
     'stats/lat_map_mcl4_vc0.dat' index 2 using (1/($1+1)):($10) axes x1y2 with lines ls 4 title "VC Map Latency", \
     'stats/lat_ord_map_mcl4_vc0.dat' index 2 using (1/($1+1)):($2) with lines ls 5 title "ROB VC Map Bandwidth", \
     'stats/lat_ord_map_mcl4_vc0.dat' index 2 using (1/($1+1)):($10) axes x1y2 with lines ls 6 title "ROB VC Map Latency"


set output "| ps2pdf - write_offer_mcl1.pdf"
set title platform . " Xeon+FPGA Uncached WRITE Varying Offered Load  (MCL=1)" offset 0,1 font ",18"
set auto x

plot 'stats/lat_mcl1_vc0.dat' index 5 using (1/($1+1)):($3) with lines ls 1 title "VA Bandwidth", \
     'stats/lat_mcl1_vc0.dat' index 5 using (1/($1+1)):($12) axes x1y2 with lines ls 2 title "VA Latency", \
     'stats/lat_map_mcl1_vc0.dat' index 5 using (1/($1+1)):($3) with lines ls 3 title "VC Map Bandwidth", \
     'stats/lat_map_mcl1_vc0.dat' index 5 using (1/($1+1)):($12) axes x1y2 with lines ls 4 title "VC Map Latency"


set output "| ps2pdf - write_offer_mcl4.pdf"
set title platform . " Xeon+FPGA Uncached WRITE Varying Offered Load  (MCL=4)" offset 0,1 font ",18"
#set xrange [0:.5]

plot 'stats/lat_mcl4_vc0.dat' index 5 using (1/($1+1)):($3) with lines ls 1 title "VA Bandwidth", \
     'stats/lat_mcl4_vc0.dat' index 5 using (1/($1+1)):($12) axes x1y2 with lines ls 2 title "VA Latency", \
     'stats/lat_map_mcl4_vc0.dat' index 5 using (1/($1+1)):($3) with lines ls 3 title "VC Map Bandwidth", \
     'stats/lat_map_mcl4_vc0.dat' index 5 using (1/($1+1)):($12) axes x1y2 with lines ls 4 title "VC Map Latency"
