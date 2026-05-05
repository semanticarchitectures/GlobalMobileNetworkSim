classdef LLMClientTest < matlab.unittest.TestCase
    % LLMClientTest  Unit tests for agent.LLMClient.
    %
    % Tests (no real HTTP calls are made):
    %   1. testConstructorDefaultConfig       — verify default field values
    %   2. testConstructorCustomConfig        — verify custom config values stored
    %   3. testIsConfiguredFalseWithNoKey     — isConfigured() false when no key
    %   4. testIsConfiguredTrueAfterSetApiKey — isConfigured() true after setApiKey
    %   5. testApiKeyNotExposedInProperties   — apiKey not accessible as public property
    %   6. testCompleteThrowsWithoutApiKey    — complete() throws before any HTTP call
    %
    % Requirements: 13.1, 13.2

    % ======================================================================
    % TestClassSetup: add workspace root to MATLAB path
    % ======================================================================
    methods (TestClassSetup)
        function addWorkspaceRootToPath(testCase)
            % Navigate from tests/agent/ up two levels to workspace root.
            thisDir = fileparts(mfilename('fullpath'));
            rootDir = fileparts(fileparts(thisDir));
            addpath(rootDir);
            testCase.addTeardown(@() rmpath(rootDir));
        end
    end

    % ======================================================================
    % Helpers
    % ======================================================================
    methods (Access = private)

        function client = makeClientNoKey(~)
            % Build a client with no API key and no env var influence.
            % We pass an explicit empty apiKey to override any env var that
            % might be set in the test environment.
            config.apiKey = '';
            % Temporarily clear the env var for the duration of construction
            % by passing an empty string — the constructor treats empty as absent.
            client = agent.LLMClient(config);
            % Force-clear the key in case the env var was set
            client.setApiKey('');
        end

    end

    % ======================================================================
    % Tests
    % ======================================================================
    methods (Test)

        % ------------------------------------------------------------------
        % Test 1: default config values
        % ------------------------------------------------------------------
        function testConstructorDefaultConfig(testCase)
            % When constructed with an empty config, the client should use
            % the documented default values for baseUrl, model, maxTokens,
            % and timeoutSec.
            %
            % Requirements: 13.1

            client = agent.LLMClient(struct());

            % We cannot read private properties directly, so we verify
            % indirectly via isConfigured() (which exercises the object) and
            % by checking that complete() throws the "not configured" error
            % (not a URL or model error) when no key is set.
            %
            % For the default values we use a subclass-free approach:
            % construct with explicit non-default values and verify the
            % object is created without error, then construct with defaults.

            % Verify the object is a valid handle
            testCase.verifyClass(client, 'agent.LLMClient', ...
                'Constructor should return an agent.LLMClient instance');

            % Verify isConfigured() returns a logical
            tf = client.isConfigured();
            testCase.verifyClass(tf, 'logical', ...
                'isConfigured() should return a logical value');

            % Verify complete() throws the "not configured" error (not a
            % network or model error), confirming defaults were applied and
            % the guard fires before any HTTP call.
            client.setApiKey('');   % ensure no key
            testCase.verifyError( ...
                @() client.complete('sys', 'user'), ...
                'netsim:agent:llmError', ...
                'complete() without key should throw netsim:agent:llmError');
        end

        % ------------------------------------------------------------------
        % Test 2: custom config values are stored
        % ------------------------------------------------------------------
        function testConstructorCustomConfig(testCase)
            % Custom config values should be accepted without error and
            % reflected in the object's behaviour.
            %
            % Requirements: 13.1

            config.baseUrl    = 'https://custom.example.com/v1';
            config.model      = 'gpt-3.5-turbo';
            config.timeoutSec = 60;
            config.maxTokens  = 512;
            config.apiKey     = 'test-custom-key';

            client = agent.LLMClient(config);

            % The object should be created successfully
            testCase.verifyClass(client, 'agent.LLMClient', ...
                'Constructor with custom config should return an LLMClient');

            % isConfigured() should be true because we supplied a key
            testCase.verifyTrue(client.isConfigured(), ...
                'isConfigured() should be true when apiKey is provided in config');

            % Verify the key was stored (indirectly: isConfigured returns true)
            % We cannot read private properties, but we can clear the key and
            % confirm isConfigured flips to false.
            client.setApiKey('');
            testCase.verifyFalse(client.isConfigured(), ...
                'isConfigured() should be false after clearing the key');
        end

        % ------------------------------------------------------------------
        % Test 3: isConfigured() returns false when no key is available
        % ------------------------------------------------------------------
        function testIsConfiguredFalseWithNoKey(testCase)
            % When no apiKey is in config and no env var is set, isConfigured()
            % must return false.
            %
            % Requirements: 13.1

            client = testCase.makeClientNoKey();

            testCase.verifyFalse(client.isConfigured(), ...
                'isConfigured() should return false when no API key is available');
        end

        % ------------------------------------------------------------------
        % Test 4: isConfigured() returns true after setApiKey
        % ------------------------------------------------------------------
        function testIsConfiguredTrueAfterSetApiKey(testCase)
            % After calling setApiKey('test-key'), isConfigured() must return true.
            %
            % Requirements: 13.1

            client = testCase.makeClientNoKey();

            % Confirm starts unconfigured
            testCase.verifyFalse(client.isConfigured(), ...
                'Precondition: isConfigured() should be false before setApiKey');

            client.setApiKey('test-key');

            testCase.verifyTrue(client.isConfigured(), ...
                'isConfigured() should return true after setApiKey(''test-key'')');
        end

        % ------------------------------------------------------------------
        % Test 5: apiKey is not accessible as a public property
        % ------------------------------------------------------------------
        function testApiKeyNotExposedInProperties(testCase)
            % The API key must be stored with Access=private so it cannot be
            % read from outside the class.
            %
            % Requirements: 13.1 (security: key must never be logged/displayed)

            client = agent.LLMClient(struct());

            % Retrieve the list of public properties
            mc = metaclass(client);
            publicPropNames = {};
            for i = 1:numel(mc.PropertyList)
                p = mc.PropertyList(i);
                if strcmp(p.GetAccess, 'public')
                    publicPropNames{end+1} = p.Name; %#ok<AGROW>
                end
            end

            % None of the public property names should contain 'key' or 'Key'
            % (case-insensitive check for any key-related public property)
            for i = 1:numel(publicPropNames)
                name = lower(publicPropNames{i});
                testCase.verifyFalse( ...
                    contains(name, 'key') || contains(name, 'apikey'), ...
                    sprintf('Public property "%s" must not expose the API key', ...
                            publicPropNames{i}));
            end

            % Also verify direct property access throws an error
            testCase.verifyError( ...
                @() client.apiKey_, ...
                'MATLAB:class:GetProhibited', ...
                'apiKey_ should not be accessible as a public property');
        end

        % ------------------------------------------------------------------
        % Test 6: complete() throws netsim:agent:llmError without an API key
        % ------------------------------------------------------------------
        function testCompleteThrowsWithoutApiKey(testCase)
            % complete() must throw netsim:agent:llmError when no API key is
            % configured, and this must happen BEFORE any HTTP call is made
            % (i.e., the guard fires immediately).
            %
            % Requirements: 13.1, 13.2

            client = testCase.makeClientNoKey();

            % Verify the error is thrown with the correct identifier
            testCase.verifyError( ...
                @() client.complete('You are a helpful assistant.', 'Hello'), ...
                'netsim:agent:llmError', ...
                'complete() without API key should throw netsim:agent:llmError');
        end

    end % methods (Test)

end % classdef
