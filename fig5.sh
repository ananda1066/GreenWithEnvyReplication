#!/bin/bash

BOND_INT="bond0"

CCAS=("illinois" "reno" "cubic" "dctcp" "bbr2" "bbr" "vegas" "westwood" "scalable" "highspeed")
MTUS=(1500 3000 6000 9000)
DEF_MTU=9000
DEF_CCA="cubic"
NUM_REPEATS=20

# Initialize debugging log for negative readings.
NEG_DEBUG="./fig5/debug/negative_debug.txt"
> $NEG_DEBUG

# For each CCA, run the iperf workflow and measure energy.
for cca in "${CCAS[@]}"; do
    # sudo sysctl -w net.ipv4.tcp_congestion_control=$cca
 
    # Now we need to change the MTUs.
    for mtu in "${MTUS[@]}"; do
        sudo ifconfig $BOND_INT mtu $mtu up
	ifconfig $BOND_INT

	# TODO: Determine if we want to track experiments using timestamps.
	# Right now we are just clearing the file upon re-running the script.
	IPERF_OUTPUT="./fig5/debug/${cca}_${mtu}.json"
	> $IPERF_OUTPUT

	ENERGY_OUTPUT="./fig5/measurements/${cca}_${mtu}.txt"
	> $ENERGY_OUTPUT
        
	# Repeat the experiment 10 times for each CCA.
        for rep in $(seq $NUM_REPEATS); do

	    # Measure energy for each CPU socket prior to experiment.
	    start_CPU_1=$(sudo cat /sys/class/powercap/intel-rapl/intel-rapl:0/energy_uj)
	    start_CPU_2=$(sudo cat /sys/class/powercap/intel-rapl/intel-rapl:1/energy_uj)

            # Conduct iperf experiment.
	    iperf3 -c 172.24.74.14 -C $cca -n 50G -M $((mtu - 40)) -p 7000 -J >> $IPERF_OUTPUT

	    # Measure energy for each CPU socket post experiment.
	    end_CPU_1=$(sudo cat /sys/class/powercap/intel-rapl/intel-rapl:0/energy_uj)
	    end_CPU_2=$(sudo cat /sys/class/powercap/intel-rapl/intel-rapl:1/energy_uj)


	    # Calculate energy difference for each socket. Flag and log when heuristic fails (end < start).
	    if [ $end_CPU_1 -ge $start_CPU_1 ]; then
                diff_CPU_1=$((end_CPU_1 - start_CPU_1))
            else
                diff_CPU_1=0
		echo "CCA=${cca}, MTU=${mtu}, REP=${rep}, CPU1_START=${start_CPU_1}, CPU1_END=${end_CPU_1}" >> $NEG_DEBUG
            fi

	    if [ $end_CPU_2 -ge $start_CPU_2 ]; then
                diff_CPU_2=$((end_CPU_2 - start_CPU_2))
            else
                diff_CPU_2=0
                echo "CCA=${cca}, MTU=${mtu}, REP=${rep}, CPU2_START=${start_CPU_2}, CPU2_END=${end_CPU_2}" >> $NEG_DEBUG
            fi

	    # Sum energy differences to get total energy consumed when heuristic is valid.
	    if [[ $diff_CPU_1 -ne 0 && $diff_CPU_2 -ne 0 ]]; then
		energy_consumed=$((diff_CPU_1 + diff_CPU_2))
		echo $energy_consumed >> $ENERGY_OUTPUT

		echo -n "," >> $IPERF_OUTPUT
		echo "CCA=${cca}, MTU=${mtu}, REP=${rep}, ENERGY=${energy_consumed}"
	    fi
        done
    done
done

# reset configurations to the default.
sudo ifconfig $BOND_INT mtu $DEF_MTU up
sudo sysctl -w net.ipv4.tcp_congestion_control=$DEF_CCA