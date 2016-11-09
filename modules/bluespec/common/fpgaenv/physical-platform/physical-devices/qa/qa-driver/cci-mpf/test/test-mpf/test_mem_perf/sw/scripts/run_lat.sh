#!/bin/sh

##
## Run latency tests.  Use $1 as a tag in the middle of file names.
##

tag=""
if [ -n "${1}" ]; then
    tag="${1}_"
fi

mkdir -p stats

for mcl in 1 2 4
do
    for vc in 0 1 2
    do
        ./test_mem_latency --vcmap-enable=0 --mcl=${mcl} --vc=${vc} | tee stats/lat_${tag}mcl${mcl}_vc${vc}.dat
    done

    ./test_mem_latency --vcmap-enable=1 --mcl=${mcl} --vc=0 | tee stats/lat_${tag}map_mcl${mcl}_vc0.dat
done
