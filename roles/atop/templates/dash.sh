#!/bin/bash

render_single_plot() {
    local data_file="$1"
    local title="$2"
    local subtitle="$3"
    local value_label="$4"

    local out_file="$data_file".png
    echo "Plotting $data_file in $out_file"
    gnuplot -e "set terminal pngcairo size 1920,1080;
set output '$out_file';
set xdata time;
set timefmt '%s';
set format x '%Y-%m-%d %H:%M:%S';
set xtics 10800;
set title \"$title\n{/*0.5 $subtitle}\";
set xlabel 'Timestamp';
set ylabel '$value_label';
plot '$data_file' using 1:2 with lines title '';"
}
render_multi_plot() {
    local data_file="$1"
    local title="$2"
    local subtitle="$3"
    local value_label="$4"
    local col_count=$(($5 + 1))

    local out_file="$data_file".png
    echo "Plotting $data_file in $out_file"
    gnuplot -e "set terminal pngcairo size 1920,1080;
set output '$out_file';
set xdata time;
set timefmt '%s';
set format x '%Y-%m-%d %H:%M:%S';
set xtics 10800;
set title \"$title\n{/*0.5 $subtitle}\";
set xlabel 'Timestamp';
set ylabel '$value_label';
plot for [i=2:$col_count] '$data_file' using 1:i with lines title columnhead(i);"
}

create_single_plot() {
    local family="$1"
    local metric="$2"
    local selector=".$family.$metric"
    local data_file="data$selector.tsv"
    local title="$3"
    local subtitle="$4"
    local value_label="$2"

    echo "timestamp	value" > $data_file
    jq -r '[.timestamp, '"$selector"'] | @tsv' single-values.data.json >> $data_file

    render_single_plot "$data_file" "$title" "$subtitle" "$value_label"
}

create_multi_plot() {
    local family="$1"
    local group="$2"
    local metric="$3"
    local data_file="data-multi-$family-$group-$metric.tsv"
    local title="$4"
    local subtitle="$5"
    local value_label="$3"

    echo "timestamp	value	group" > $data_file
    jq -r '.timestamp as $ts | .'"$family"'[] | [$ts, .'"$metric"', "'"$group"'-" + (.'"$group"' | tostring)] | @tsv' array-values.data.json >> $data_file
    
    mlr --tsv reshape -s group,value then unsparsify then reorder -e -f CLEARED $data_file > $data_file.pivot
    local col_count="$(cat $data_file | awk '{print $3}' | sort -u | grep -v group | wc -l)"

    render_multi_plot "$data_file.pivot" "$title" "$subtitle" "$value_label" "$col_count"
}

