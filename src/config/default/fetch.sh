#!/bin/bash -x

CONFIG_LOCATION=${SPINNAKER_HOME:-"/opt/spinnaker"}/config/
CONTAINER=$1

rm -f /opt/spinnaker/config/*.yml

mkdir -p ${CONFIG_LOCATION}

# Setup the default configuration that comes with a distribution
for filename in /opt/spinnaker/config/default/*.yml; do
    cp $filename ${CONFIG_LOCATION}
done

# User specific config
for filename in /opt/spinnaker/config/custom/*.yml; do
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

saml_pem_path="/opt/spinnaker/config/custom/idp.pem"
saml_pkcs12_path="/tmp/saml.pkcs12"
saml_jks_path="${CONFIG_LOCATION}/saml.jks"
if [ "${CONTAINER}" == "gate" ]; then
    if [ -f ${saml_cert_path} ]; then
        echo "Loading ${saml_cert_path} into ${saml_jks_path}"
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
        echo "No SAML IDP pemfile found at ${saml_cert_path}"
    fi
fi



