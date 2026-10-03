using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;

namespace Bma.Data.Migrations;

[DbContext(typeof(BmaDbContext))]
[Migration("202609110001_LinkApprovedEmployeeProfiles")]
public sealed class LinkApprovedEmployeeProfiles : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder) => migrationBuilder.Sql("""
        WITH linked AS (
            UPDATE employee_profiles AS profile
            SET user_id = account.id,
                updated_at = CURRENT_TIMESTAMP
            FROM app_users AS account
            WHERE profile.user_id IS NULL
              AND account.status = 'Approved'
              AND account.employee_code IS NOT NULL
              AND profile.employee_code = account.employee_code
              AND NOT EXISTS (
                  SELECT 1 FROM employee_profiles AS existing
                  WHERE existing.user_id = account.id
              )
            RETURNING profile.id, profile.employee_code, profile.user_id
        )
        INSERT INTO audit_entries (
            id, occurred_at, actor_user_id, action, subject_type, subject_id,
            correlation_id, before_json, after_json, ip_address
        )
        SELECT gen_random_uuid(), CURRENT_TIMESTAMP, NULL,
               'ACCOUNT_EMPLOYEE_LINKED_MIGRATION', 'EMPLOYEE_PROFILE', id::text,
               NULL, NULL,
               jsonb_build_object('employee_code', employee_code, 'user_id', user_id),
               NULL
        FROM linked;
        """);

    // The previous link state is unknowable after deployment. Do not silently unlink users on rollback.
    protected override void Down(MigrationBuilder migrationBuilder)
    {
    }
}
