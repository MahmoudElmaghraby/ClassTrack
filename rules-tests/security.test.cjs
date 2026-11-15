const {test,before,beforeEach,after} = require('node:test');
const fs = require('node:fs');
const {initializeTestEnvironment,assertSucceeds,assertFails} = require('@firebase/rules-unit-testing');
const {doc,setDoc,getDoc,updateDoc,writeBatch,serverTimestamp,Timestamp,collectionGroup,query,where,getDocs} = require('firebase/firestore');
let env;
const lat=30.0444, lng=31.2357;
const stamp = ms=>Timestamp.fromMillis(ms);
const dbFor=(id)=>env.authenticatedContext(id,{email:`${id}@example.test`}).firestore();
before(async()=>{env=await initializeTestEnvironment({projectId:'demo-classtrack',firestore:{rules:fs.readFileSync('firestore.rules','utf8')}});});
after(async()=>{if(env)await env.cleanup();});
beforeEach(async()=>{
 await env.clearFirestore();
 await env.withSecurityRulesDisabled(async ctx=>{
  const db=ctx.firestore(), b=writeBatch(db), now=Date.now();
  for(const [id,role] of [['t','teacher'],['t2','teacher'],['s','student'],['s2','student'],['u','student']])
   b.set(doc(db,`users/${id}`),{name:id,email:`${id}@example.test`,role,studentID:`UNI-${id}`});
  b.set(doc(db,'classes/c'),{name:'Mobile',semester:'Fall',teacherID:'t',joinCode:'ABCDEFGH',createdAt:stamp(now-100000)});
  b.set(doc(db,'class_join_codes/ABCDEFGH'),{classID:'c',teacherID:'t',className:'Mobile'});
  for(const id of ['s','s2']) b.set(doc(db,`enrollments/c__${id}`),{classID:'c',studentID:id,studentName:id,universityStudentID:`UNI-${id}`,createdAt:stamp(now-100000)});
  for(const [id,mode,expired] of [['p','punch_in',false],['q','quiz',false],['old','punch_in',true],['oldq','quiz',true]]){
   const start=now-(expired?130000:1000);
   b.set(doc(db,`attendance_sessions/${id}`),{classID:'c',teacherID:'t',mode,latitude:lat,longitude:lng,radius:50,startTime:stamp(start),expiryTime:stamp(start+120000),status:'active',initialized:true});
   if(mode==='quiz'){
    b.set(doc(db,`attendance_sessions/${id}/quiz/public`),{questions:Array.from({length:5},()=>({text:'Question',options:['A','B','C','D']}))});
    b.set(doc(db,`attendance_sessions/${id}/quiz_private/key`),{correctAnswers:[0,1,2,3,0]});
   }
  }
  await b.commit();
 });
});
function attemptData(sessionID='p',overrides={}) {
 const quiz=['q','oldq'].includes(sessionID);
 return {studentID:'s',sessionID,classID:'c',timestamp:serverTimestamp(),latitude:lat,longitude:lng,distance:0,
  locationVerified:true,quizOpened:quiz,quizSubmitted:quiz,submissionTime:quiz?serverTimestamp():null,
  answers:quiz?[0,1,2,3,0]:null,quizScore:null,gradedAt:null,status:'present',rejectionReason:null,
  eventType:quiz?'quiz_submit':'punch_in',finalized:true,...overrides};
}
async function attempt(db,data,id='one',{summary=true}={}) {
 const root=`attendance_records/${data.sessionID}__${data.studentID}`, b=writeBatch(db);
 b.set(doc(db,`${root}/attempts/${id}`),data);
 if(summary)b.set(doc(db,root),{...data,lastAttemptId:id});
 return b.commit();
}
test('anonymous users cannot read classes',async()=>assertFails(getDoc(doc(env.unauthenticatedContext().firestore(),'classes/c'))));
test('students cannot promote their stored role',async()=>assertFails(updateDoc(doc(dbFor('s'),'users/s'),{role:'teacher'})));
test('students cannot read another profile',async()=>assertFails(getDoc(doc(dbFor('s'),'users/s2'))));
test('students cannot create classes',async()=>assertFails(setDoc(doc(dbFor('s'),'classes/evil'),{teacherID:'s'})));
test('another teacher cannot edit a class',async()=>assertFails(updateDoc(doc(dbFor('t2'),'classes/c'),{name:'Hijack'})));
test('owning teacher can edit class name',async()=>assertSucceeds(updateDoc(doc(dbFor('t'),'classes/c'),{name:'Mobile 2'})));
test('student joins only using a valid code and own identity',async()=>{
 const db=dbFor('u');
 const data={classID:'c',studentID:'u',joinCodeUsed:'ABCDEFGH',studentName:'u',universityStudentID:'UNI-u',className:'Mobile',createdAt:serverTimestamp()};
 await assertFails(setDoc(doc(db,'enrollments/c__u'),{...data,joinCodeUsed:'INVALIDX'}));
 await assertFails(setDoc(doc(db,'enrollments/c__s2'),{...data,studentID:'s2'}));
 await assertSucceeds(setDoc(doc(db,'enrollments/c__u'),data));
 await assertFails(setDoc(doc(db,'enrollments/c__u'),data));
});
test('enrolled student sees sessions without location predicates',async()=>assertSucceeds(getDoc(doc(dbFor('s'),'attendance_sessions/p'))));
test('unenrolled student cannot see class session',async()=>assertFails(getDoc(doc(dbFor('u'),'attendance_sessions/p'))));
test('punch-in succeeds inside radius with linked audit event',async()=>assertSucceeds(attempt(dbFor('s'),attemptData())));
test('client cannot write a present record without a matching event',async()=>assertFails(setDoc(doc(dbFor('s'),'attendance_records/p__s'),{...attemptData(),lastAttemptId:'forged'})));
test('outside coordinates cannot claim zero distance or presence',async()=>assertFails(attempt(dbFor('s'),attemptData('p',{latitude:lat+.01}))));
test('outside attempt is recorded only as rejected',async()=>assertSucceeds(attempt(dbFor('s'),attemptData('p',{latitude:lat+.01,distance:1111.9510118,locationVerified:false,status:'rejected',rejectionReason:'outside_radius'}))));
test('no GPS cannot become present',async()=>assertFails(attempt(dbFor('s'),attemptData('p',{latitude:null,longitude:null,distance:null,locationVerified:false}))));
test('permission rejection can be audited without fake coordinates',async()=>assertSucceeds(attempt(dbFor('s'),attemptData('p',{latitude:null,longitude:null,distance:null,locationVerified:false,status:'rejected',rejectionReason:'permission_denied'}))));
test('expired session rejects presence but allows truthful late rejection',async()=>{
 await assertFails(attempt(dbFor('s'),attemptData('old')));
 await assertSucceeds(attempt(dbFor('s'),attemptData('old',{status:'rejected',rejectionReason:'expired'})));
});
test('unenrolled or impersonating client cannot attend',async()=>{
 await assertFails(attempt(dbFor('u'),attemptData('p',{studentID:'u'})));
 await assertFails(attempt(dbFor('s2'),attemptData()));
});
test('accepted record cannot be overwritten or duplicated',async()=>{
 const db=dbFor('s');await assertSucceeds(attempt(db,attemptData()));
 await assertFails(attempt(db,attemptData(),'second'));
 await assertSucceeds(attempt(db,attemptData('p',{status:'rejected',rejectionReason:'already_present'}),'duplicate',{summary:false}));
 const saved=(await getDoc(doc(db,'attendance_records/p__s'))).data();
 if(saved.status!=='present'||saved.lastAttemptId!=='one')throw Error('Accepted result changed');
});
test('quiz accepts all five valid answers without a pass-score threshold',async()=>assertSucceeds(attempt(dbFor('s'),attemptData('q',{answers:[1,2,3,0,1]}))));
test('quiz rejects missing or out-of-range answers',async()=>{
 await assertFails(attempt(dbFor('s'),attemptData('q',{answers:[0,1,2,3]})));
 await assertFails(attempt(dbFor('s'),attemptData('q',{answers:[0,1,2,3,99]})));
});
test('quiz opening does not reserve a successful attendance record',async()=>assertSucceeds(attempt(dbFor('s'),attemptData('q',{quizSubmitted:false,submissionTime:null,answers:null,status:'absent',eventType:'quiz_open',finalized:false}),'open',{summary:false})));
test('student cannot read answer keys or invent a grade',async()=>{
 const db=dbFor('s');await assertSucceeds(getDoc(doc(db,'attendance_sessions/q/quiz/public')));
 await assertFails(getDoc(doc(db,'attendance_sessions/q/quiz_private/key')));
 await assertFails(attempt(db,attemptData('q',{quizScore:5})));
});
test('teacher grading must match stored answers and cannot alter attendance',async()=>{
 await attempt(dbFor('s'),attemptData('q',{answers:[1,2,3,0,1]}));
 const db=dbFor('t'), ref=doc(db,'attendance_records/q__s');
 await assertFails(updateDoc(ref,{quizScore:5,gradedAt:serverTimestamp()}));
 await assertFails(updateDoc(ref,{quizScore:0,gradedAt:serverTimestamp(),status:'rejected'}));
 await assertSucceeds(updateDoc(ref,{quizScore:0,gradedAt:serverTimestamp()}));
});
test('student cannot read another attendance result',async()=>{
 await attempt(dbFor('s'),attemptData());
 await assertFails(getDoc(doc(dbFor('s2'),'attendance_records/p__s')));
});
test('session time cannot be extended, nor session closed early',async()=>{
 const db=dbFor('t');
 await assertFails(updateDoc(doc(db,'attendance_sessions/p'),{expiryTime:stamp(Date.now()+999999)}));
 await assertFails(updateDoc(doc(db,'attendance_sessions/p'),{status:'closed'}));
 await assertSucceeds(updateDoc(doc(db,'attendance_sessions/old'),{status:'closed'}));
});
test('session activation uses an immutable server clock and exactly 120 seconds',async()=>{
 const db=dbFor('t'), ref=doc(db,'attendance_sessions/new');
 await assertSucceeds(setDoc(ref,{classID:'c',teacherID:'t',mode:'punch_in',latitude:lat,longitude:lng,radius:50,startTime:null,expiryTime:null,status:'closed',initialized:false,createdAt:serverTimestamp()}));
 const clock=doc(db,'session_clocks/new');
 await assertFails(setDoc(clock,{teacherID:'t',classID:'c',startedAt:stamp(Date.now()+999999)}));
 await assertSucceeds(setDoc(clock,{teacherID:'t',classID:'c',startedAt:serverTimestamp()}));
 const start=(await getDoc(clock)).data().startedAt;
 await assertFails(updateDoc(ref,{startTime:start,expiryTime:stamp(start.toMillis()+121000),status:'active',initialized:true}));
 await assertSucceeds(updateDoc(ref,{startTime:start,expiryTime:stamp(start.toMillis()+120000),status:'active',initialized:true}));
 await assertFails(updateDoc(clock,{startedAt:serverTimestamp()}));
});
test('teacher can query session attempt group, other teacher cannot',async()=>{
 await attempt(dbFor('s'),attemptData());
 await assertSucceeds(getDocs(query(collectionGroup(dbFor('t'),'attempts'),where('sessionID','==','p'),where('classID','==','c'))));
 await assertFails(getDocs(query(collectionGroup(dbFor('t2'),'attempts'),where('sessionID','==','p'),where('classID','==','c'))));
});
test('user can create only their own complete role profile',async()=>{
 const db=dbFor('new');const data={name:'New',email:'new@example.test',role:'student',studentID:'N1',createdAt:serverTimestamp()};
 await assertFails(setDoc(doc(db,'users/other'),data));
 await assertFails(setDoc(doc(db,'users/new'),{...data,role:'admin'}));
 await assertSucceeds(setDoc(doc(db,'users/new'),data));
});
test('teacher creates a class and its unique join code atomically',async()=>{
 const db=dbFor('t'), b=writeBatch(db);
 b.set(doc(db,'classes/newclass'),{name:'New class',semester:'Fall',teacherID:'t',joinCode:'NEWCODEX',createdAt:serverTimestamp()});
 b.set(doc(db,'class_join_codes/NEWCODEX'),{classID:'newclass',teacherID:'t',className:'New class'});
 await assertSucceeds(b.commit());
});
test('quiz can be prepared atomically and becomes immutable when its clock starts',async()=>{
 const db=dbFor('t'), root='attendance_sessions/newquiz', b=writeBatch(db);
 b.set(doc(db,root),{classID:'c',teacherID:'t',mode:'quiz',latitude:lat,longitude:lng,radius:50,startTime:null,expiryTime:null,status:'closed',initialized:false,createdAt:serverTimestamp()});
 b.set(doc(db,root+'/quiz/public'),{questions:Array.from({length:5},()=>({text:'Q',options:['A','B','C','D']}))});
 b.set(doc(db,root+'/quiz_private/key'),{correctAnswers:[0,1,2,3,0]});
 await assertSucceeds(b.commit());
 await assertSucceeds(setDoc(doc(db,'session_clocks/newquiz'),{teacherID:'t',classID:'c',startedAt:serverTimestamp()}));
 await assertFails(updateDoc(doc(db,root+'/quiz_private/key'),{correctAnswers:[1,1,1,1,1]}));
 const start=(await getDoc(doc(db,'session_clocks/newquiz'))).data().startedAt;
 await assertSucceeds(updateDoc(doc(db,root),{startTime:start,expiryTime:stamp(start.toMillis()+120000),status:'active',initialized:true}));
});
test('teacher and enrolled student can query published class sessions',async()=>{
 const {collection}=require('firebase/firestore');
 for(const id of ['t','s'])await assertSucceeds(getDocs(query(collection(dbFor(id),'attendance_sessions'),where('classID','==','c'),where('initialized','==',true))));
 await assertFails(getDocs(query(collection(dbFor('u'),'attendance_sessions'),where('classID','==','c'),where('initialized','==',true))));
});
test('teacher can query session attendance without exposing it to another student',async()=>{
 const {collection}=require('firebase/firestore');await attempt(dbFor('s'),attemptData());
 await assertSucceeds(getDocs(query(collection(dbFor('t'),'attendance_records'),where('sessionID','==','p'))));
 await assertFails(getDocs(query(collection(dbFor('s2'),'attendance_records'),where('sessionID','==','p'))));
});
function absent(sessionID){return {sessionID,studentID:'s',classID:'c',timestamp:null,latitude:null,longitude:null,distance:null,locationVerified:false,quizOpened:false,quizSubmitted:false,submissionTime:null,answers:null,quizScore:null,gradedAt:null,status:'absent',rejectionReason:null,finalized:true,finalizedAt:serverTimestamp(),lastAttemptId:null};}
test('absence is finalized only after expiry and cannot replace presence',async()=>{
 const db=dbFor('t');
 await assertFails(setDoc(doc(db,'attendance_records/p__s'),absent('p')));
 await assertSucceeds(setDoc(doc(db,'attendance_records/old__s'),absent('old')));
 await attempt(dbFor('s'),attemptData());
 await assertFails(setDoc(doc(db,'attendance_records/p__s'),absent('p')));
});
test('runtime server clock cannot be forged with a client timestamp',async()=>{
 const db=dbFor('s'),ref=doc(db,'users/s/runtime/clock');
 await assertFails(setDoc(ref,{time:stamp(Date.now()+999999)}));
 await assertSucceeds(setDoc(ref,{time:serverTimestamp()}));
});
