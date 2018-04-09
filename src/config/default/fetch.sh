#!/bin/bash -x

rm -f /opt/spinnaker/config/*.yml

# Setup the default configuration that comes with a distribution
for filename in /opt/spinnaker/config/default/*.yml; do
    ln -s $filename /opt/spinnaker/config/
done

# User specific config
for filename in /opt/spinnaker/config/custom/*.yml; do
    ln -s $filename /opt/spinnaker/config/
done