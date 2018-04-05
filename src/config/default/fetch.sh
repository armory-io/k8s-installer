#!/bin/bash -x

for filename in /opt/spinnaker/config/default/*.yml; do
    ln -s $filename /opt/spinnaker/config/
done