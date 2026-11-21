# Freely CMS - Church Management System (Android, Flutter)

Offline-first church app. Every phone keeps its own SQLite database; the church's central copy is a Google Sheet
reached through an Apps Script web app (same architecture as MRMSji). No other server.

## Login (same as MRMSji)
1. Admin installs the app, chooses **I am the admin**, enters the church name and the Google Sheet web-app URL
   (in-app setup guide; `assets/freely_apps_script.txt` is the script to paste) -> church created, **invite code** shown in Users.
2. Admin shares the invite code. A member chooses **I am a user**, enters mobile number, name and the invite code -> **Request access**.
3. Admin opens **Users & roles**, **approves** the phone, and (optionally) gives roles. One-time: afterwards the app opens straight in.
4. Admin can disable a person, log every phone out, and recover the church on a new phone with the admin key.

## Modules in this release
Members (+family, restricted baptism details), Attendance, Events & calendar, Announcements (urgent/share), Finance cash book
(cash/bank, receipts/payments, opening balance, Balance C/F, void instead of delete, receipt sharing, Excel export in the layout of
`Receipts&Expenses_Aby.xlsx`), Reports, Users & roles (RBAC, multiple roles per person), Sync with conflict detection,
encrypted Backup/Restore, Audit log.

Roles: Pastor, Church Secretary, Treasurer, Deacon, Sunday School Coordinator/Teacher, Ministry Leader, Parent, Church Member.
The matrix lives in `lib/core/perms.dart` and is enforced again by `google-apps-script/Code.gs` (a phone never receives data its roles may not read).

## Develop
```
flutter pub get
flutter test                 # accounting logic
node google-apps-script/test.js   # backend: approval, roles, conflicts, finance rules
flutter build apk --debug
```
Changing `google-apps-script/Code.gs`? Copy it to `assets/freely_apps_script.txt` too.

## Not in this release (spec phases 2-4)
Sunday School marks/lessons, prayer requests, ministries, pastoral care, church records/certificates, assets, push notifications, multiple languages.
