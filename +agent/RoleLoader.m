classdef RoleLoader
    % RoleLoader  Static utility for loading Role_Definition Markdown files.
    %
    % Usage:
    %   role = agent.RoleLoader.load(filePath)
    %
    % Returns a struct with fields:
    %   name         — role name extracted from the first H1 heading
    %   sourceRef    — the file path supplied to load()
    %   fullMarkdown — complete file content as a string
    %
    % Errors (identifier: netsim:agent:roleLoadError):
    %   - File does not exist or cannot be read
    %   - File is empty
    %   - No H1 heading found in the file
    %
    % Requirements: 11.1, 11.2, 11.3, 11.4

    methods (Static)

        function role = load(filePath)
            % load  Load and validate a Role_Definition Markdown file.
            %
            %   role = agent.RoleLoader.load(filePath)
            %
            % Parameters:
            %   filePath — path to the Markdown role definition file
            %
            % Returns:
            %   role.name         — role name (text after "# " on first H1 line)
            %   role.sourceRef    — filePath as supplied
            %   role.fullMarkdown — complete file content

            % ------------------------------------------------------------------
            % 1. Validate the file exists and is readable
            % ------------------------------------------------------------------
            if ~isfile(filePath)
                error('netsim:agent:roleLoadError', ...
                    'Cannot read role definition file: %s', filePath);
            end

            % Attempt to open the file to confirm read access
            fid = fopen(filePath, 'r');
            if fid == -1
                error('netsim:agent:roleLoadError', ...
                    'Cannot read role definition file: %s', filePath);
            end
            fclose(fid);

            % ------------------------------------------------------------------
            % 2. Read the full file content
            % ------------------------------------------------------------------
            content = fileread(filePath);

            % ------------------------------------------------------------------
            % 3. Validate the content is non-empty
            % ------------------------------------------------------------------
            if isempty(strtrim(content))
                error('netsim:agent:roleLoadError', ...
                    'Role definition file is empty: %s', filePath);
            end

            % ------------------------------------------------------------------
            % 4. Extract the role name from the first H1 heading
            % ------------------------------------------------------------------
            % Split content into lines (handle \r\n, \n, \r)
            lines = strsplit(content, {'\r\n', '\n', '\r'});

            roleName = '';
            for i = 1:numel(lines)
                line = lines{i};
                % Match a line that starts with "# " (H1 heading)
                if numel(line) >= 3 && strcmp(line(1:2), '# ')
                    roleName = strtrim(line(3:end));
                    break;
                end
            end

            if isempty(roleName)
                error('netsim:agent:roleLoadError', ...
                    'No H1 heading found in role definition file: %s', filePath);
            end

            % ------------------------------------------------------------------
            % 5. Build and return the result struct
            % ------------------------------------------------------------------
            role.name         = string(roleName);
            role.sourceRef    = string(filePath);
            role.fullMarkdown = string(content);
        end

    end % methods (Static)

end % classdef
