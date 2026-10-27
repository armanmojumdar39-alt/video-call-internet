#!/usr/bin/env bash
# Run once inside connecto/app to generate android/ios folders and add permissions.
# Requires Flutter SDK (3.19+). Usage: bash setup.sh
set -e

flutter create --project-name connecto --org com.connecto --platforms android,ios .
rm -rf test   # default generated test references a counter app that no longer exists

MANIFEST=android/app/src/main/AndroidManifest.xml
python3 - "$MANIFEST" <<'PY'
import sys, re
p = sys.argv[1]
s = open(p, encoding='utf-8').read()
perms = [
 'android.permission.INTERNET','android.permission.ACCESS_NETWORK_STATE',
 'android.permission.CAMERA','android.permission.RECORD_AUDIO',
 'android.permission.MODIFY_AUDIO_SETTINGS','android.permission.READ_CONTACTS',
 'android.permission.BLUETOOTH','android.permission.BLUETOOTH_CONNECT',
 'android.permission.CHANGE_NETWORK_STATE',
]
add = ''.join(f'    <uses-permission android:name="{x}"/>\n' for x in perms if x not in s)
s = s.replace('<application', add + '    <application', 1)
if 'usesCleartextTraffic' not in s:
    s = s.replace('<application', '<application android:usesCleartextTraffic="true"', 1)  # dev only: http server
open(p, 'w', encoding='utf-8').write(s)
print('AndroidManifest patched')
PY

PLIST=ios/Runner/Info.plist
if command -v /usr/libexec/PlistBuddy >/dev/null 2>&1; then
  add() { /usr/libexec/PlistBuddy -c "Add :$1 string $2" "$PLIST" 2>/dev/null || true; }
  add NSCameraUsageDescription "ভিডিও কলের জন্য ক্যামেরা দরকার"
  add NSMicrophoneUsageDescription "কলের জন্য মাইক্রোফোন দরকার"
  add NSContactsUsageDescription "কোন কন্টাক্টে Connecto আছে তা দেখাতে কন্টাক্ট দরকার"
  echo "Info.plist patched"
else
  echo "NOTE: not on macOS - add NSCameraUsageDescription, NSMicrophoneUsageDescription,"
  echo "      NSContactsUsageDescription to ios/Runner/Info.plist manually."
fi

# flutter_webrtc needs minSdk >= 21; set 23 in whichever gradle file exists.
python3 - <<'PY'
import re, os
for f in ('android/app/build.gradle.kts', 'android/app/build.gradle'):
    if not os.path.exists(f):
        continue
    s = open(f, encoding='utf-8').read()
    n = re.sub(r'minSdk(Version)?(\s*=\s*|\s+)flutter\.minSdkVersion',
               lambda m: 'minSdk' + ('Version' if m.group(1) else '') + m.group(2) + '23', s)
    if n == s:
        print('WARNING: minSdk line not found in', f, '- set it to 23 manually')
    else:
        open(f, 'w', encoding='utf-8').write(n)
        print('minSdk set to 23 in', f)
PY
flutter pub get
echo "Done. Run: flutter run"
