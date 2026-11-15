"""Convert the user's Android Firebase config into explicit Flutter options."""
import json
import pathlib
import sys

source = json.loads(pathlib.Path(sys.argv[1]).read_text())
client = next((c for c in source['client'] if c['client_info']['android_client_info']['package_name'] == 'com.classtrack.classtrack'), None)
if not client:
    raise SystemExit('Expected Android package com.classtrack.classtrack')
if source['project_info']['project_id'] != 'classtrack-b9bb8':
    raise SystemExit('Unexpected Firebase project: review before importing')
out = pathlib.Path(__file__).resolve().parents[1] / 'config/firebase.android.json'
out.write_text(json.dumps({
    'FIREBASE_PROJECT_ID': source['project_info']['project_id'],
    'FIREBASE_API_KEY': client['api_key'][0]['current_key'],
    'FIREBASE_APP_ID': client['client_info']['mobilesdk_app_id'],
    'FIREBASE_MESSAGING_SENDER_ID': source['project_info']['project_number'],
}, indent=2) + '\n')
print('Saved config/firebase.android.json; no credentials printed.')
