for i in $(seq 1 254); do
    ping -c1 -W1 172.16.8.$i &>/dev/null && echo "172.16.8.$i is up" &
done
wait

#Bash ping sweep script to discover live hosts in a /24 subnet.
#Sends 1 ICMP packet with 1 second timeout to each host (1-254) in parallel using background processes.
#Prints live hosts to stdout. Usage: replace 172.16.8 with your target subnet.
