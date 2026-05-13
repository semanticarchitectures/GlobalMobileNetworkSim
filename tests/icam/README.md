# `tests/icam/` — ICAM Layer Test Suite

## Overview

This directory contains unit tests and property-based tests for the `+icam/` package. Tests mirror the package structure and follow the same conventions as the rest of the `tests/` directory.

## Test Files

| File | Component Under Test | Coverage |
|---|---|---|
| `EntityRegistryTest.m` | `icam.EntityRegistry` | Construction, validation, getEntity, getSubEntities, indexOf, count, addEntity |
| `CredentialStoreTest.m` | `icam.CredentialStore` | issueCertificate, getCertificate, checkExpiry, revoke |

## Conventions

- All test classes extend `matlab.unittest.TestCase`.
- Test methods are grouped by the feature they cover using `methods (Test)` blocks.
- Helper/fixture methods are placed in `methods (Access = private)` blocks.
- Error identifier assertions use `testCase.verifyError(@() ..., 'netsim:icam:<type>')`.
- Property-based tests (when present) are tagged with:
  ```matlab
  % Feature: matlab-network-sim, Property N: <property_text>
  ```

## Running Tests

From the project root in MATLAB:

```matlab
% Run all ICAM tests
results = runtests('tests/icam');
disp(results);

% Run a specific test file
results = runtests('tests/icam/EntityRegistryTest');
disp(results);
```

Or use the top-level runner:

```matlab
run tests/run_all_tests.m
```

## Requirements Coverage

- Requirement 17: Entity and Sub-Entity Identity Model
- Requirement 18: Credential Management and PKI
