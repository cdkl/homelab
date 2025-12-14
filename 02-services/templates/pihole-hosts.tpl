%{ for h, ip in hosts ~}
host-record=${h},${ip}
%{ endfor ~}
%{ for alias, target in cnames ~}
cname=${alias},${target}
%{ endfor ~}
