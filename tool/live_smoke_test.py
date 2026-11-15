"""Owner-authorized smoke test using ordinary Firebase users, never Admin SDK.

Creates clearly labelled demo data. State/tokens stay outside the source archive.
Uses synthetic 0,0 coordinates; this is not a real-device GPS test.
"""
import datetime as dt
import json
from pathlib import Path
import secrets
import sys
import urllib.request
import urllib.error

ROOT = Path(__file__).resolve().parents[1]
STATE = ROOT.parent / '.classtrack-live-state.json'
CONFIG = json.loads((ROOT / 'config/firebase.android.json').read_text())
PROJECT = CONFIG['FIREBASE_PROJECT_ID']
BASE = f'https://firestore.googleapis.com/v1/projects/{PROJECT}/databases/(default)/documents'
NAME = f'projects/{PROJECT}/databases/(default)/documents/'
SERVER = object()
PASS = []

def encode(v):
    if v is None: return {'nullValue': None}
    if isinstance(v, bool): return {'booleanValue': v}
    if isinstance(v, int): return {'integerValue': str(v)}
    if isinstance(v, float): return {'doubleValue': v}
    if isinstance(v, dt.datetime): return {'timestampValue': v.isoformat().replace('+00:00', 'Z')}
    if isinstance(v, str): return {'stringValue': v}
    if isinstance(v, list): return {'arrayValue': {'values': [encode(x) for x in v]}}
    return {'mapValue': {'fields': {k: encode(x) for k, x in v.items()}}}

def decode(v):
    for k, value in v.items():
        if k == 'nullValue': return None
        if k == 'integerValue': return int(value)
        if k == 'arrayValue': return [decode(x) for x in value.get('values', [])]
        if k == 'mapValue': return {a: decode(b) for a, b in value.get('fields', {}).items()}
        return value

def api(method, url, person=None, body=None, expected=200):
    headers = {'Authorization': 'Bearer ' + person['idToken']} if person else {}
    headers['Content-Type'] = 'application/json'
    req = urllib.request.Request(url, data=json.dumps(body).encode() if body is not None else None, headers=headers, method=method)
    try:
        response = urllib.request.urlopen(req, timeout=35)
    except urllib.error.HTTPError as error:
        response = error
    result = json.loads(response.read() or b'{}')
    if response.code != expected:
        code = result.get('error', {}).get('status', result.get('error', {}).get('message', 'request_failed'))
        raise RuntimeError(f'Expected HTTP {expected}; received {response.code}: {code}')
    return result

def write(path, data, patch=False):
    w = {'update': {'name': NAME + path, 'fields': {k: encode(v) for k, v in data.items() if v is not SERVER}}}
    transforms = [{'fieldPath': k, 'setToServerValue': 'REQUEST_TIME'} for k, v in data.items() if v is SERVER]
    if transforms: w['updateTransforms'] = transforms
    if patch: w['updateMask'] = {'fieldPaths': list(data)}
    return w

def commit(person, writes, expected=200):
    return api('POST', BASE + ':commit', person, {'writes': writes}, expected)

def get(person, path, expected=200):
    result = api('GET', BASE + '/' + path, person, expected=expected)
    return {k: decode(v) for k, v in result.get('fields', {}).items()}

def passed(label):
    PASS.append(label)
    print('PASS:', label, flush=True)

def save(state):
    STATE.write_text(json.dumps(state, indent=2)); STATE.chmod(0o600)

def signup(role, suffix):
    password = secrets.token_urlsafe(18) + '7aA!'
    email = f'ct.{role}.{suffix}@example.test'
    result = api('POST', 'https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=' + CONFIG['FIREBASE_API_KEY'], body={
        'email': email, 'password': password, 'returnSecureToken': True})
    return {'email': email, 'password': password, 'uid': result['localId'], 'idToken': result['idToken']}

