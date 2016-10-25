#set term postscript color enhanced font "Helvetica" 17 butt dashed
#set terminal png transparent nocrop enhanced size 450,320 font "Helvetica,8" 
#set output 'hidden.7.png'

set grid xtics nomxtics ytics nomytics noztics nomztics \
 nox2tics nomx2tics noy2tics nomy2tics nocbtics nomcbtics

set dgrid3d 15,45

set xrange [ 0 : 129 ] noreverse nowriteback
set yrange [ 64 : 1073741824 ] noreverse nowriteback
set format y '%.0s%cB'

set title "Bandwidth (GB/s) MCL=1" font ",18" offset 0,1
set key font ",13" above box
set ylabel "Memory Footprint" font ",15" offset -1,-1
set ytics  font ",11" offset 0,-0.5
set xlabel "Stride (64 byte lines)" font ",15" offset 0,-1
set xtics  font ",11" offset 0,-0.25
set zlabel "GB/s" font ",15" offset 2
set ztics  font ",11" offset 0.5

unset colorbox
set border 4095
set view 102,51

set palette defined (0 0 0 0.5, 1 0 0 1, 2 0 0.5 1, 3 0 1 1, 4 0.5 1 0.5, 5 1 1 0, 6 1 0.5 0, 7 1 0 0, 8 0.5 0 0)
set palette maxcolors 10
set pm3d explicit flush center

#splot "<paste -d '' stats/mcl1_wrm_va_base.dat stats/mcl1_wrm_va_dedup.dat" index 0 using 2:1:($9-$3) with pm3d notitle

splot "results.dat" index 0 using 2:1:3 with lines lc "red" lw 1.5 title "Read", \
      "results.dat" index 1 using 2:1:4 with lines lc "blue" lw 1.5 title "Write", \
      "results.dat" index 2 using 2:1:($3+$4) with lines lc "green" lw 1.5 title "Read+Write"
