#!/bin/bash -e
cd "$(dirname "$0")"

## This is the public installer script that will fetch the kubernetes installer run it
## The intention is that the AWS install script pieces will one day be cherry-picked into here.


ARMORY_INSTALLER_ARTIFACT_URL="${KUBERNETES_INSTALLER_LATEST_ARTIFACT_URL}"
TMP_PATH="${HOME}/tmp/armory/kubernetes-installer"
mkdir -p ${TMP_PATH}
cd ${TMP_PATH}


cat <<EOF

    :::     :::::::::  ::::    ::::   ::::::::  :::::::::  :::   :::
  :+: :+:   :+:    :+: +:+:+: :+:+:+ :+:    :+: :+:    :+: :+:   :+:
 +:+   +:+  +:+    +:+ +:+ +:+:+ +:+ +:+    +:+ +:+    +:+  +:+ +:+
+#++:++#++: +#++:++#:  +#+  +:+  +#+ +#+    +:+ +#++:++#:    +#++:
+#+     +#+ +#+    +#+ +#+       +#+ +#+    +#+ +#+    +#+    +#+
#+#     #+# #+#    #+# #+#       #+# #+#    #+# #+#    #+#    #+#
###     ### ###    ### ###       ###  ########  ###    ###    ###

......................................................................

EOF


INSTALLER_LOCAL_PATH="${TMP_PATH}/kubernetes-installer.tar.gz"
curl -o ${INSTALLER_LOCAL_PATH} -sS "${ARMORY_INSTALLER_ARTIFACT_URL}"

tar -xf ${INSTALLER_LOCAL_PATH}

# run the script
./src/install.sh
