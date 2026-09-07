\set ON_ERROR_STOP on
\pset pager off
\pset null '(null)'

\echo '1/4 Raw canonical events from Terminal'
SELECT
    received_at,
    event_id,
    event_type,
    sequence,
    processing_state,
    processing_error
FROM raw_integration_events
WHERE source_system = 'ENTRY_EXIT'
  AND source_device_id = :'device_id'
ORDER BY received_at DESC
LIMIT 20;

\echo '2/4 Projected attendance events'
SELECT
    occurred_at,
    source_event_id,
    employee_id,
    kind,
    sequence,
    evidence_ref
FROM attendance_events
WHERE source_system = 'ENTRY_EXIT'
  AND source_device_id = :'device_id'
ORDER BY occurred_at DESC
LIMIT 20;

\echo '3/4 Attendance sessions built from Entry/Exit'
SELECT
    employee_id,
    entry_at,
    exit_at,
    status,
    review_reason,
    entry_event_id,
    exit_event_id
FROM attendance_sessions
WHERE entry_event_id IN (
        SELECT source_event_id FROM attendance_events WHERE source_device_id = :'device_id'
    )
   OR exit_event_id IN (
        SELECT source_event_id FROM attendance_events WHERE source_device_id = :'device_id'
    )
ORDER BY COALESCE(entry_at, exit_at) DESC
LIMIT 20;

\echo '4/4 Projection failures that require intervention'
SELECT
    received_at,
    event_id,
    event_type,
    processing_error
FROM raw_integration_events
WHERE source_system = 'ENTRY_EXIT'
  AND source_device_id = :'device_id'
  AND processing_state = 'Failed'
ORDER BY received_at DESC
LIMIT 20;