def create_session(t, c, mode, suffix):
    sid = 'demo_' + mode + '_' + suffix
    writes = [write('attendance_sessions/' + sid, {'classID': c, 'teacherID': t['uid'], 'mode': mode,
        'latitude': 0.0, 'longitude': 0.0, 'radius': 50.0, 'startTime': None, 'expiryTime': None,
        'status': 'closed', 'initialized': False, 'createdAt': SERVER})]
    if mode == 'quiz':
        writes += [write(f'attendance_sessions/{sid}/quiz/public', {'questions': [
            {'text': f'سؤال تجريبي {i+1}', 'options': ['أ', 'ب', 'ج', 'د']} for i in range(5)]}),
            write(f'attendance_sessions/{sid}/quiz_private/key', {'correctAnswers': [0, 1, 2, 3, 0]})]
    commit(t, writes)
    commit(t, [write('session_clocks/' + sid, {'teacherID': t['uid'], 'classID': c, 'startedAt': SERVER})])
    start = dt.datetime.fromisoformat(get(t, 'session_clocks/' + sid)['startedAt'].replace('Z', '+00:00'))
    commit(t, [write('attendance_sessions/' + sid, {'startTime': start, 'expiryTime': start + dt.timedelta(seconds=120),
        'status': 'active', 'initialized': True}, True)])
    return sid

def event(person, sid, c, quiz=False, outside=False, **changes):
    return {'studentID': person['uid'], 'sessionID': sid, 'classID': c, 'timestamp': SERVER,
        'latitude': 0.001 if outside else 0.0, 'longitude': 0.0, 'distance': 111.19510118 if outside else 0.0,
        'locationVerified': not outside, 'quizOpened': quiz, 'quizSubmitted': quiz,
        'submissionTime': SERVER if quiz else None, 'answers': [0, 1, 2, 3, 0] if quiz else None,
        'quizScore': None, 'gradedAt': None, 'status': 'rejected' if outside else 'present',
        'rejectionReason': 'outside_radius' if outside else None,
        'eventType': 'quiz_submit' if quiz else 'punch_in', 'finalized': True, **changes}

def attend(person, data, attempt_id='first', expected=200):
    root = 'attendance_records/' + data['sessionID'] + '__' + person['uid']
    commit(person, [write(root + '/attempts/' + attempt_id, data), write(root, {**data, 'lastAttemptId': attempt_id})], expected)
    return root

def prepare():
    if STATE.exists(): raise RuntimeError('Existing smoke-test state found; do not recreate accounts blindly.')
    suffix = dt.datetime.now(dt.timezone.utc).strftime('%m%d%H%M%S')
    state = {'project': PROJECT, 'suffix': suffix, 'passes': []}
    state['teacher'] = signup('teacher', suffix); save(state)
    state['student'] = signup('student', suffix); save(state)
    state['outside'] = signup('outside', suffix); save(state)
    t, s, out = state['teacher'], state['student'], state['outside']
    for p, role, name in [(t, 'teacher', 'مدرس تجريبي ClassTrack'), (s, 'student', 'طالب تجريبي داخل النطاق'), (out, 'student', 'طالب تجريبي خارج النطاق')]:
        data = {'name': name, 'email': p['email'], 'role': role, 'createdAt': SERVER}
        if role == 'student': data['studentID'] = 'DEMO-' + p['uid'][:6]
        commit(p, [write('users/' + p['uid'], data)])
    passed('Live Auth and role profiles')
    c = 'demo_class_' + suffix
    code = ''.join(secrets.choice('ABCDEFGHJKLMNPQRSTUVWXYZ23456789') for _ in range(8))
    state.update(classID=c, joinCode=code); save(state)
    commit(t, [write('classes/' + c, {'name': 'تجربة ClassTrack', 'semester': 'Demo', 'teacherID': t['uid'], 'joinCode': code, 'createdAt': SERVER}),
               write('class_join_codes/' + code, {'classID': c, 'teacherID': t['uid'], 'className': 'تجربة ClassTrack'})])
    for p in (s, out):
        profile = get(p, 'users/' + p['uid'])
        commit(p, [write('enrollments/' + c + '__' + p['uid'], {'classID': c, 'studentID': p['uid'],
            'studentName': profile['name'], 'universityStudentID': profile['studentID'], 'className': 'تجربة ClassTrack',
            'joinCodeUsed': code, 'createdAt': SERVER})])
    passed('Live class creation and join-code enrollment')
    punch = create_session(t, c, 'punch_in', suffix)
    state['punch'] = punch; save(state)
    get(out, 'attendance_sessions/' + punch)
    passed('Session visibility for outside student')
    attend(s, event(s, punch, c))
    passed('Backend accepts in-range punch-in')
    attend(s, event(s, punch, c), 'duplicate', 403)
    passed('Backend blocks duplicate success')
    attend(out, event(out, punch, c, outside=True, distance=0.0, locationVerified=True, status='present', rejectionReason=None), 'forged', 403)
    attend(out, event(out, punch, c, outside=True))
    passed('Backend rejects forged distance and records truthful rejection')
    quiz = create_session(t, c, 'quiz', suffix)
    state['quiz'] = quiz; save(state)
    get(s, f'attendance_sessions/{quiz}/quiz_private/key', 403)
    passed('Answer key stays private on live backend')
    record = attend(s, event(s, quiz, c, quiz=True))
    commit(t, [write(record + '/attempts/first', {'quizScore': 5, 'gradedAt': SERVER}, True),
               write(record, {'quizScore': 5, 'gradedAt': SERVER}, True)])
    result = get(s, record)
    if result['status'] != 'present' or result['quizScore'] != 5: raise RuntimeError('Unexpected quiz result')
    passed('Live quiz submission, verified grade and private result')
    result = api('POST', BASE + ':runQuery', t, {'structuredQuery': {'from': [{'collectionId': 'attempts', 'allDescendants': True}],
        'where': {'compositeFilter': {'op': 'AND', 'filters': [
            {'fieldFilter': {'field': {'fieldPath': 'classID'}, 'op': 'EQUAL', 'value': encode(c)}},
            {'fieldFilter': {'field': {'fieldPath': 'sessionID'}, 'op': 'EQUAL', 'value': encode(quiz)}}]}}}})
    if not any('document' in r for r in result): raise RuntimeError('Live results query was empty')
    passed('Live teacher collection-group query and deployed index')
    state['passes'] = PASS.copy(); save(state)
    credentials = ROOT.parent / 'ClassTrack_Demo_Accounts.txt'
    credentials.write_text('حسابات اختبار ClassTrack — بيانات تجريبية وليست حضورًا فعليًا\n\n' +
        '\n\n'.join(f"{label}\nEmail: {p['email']}\nPassword: {p['password']}" for label,p in [('مدرس', t), ('طالب أول', s), ('طالب ثانٍ', out)]) +
        '\n\nClass: تجربة ClassTrack\nJoin code: ' + code + '\nSynthetic test coordinates: 0,0\n')
    credentials.chmod(0o600)
    print('Prepared demo accounts and live scenarios; exact-expiry checks are pending.', flush=True)

