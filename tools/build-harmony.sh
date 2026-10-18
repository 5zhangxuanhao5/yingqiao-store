#!/bin/bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
deveco=${DEVECO_STUDIO_HOME:-/Applications/DevEco-Studio.app/Contents}
cd "$root/harmony"
export DEVECO_SDK_HOME="$deveco/sdk"
export JAVA_HOME="$deveco/jbr/Contents/Home"
export PATH="$deveco/tools/node/bin:$PATH"
"$deveco/tools/node/bin/node" "$deveco/tools/hvigor/bin/hvigorw.js" assembleHap --mode module -p product=default -p module=entry@default -p buildMode=release --no-daemon
# No signing, installation, HDC, emulator launch, or SDK-schema modification.
