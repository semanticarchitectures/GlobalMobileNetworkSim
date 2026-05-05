classdef LLMClient < handle
    % LLMClient  HTTP client for OpenAI-compatible chat completions endpoints.
    %
    % Usage:
    %   config.baseUrl    = 'https://api.openai.com/v1';  % optional
    %   config.apiKey     = 'sk-...';                      % optional; falls back to env var
    %   config.model      = 'gpt-4o';                      % optional
    %   config.timeoutSec = 30;                            % optional
    %   config.maxTokens  = 2048;                          % optional
    %   client = agent.LLMClient(config)
    %
    %   response = client.complete(systemPrompt, userMessage)
    %   % response.content       — string
    %   % response.finishReason  — string
    %   % response.usageTokens   — struct with promptTokens, completionTokens, totalTokens
    %
    % Security:
    %   The API key is NEVER logged, displayed, or included in error messages.
    %
    % Requirements: 13.1, 13.2

    % ======================================================================
    % Private properties — apiKey is intentionally private to prevent exposure
    % ======================================================================
    properties (Access = private)
        apiKey_      (1,1) string = ""
        baseUrl_     (1,1) string = "https://api.openai.com/v1"
        model_       (1,1) string = "gpt-4o"
        timeoutSec_  (1,1) double = 30
        maxTokens_   (1,1) double = 2048
    end

    % ======================================================================
    % Constructor
    % ======================================================================
    methods

        function obj = LLMClient(config)
            % LLMClient  Construct an LLM client from an optional config struct.
            %
            %   client = agent.LLMClient()
            %   client = agent.LLMClient(config)
            %
            % Config fields (all optional):
            %   baseUrl    — API base URL (default: 'https://api.openai.com/v1')
            %   apiKey     — API key; if absent/empty, reads NETSIM_LLM_API_KEY env var
            %   model      — model name (default: 'gpt-4o')
            %   timeoutSec — HTTP timeout in seconds (default: 30)
            %   maxTokens  — max tokens in response (default: 2048)

            if nargin < 1 || isempty(config)
                config = struct();
            end

            % Apply config values, keeping defaults for missing fields
            if isfield(config, 'baseUrl') && ~isempty(config.baseUrl)
                obj.baseUrl_ = string(config.baseUrl);
            end

            if isfield(config, 'model') && ~isempty(config.model)
                obj.model_ = string(config.model);
            end

            if isfield(config, 'timeoutSec') && ~isempty(config.timeoutSec)
                obj.timeoutSec_ = double(config.timeoutSec);
            end

            if isfield(config, 'maxTokens') && ~isempty(config.maxTokens)
                obj.maxTokens_ = double(config.maxTokens);
            end

            % Resolve API key: config field takes precedence over env var.
            % NEVER log or display the key value.
            if isfield(config, 'apiKey') && ~isempty(config.apiKey) && strlength(string(config.apiKey)) > 0
                obj.apiKey_ = string(config.apiKey);
            else
                % Fall back to environment variable
                envKey = getenv('NETSIM_LLM_API_KEY');
                if ~isempty(envKey)
                    obj.apiKey_ = string(envKey);
                end
                % If still empty, apiKey_ remains "" — isConfigured() returns false
            end
        end

    end % constructor methods

    % ======================================================================
    % Public methods
    % ======================================================================
    methods (Access = public)

        function response = complete(obj, systemPrompt, userMessage)
            % complete  Send a chat completion request to the LLM endpoint.
            %
            %   response = client.complete(systemPrompt, userMessage)
            %
            % Parameters:
            %   systemPrompt — string: system role context
            %   userMessage  — string: user message content
            %
            % Returns struct with fields:
            %   content       — string: LLM response text
            %   finishReason  — string: stop reason from API
            %   usageTokens   — struct: promptTokens, completionTokens, totalTokens
            %
            % Throws netsim:agent:llmError on HTTP failure or missing API key.

            % Guard: require a configured API key before attempting any HTTP call
            if ~obj.isConfigured()
                error('netsim:agent:llmError', ...
                    'LLM API key is not configured. Set NETSIM_LLM_API_KEY or provide apiKey in config.');
            end

            % Build request URL
            url = char(obj.baseUrl_ + "/chat/completions");

            % Build messages array
            messages = struct();
            messages(1).role    = 'system';
            messages(1).content = char(systemPrompt);
            messages(2).role    = 'user';
            messages(2).content = char(userMessage);

            % Build request body struct (will be JSON-encoded by webwrite)
            body.model      = char(obj.model_);
            body.max_tokens = obj.maxTokens_;
            body.messages   = messages;

            % Build weboptions — API key in Authorization header only, never logged
            opts = weboptions( ...
                'MediaType',    'application/json', ...
                'Timeout',      obj.timeoutSec_, ...
                'HeaderFields', { ...
                    'Authorization', ['Bearer ' char(obj.apiKey_)]; ...
                    'Content-Type',  'application/json' ...
                });

            % Send request and handle errors
            try
                raw = webwrite(url, body, opts);
            catch ME
                % Extract HTTP status code and message without exposing the key
                statusCode   = obj.extractStatusCode_(ME);
                errorMessage = obj.sanitizeErrorMessage_(ME.message);
                error('netsim:agent:llmError', ...
                    'LLM API call failed (HTTP %d): %s', statusCode, errorMessage);
            end

            % Parse response
            response = obj.parseResponse_(raw);
        end

        function setApiKey(obj, key)
            % setApiKey  Inject an API key directly (for testing purposes).
            %
            %   client.setApiKey('test-key')
            %
            % The key value is stored privately and never logged.

            obj.apiKey_ = string(key);
        end

        function tf = isConfigured(obj)
            % isConfigured  Return true if an API key is available.
            %
            %   tf = client.isConfigured()

            tf = strlength(obj.apiKey_) > 0;
        end

    end % public methods

    % ======================================================================
    % Private helpers
    % ======================================================================
    methods (Access = private)

        function response = parseResponse_(~, raw)
            % parseResponse_  Extract content, finishReason, and usageTokens
            % from the raw API response struct returned by webwrite.

            % Extract first choice
            if ~isfield(raw, 'choices') || isempty(raw.choices)
                error('netsim:agent:llmError', ...
                    'LLM API call failed (HTTP 0): Response missing "choices" field');
            end

            choice = raw.choices(1);

            % Content
            if isfield(choice, 'message') && isfield(choice.message, 'content')
                content = string(choice.message.content);
            else
                content = "";
            end

            % Finish reason
            if isfield(choice, 'finish_reason')
                finishReason = string(choice.finish_reason);
            else
                finishReason = "";
            end

            % Usage tokens
            usageTokens.promptTokens     = 0;
            usageTokens.completionTokens = 0;
            usageTokens.totalTokens      = 0;

            if isfield(raw, 'usage')
                u = raw.usage;
                if isfield(u, 'prompt_tokens')
                    usageTokens.promptTokens = u.prompt_tokens;
                end
                if isfield(u, 'completion_tokens')
                    usageTokens.completionTokens = u.completion_tokens;
                end
                if isfield(u, 'total_tokens')
                    usageTokens.totalTokens = u.total_tokens;
                end
            end

            response.content      = content;
            response.finishReason = finishReason;
            response.usageTokens  = usageTokens;
        end

        function code = extractStatusCode_(~, ME)
            % extractStatusCode_  Try to extract an HTTP status code from a
            % MATLAB webwrite exception. Returns 0 if not determinable.

            code = 0;
            % MATLAB's webwrite throws MException with identifier
            % 'MATLAB:webservices:HTTP<code>StatusCodeError' or similar.
            % Try to parse the identifier or message for a 3-digit code.
            tokens = regexp(ME.identifier, '(\d{3})', 'tokens');
            if ~isempty(tokens)
                code = str2double(tokens{1}{1});
                return;
            end
            % Fall back to scanning the message
            tokens = regexp(ME.message, 'HTTP (\d{3})', 'tokens');
            if ~isempty(tokens)
                code = str2double(tokens{1}{1});
            end
        end

        function msg = sanitizeErrorMessage_(~, rawMsg)
            % sanitizeErrorMessage_  Return the error message with any
            % potential key-like tokens removed. The API key must never
            % appear in error output.
            %
            % We do not include the raw message verbatim because it may
            % contain request headers. Instead we return a safe summary.
            % Truncate to avoid leaking header content.
            if numel(rawMsg) > 200
                msg = rawMsg(1:200);
            else
                msg = rawMsg;
            end
            % Strip anything that looks like a Bearer token (sk-... or similar)
            msg = regexprep(msg, 'Bearer\s+\S+', 'Bearer [REDACTED]');
            msg = regexprep(msg, 'sk-[A-Za-z0-9\-_]+', '[REDACTED]');
        end

    end % private methods

end % classdef
