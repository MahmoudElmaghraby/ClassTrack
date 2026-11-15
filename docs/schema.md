# Firestore schema

Original assignment fields are retained. References are string document IDs.
`users.studentID` means university number; other `studentID` fields mean Firebase Auth UID.

| Collection | Document ID | Fields |
|---|---|---|
| users | Auth UID | name, email, role (teacher/student), studentID (students only), createdAt |
| classes | generated | name, teacherID, semester, joinCode, createdAt |
| class_join_codes | join code | classID, teacherID, className |
| enrollments | classID__UID | classID, studentID, studentName, universityStudentID, className, joinCodeUsed, createdAt |
| attendance_sessions | generated | classID, teacherID, mode (punch_in/quiz), latitude, longitude, radius, startTime, expiryTime, status (active/closed), initialized, createdAt |
| session_clocks | sessionID | teacherID, classID, startedAt |
| attendance_records | sessionID__UID | sessionID, studentID, classID, timestamp, latitude, longitude, distance, status (present/rejected/absent), quizScore, quizOpened, quizSubmitted, locationVerified, submissionTime, answers, gradedAt, rejectionReason, eventType, finalized, lastAttemptId |

Subcollections:

- `attendance_sessions/{id}/quiz/public`: exactly five `questions`, each a map of text and four options.
- `attendance_sessions/{id}/quiz_private/key`: five `correctAnswers` indices, 0–3. Only the owner teacher reads this document.
- `attendance_records/{recordId}/attempts/{attemptId}`: immutable event fields corresponding to the summary, without lastAttemptId. Owner teacher may add a verified quizScore and gradedAt only. Open events can exist before a parent summary document.
- `users/{uid}/runtime/clock`: server timestamp `time` for display synchronization. Backend time validation always uses request.time.

All time values are Firestore timestamps. Radius/distance are meters. Coordinates are degrees.
No-attempt absence has null timestamp, coordinates, distance, answers, quizScore, submissionTime, gradedAt, lastAttemptId and adds finalizedAt; eventType is absent because no new attempt was made. Opening history remains in attempts. Null grade is pending/unsubmitted, never a score of zero.

Session setup uses initialized=false/status=closed. It is private to the teacher until activated. A one-time clock initializes an exact 120-second interval. Settings/questions/keys are frozen when the clock starts. Expired sessions reject attendance independently of stored status.

Students write linked events and a deterministic summary atomically. Accepted summaries cannot be overwritten by students. Teacher grading verifies score against stored answers and the private key without changing status. Missing absence records are finalized when teacher results are reviewed; enrollments after expiry are excluded.

The collection-group index in firestore.indexes.json covers attempts with classID ASCENDING and sessionID ASCENDING. Session history is sorted locally; equality queries use automatic indexes/index merging.
