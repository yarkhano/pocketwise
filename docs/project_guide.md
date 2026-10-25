# PocketWise Project Guide

## Status

This repository contains a runnable Flutter starter and
placeholder files for the planned expense tracker.

## Architecture

Flutter → FastAPI → SQLAlchemy → PostgreSQL.

Flutter does not connect directly to PostgreSQL.

## File organization

- Flutter feature screens contain their own forms and dialogs.
- api.dart handles mobile API requests.
- Backend feature files contain routes and feature logic.
- models.py defines database tables.
- schemas.py defines request and response validation.
- notifications.dart schedules device reminders.

## Implementation order

1. Database configuration and migrations
2. Authentication and user-data isolation
3. Categories
4. Transactions and filters
5. Dashboard and budgets
6. Reports and charts
7. Reminders and templates
8. Settings, testing, and database backups

## Important rules

- Use PKR only.
- Use decimal amounts in PostgreSQL and Python.
- Use integer paisa for Flutter money calculations.
- Authenticate requests and enforce record ownership.
- Archive categories used by historical records.
- Show budget warnings at 80% and at or above 100%.
- Require confirmation before saving a template as a transaction.
- Reminders do not create expenses or make payments.
- Cancel the account's local reminders on logout.
- Keep credentials and database backups out of Git.
- CSV export is excluded.

## Approval

Obtain instructor approval before Assignment 2.
Discuss major changes to scope or technology with the instructor.
