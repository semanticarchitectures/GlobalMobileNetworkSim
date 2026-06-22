# Implementation Plan: Mission Video Generator

## Overview

Implement the `io.MissionVideoGenerator` class that produces animated MP4 videos from simulation event logs containing NODE_POSITION data. The implementation renders node positions over time on a geographic map using Natural Earth coastline/border data and MATLAB's `geoaxes`/`geoplot`/`geoscatter` functions. The feature integrates with the existing `+io` package, follows the `io.ReportWriter` constructor pattern, and outputs to the existing `output/{scenario_name}/` directory structure.

## Tasks

- [x] 1. Create MissionVideoGenerator class skeleton and configuration validation
  - [x] 1.1 Create `+io/MissionVideoGenerator.m` with constructor, properties, and config validation
    - Create the classdef file in the `+io` package as a handle class
    - Implement constructor accepting `(outputDir, scenarioName)` and optional `(outputDir, scenarioName, config)` matching the `io.ReportWriter` pattern
    - Define private properties: outputDir, scenarioName, config, coastlineLat, coastlineLon, boundaryLat, boundaryLon
    - Implement `validateConfig` private method that checks frameRate (integer 1–120), speedupFactor (0.1–1000), resolution (1x2 integer, width 1–7680, height 1–4320), showLinks (logical)
    - Apply defaults: frameRate=30, speedupFactor=60, resolution=[1920 1080], outputDir=pwd, showLinks=true
    - Throw structured errors with identifier `netsim:io:invalidConfig` naming the invalid field and expected constraint
    - Create output directory if it does not exist; throw `netsim:io:fileWriteError` if creation fails
    - _Requirements: 7.1, 7.2, 7.4, 7.5, 7.6, 8.1, 8.3, 8.4, 8.6_

  - [ ]* 1.2 Write property test for configuration validation (Property 12)
    - **Property 12: Configuration validation rejects invalid values with descriptive errors**
    - Generate 100+ random invalid configs: frameRate outside [1,120], speedupFactor outside [0.1,1000], resolution not 1x2 integer with width in [1,7680] and height in [1,4320]
    - Verify rejection and that error message contains the invalid field name and expected constraint
    - **Validates: Requirements 7.4, 7.5**

  - [ ]* 1.3 Write property test for output path construction (Property 8)
    - **Property 8: Output path construction**
    - Generate 100+ random alphanumeric scenario names (3–30 chars)
    - Verify output path equals `fullfile(outputDir, [scenarioName, '_mission_video.mp4'])`
    - **Validates: Requirements 4.4, 8.2**

- [x] 2. Implement basemap data acquisition
  - [x] 2.1 Implement `loadBasemapData` and `downloadAndParseGeoJSON` private methods
    - Download Natural Earth 110m coastline GeoJSON from public GitHub repository using `webread` with 30-second timeout
    - Download Natural Earth 110m admin-0 boundary GeoJSON using same approach
    - Cache downloaded files to `data/ne_110m_coastline.geojson` and `data/ne_110m_admin_0_boundary.geojson`
    - Load from cache if files already exist on disk
    - Parse GeoJSON using `jsondecode` and extract coordinates into NaN-separated lat/lon vectors
    - Handle corrupted cache: delete file and re-attempt download
    - Throw `netsim:io:downloadError` with URL and reason on network failure
    - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5, 2.6_

  - [ ]* 2.2 Write property test for GeoJSON coordinate extraction (Property 3)
    - **Property 3: GeoJSON coordinate extraction preserves structure**
    - Generate 100+ random GeoJSON FeatureCollections with 1–20 polygons, 3–50 coordinates per polygon
    - Verify parsing produces lat/lon vectors with exactly N-1 NaN delimiters for N polygons
    - Verify all original coordinate values are preserved in order
    - **Validates: Requirements 2.4**

- [x] 3. Implement event log parsing and position grouping
  - [x] 3.1 Implement `parsePositionLog` and `groupByTimestamp` private methods
    - Read CSV file using header row to identify columns
    - Extract only rows where eventType equals "NODE_POSITION"
    - Map columns: linkId → nodeId, msgId → lat (numeric), srcNodeId → lon (numeric), dstNodeId → altM (numeric), simTimeSec → simTimeSec (numeric)
    - Skip rows with non-numeric lat/lon/altM values
    - Throw `netsim:io:fileReadError` if CSV file does not exist or cannot be read
    - Throw `netsim:io:noPositionData` if zero NODE_POSITION rows found, suggesting `positionUpdateIntervalSec > 0`
    - Group entries by simTimeSec into snapshots sorted in ascending order
    - Each snapshot contains simTimeSec and a struct array of positions (one per nodeId at that timestamp)
    - _Requirements: 5.1, 5.2, 5.3, 5.4, 5.5, 5.6_

  - [ ]* 3.2 Write property test for position log parsing (Property 10)
    - **Property 10: Position log parsing extracts and maps correctly**
    - Generate 100+ random event log CSVs with 50–500 rows, mix of event types, some NODE_POSITION rows with non-numeric values
    - Verify only NODE_POSITION rows extracted, invalid rows skipped, column mapping correct
    - **Validates: Requirements 5.1, 5.6**

  - [ ]* 3.3 Write property test for timestamp grouping (Property 11)
    - **Property 11: Timestamp grouping produces unique sorted snapshots**
    - Generate 100+ random position logs with 5–50 timestamps, 3–20 nodes
    - Verify exactly K snapshots for K distinct timestamps, sorted ascending, sum of entries equals total valid entries
    - **Validates: Requirements 5.3, 5.4**

