if (! exists("platform")) platform = "SKX"

set term postscript color enhanced font "Helvetica" 17 butt dashed

set ylabel "Bandwidth (GB/s)" offset 1.75,0 font ",15"
set xlabel "Latency (ns)" offset 0,.25 font ",15"
set x2label "Latency (400MHz cycles)" font ",15"


set mxtics 3
set boxwidth 0.8

set xtics out nomirror font ",12"
set x2tics out font ",12"
set link x2 via x/2.5 inverse x*2.5

set ytics out font ",12"
set auto x
set yrange [0:]
#set size square
set bmargin 0.25
set tmargin 3.0
set lmargin 1.5
set rmargin 2.0

set key on inside left top width 2 samplen 4 spacing 1.5 font ",14"
set style fill pattern
set style data histograms

set style line 1 lc rgb "red" lw 3
set style line 2 lc rgb "red" lw 3 dashtype "-"
set style line 3 lc rgb "blue" lw 3
set style line 4 lc rgb "blue" lw 3 dashtype "-"
set style line 5 lc rgb "green" lw 3
set style line 6 lc rgb "green" lw 3 dashtype "-"
set style line 7 lc rgb "brown" lw 3
set style line 8 lc rgb "brown" lw 3 dashtype "."


set output "| ps2pdf - read_bw_mcl1.pdf"
set title platform . " Xeon+FPGA Uncached READ Latency vs. Bandwidth  (MCL=1)" offset 0,.25 font ",18"

plot 'stats/lat_mcl1_vc1.dat' index 1 using ($9*2.5):($1) with lines ls 1 title "VL0", \
     'stats/lat_ord_mcl1_vc1.dat' index 1 using ($9*2.5):($1) with lines ls 2 title "VL0 with ROB", \
     'stats/lat_mcl1_vc2.dat' index 1 using ($9*2.5):($1) with lines ls 3 title "VH0", \
     'stats/lat_ord_mcl1_vc2.dat' index 1 using ($9*2.5):($1) with lines ls 4 title "VH0 with ROB", \
     'stats/lat_mcl1_vc0.dat' index 1 using ($9*2.5):($1) with lines ls 5 title "VA", \
     'stats/lat_ord_mcl1_vc0.dat' index 1 using ($9*2.5):($1) with lines ls 6 title "VA with ROB", \
     'stats/lat_map_mcl1_vc0.dat' index 1 using ($9*2.5):($1) with lines ls 7 title "VC Map", \
     'stats/lat_ord_map_mcl1_vc0.dat' index 1 using ($9*2.5):($1) with lines ls 8 title "VC Map with ROB"


set output "| ps2pdf - read_bw_mcl4.pdf"
set title platform . " Xeon+FPGA Uncached READ Latency vs. Bandwidth  (MCL=4)" offset 0,.25 font ",18"

plot 'stats/lat_mcl4_vc1.dat' index 1 using ($9*2.5):($1) with lines ls 1 title "VL0", \
     'stats/lat_ord_mcl4_vc1.dat' index 1 using ($9*2.5):($1) with lines ls 2 title "VL0 with ROB", \
     'stats/lat_mcl4_vc2.dat' index 1 using ($9*2.5):($1) with lines ls 3 title "VH0", \
     'stats/lat_ord_mcl4_vc2.dat' index 1 using ($9*2.5):($1) with lines ls 4 title "VH0 with ROB", \
     'stats/lat_mcl4_vc0.dat' index 1 using ($9*2.5):($1) with lines ls 5 title "VA", \
     'stats/lat_ord_mcl4_vc0.dat' index 1 using ($9*2.5):($1) with lines ls 6 title "VA with ROB", \
     'stats/lat_map_mcl4_vc0.dat' index 1 using ($9*2.5):($1) with lines ls 7 title "VC Map", \
     'stats/lat_ord_map_mcl4_vc0.dat' index 1 using ($9*2.5):($1) with lines ls 8 title "VC Map with ROB"


set output "| ps2pdf - write_bw_mcl1.pdf"
set title platform . " Xeon+FPGA Uncached WRITE Latency vs. Bandwidth  (MCL=1)" offset 0,.25 font ",18"

plot 'stats/lat_mcl1_vc1.dat' index 4 using ($11*2.5):($2) with lines ls 1 title "VL0", \
     'stats/lat_mcl1_vc2.dat' index 4 using ($11*2.5):($2) with lines ls 3 title "VH0", \
     'stats/lat_mcl1_vc0.dat' index 4 using ($11*2.5):($2) with lines ls 5 title "VA", \
     'stats/lat_map_mcl1_vc0.dat' index 4 using ($11*2.5):($2) with lines ls 7 title "VC Map"


set output "| ps2pdf - write_bw_mcl4.pdf"
set title platform . " Xeon+FPGA Uncached WRITE Latency vs. Bandwidth  (MCL=4)" offset 0,.25 font ",18"

plot 'stats/lat_mcl4_vc1.dat' index 4 using ($11*2.5):($2) with lines ls 1 title "VL0", \
     'stats/lat_mcl4_vc2.dat' index 4 using ($11*2.5):($2) with lines ls 3 title "VH0", \
     'stats/lat_mcl4_vc0.dat' index 4 using ($11*2.5):($2) with lines ls 5 title "VA", \
     'stats/lat_map_mcl4_vc0.dat' index 4 using ($11*2.5):($2) with lines ls 7 title "VC Map"
