#!/bin/bash

redis_port=6379
sentinel_port=26379
master_group=mymaster

panic () {
  >&2 echo $1
  exit 1
}

### boot

sleep 10
redis-cli -p $redis_port ping > /dev/null \
  && redis-cli -p $sentinel_port ping > /dev/null \
  || panic "redis and/or sentinel not up"; 

master=`redis-cli -p $sentinel_port sentinel get-master-addr-by-name mymaster`
if [[ -n $master ]]; then
  # there's a master, have this instance connect to it
  redis-cli -p $redis_port slaveof $master $redis_port
else
  # there's no master, promote this instance
  redis-cli -p $sentinel_port sentinel monitor mymaster `hostname -i` $redis_port 2
  redis-cli -p $sentinel_port sentinel set mymaster down-after-milliseconds 1000
  redis-cli -p $sentinel_port sentinel set mymaster failover-timeout 10000
  redis-cli -p $sentinel_port sentinel set mymaster parallel-syncs 1
fi

### monitor

last_role="none"
while true; do
  current_role=`redis-cli -p $redis_port info | grep "role:" | sed "s/role://" | tr -d '\n' | tr -d '\r'`
  if [[ "$last_role" != "$current_role" ]]; then
    # role changed, update pod label
    kubectl label --overwrite pods `hostname` role=$current_role
    last_role=$current_role
  fi
  sleep 1
done
