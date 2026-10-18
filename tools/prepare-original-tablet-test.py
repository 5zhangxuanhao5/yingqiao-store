#!/usr/bin/env python3
"""Opt-in device-test-only input profile. Not an AppGallery release build.
Uses a separate SDK facade; never writes through links into the installed SDK.
"""
from pathlib import Path
import argparse,json,shutil,hashlib
p=argparse.ArgumentParser();p.add_argument('--sdk',type=Path,required=True);p.add_argument('--output',type=Path,required=True);p.add_argument('--project',type=Path,required=True);p.add_argument('--device-test-only',action='store_true');a=p.parse_args()
assert a.device_test_only, 'Explicit device-test opt-in required'
sdk=a.sdk.resolve();out=a.output.absolute();project=a.project.resolve()
assert not out.exists(), 'Use a new SDK facade directory'
assert json.loads((project/'AppScope/app.json5').read_text())['app']['bundleName']=='cn.edgelink.store'
schema_rel=Path('default/hms/toolchains/modulecheck/easy_go.json')
original=(sdk/schema_rel).read_bytes();d=json.loads(original)
# Only ancestors of the copied modulecheck directory are real directories.
def facade(src,dst,parts):
 dst.mkdir()
 for child in src.iterdir():
  target=dst/child.name
  if child.name==parts[0]:
   if len(parts)==1: shutil.copytree(child,target)
   else: facade(child,target,parts[1:])
  else: target.symlink_to(child,target_is_directory=child.is_dir())
facade(sdk,out,['default','hms','toolchains','modulecheck'])
options={'type':'object','properties':{'mouse2TouchEventMode':{'type':'string','enum':['disabled']}},'additionalProperties':False,'required':['mouse2TouchEventMode']}
d['definitions']['deviceConfig']['properties']['multiModalInputOptions']=options
(out/schema_rel).write_text(json.dumps(d,indent=2)+'\n')
profile={'common':{},'tablet':{'multiModalInputOptions':{'mouse2TouchEventMode':'disabled'}}}
(project/'entry/src/main/resources/base/profile/easy_go.json').write_text(json.dumps(profile,indent=2)+'\n')
assert (sdk/schema_rel).read_bytes()==original
(out/'DEVICE_TEST_ONLY.json').write_text(json.dumps({'officialSDKUnmodified':True,'officialSchemaSHA256':hashlib.sha256(original).hexdigest(),'appGalleryReady':False,'reason':'isolated input-profile schema extension'},indent=2)+'\n')
print('Device-test facade prepared; official SDK unchanged; not a store-ready build')
