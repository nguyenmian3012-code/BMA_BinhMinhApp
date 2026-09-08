using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;

namespace Bma.Data.Migrations;

[DbContext(typeof(BmaDbContext))]
[Migration("202609080001_AutomaticAttendance")]
public sealed class AutomaticAttendance : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder) => migrationBuilder.Sql("""
        ALTER TABLE attendance_sessions ADD COLUMN work_date date;
        ALTER TABLE attendance_sessions ADD COLUMN shift_code varchar(32);
        ALTER TABLE attendance_sessions ADD COLUMN credited_minutes integer NOT NULL DEFAULT 0;
        ALTER TABLE attendance_sessions ADD CONSTRAINT ck_attendance_credited_minutes
            CHECK (credited_minutes >= 0);
        CREATE UNIQUE INDEX ux_attendance_session_employee_work_date
            ON attendance_sessions(employee_id, work_date)
            WHERE work_date IS NOT NULL;
        """);

    protected override void Down(MigrationBuilder migrationBuilder) => migrationBuilder.Sql("""
        DROP INDEX IF EXISTS ux_attendance_session_employee_work_date;
        ALTER TABLE attendance_sessions DROP CONSTRAINT IF EXISTS ck_attendance_credited_minutes;
        ALTER TABLE attendance_sessions DROP COLUMN IF EXISTS credited_minutes;
        ALTER TABLE attendance_sessions DROP COLUMN IF EXISTS shift_code;
        ALTER TABLE attendance_sessions DROP COLUMN IF EXISTS work_date;
        """);
}