- [x] 4. Checkpoint - Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [x] 5. Implement frame rendering
  - [x] 5.1 Implement `createFigure`, `renderFrame`, `getNodeMarker`, `interpolatePosition`, `formatSimTime`, and `computeBounds` private methods
    - Create figure with 'Visible' off and resolution from config (1920x1080 default)
    - Use `geoaxes` for geographic axes; render coastline/boundary with `geoplot`
    - Render node positions with `geoscatter`: circle for Stationary, triangle for Mobile+waypoints, pentagram for satellite (Mobile+keplerElements)
    - Display node ID labels offset 1° lon right, 0.5° lat above, font size 8
    - Display simulation time as HH:MM:SS text annotation in top-right corner
    - Set lat/lon limits to encompass all positions across full timeline with configurable padding (default 2°)
    - Render trajectory paths as dashed lines beneath current position markers
    - Render active communication links with distinct colors per type (LEO_Satellite, GEO_Satellite, Fiber, Line_Of_Sight) with legend
    - Omit nodes whose position cannot be computed (graceful skip)
    - Include legend for node type markers and link type colors
    - Implement linear interpolation between position snapshots for smooth motion
    - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 3.7, 3.8, 3.9_

  - [ ]* 5.2 Write property test for node marker assignment (Property 4)
    - **Property 4: Node type determines marker shape**
    - Generate 100+ random nodes from {Stationary, Mobile+waypoints, Mobile+kepler}
    - Verify circle for Stationary, triangle for Mobile+waypoints, pentagram for satellite
    - **Validates: Requirements 3.2**

  - [ ]* 5.3 Write property test for simulation time formatting (Property 5)
    - **Property 5: Simulation time formatting**
    - Generate 100+ random non-negative seconds [0, 360000]
    - Verify formatted string equals `sprintf('%02d:%02d:%02d', floor(t/3600), floor(mod(t,3600)/60), floor(mod(t,60)))`
    - **Validates: Requirements 3.4**

  - [ ]* 5.4 Write property test for geographic bounds computation (Property 6)
    - **Property 6: Geographic bounds encompass all positions with padding**
    - Generate 100+ random position sets (1–50 positions), random padding [0, 10]
    - Verify latLim and lonLim encompass all positions plus padding
    - **Validates: Requirements 3.5**

- [x] 6. Implement video assembly with VideoWriter
  - [x] 6.1 Implement `generate` public method and `writeVideo` private method
    - Implement the main `generate(eventLogCsvPath)` and `generate(eventLogCsvPath, scenarioStruct)` entry point
    - Parse position log from CSV, acquire basemap data, compute bounds
    - Calculate total frames: `ceil((simulationDurationSec / speedupFactor) * frameRate)`
    - Calculate frame time step: `speedupFactor / frameRate` seconds per frame
    - Open VideoWriter with 'MPEG-4' profile, set FrameRate from config
    - Render frames sequentially starting at simTime 0, advancing by timeStep per frame
    - Capture each frame with `getframe` and write to VideoWriter
    - Close VideoWriter and release figure resources on success
    - Output file: `{outputDir}/{ScenarioName}_mission_video.mp4`
    - Implement try/catch cleanup: close VideoWriter, delete partial MP4, close figure, re-throw with frame number context using `netsim:io:videoRenderError`
    - Respect `showLinks` config option (omit links when false)
    - _Requirements: 4.1, 4.2, 4.3, 4.4, 4.5, 4.6, 4.7, 4.8, 7.3_

  - [ ]* 6.2 Write property test for total video frame count (Property 7)
    - **Property 7: Total video frame count formula**
    - Generate 100+ random combinations: duration (1–100000), speedup (0.1–1000), frameRate (1–120)
    - Verify frame count equals `ceil((simulationDurationSec / speedupFactor) * frameRate)`
    - **Validates: Requirements 4.3**

  - [ ]* 6.3 Write property test for frame time advancement (Property 9)
    - **Property 9: Frame time advancement**
    - Generate 100+ random speedup/frameRate combinations
    - Verify frame N (0-indexed) corresponds to simulation time `N * (speedupFactor / frameRate)`
    - **Validates: Requirements 4.8**

