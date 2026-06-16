# Requirements Document

## Introduction

The Mission Video Generator feature produces animated MP4 videos from simulation event logs containing NODE_POSITION data. Videos render node positions over time on a geographic map using Natural Earth coastline/border data and MATLAB's `geoplot`/`geoscatter` functions (no Mapping Toolbox dependency). The feature supports both the Dragon Cart Improved and Airdrop Mission scenarios, outputting videos to the existing `output/{scenario_name}/` directory structure.

## Glossary

- **Video_Generator**: The `io.MissionVideoGenerator` class responsible for parsing position data from event logs and rendering animated geographic video frames
- **Position_Log**: The subset of event log entries with eventType `NODE_POSITION`, each containing simTimeSec, nodeId, lat, lon, and altM fields
- **Frame_Renderer**: The component within Video_Generator that draws a single video frame using `geoplot` and `geoscatter` on a geographic axes with Natural Earth basemap data
- **Basemap_Provider**: The component that downloads and caches Natural Earth 110m coastline and admin-0 boundary GeoJSON data for use as the map background
- **Video_Writer**: MATLAB's `VideoWriter` configured with the `'MPEG-4'` profile for producing MP4 output files
- **Scenario_Runner**: The script or function that executes a simulation scenario with `positionUpdateIntervalSec` configured to produce position-enriched event logs

## Requirements

### Requirement 1: Position-Enriched Event Log Generation

**User Story:** As a simulation operator, I want to re-run scenarios with position tracking enabled, so that the event log contains the NODE_POSITION data needed for video generation.

#### Acceptance Criteria

1. WHEN the Scenario_Runner executes a scenario with `positionUpdateIntervalSec` set to a value greater than 0, THE SimController SHALL record NODE_POSITION events in the event log at intervals equal to `positionUpdateIntervalSec` seconds, starting at time `positionUpdateIntervalSec` and continuing up to but not including `simulationDurationSec`, for every node registered in the NodeRegistry
2. THE event log CSV SHALL represent each NODE_POSITION entry as a row with the columns: eventId (unique integer), simTimeSec (event timestamp in seconds), eventType (the string "NODE_POSITION"), linkId (the node identifier), msgId (latitude as a decimal string with 4 decimal places), srcNodeId (longitude as a decimal string with 4 decimal places), dstNodeId (altitude in metres as a decimal string with 1 decimal place), latencyMs (empty), and reason (empty)
3. WHEN the Dragon Cart Improved scenario is executed with `positionUpdateIntervalSec = 10`, THE Scenario_Runner SHALL produce an event log CSV file in `output/dragon_cart_improved/` containing NODE_POSITION entries at 10-second intervals from simTimeSec 10 through simTimeSec 7190 inclusive, yielding 719 distinct timestamps with one entry per node per timestamp (20 nodes × 719 timestamps = 14380 NODE_POSITION rows)
4. IF `positionUpdateIntervalSec` is set to 0 or is not specified, THEN THE SimController SHALL not schedule or record any NODE_POSITION events in the event log

### Requirement 2: Natural Earth Basemap Data Acquisition

**User Story:** As a video generator, I want to download and cache Natural Earth coastline and boundary data, so that geographic context is rendered without requiring the Mapping Toolbox.

#### Acceptance Criteria

1. WHEN the Basemap_Provider is initialized and no cached coastline file exists, THE Basemap_Provider SHALL download Natural Earth 110m coastline GeoJSON from the public Natural Earth GitHub repository using `webread` with a timeout of 30 seconds
2. WHEN the Basemap_Provider is initialized and no cached boundary file exists, THE Basemap_Provider SHALL download Natural Earth 110m admin-0 country boundary GeoJSON from the public Natural Earth GitHub repository using `webread` with a timeout of 30 seconds
3. IF the corresponding GeoJSON file already exists in the local `data/` directory, THEN THE Basemap_Provider SHALL load the cached file from disk instead of re-downloading
4. THE Basemap_Provider SHALL parse GeoJSON data using `jsondecode` and extract latitude and longitude coordinate arrays as numeric vectors, with polygon boundaries separated by NaN delimiters, suitable for passing directly to `geoplot`
5. IF a network error or timeout occurs during GeoJSON download, THEN THE Basemap_Provider SHALL return an error message including the URL that failed and the underlying error reason
6. IF a cached GeoJSON file exists but fails to parse via `jsondecode`, THEN THE Basemap_Provider SHALL delete the corrupted cache file and re-attempt the download

### Requirement 3: Geographic Frame Rendering

