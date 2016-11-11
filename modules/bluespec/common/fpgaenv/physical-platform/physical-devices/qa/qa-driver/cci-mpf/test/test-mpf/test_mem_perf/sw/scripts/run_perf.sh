#!/bin/sh

##
## Run bandwidth tests.  Use $1 as a tag in the middle of file names.
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
        ./test_mem_perf --vcmap-enable=0 --mcl=${mcl} --vc=${vc} --rdline-s=0 --wrline-m=0 | tee stats/perf_${tag}mcl${mcl}_vc${vc}.dat
    done

    ./test_mem_perf --vcmap-enable=1 --mcl=${mcl} --vc=0 --rdline-s=0 --wrline-m=0 | tee stats/perf_${tag}map_mcl${mcl}_vc0.dat
done
