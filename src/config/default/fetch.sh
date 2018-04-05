#!/bin/bash -x

# Setup the default configuration that comes with a distribution
for filename in /opt/spinnaker/config/default/*.yml; do
    ln -s $filename /opt/spinnaker/config/
done
