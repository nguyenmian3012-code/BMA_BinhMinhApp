using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;

namespace Bma.Data.Migrations;

[DbContext(typeof(BmaDbContext))]
[Migration("202609260001_EmployeeDirectory")]
public sealed class EmployeeDirectory : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder) => migrationBuilder.Sql("""
        ALTER TABLE employee_profiles ADD COLUMN hired_on date;
        ALTER TABLE employee_profiles ADD COLUMN is_active boolean NOT NULL DEFAULT true;
        ALTER TABLE app_users ADD COLUMN auth_version integer NOT NULL DEFAULT 0;

        -- Existing unique indexes are case-sensitive; imports must not create BM001/bm001.
        CREATE UNIQUE INDEX ux_employee_profiles_code_normalized
            ON employee_profiles (upper(btrim(employee_code)));
        CREATE UNIQUE INDEX ux_app_users_employee_code_normalized
            ON app_users (upper(btrim(employee_code))) WHERE employee_code IS NOT NULL;

        CREATE FUNCTION bma_guard_employee_identity() RETURNS trigger AS $$
        BEGIN
            IF NEW.employee_code IS DISTINCT FROM OLD.employee_code
               OR NEW.full_name IS DISTINCT FROM OLD.full_name THEN
                RAISE EXCEPTION 'Employee code and full name are immutable; review identity corrections separately';
            END IF;
            RETURN NEW;
        END;
        $$ LANGUAGE plpgsql;
        CREATE TRIGGER tr_employee_identity_immutable
            BEFORE UPDATE ON employee_profiles FOR EACH ROW
            EXECUTE FUNCTION bma_guard_employee_identity();
        """);

    protected override void Down(MigrationBuilder migrationBuilder) => migrationBuilder.Sql("""
        DROP TRIGGER IF EXISTS tr_employee_identity_immutable ON employee_profiles;
        DROP FUNCTION IF EXISTS bma_guard_employee_identity();
        DROP INDEX IF EXISTS ux_app_users_employee_code_normalized;
        DROP INDEX IF EXISTS ux_employee_profiles_code_normalized;
        ALTER TABLE employee_profiles DROP COLUMN IF EXISTS is_active;
        ALTER TABLE employee_profiles DROP COLUMN IF EXISTS hired_on;
        ALTER TABLE app_users DROP COLUMN IF EXISTS auth_version;
        """);
}
