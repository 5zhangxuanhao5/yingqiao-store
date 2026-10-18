from pathlib import Path
import hashlib,json,re
r=Path(__file__).resolve().parents[1]
for x in json.loads((r/'SOURCE_MANIFEST.json').read_text()):
 p=r/x['path'];assert p.is_file() and hashlib.sha256(p.read_bytes()).hexdigest()==x['sha256'],x['path']
 assert p.suffix.lower() not in {'.p12','.p7b','.cer','.pem','.key','.hap','.dmg','.pkg'},x['path']
 raw=p.read_bytes();assert not re.search(rb'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----|(?:gh[pousr]_|github_pat_)[A-Za-z0-9_]{25,}|tskey-[A-Za-z0-9-]{20,}',raw),x['path']
profile=json.loads((r/'harmony/build-profile.json5').read_text());assert not profile['app'].get('signingConfigs');assert all('signingConfig' not in x for x in profile['app']['products'])
manifest=json.loads((r/'harmony/entry/src/main/module.json5').read_text());assert manifest['module']['deviceTypes']==['tablet'];names={x['name'] for x in manifest['module']['requestPermissions']};assert names=={'ohos.permission.INTERNET','ohos.permission.GET_NETWORK_INFO','ohos.permission.LOCK_WINDOW_CURSOR'}
pair=json.loads((r/'harmony/entry/src/main/resources/rawfile/pairing.json').read_text());assert not pair['token'] and not pair['cert'];assert pair['port']==49563
cm=(r/'harmony/entry/src/main/cpp/CMakeLists.txt').read_text();assert 'remote_audio_stub.cpp' in cm and 'libohaudio.so' not in cm
assert 'disabled_store_edition' in (r/'harmony/entry/src/main/cpp/network.cpp').read_text()
assert 'only' in (r/'harmony/entry/src/main/cpp/store_policy.h').read_text() or 'PrivateAddress' in (r/'harmony/entry/src/main/cpp/store_policy.h').read_text()
print('PASS public source SHA-256, unpaired templates, no signing identities, tablet classification, no microphone/global monitor permission, disabled WAN/audio providers')
