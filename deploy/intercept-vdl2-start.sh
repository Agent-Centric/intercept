#!/bin/bash
for i in $(seq 1 40); do
    STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:5050/vdl2/status 2>/dev/null)
    if [ "$STATUS" = "200" ]; then
        sleep 10
        break
    fi
    sleep 2
done
curl -s -X POST http://localhost:5050/vdl2/start \
  -H "Content-Type: application/json" \
  -d '{"device":"0","gain":"40","sdr_type":"rtlsdr","frequencies":["136975000","136100000","136650000","136700000","136800000"]}'
