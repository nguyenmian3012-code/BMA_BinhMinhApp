# ADR-0001: Modular monolith

- Status: Accepted
- Date: 2026-08-30

## Decision

Dùng một ASP.NET Core .NET 10 service chứa API, background workers và Razor
Admin; module tách bằng namespace/data ownership. PostgreSQL dùng chung instance.

## Reason

Nhanh, ít chi phí và dễ debug/deploy hơn microservice, trong khi event contract
vẫn cho phép tách module về sau nếu có nhu cầu đo được.

## Excluded

Không Kubernetes, Kafka, Redis, service mesh, GraphQL hoặc CQRS framework trong
baseline.
