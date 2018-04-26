#!/bin/bash -x

rm -f /opt/spinnaker/config/*.yml

# Setup the default configuration that comes with a distribution
for filename in /opt/spinnaker/config/default/*.yml; do
    cp $filename /opt/spinnaker/config/
done

# User specific config
for filename in /opt/spinnaker/config/custom/*.yml; do
    cp $filename /opt/spinnaker/config/
done

# if CA exists, mount it into the default JKS store
ca_cert_path="/opt/spinnaker/certs/ca.crt"
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