**User Story:** As a simulation analyst, I want each video frame to show node positions on a geographic map with coastlines, so that I can visually track node movement over time.

#### Acceptance Criteria

1. THE Frame_Renderer SHALL create a geographic axes using `geoaxes` and render coastline and boundary polygons using `geoplot` with the figure Visible property set to 'off'
2. THE Frame_Renderer SHALL render each node position as a marker using `geoscatter`, using a circle marker for Stationary nodes, a triangle marker for Mobile nodes with waypoint trajectories, and a pentagram marker for satellite nodes (Mobile nodes with keplerElements)
3. THE Frame_Renderer SHALL display node ID labels offset by 1 degree longitude to the right and 0.5 degrees latitude above each node marker, using a font size of 8 points
4. THE Frame_Renderer SHALL display the current simulation time (formatted as HH:MM:SS from elapsed simulation seconds) as a text annotation positioned in the top-right corner of the axes
5. THE Frame_Renderer SHALL set geographic axes latitude and longitude limits to encompass all node positions across the full simulation timeline, extended by a configurable padding margin that defaults to 2 degrees in each direction
6. WHEN a node has a waypoint trajectory, THE Frame_Renderer SHALL render the full planned trajectory path as a dashed line plotted beneath the current position marker in visual stacking order
7. THE Frame_Renderer SHALL render active communication links between connected nodes as lines, using a distinct color for each link type: one color for LEO_Satellite, one for GEO_Satellite, one for Fiber, and one for Line_Of_Sight, with a legend mapping each color to its link type
8. IF a node position cannot be computed for the current frame time, THEN THE Frame_Renderer SHALL omit that node from the frame without raising an error
9. THE Frame_Renderer SHALL include a legend identifying all rendered node type markers and link type colors

### Requirement 4: Video Assembly and Output

**User Story:** As a simulation operator, I want the video generator to produce a playable MP4 file from the rendered frames, so that I can review and share mission animations.

#### Acceptance Criteria

1. THE Video_Generator SHALL create an MP4 video file using `VideoWriter` with the `'MPEG-4'` profile
2. THE Video_Generator SHALL produce video at a configurable frame rate with a default of 30 frames per second
3. THE Video_Generator SHALL map simulation time to video time using a configurable speedup factor with a default of 60x (1 second of video represents 60 seconds of simulation time), such that the total number of video frames equals ceil((simulationDurationSec / speedupFactor) * frameRate)
4. WHEN video generation completes successfully, THE Video_Generator SHALL write the output MP4 file to `output/{scenario_name}/{ScenarioName}_mission_video.mp4`
5. THE Video_Generator SHALL produce video frames with a resolution of 1920x1080 pixels
6. WHEN video generation completes successfully, THE Video_Generator SHALL close the VideoWriter and release all figure resources
7. IF an error occurs during frame rendering or video writing, THEN THE Video_Generator SHALL close the VideoWriter, release all figure resources, delete any partially written output file, and return a descriptive error message indicating the frame number at which the failure occurred
8. THE Video_Generator SHALL write frames sequentially in ascending simulation time order, beginning at simulation time 0 and advancing by (speedupFactor / frameRate) seconds of simulation time per frame

### Requirement 5: Event Log Parsing for Position Data

**User Story:** As a video generator component, I want to parse NODE_POSITION events from CSV event logs, so that I can reconstruct node positions at each time step.

#### Acceptance Criteria

1. WHEN a CSV event log file path is provided, THE Video_Generator SHALL read the CSV file using the column header row (`eventId,simTimeSec,eventType,linkId,msgId,srcNodeId,dstNodeId,latencyMs,reason`) and parse all rows where the `eventType` column equals `NODE_POSITION` into a structured Position_Log, where each entry contains: nodeId (from the `linkId` column), lat (numeric, parsed from the `msgId` column), lon (numeric, parsed from the `srcNodeId` column), altM (numeric, parsed from the `dstNodeId` column), and simTimeSec (numeric, from the `simTimeSec` column)
2. IF the provided CSV file path does not exist or the file cannot be read, THEN THE Video_Generator SHALL return an error indicating the file path and the reason for the read failure
3. THE Video_Generator SHALL extract unique simulation timestamps from the Position_Log and sort them in ascending numerical order, producing a 1-by-N array of time step values where N is the count of distinct `simTimeSec` values across all parsed NODE_POSITION rows
4. THE Video_Generator SHALL group position entries by simulation timestamp to produce a complete node position snapshot for each time step, where each snapshot contains one entry per nodeId present at that timestamp
5. IF the event log contains zero rows where `eventType` equals `NODE_POSITION`, THEN THE Video_Generator SHALL return an error indicating that position data is missing and suggest re-running with `positionUpdateIntervalSec > 0`
6. IF any NODE_POSITION row contains a non-numeric value in the lat, lon, or altM fields, THEN THE Video_Generator SHALL skip that row and continue parsing the remaining rows

