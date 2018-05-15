#!/bin/bash -xe

CONFIG_LOCATION=${SPINNAKER_HOME:-"/opt/spinnaker"}/config/
CONTAINER=$1

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

  if [[ "$(whoami)" != "root" ]]; then
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

if [ `which keytool` ]; then
  echo "INFO: Keytool found adding certs where appropriate"
  add_ca_certs
  #we'll want to add saml, oauth, authn/authz stuff here too
else
  echo "INFO: Keytool not found, not adding any certs/private keys"
fi

saml_pem_path="/opt/spinnaker/config/custom/saml.pem"
saml_pkcs12_path="/tmp/saml.pkcs12"
saml_jks_path="${CONFIG_LOCATION}/saml.jks"
if [ "${CONTAINER}" == "gate" ]; then
    if [ -f ${saml_pem_path} ]; then
        echo "Loading ${saml_pem_path} into ${saml_jks_path}"
        # Convert PEM to PKCS12 with a password.
        openssl pkcs12 -export -out ${saml_pkcs12_path} -in ${saml_pem_path} -password pass:changeit -name saml
        keytool -genkey -v -keystore ${saml_jks_path} -alias saml \
                -keyalg RSA -keysize 2048 -validity 10000 \
                -storepass changeit -keypass changeit -dname "CN=armory"
        keytool -importkeystore \
                -srckeystore ${saml_pkcs12_path} \
                -srcstoretype PKCS12 \
                -srcstorepass changeit \
                -destkeystore ${saml_jks_path} \
                -deststoretype JKS \
                -storepass changeit \
                -alias saml \
                -destalias saml \
                -noprompt
    else
        echo "No SAML IDP pemfile found at ${saml_pem_path}"
    fi
fi



