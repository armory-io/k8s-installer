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

add_ca_certs() {
  # if CA exists, mount it into the default JKS store
  ca_cert_path="${CONFIG_LOCATION}/ca.crt"
  jks_path="/etc/ssl/certs/java/cacerts"

  if [[ "$(whoami)" -ne "root" ]]; then
    echo "INFO: I do not have proper permisions to add CA roots"
    return
  fi

  if [[ ! -f ${ca_cert_path} ]]; then
    echo "INFO: No CA cert found at ${ca_cert_path}"
    return
  fi
  keytool -importcert \
      -file ${ca_cert_path} \
      -keystore ${jks_path} \
      -alias custom-ca \
      -storepass changeit \
      -noprompt
}

if type keytool > /dev/null; then
  echo "INFO: Keytool found adding certs where appropriate"
  add_ca_certs
  #we'll want to add saml, oauth, authn/authz stuff here too
else
  echo "INFO: Keytool not found"
fi
