# BMA employee directory

The employee roster belongs in `employee_profiles`. A profile may exist before
the worker creates an app account. Account approval links it by employee code.
The face terminal will use that stable code as its employee identifier. Device
template IDs and face images must stay in a separate restricted mapping; they
are not stored in this directory.

The administrator assigns `Accounting`, `Operations`, `HR`, or `Executive` to
approved accounts at `/bmapp/admin/accounts`. Those roles may edit department,
position, hire date, and active status at `/bmapp/admin/employees`. Only `Admin`
may assign roles or reset an employee password. Identity fields are immutable;
corrections require an explicit audited reconciliation workflow. Deactivation
blocks app and web access and revokes refresh sessions.

The supplied 2026 health-check workbook is not a reliable source for all HR
fields. Both roster worksheets disagree on the first two employee codes, and
one row has no name. The factory owner confirmed the `Tại CTy` identities for
those two codes and supplied the missing KCS name and role. The hire-date column
is empty. The private one-time SQL import contains 71 reviewed rows from the
`Tại CTy` worksheet. It imports no citizen ID, medical information,
birth date, address, or health-examination marker. The SQL refuses to proceed
if an existing employee code has another name or a name has another code.
It does not overwrite existing profiles. Apply it against a backed-up staging
database after the `EmployeeDirectory` migration, then review the directory
before production use.

There is no common employee password. Employees may register their own account
and have it approved after matching the directory. Forgotten passwords use
an admin-assisted reset after in-person identity verification. The admin sees
the random replacement only once. Employees change it in the app's Profile
screen. The server revokes refresh sessions and invalidates access tokens when
passwords or roles change.
