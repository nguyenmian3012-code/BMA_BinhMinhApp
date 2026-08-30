using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;

namespace Bma.Data.Migrations;

[DbContext(typeof(BmaDbContext))]
[Migration("202608300001_Initial")]
public sealed class Initial : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder) => migrationBuilder.Sql("""
        CREATE TABLE app_users (
            id uuid PRIMARY KEY,
            user_name varchar(64) NOT NULL,
            normalized_user_name varchar(64) NOT NULL,
            display_name varchar(120) NOT NULL,
            employee_code varchar(64),
            password_hash text NOT NULL,
            status varchar(20) NOT NULL,
            roles varchar(256) NOT NULL,
            created_at timestamptz NOT NULL,
            approved_at timestamptz,
            approved_by uuid
        );
        CREATE UNIQUE INDEX ux_app_users_normalized_name ON app_users(normalized_user_name);
        CREATE UNIQUE INDEX ux_app_users_employee_code ON app_users(employee_code);

        CREATE TABLE refresh_sessions (
            id uuid PRIMARY KEY,
            user_id uuid NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
            token_hash text NOT NULL,
            token_family text NOT NULL,
            device_name text,
            ip_address text,
            created_at timestamptz NOT NULL,
            expires_at timestamptz NOT NULL,
            revoked_at timestamptz,
            revocation_reason text,
            replaced_by_hash text
        );
        CREATE UNIQUE INDEX ux_refresh_sessions_token_hash ON refresh_sessions(token_hash);
        CREATE INDEX ix_refresh_sessions_user_family ON refresh_sessions(user_id, token_family);

        CREATE TABLE raw_integration_events (
            id uuid PRIMARY KEY,
            event_id text NOT NULL,
            event_type text NOT NULL,
            source_system text NOT NULL,
            source_device_id text,
            sequence bigint,
            occurred_at timestamptz NOT NULL,
            received_at timestamptz NOT NULL,
            schema_version text NOT NULL,
            correlation_id text,
            payload_json jsonb NOT NULL,
            payload_hash text NOT NULL,
            signature text,
            processing_state varchar(20) NOT NULL,
            processing_error text
        );
        CREATE UNIQUE INDEX ux_raw_event_source_id ON raw_integration_events(source_system, event_id);
        CREATE INDEX ix_raw_event_device_sequence ON raw_integration_events(source_device_id, sequence);

        CREATE TABLE outbox_messages (
            id uuid PRIMARY KEY,
            topic text NOT NULL,
            message_key text NOT NULL,
            payload_json jsonb NOT NULL,
            occurred_at timestamptz NOT NULL,
            next_attempt_at timestamptz NOT NULL,
            attempt_count integer NOT NULL,
            processed_at timestamptz,
            last_error text
        );
        CREATE UNIQUE INDEX ux_outbox_topic_key ON outbox_messages(topic, message_key);
        CREATE INDEX ix_outbox_pending ON outbox_messages(processed_at, next_attempt_at);

        CREATE TABLE audit_entries (
            id uuid PRIMARY KEY,
            occurred_at timestamptz NOT NULL,
            actor_user_id uuid,
            action text NOT NULL,
            subject_type text NOT NULL,
            subject_id text NOT NULL,
            correlation_id text,
            before_json jsonb,
            after_json jsonb,
            ip_address text
        );
        CREATE INDEX ix_audit_subject_time ON audit_entries(subject_type, subject_id, occurred_at);

        CREATE TABLE integration_cursors (
            source_system text PRIMARY KEY,
            cursor text NOT NULL,
            updated_at timestamptz NOT NULL
        );

        CREATE TABLE motor_state_projections (
            position text PRIMARY KEY,
            motor_id text NOT NULL,
            is_on boolean NOT NULL,
            heartbeat_at timestamptz NOT NULL,
            changed_at timestamptz NOT NULL,
            source_event_id text NOT NULL
        );
        CREATE UNIQUE INDEX ux_motor_projection_source_event ON motor_state_projections(source_event_id);

        CREATE TABLE plant_state_periods (
            id uuid PRIMARY KEY,
            state varchar(20) NOT NULL,
            started_at timestamptz NOT NULL,
            ended_at timestamptz,
            source_event_id text NOT NULL
        );
        CREATE INDEX ix_plant_period_time ON plant_state_periods(started_at, ended_at);

        CREATE TABLE run_schedules (
            id uuid PRIMARY KEY,
            planned_start_at timestamptz NOT NULL,
            status text NOT NULL,
            note text,
            created_by uuid NOT NULL,
            created_at timestamptz NOT NULL,
            updated_at timestamptz NOT NULL
        );
        CREATE INDEX ix_run_schedules_status_time ON run_schedules(status, planned_start_at);

        CREATE TABLE quality_readings (
            id uuid PRIMARY KEY,
            source_event_id text NOT NULL,
            result_id text NOT NULL,
            lot_code text NOT NULL,
            measured_at timestamptz NOT NULL,
            ph numeric(6,3) NOT NULL,
            whiteness numeric(7,3) NOT NULL,
            moisture numeric(7,3) NOT NULL,
            fineness numeric(12,4),
            fineness_unit text,
            viscosity numeric(12,4),
            viscosity_unit text,
            extra_value numeric(12,4),
            product_code text,
            operator_code text,
            quality_code text,
            customer_code text
        );
        CREATE UNIQUE INDEX ux_quality_source_event ON quality_readings(source_event_id);
        CREATE UNIQUE INDEX ux_quality_result_id ON quality_readings(result_id);
        CREATE INDEX ix_quality_measured_at ON quality_readings(measured_at);

        CREATE TABLE production_mass_readings (
            id uuid PRIMARY KEY,
            source_event_id text NOT NULL,
            period_id text NOT NULL,
            kind varchar(30) NOT NULL,
            mass_kg numeric(18,3) NOT NULL,
            basis varchar(20) NOT NULL,
            approved boolean NOT NULL,
            formula_version text NOT NULL,
            recorded_at timestamptz NOT NULL
        );
        CREATE UNIQUE INDEX ux_mass_source_event ON production_mass_readings(source_event_id);
        CREATE INDEX ix_mass_period_basis_kind ON production_mass_readings(period_id, basis, kind);

        CREATE TABLE attendance_events (
            id uuid PRIMARY KEY,
            source_event_id text NOT NULL,
            employee_id text NOT NULL,
            kind varchar(10) NOT NULL,
            occurred_at timestamptz NOT NULL,
            source_system text NOT NULL,
            source_device_id text,
            sequence bigint,
            evidence_ref text NOT NULL
        );
        CREATE UNIQUE INDEX ux_attendance_source_event ON attendance_events(source_event_id);
        CREATE INDEX ix_attendance_employee_time ON attendance_events(employee_id, occurred_at);

        CREATE TABLE attendance_sessions (
            id uuid PRIMARY KEY,
            employee_id text NOT NULL,
            entry_at timestamptz,
            exit_at timestamptz,
            entry_event_id text,
            exit_event_id text,
            status varchar(20) NOT NULL,
            review_reason text,
            approved_by uuid,
            approved_at timestamptz,
            created_at timestamptz NOT NULL
        );
        CREATE INDEX ix_attendance_session_employee_time ON attendance_sessions(employee_id, entry_at, exit_at);

        CREATE TABLE employee_profiles (
            id uuid PRIMARY KEY,
            user_id uuid,
            employee_code text NOT NULL,
            full_name text NOT NULL,
            department text,
            position text,
            manager_employee_code text,
            responsibilities text NOT NULL,
            obligations text NOT NULL,
            benefits text NOT NULL,
            accountabilities text NOT NULL,
            effective_from date NOT NULL,
            version integer NOT NULL,
            updated_at timestamptz NOT NULL
        );
        CREATE UNIQUE INDEX ux_employee_profiles_code ON employee_profiles(employee_code);
        CREATE UNIQUE INDEX ux_employee_profiles_user ON employee_profiles(user_id);

        CREATE TABLE announcements (
            id uuid PRIMARY KEY,
            title text NOT NULL,
            body text NOT NULL,
            audience varchar(20) NOT NULL,
            audience_value text,
            priority text NOT NULL,
            published_at timestamptz NOT NULL,
            expires_at timestamptz,
            created_by uuid NOT NULL
        );
        CREATE INDEX ix_announcements_time ON announcements(published_at, expires_at);

        CREATE TABLE announcement_reads (
            announcement_id uuid NOT NULL,
            user_id uuid NOT NULL,
            read_at timestamptz NOT NULL,
            PRIMARY KEY (announcement_id, user_id)
        );

        CREATE TABLE push_devices (
            id uuid PRIMARY KEY,
            user_id uuid NOT NULL,
            platform text NOT NULL,
            token_hash text NOT NULL,
            encrypted_token text NOT NULL,
            registered_at timestamptz NOT NULL,
            revoked_at timestamptz
        );
        CREATE UNIQUE INDEX ux_push_device_user_token ON push_devices(user_id, token_hash);
        """);

    protected override void Down(MigrationBuilder migrationBuilder) => migrationBuilder.Sql("""
        DROP TABLE IF EXISTS push_devices;
        DROP TABLE IF EXISTS announcement_reads;
        DROP TABLE IF EXISTS announcements;
        DROP TABLE IF EXISTS employee_profiles;
        DROP TABLE IF EXISTS attendance_sessions;
        DROP TABLE IF EXISTS attendance_events;
        DROP TABLE IF EXISTS production_mass_readings;
        DROP TABLE IF EXISTS quality_readings;
        DROP TABLE IF EXISTS run_schedules;
        DROP TABLE IF EXISTS plant_state_periods;
        DROP TABLE IF EXISTS motor_state_projections;
        DROP TABLE IF EXISTS integration_cursors;
        DROP TABLE IF EXISTS audit_entries;
        DROP TABLE IF EXISTS outbox_messages;
        DROP TABLE IF EXISTS raw_integration_events;
        DROP TABLE IF EXISTS refresh_sessions;
        DROP TABLE IF EXISTS app_users;
        """);
}