main() {
    work_dir="$(mktemp -d)"
    pushd "$work_dir" || exit 1

    atop -r "/var/log/atop/atop_$(date -d '24 hours ago' '+%Y%m%d')" -b "$(date -d '24 hours ago' '+%Y%m%d%H%M')" -e "$(date '+%Y%m%d%H%M')" -JALL > raw.data.json
    atop -r "/var/log/atop/atop_$(date '+%Y%m%d')" -b "$(date -d '24 hours ago' '+%Y%m%d%H%M')" -e "$(date '+%Y%m%d%H%M')" -JALL >> raw.data.json

    jq '. | del(.PRG, .PRC, .PRM, .PRD)' raw.data.json > no-proc.data.json
    rm raw.data.json
    jq '. | {host:.host, timestamp:.timestamp, elapsed:.elapsed, CPU:.CPU, CPL:.CPL, MEM:.MEM, SWP:.SWP, PAG:.PAG, PSI:.PSI, NFC:.NFC, NFS:.NFS, NET_GENERAL:.NET_GENERAL}' no-proc.data.json > single-values.data.json
    jq '. | {host:.host, timestamp:.timestamp, elapsed:.elapsed, cpu:.cpu, LVM:.LVM, MDD:.MDD, DSK:.DSK, NET:.NET, NUM:.NUM}' no-proc.data.json > array-values.data.json


    create_single_plot "CPU" "nrcpu" "Number of CPUs" "The total number of CPUs in the system"

    cpu_stime_title="System Mode Time"
    cpu_stime_desc="Time the CPU spent in system mode (e.g., kernel space)."
    create_single_plot "CPU" "stime" "$cpu_stime_title" "$cpu_stime_desc"
    create_multi_plot "cpu" "cpuid" "stime" "$cpu_stime_title" "$cpu_stime_desc"

    cpu_utime_title="User Mode Time"
    cpu_utime_desc="Time the CPU spent in user mode (e.g., user applications)."
    create_single_plot "CPU" "utime" "$cpu_utime_title" "$cpu_utime_desc"
    create_multi_plot "cpu" "cpuid" "utime" "$cpu_utime_title" "$cpu_utime_desc"
    
    cpu_ntime_title="Niced User Tasks Time"
    cpu_ntime_desc="Time the CPU spent processing niced (lower-priority) user tasks."
    create_single_plot "CPU" "ntime" "$cpu_ntime_title" "$cpu_ntime_desc"
    create_multi_plot "cpu" "cpuid" "ntime" "$cpu_ntime_title" "$cpu_ntime_desc"
    
    cpu_itime_title="Idle Time"
    cpu_itime_desc="Time the CPU was idle and not executing any tasks."
    create_single_plot "CPU" "itime" "$cpu_itime_title" "$cpu_itime_desc"
    create_multi_plot "cpu" "cpuid" "itime" "$cpu_itime_title" "$cpu_itime_desc"
    
    cpu_wtime_title="I/O Wait Time"
    cpu_wtime_desc="Time the CPU was waiting for I/O operations to complete."
    create_single_plot "CPU" "wtime" "$cpu_wtime_title" "$cpu_wtime_desc"
    create_multi_plot "cpu" "cpuid" "wtime" "$cpu_wtime_title" "$cpu_wtime_desc"
    
    cpu_Itime_title="Hardware Interrupts Time"
    cpu_Itime_desc="Time the CPU spent handling hardware interrupts."
    create_single_plot "CPU" "Itime" "$cpu_Itime_title" "$cpu_Itime_desc"
    create_multi_plot "cpu" "cpuid" "Itime" "$cpu_Itime_title" "$cpu_Itime_desc"
    
    cpu_Stime_title="Software Interrupts Time"
    cpu_Stime_desc="Time the CPU spent handling software interrupts."
    create_single_plot "CPU" "Stime" "$cpu_Stime_title" "$cpu_Stime_desc"
    create_multi_plot "cpu" "cpuid" "Stime" "$cpu_Stime_title" "$cpu_Stime_desc"
    
    cpu_steal_title="Steal Time"
    cpu_steal_desc="Time 'stolen' from this VM by the hypervisor for other tasks (relevant in virtualized environments)."
    create_single_plot "CPU" "steal" "$cpu_steal_title" "$cpu_steal_desc"
    create_multi_plot "cpu" "cpuid" "steal" "$cpu_steal_title" "$cpu_steal_desc"
    
    cpu_guest_title="Guest Time"
    cpu_guest_desc="Time the CPU spent running a virtual CPU for guest OSes (under hypervisors)."
    create_single_plot "CPU" "guest" "$cpu_guest_title" "$cpu_guest_desc"
    create_multi_plot "cpu" "cpuid" "guest" "$cpu_guest_title" "$cpu_guest_desc"
    
    cpu_freq_title="CPU Frequency"
    cpu_freq_desc="The operating frequency over the CPU overall"
    create_single_plot "CPU" "freq" "$cpu_freq_title" "$cpu_freq_desc"
    create_multi_plot "cpu" "cpuid" "freq" "$cpu_freq_title" "$cpu_freq_desc"
    
    cpu_freqperc_title="CPU Percent Frequency"
    cpu_freqperc_desc="The frequency of the CPU relative to the max frequency"
    create_single_plot "CPU" "freqperc" "$cpu_freqperc_title" "$cpu_freqperc_desc"
    create_multi_plot "cpu" "cpuid" "freqperc" "$cpu_freqperc_title" "$cpu_freqperc_desc"
    
    cpu_instr_title="CPU Instructions"
    cpu_instr_desc="Total number of CPU instructions executed."
    create_single_plot "CPU" "instr" "$cpu_instr_title" "$cpu_instr_desc"
    create_multi_plot "cpu" "cpuid" "stime" "instr" "$cpu_instr_title" "$cpu_instr_desc"
    
    cpu_cycle_title="CPU Cycles"
    cpu_cycle_desc="Total number of CPU cycles used."
    create_single_plot "CPU" "cycle" "$cpu_cycle_title" "$cpu_cycle_desc"
    create_multi_plot "cpu" "cpuid" "cycle" "$cpu_cycle_title" "$cpu_cycle_desc"


    create_single_plot "CPL" "lavg1" "1-Minute Load Average" "Average system load over the past 1 minute."
    create_single_plot "CPL" "lavg5" "5-Minute Load Average" "Average system load over the past 5 minutes."
    create_single_plot "CPL" "lavg15" "15-Minute Load Average" "Average system load over the past 15 minutes."
    create_single_plot "CPL" "csw" "Context Switches" "Number of times the OS switched between different tasks/processes."
    create_single_plot "CPL" "devint" "Device Interrupts" "Number of hardware interrupts received by the CPU from devices."

    create_single_plot "MEM" "physmem" "Physical Memory" "The amount of physical memory in the system"
    create_single_plot "MEM" "freemem" "Free Memory" "Amount of free memory in the system."
    create_single_plot "MEM" "cachemem" "Cache Memory" "Amount of memory used as cache."
    create_single_plot "MEM" "buffermem" "Buffer Memory" "Amount of memory used for buffers."
    create_single_plot "MEM" "slabmem" "Slab Memory" "Memory used by kernel data structures."
    create_single_plot "MEM" "cachedrt" "Dirty Cache Memory" "Amount of cache memory that is dirty."
    create_single_plot "MEM" "slabreclaim" "Reclaimable Slab Memory" "Amount of slab memory that can be reclaimed."
    create_single_plot "MEM" "vmwballoon" "VMware Balloon Memory" "Memory claimed by VMware balloon."
    create_single_plot "MEM" "shmem" "Shared Memory (Total)" "Total amount of shared memory, including tmpfs."
    create_single_plot "MEM" "shmrss" "Resident Shared Memory" "Amount of shared memory that is resident."
    create_single_plot "MEM" "shmswp" "Swapped Shared Memory" "Amount of shared memory that is swapped out."
    create_single_plot "MEM" "hugepagesz" "Huge Page Size (Small)" "Size of small huge pages in bytes."
    create_single_plot "MEM" "tothugepage" "Total Small Huge Pages" "Total number of small huge pages."
    create_single_plot "MEM" "freehugepage" "Free Small Huge Pages" "Number of free small huge pages."
    # future versions have lhugepagesz, ltothugepage, and lfreehugepage

    create_single_plot "SWP" "totswap" "Total Swap Space" "Total amount of swap space available in the system."
    create_single_plot "SWP" "freeswap" "Free Swap Space" "Amount of unused swap space in the system."
    create_single_plot "SWP" "swcac" "Swap Cache" "Amount of memory that is in the swap cache."
    create_single_plot "SWP" "committed" "Committed Memory" "Amount of memory that has been reserved or committed."
    create_single_plot "SWP" "commitlim" "Commit Limit" "Maximum amount of memory that can be reserved or committed."

    create_single_plot "PAG" "compacts" "Memory Compactions" "Number of times memory was compacted for allocation."
    create_single_plot "PAG" "numamigs" "NUMA Migrations" "Counter for the number of pages migrated across NUMA nodes."
    create_single_plot "PAG" "migrates" "Page Migrations" "Counter for pages that were migrated successfully."
    create_single_plot "PAG" "pgscans" "Page Scans" "Number of times the system scanned for pages."
    create_single_plot "PAG" "allocstall" "Allocation Stalls" "Number of times the system tried to free up pages due to allocation stalls."
    create_single_plot "PAG" "pgins" "Pages Read From Disk" "Total number of pages read from a block device."
    create_single_plot "PAG" "pgouts" "Pages Written To Disk" "Total number of pages written to a block device."
    create_single_plot "PAG" "swins" "Swap-Ins" "Number of pages swapped into memory from swap space."
    create_single_plot "PAG" "swouts" "Swap-Outs" "Number of pages swapped out from memory to swap space."
    create_single_plot "PAG" "oomkills" "Out-of-Memory Kills" "Number of processes killed due to out-of-memory conditions."

    create_single_plot "PSI" "cs10" "CPU 'Some' Pressure (10s Avg)" "Average CPU pressure due to 'some' tasks waiting for resources in the last 10 seconds."
    create_single_plot "PSI" "cs60" "CPU 'Some' Pressure (60s Avg)" "Average CPU pressure due to 'some' tasks waiting for resources in the last 60 seconds."
    create_single_plot "PSI" "cs300" "CPU 'Some' Pressure (5m Avg)" "Average CPU pressure due to 'some' tasks waiting for resources in the last 5 minutes."
    create_single_plot "PSI" "cstot" "Total CPU 'Some' Pressure Duration" "Total milliseconds of CPU pressure due to 'some' tasks waiting for resources."

    create_single_plot "PSI" "ms10" "Memory 'Some' Pressure (10s Avg)" "Average memory pressure when 'some' tasks are waiting for resources in the last 10 seconds."
    create_single_plot "PSI" "ms60" "Memory 'Some' Pressure (60s Avg)" "Average memory pressure when 'some' tasks are waiting for resources in the last 60 seconds."
    create_single_plot "PSI" "ms300" "Memory 'Some' Pressure (5m Avg)" "Average memory pressure when 'some' tasks are waiting for resources in the last 5 minutes."
    create_single_plot "PSI" "mstot" "Total Memory 'Some' Pressure Duration" "Total milliseconds of memory pressure when 'some' tasks are waiting for resources."

    create_single_plot "PSI" "mf10" "Memory 'Full' Pressure (10s Avg)" "Average memory pressure when all tasks are stalled in the last 10 seconds."
    create_single_plot "PSI" "mf60" "Memory 'Full' Pressure (60s Avg)" "Average memory pressure when all tasks are stalled in the last 60 seconds."
    create_single_plot "PSI" "mf300" "Memory 'Full' Pressure (5m Avg)" "Average memory pressure when all tasks are stalled in the last 5 minutes."
    create_single_plot "PSI" "mftot" "Total Memory 'Full' Pressure Duration" "Total milliseconds of memory pressure when all tasks are stalled."

    create_single_plot "PSI" "ios10" "IO 'Some' Pressure (10s Avg)" "Average IO pressure due to 'some' tasks waiting for resources in the last 10 seconds."
    create_single_plot "PSI" "ios60" "IO 'Some' Pressure (60s Avg)" "Average IO pressure due to 'some' tasks waiting for resources in the last 60 seconds."
    create_single_plot "PSI" "ios300" "IO 'Some' Pressure (5m Avg)" "Average IO pressure due to 'some' tasks waiting for resources in the last 5 minutes."
    create_single_plot "PSI" "iostot" "Total IO 'Some' Pressure Duration" "Total milliseconds of IO pressure due to 'some' tasks waiting for resources."

    create_single_plot "PSI" "iof10" "IO 'Full' Pressure (10s Avg)" "Average IO pressure when all tasks are stalled in the last 10 seconds."
    create_single_plot "PSI" "iof60" "IO 'Full' Pressure (60s Avg)" "Average IO pressure when all tasks are stalled in the last 60 seconds."
    create_single_plot "PSI" "iof300" "IO 'Full' Pressure (5m Avg)" "Average IO pressure when all tasks are stalled in the last 5 minutes."
    create_single_plot "PSI" "ioftot" "Total IO 'Full' Pressure Duration" "Total milliseconds of IO pressure when all tasks are stalled."


    create_multi_plot "LVM" "lvmname" "io_ms" "I/O Time" "Milliseconds spent for I/O operations across LVMs."
    create_multi_plot "LVM" "lvmname" "nread" "Read Transfers" "Total number of read transfers across LVMs."
    create_multi_plot "LVM" "lvmname" "nrsect" "Sectors Read" "Total number of sectors read across LVMs."
    create_multi_plot "LVM" "lvmname" "nwrite" "Write Transfers" "Total number of write transfers across LVMs."
    create_multi_plot "LVM" "lvmname" "nwsect" "Sectors Written" "Total number of sectors written across LVMs."
    create_multi_plot "LVM" "lvmname" "avque" "Average Queue Length" "Average I/O queue length across LVMs."
    create_multi_plot "LVM" "lvmname" "inflight" "Inflight I/O" "Number of inflight I/O operations across LVMs."

    # We should add MDD eventually

    create_multi_plot "DSK" "dskname" "io_ms" "I/O Time" "Milliseconds spent for I/O operations across disks."
    create_multi_plot "DSK" "dskname" "nread" "Read Transfers" "Total number of read transfers across disks."
    create_multi_plot "DSK" "dskname" "nrsect" "Sectors Read" "Total number of sectors read across disks."
    create_multi_plot "DSK" "dskname" "ndiscrd" "Discards" "Total number of discards across disks."
    create_multi_plot "DSK" "dskname" "nwrite" "Write Transfers" "Total number of write transfers across disks."
    create_multi_plot "DSK" "dskname" "nwsect" "Sectors Written" "Total number of sectors written across disks."
    create_multi_plot "DSK" "dskname" "avque" "Average Queue Length" "Average I/O queue length across disks."
    create_multi_plot "DSK" "dskname" "inflight" "Inflight I/O" "Number of inflight I/O operations across disks."

    # Skipping NFC/NFS

    create_single_plot "NET_GENERAL" "rpacketsTCP" "Received TCP Packets" "Total number of TCP packets received by the host."
    create_single_plot "NET_GENERAL" "spacketsTCP" "Sent TCP Packets" "Total number of TCP packets sent by the host."
    create_single_plot "NET_GENERAL" "activeOpensTCP" "Active TCP Opens" "Number of TCP connections actively initiated by the host."
    create_single_plot "NET_GENERAL" "passiveOpensTCP" "Passive TCP Opens" "Number of TCP connections that the host waited for a peer to initiate."
    create_single_plot "NET_GENERAL" "retransSegsTCP" "Retransmitted TCP Segments" "Total number of TCP segments that were retransmitted."
    create_single_plot "NET_GENERAL" "rpacketsUDP" "Received UDP Packets" "Total number of UDP packets received by the host."
    create_single_plot "NET_GENERAL" "spacketsUDP" "Sent UDP Packets" "Total number of UDP packets sent by the host."
    create_single_plot "NET_GENERAL" "rpacketsIP" "Received IP Packets" "Total number of IP packets received by the host."
    create_single_plot "NET_GENERAL" "spacketsIP" "Sent IP Packets" "Total number of IP packets sent by the host."
    create_single_plot "NET_GENERAL" "dpacketsIP" "Delivered IP Packets" "Total number of IP packets delivered to the host's IP layer."
    create_single_plot "NET_GENERAL" "fpacketsIP" "Forwarded IP Packets" "Total number of IP packets forwarded by the host."
    create_single_plot "NET_GENERAL" "icmpi" "Received ICMP Messages" "Total number of ICMP messages received by the host."
    create_single_plot "NET_GENERAL" "icmpo" "Sent ICMP Messages" "Total number of ICMP messages sent by the host."


    create_multi_plot "NET" "name" "rpack" "Received Packets" "Total number of packets received on the interface."
    create_multi_plot "NET" "name" "rbyte" "Received Bytes" "Total number of bytes received on the interface."
    create_multi_plot "NET" "name" "rerrs" "Receive Errors" "Total number of receive errors on the interface."
    create_multi_plot "NET" "name" "spack" "Sent Packets" "Total number of packets sent from the interface."
    create_multi_plot "NET" "name" "sbyte" "Sent Bytes" "Total number of bytes sent from the interface."
    create_multi_plot "NET" "name" "serrs" "Transmit Errors" "Total number of transmission errors on the interface."
    create_multi_plot "NET" "name" "speed" "Interface Speed" "Speed of the network interface in megabits per second."
    create_multi_plot "NET" "name" "duplex" "Duplex Mode" "Duplex mode of the interface (Full Duplex: 1, Half Duplex: 0)."

    create_multi_plot "NUM" "numanr" "frag" "NUMA Fragmentation Level" "Percentage of memory fragmentation for a specific NUMA node."
    create_multi_plot "NUM" "numanr" "totmem" "Total Memory" "Total physical memory allocated for a specific NUMA node."
    create_multi_plot "NUM" "numanr" "freemem" "Free Memory" "Amount of unused memory in a specific NUMA node."
    create_multi_plot "NUM" "numanr" "active" "Active Memory" "Memory pages used more recently in a specific NUMA node."
    create_multi_plot "NUM" "numanr" "inactive" "Inactive Memory" "Memory pages used less recently in a specific NUMA node."
    create_multi_plot "NUM" "numanr" "filepage" "File Pages Memory" "Memory used by file pages in a specific NUMA node."
    create_multi_plot "NUM" "numanr" "dirtymem" "Dirty Memory Pages" "Dirty (modified but not yet written to disk) cache pages in a specific NUMA node."
    create_multi_plot "NUM" "numanr" "slabmem" "Slab Memory" "Memory used by slab pages in a specific NUMA node."
    create_multi_plot "NUM" "numanr" "slabreclaim" "Reclaimable Slab Memory" "Amount of slab memory that can be reclaimed in a specific NUMA node."
    create_multi_plot "NUM" "numanr" "shmem" "Shared Memory" "Total shared memory, including tmpfs, in a specific NUMA node."
    create_multi_plot "NUM" "numanr" "tothp" "Total Huge Pages" "Total number of huge pages allocated in a specific NUMA node."

    find . -type f -name '*.png' | sort | awk 'BEGIN {print "<ul>"} {print "<li><a href=\"" $0 "\">" $0 "</a></li>"} END {print "</ul>"}' > index.html

    popd || exit 1
}

main