- [x] 7. Checkpoint - Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [x] 8. Create scenario runner scripts
  - [x] 8.1 Create `run_dragon_cart_video.m` scenario runner script
    - Load Dragon Cart Improved scenario from `scenarios/dragon_cart/dragon_cart_improved.json` using `io.ScenarioLoader.load`
    - Construct SimController, set `positionUpdateIntervalSec = 10`
    - Run simulation
    - Write event log CSV to `output/dragon_cart_improved/` using `io.ReportWriter`
    - Invoke `io.MissionVideoGenerator` with event log CSV path and scenario struct
    - Print absolute path of generated MP4 on success
    - Print error message with failure stage on scenario load/simulation error (terminate without invoking Video_Generator)
    - Print error message with event log CSV path on video generation failure
    - _Requirements: 6.1, 6.3, 6.4, 6.5_

  - [x] 8.2 Create `run_airdrop_video.m` scenario runner script
    - Load Airdrop Mission scenario from `scenarios/airdrop_mission/airdrop_mission.json` using `io.ScenarioLoader.load`
    - Construct SimController, set `positionUpdateIntervalSec = 10`
    - Run simulation
    - Write event log CSV to `output/airdrop_mission/` using `io.ReportWriter`
    - Invoke `io.MissionVideoGenerator` with event log CSV path and scenario struct
    - Print absolute path of generated MP4 on success
    - Print error message with failure stage on scenario load/simulation error
    - Print error message with event log CSV path on video generation failure
    - _Requirements: 6.2, 6.3, 6.4, 6.5_

- [ ] 9. Write unit and integration tests
  - [x] 9.1 Create `tests/io/MissionVideoGeneratorTest.m` with unit tests
    - Test constructor with default config values
    - Test constructor with custom config
    - Test outputDir/scenarioName storage
    - Test directory creation on construction
    - Test error on missing CSV file (`netsim:io:fileReadError`)
    - Test error on empty position data (`netsim:io:noPositionData`)
    - Test error on invalid config values (`netsim:io:invalidConfig`)
    - Test basemap caching (cached file loaded from disk)
    - Test figure visibility off during rendering
    - Test end-to-end with small synthetic event log (5 nodes, 10 timestamps)
    - _Requirements: 7.1, 7.2, 7.4, 7.5, 5.2, 5.5, 8.1, 8.6_

  - [ ]* 9.2 Create `tests/io/MissionVideoGeneratorPropertyTest.m` with remaining property tests
    - **Property 1: Position event scheduling produces correct timestamps**
    - Generate 100+ random intervals (1–100) and durations (100–10000)
    - Verify timestamps start at interval, advance by interval, last < duration
    - **Validates: Requirements 1.1**
    - **Property 2: NODE_POSITION serialization format**
    - Generate 100+ random nodeIds, lat [-90,90], lon [-180,180], altM [0,50000]
    - Verify CSV row format: eventType="NODE_POSITION", linkId=nodeId, msgId=lat (4 decimal places), srcNodeId=lon (4 decimal places), dstNodeId=altM (1 decimal place), latencyMs empty, reason empty
    - **Validates: Requirements 1.2**

- [ ] 10. Final checkpoint - Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional and can be skipped for faster MVP
- Each task references specific requirements for traceability
- Checkpoints ensure incremental validation
- Property tests validate universal correctness properties using 100+ iterations with random generators
- Unit tests validate specific examples and edge cases
- The implementation language is MATLAB R2025b
- No Mapping Toolbox dependency — uses only `geoaxes`, `geoplot`, `geoscatter` from base MATLAB
- The `io.MissionVideoGenerator` class follows the `io.ReportWriter` constructor pattern (outputDir, scenarioName)
- SimController already has `positionUpdateIntervalSec` and `handleNodePosition` implemented — no changes needed
- Natural Earth 110m GeoJSON downloads and parses correctly via `jsondecode(webread(url))`

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["1.1"] },
    { "id": 1, "tasks": ["1.2", "1.3", "2.1", "3.1"] },
    { "id": 2, "tasks": ["2.2", "3.2", "3.3"] },
    { "id": 3, "tasks": ["5.1"] },
    { "id": 4, "tasks": ["5.2", "5.3", "5.4", "6.1"] },
    { "id": 5, "tasks": ["6.2", "6.3", "8.1", "8.2"] },
    { "id": 6, "tasks": ["9.1", "9.2"] }
  ]
}
```
