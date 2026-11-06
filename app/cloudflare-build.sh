#!/usr/bin/env bash
# Cloudflare Pages build for the web app (Pages → Settings → Build):
#   Root directory: app      Build command: bash cloudflare-build.sh      Output directory: build/web
# App settings come from the Pages environment variables: API_URL, IDENTITY_POOL_ID,
# GOOGLE_WEB_CLIENT_ID (optional AWS_REGION, SITE_URL, ANDROID_CERT_SHA256).
set -euo pipefail
FLUTTER_VERSION=3.47.9

if [ -z "${API_URL:-}" ] || [ -z "${IDENTITY_POOL_ID:-}" ]; then
  echo "Set API_URL and IDENTITY_POOL_ID in Pages → Settings → Variables (README step 6)." >&2
  exit 1
fi

# The Pages build image has no Flutter, so fetch the pinned version.
if [ ! -x "$HOME/flutter/bin/flutter" ]; then
  git clone --depth 1 --branch "$FLUTTER_VERSION" https://github.com/flutter/flutter.git "$HOME/flutter"
fi
export PATH="$HOME/flutter/bin:$PATH"
flutter config --no-analytics >/dev/null
flutter --version

python3 - <<'PY'
import json, os
keys = ['AWS_REGION', 'IDENTITY_POOL_ID', 'API_URL', 'GOOGLE_WEB_CLIENT_ID', 'SITE_URL']
json.dump({k: os.environ[k] for k in keys if os.environ.get(k)}, open('env.json', 'w'))
PY

flutter pub get
flutter build web --release --no-web-resources-cdn --dart-define-from-file=env.json

# Android app links. Pages serves index.html for app routes like /e/<id> on its own (no 404.html).
mkdir -p build/web/.well-known
python3 - <<'PY'
import json, os
fps = [s.strip() for s in os.environ.get('ANDROID_CERT_SHA256', '').split(',') if s.strip()]
links = [{'relation': ['delegate_permission/common.handle_all_urls'],
          'target': {'namespace': 'android_app', 'package_name': 'com.artifisi.sidekick',
                     'sha256_cert_fingerprints': fps}}] if fps else []
json.dump(links, open('build/web/.well-known/assetlinks.json', 'w'))
PY
# Entry files must always be fresh; hashed assets can be cached.
cat > build/web/_headers <<'H'
/
  Cache-Control: no-cache
/index.html
  Cache-Control: no-cache
/flutter_bootstrap.js
  Cache-Control: no-cache
/flutter_service_worker.js
  Cache-Control: no-cache
/main.dart.js
  Cache-Control: no-cache
/version.json
  Cache-Control: no-cache
H
echo "Built build/web"