def finish():
    state = json.loads(STATE.read_text()); t, s = state['teacher'], state['outside']
    sid = state['quiz']; session = get(t, 'attendance_sessions/' + sid)
    expiry = dt.datetime.fromisoformat(session['expiryTime'].replace('Z', '+00:00'))
    if dt.datetime.now(dt.timezone.utc) < expiry:
        print('Not expired yet; no writes performed.'); return
    attend(s, event(s, sid, state['classID'], quiz=True), 'late-forged', 403)
    passed('Live backend rejects presence after expiry')
    commit(t, [write('attendance_sessions/' + sid, {'status': 'closed'}, True)])
    root = 'attendance_records/' + sid + '__' + s['uid']
    data = {'sessionID': sid, 'studentID': s['uid'], 'classID': state['classID'], 'timestamp': None,
        'latitude': None, 'longitude': None, 'distance': None, 'locationVerified': False,
        'quizOpened': False, 'quizSubmitted': False, 'submissionTime': None, 'answers': None,
        'quizScore': None, 'gradedAt': None, 'status': 'absent', 'rejectionReason': None,
        'finalized': True, 'finalizedAt': SERVER, 'lastAttemptId': None}
    commit(t, [write(root, data)])
    passed('Live teacher finalizes a non-submitting student as absent')
    state['passes'] += PASS; state['finished'] = True; save(state)
    report = ROOT / 'docs/LIVE_BACKEND_TEST.md'
    report.write_text('# اختبار Firebase الحقيقي\n\nProject: classtrack-b9bb8\n\n' +
        '\n'.join('- PASS: ' + label for label in state['passes']) +
        '\n\nالاختبار بحسابات وبيانات تجريبية وإحداثيات مصطنعة. لا يثبت تجربة GPS على جهاز فعلي.\n')

if __name__ == '__main__':
    try:
        if len(sys.argv) != 2 or sys.argv[1] not in ['prepare', 'finish']:
            raise RuntimeError('Choose prepare or finish')
        (prepare if sys.argv[1] == 'prepare' else finish)()
    except Exception as error:
        print('Smoke test stopped:', str(error).replace(CONFIG['FIREBASE_API_KEY'], '[redacted]'))
        sys.exit(1)
