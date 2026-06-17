
# LINUX
for i in $(seq 254); do ping 172.16.8.$i -c1 -W1 & done | grep from

# PS 
1..254 | ForEach-Object { $ip = "172.16.8.$_"; if (Test-Connection -ComputerName $ip -Count 1 -TimeToLive 1 -Quiet) { Write-Output "$ip está VIVO" } }
#Bash ping sweep script to discover live hosts in a /24 subnet.
#Sends 1 ICMP packet with 1 second timeout to each host (1-254) in parallel using background processes.
#Prints live hosts to stdout. Usage: replace 172.16.8 with your target subnet.
