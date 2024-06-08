#!/bin/bash

BITRATES=(0 1 2 3 4 5 6 7 8 9 10)
LINE_RATE=10
REPS=10


ENERGY_LOG="./fig1_energy_runs.txt"
IPERF_LOG="./fig1_iperflog_runs.json"

sudo ifconfig bond0 mtu 9000 up

for rep in $(seq $REPS); do
	echo "Rep $rep:" >> $ENERGY_LOG

for bitrate in "${BITRATES[@]}"; do
    total_energy=0


    #echo "BITRATE: $bitrate"
    flow1_band=$bitrate
    flow2_band=$(($LINE_RATE-$bitrate))

    # Begin the Energy Measurements
    start_CPU_1=$(sudo cat /sys/class/powercap/intel-rapl/intel-rapl:0/energy_uj)
    start_CPU_2=$(sudo cat /sys/class/powercap/intel-rapl/intel-rapl:1/energy_uj)

    # Special cases for the full speed then idle approach in the paper
    # Note: Flow 2 -> port 9020, Flow 1 -> port 9021
    if [ "$bitrate" -eq 0 ]; then
        iperf3 -c 172.24.74.14 -n 1250000K -i 60 -b ${flow2_band}G -p 9021 > $IPERF_LOG
        iperf3 -c 172.24.74.14 -n 1250000K -i 60 -b ${bitrate}G -p 9020 > $IPERF_LOG
        wait

    elif [ "$bitrate" -eq 10 ]; then
        iperf3 -c 172.24.74.14 -i 60 -n 1250000K -b ${bitrate}G -p 9020 > $IPERF_LOG
        iperf3 -c 172.24.74.14 -n 1250000K -i 60 -b ${flow2_band}G -p 9021  > $IPERF_LOG
        wait
    
    else 
        # Default case where we run flows concurrently
        iperf3 -c 172.24.74.14 -n 1250000K -b ${flow2_band}G -p 9021 -i 60 > $IPERF_LOG & 
        iperf3 -c 172.24.74.14 -n 1250000K -b ${bitrate}G -p 9020 -i 60 > $IPERF_LOG &
        wait # ensure the background jobs have stopped before proceeding

    fi 
    

    # Measure energy for each CPU socket post experiment.
    end_CPU_1=$(sudo cat /sys/class/powercap/intel-rapl/intel-rapl:0/energy_uj)
    end_CPU_2=$(sudo cat /sys/class/powercap/intel-rapl/intel-rapl:1/energy_uj)

    # Note: Used Fig 5 energy logic
    # Calculate energy difference for each socket. Flag and log when heuristic fails (end < start).
    if [ $end_CPU_1 -ge $start_CPU_1 ]; then
        diff_CPU_1=$((end_CPU_1 - start_CPU_1))
    else
        diff_CPU_1=0
        echo "Flow 1 bitrate made negative core 1: $bitrate"
    fi

    if [ $end_CPU_2 -ge $start_CPU_2 ]; then
        diff_CPU_2=$((end_CPU_2 - start_CPU_2))
    else
        diff_CPU_2=0
        echo "Flow 1 bitrate made negative core 2: $bitrate"
    fi

    # Sum energy differences to get total energy consumed.
    energy_consumed=$((diff_CPU_1 + diff_CPU_2))
    total_energy=$((total_energy + energy_consumed))
    echo "Energy consumed with flow 1 bitrate $bitrate is: $energy_consumed" >> $ENERGY_LOG

done
done