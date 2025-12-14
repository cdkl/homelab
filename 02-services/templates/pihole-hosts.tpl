%{ for h, ip in hosts ~}
host-record=${h},${ip}
%{ endfor ~}
