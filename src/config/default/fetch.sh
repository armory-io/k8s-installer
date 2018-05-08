#!/bin/bash -xe

CONFIG_LOCATION=${SPINNAKER_HOME:-"/opt/spinnaker"}/config/

rm -f /opt/spinnaker/config/*.yml

mkdir -p ${CONFIG_LOCATION}

# Setup the default configuration that comes with a distribution
for filename in /opt/spinnaker/config/default/*.yml; do
    cp $filename ${CONFIG_LOCATION}
done

# User specific config
for filename in /opt/spinnaker/config/custom/*; do
    cp $filename ${CONFIG_LOCATION}
done

# if CA exists, mount it into the default JKS store
ca_cert_path="${CONFIG_LOCATION}/certs/ca.crt"
jks_path="/etc/ssl/certs/java/cacerts"
if [  -f ${ca_cert_path} ]; then
    echo "Loading CA cert into the Java Keystore located at ${jks_path}"
    keytool -importcert \
        -file ${ca_cert_path} \
        -keystore ${jks_path} \
        -alias custom-ca \
        -storepass changeit \
        -noprompt
else
    echo "No CA cert found at ${ca_cert_path}"
fi