### Requirement 6: Scenario Execution Scripts

**User Story:** As a simulation operator, I want ready-to-run scripts that execute scenarios with position tracking and generate videos, so that I can produce mission videos with a single command.

#### Acceptance Criteria

1. THE Scenario_Runner SHALL provide a script `run_dragon_cart_video.m` in the project root that loads the Dragon Cart Improved scenario from `scenarios/dragon_cart/dragon_cart_improved.json` using `io.ScenarioLoader.load`, sets `positionUpdateIntervalSec = 10` on the SimController, runs the simulation, writes the event log CSV to `output/dragon_cart_improved/`, and invokes `io.MissionVideoGenerator` with the path to that event log CSV
2. THE Scenario_Runner SHALL provide a script `run_airdrop_video.m` in the project root that loads the Airdrop Mission scenario from `scenarios/airdrop_mission/airdrop_mission.json` using `io.ScenarioLoader.load`, sets `positionUpdateIntervalSec = 10` on the SimController, runs the simulation, writes the event log CSV to `output/airdrop_mission/`, and invokes `io.MissionVideoGenerator` with the path to that event log CSV
3. WHEN a scenario execution script completes successfully, THE Scenario_Runner SHALL print the absolute path of the generated MP4 file to the MATLAB command window using `fprintf`
4. IF the scenario file fails to load or the simulation encounters an error, THEN THE Scenario_Runner SHALL print an error message indicating the failure stage and reason to the MATLAB command window and terminate the script without invoking the Video_Generator
5. IF video generation fails after a successful simulation run, THEN THE Scenario_Runner SHALL print an error message indicating video generation failure and print the absolute path of the event log CSV that was produced

### Requirement 7: Video Generation Configuration

**User Story:** As a simulation operator, I want to configure video generation parameters, so that I can adjust output quality and playback speed for different use cases.

#### Acceptance Criteria

1. THE Video_Generator SHALL accept a configuration struct with optional fields: frameRate, speedupFactor, resolution, outputDir, and showLinks
2. WHEN a configuration field is omitted, THE Video_Generator SHALL use the following defaults: frameRate = 30, speedupFactor = 60, resolution = [1920 1080], outputDir = current working directory, showLinks = true
3. WHERE the showLinks option is set to false, THE Video_Generator SHALL omit communication link rendering from video frames
4. THE Video_Generator SHALL validate that frameRate is an integer in the range 1 to 120, speedupFactor is a number in the range 0.1 to 1000, and resolution is a 1x2 integer array where width is in the range 1 to 7680 and height is in the range 1 to 4320
5. IF an invalid configuration value is provided, THEN THE Video_Generator SHALL return an error that identifies the invalid field name and states the expected constraint for that field
6. IF the outputDir field specifies a path that does not exist or is not writable, THEN THE Video_Generator SHALL return an error identifying outputDir as the invalid field and indicating that the directory must exist and be writable

### Requirement 8: Integration with Existing Output Structure

**User Story:** As a project maintainer, I want the video generator to follow existing project conventions, so that outputs are organized consistently.

#### Acceptance Criteria

1. THE Video_Generator SHALL reside in the `+io` package as a classdef file named `MissionVideoGenerator.m`, accessible as `io.MissionVideoGenerator`
2. THE Video_Generator SHALL write the output video file to the `output/{scenario_name}/` directory, using the filename pattern `{ScenarioName}_mission_video.mp4` consistent with existing output naming conventions (e.g., `AirdropMission_mission_video.mp4`)
3. WHEN the output directory `output/{scenario_name}/` does not exist, THE Video_Generator SHALL create the directory and any required parent directories before writing the video file
4. IF the output directory cannot be created or the video file cannot be written, THEN THE Video_Generator SHALL throw a structured error with identifier `netsim:io:fileWriteError` and a message indicating the failing path
5. THE Video_Generator SHALL not depend on the Mapping Toolbox; geographic rendering SHALL use only `geoaxes`, `geoplot`, and `geoscatter` functions available in base MATLAB R2025b
6. THE Video_Generator SHALL accept `outputDir` and `scenarioName` as constructor arguments, matching the interface pattern used by `io.ReportWriter`
