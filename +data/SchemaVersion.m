classdef SchemaVersion
    % SCHEMAVERSION Schema version constants and migration registry for
    % the SimulationStore HDF5 archive.
    %
    % The schema version uses a MAJOR.MINOR format:
    %   - MAJOR version changes indicate incompatible schema modifications
    %   - MINOR version changes indicate backward-compatible additions
    %
    % Migrations are registered to upgrade data from one version to another.
    %
    % Requirements: R30

    properties (Constant)
        % Current schema version
        CURRENT = "1.0"
    end

    methods (Static)
        function [major, minor] = parse(versionStr)
            % PARSE Parse a "MAJOR.MINOR" version string into numeric parts.
            %
            % Args:
            %   versionStr (string): Version string in "MAJOR.MINOR" format
            %
            % Returns:
            %   major (double): Major version number
            %   minor (double): Minor version number

            arguments
                versionStr (1,1) string
            end
            parts = split(versionStr, '.');
            major = str2double(parts(1));
            minor = str2double(parts(2));
        end

        function tf = isCompatible(fileVersion, currentVersion)
            % ISCOMPATIBLE Check if a file version is compatible with current.
            % Compatible means same major version.
            %
            % Args:
            %   fileVersion (string): Version from the archive file
            %   currentVersion (string): Version to compare against
            %
            % Returns:
            %   tf (logical): true if major versions match

            arguments
                fileVersion (1,1) string
                currentVersion (1,1) string
            end
            [fileMajor, ~] = data.SchemaVersion.parse(fileVersion);
            [curMajor, ~] = data.SchemaVersion.parse(currentVersion);
            tf = (fileMajor == curMajor);
        end

        function registry = getMigrationRegistry(newEntry)
            % GETMIGRATIONREGISTRY Access the shared migration registry.
            % Called with no args to read; called with a struct to append.
            persistent reg
            if isempty(reg)
                reg = struct('fromVersion', {}, 'toVersion', {}, 'migrationFn', {});
            end
            if nargin == 1
                reg(end+1) = newEntry;
            end
            registry = reg;
        end

        function registerMigration(fromVersion, toVersion, migrationFn)
            % REGISTERMIGRATION Register a migration function for upgrading
            % archive data from fromVersion to toVersion.
            %
            % Args:
            %   fromVersion (string): Source schema version (e.g., "1.0")
            %   toVersion (string): Target schema version (e.g., "1.1")
            %   migrationFn (function_handle): Function that accepts a
            %       SimulationStore handle and performs the migration.
            %
            % Example:
            %   data.SchemaVersion.registerMigration("1.0", "1.1", @myMigrationFn)

            arguments
                fromVersion (1,1) string
                toVersion (1,1) string
                migrationFn (1,1) function_handle
            end

            entry.fromVersion = fromVersion;
            entry.toVersion = toVersion;
            entry.migrationFn = migrationFn;
            data.SchemaVersion.getMigrationRegistry(entry);
        end

        function applyMigrations(store, fileVersion)
            % APPLYMIGRATIONS Apply all registered migrations to bring an
            % archive from fileVersion to the current version.
            %
            % Args:
            %   store (data.SimulationStore): The store handle to migrate
            %   fileVersion (string): The schema version currently in the file

            arguments
                store
                fileVersion (1,1) string
            end

            currentVersion = data.SchemaVersion.CURRENT;

            % Parse versions
            [fileMajor, fileMinor] = data.SchemaVersion.parse(fileVersion);
            [curMajor, curMinor] = data.SchemaVersion.parse(currentVersion);

            % Major version mismatch is fatal
            if fileMajor ~= curMajor
                error('netsim:data:schemaMajorVersionMismatch', ...
                    'Archive has schema major version %d but current is %d (file: %s, current: %s).', ...
                    fileMajor, curMajor, fileVersion, currentVersion);
            end

            % If file is already current, nothing to do
            if fileMinor >= curMinor
                return;
            end

            % Get migrations from shared registry and apply in order
            registry = data.SchemaVersion.getMigrationRegistry();

            version = fileVersion;
            while ~strcmp(version, currentVersion)
                applied = false;
                for i = 1:numel(registry)
                    if strcmp(registry(i).fromVersion, version)
                        registry(i).migrationFn(store);
                        version = registry(i).toVersion;
                        applied = true;
                        break;
                    end
                end
                if ~applied
                    warning('netsim:data:noMigrationPath', ...
                        'No migration registered from version %s. Stopping migration.', version);
                    break;
                end
            end

            % Update the schema version attribute in the file
            if ~strcmp(version, fileVersion)
                h5writeatt(store.ArchivePath, '/', 'schemaVersion', char(version));
            end
        end
    end
end
