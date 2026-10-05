using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;

namespace Bma.Data.Migrations;

[DbContext(typeof(BmaDbContext))]
[Migration("202610050001_AttendanceCorrections")]
public sealed class AttendanceCorrections : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder) => migrationBuilder.Sql("""
        CREATE TABLE attendance_correction_requests (
            id uuid PRIMARY KEY,
            attendance_session_id uuid NOT NULL REFERENCES attendance_sessions(id) ON DELETE RESTRICT,
            employee_id text NOT NULL,
            correction_type varchar(20) NOT NULL,
            reason varchar(500) NOT NULL,
            proposed_at timestamptz NOT NULL,
            evidence_ref varchar(500),
            status varchar(20) NOT NULL,
            requested_by uuid NOT NULL REFERENCES app_users(id) ON DELETE RESTRICT,
            requested_at timestamptz NOT NULL,
            reviewed_by uuid REFERENCES app_users(id) ON DELETE RESTRICT,
            reviewed_at timestamptz,
            review_comment varchar(500),
            CONSTRAINT ck_attendance_correction_type CHECK (
                correction_type IN ('MissingEntry', 'MissingExit', 'WrongEntry', 'WrongExit')),
            CONSTRAINT ck_attendance_correction_status CHECK (
                status IN ('Submitted', 'Approved', 'Rejected', 'Cancelled')),
            CONSTRAINT ck_attendance_correction_reason CHECK (
                char_length(btrim(reason)) BETWEEN 10 AND 500)
        );
        CREATE INDEX ix_attendance_correction_employee_requested
            ON attendance_correction_requests(employee_id, requested_at);
        CREATE UNIQUE INDEX ux_attendance_correction_active
            ON attendance_correction_requests(attendance_session_id, correction_type)
            WHERE status = 'Submitted';
        """);

    protected override void Down(MigrationBuilder migrationBuilder) => migrationBuilder.Sql("""
        DROP TABLE IF EXISTS attendance_correction_requests;
        """);
}
