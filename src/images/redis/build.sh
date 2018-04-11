#!/bin/bash

docker build -t armory/k8s-redis .
docker push armory/k8s-redis