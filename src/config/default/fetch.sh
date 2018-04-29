#!/bin/bash -x

rm -f /opt/spinnaker/config/*.yml

mkdir -p ${HOME}/.spinnaker

# Setup the default configuration that comes with a distribution
for filename in /opt/spinnaker/config/default/*.yml; do
    cp $filename ${HOME}/.spinnaker/
done

# User specific config
for filename in /opt/spinnaker/config/custom/*.yml; do
    cp $filename ${HOME}/.spinnaker/
done

# if CA exists, mount it into the default JKS store
config_location=${SPINNAKER_CONFIG_DIR:-"/opt/spinnaker/"}
ca_cert_path="${config_location}/certs/ca.crt"
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
