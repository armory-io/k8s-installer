#!/bin/bash

redis_port=6379
sentinel_port=26379
master_group=mymaster

sentinel-monitor() {
  redis-cli -p $sentinel_port sentinel monitor mymaster $1 $redis_port 2
  redis-cli -p $sentinel_port sentinel set mymaster down-after-milliseconds 1000
  redis-cli -p $sentinel_port sentinel set mymaster failover-timeout 10000
  redis-cli -p $sentinel_port sentinel set mymaster parallel-syncs 1
}

become-slave-of() {
  redis-cli -p $redis_port slaveof $1 $redis_port
}

hosts() {
  kubectl get pods -l=app=redis --template="{{range \$i, \$e :=.items}}{{\$e.status.podIP}} {{end}}"
}

get-role() {
  grep "role:" | sed "s/role://" | tr -d '\n' | tr -d '\r'
}

role() {
  redis-cli -h $1 -p $redis_port info | get-role
}

other-active-master() {
  master=""
  for host in `hosts`; do
    host=$(echo $host | tr -d '\n' | tr -d '\r')
    if [[ `role $host` = "master" ]]; then
      if [[ $host != `hostname -i` ]]; then
        master=$host
      fi
      break
    fi
  done
  echo -n $master
}

until redis-cli -p $redis_port ping > /dev/null && redis-cli -p $sentinel_port ping > /dev/null; do
  sleep 1
done

master=`other-active-master`
if [[ -n $master ]]; then
  echo "becoming slave of $master"
  become-slave-of $master
  sentinel-monitor $master
else
  host=`hostname -i`
  echo "starting master @ $host"
  sentinel-monitor `hostname -i`
fi

last_role="none"
while true; do
  # when role changed, update pod label
  current_role=`redis-cli -p $redis_port info | get-role`
  if [[ "$last_role" != "$current_role" ]]; then
    echo "last_role is $last_role, current_role is $current_role"
    kubectl label --overwrite pods `hostname` role=$current_role
    last_role=$current_role
  fi

  # don't allow multiple masters
  if [ "$current_role" = "master" ]; then
    master=`other-active-master`
    if [[ -n $master ]]; then
      echo "active master is $master, we are `hostname -i`, demoting ourselves"
      become-slave-of $master
    fi
  fi

  sleep 1
done
