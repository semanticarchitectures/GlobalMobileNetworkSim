classdef MockLLMClient < handle
    % MockLLMClient  Minimal mock for agent.LLMClient used in unit tests.
    %
    % Returns a canned response from complete() without making any HTTP call,
    % allowing AgentRegistry and other agent tests to run without a live LLM
    % endpoint.
    %
    % Usage:
    %   llm = MockLLMClient();
    %   response = llm.complete(systemPrompt, userMessage);
    %
    % The CannedContent property can be overridden before calling complete()
    % to simulate different LLM responses.

    properties
        CannedContent = '- ACKNOWLEDGE\n- SEND_STATUS'
    end

    methods

        function response = complete(obj, ~, ~)
            % complete  Return a canned response struct without any HTTP call.
            %
            %   response = llm.complete(systemPrompt, userMessage)
            %
            % Returns:
            %   response.content       — string (from CannedContent)
            %   response.finishReason  — 'stop'
            %   response.usageTokens   — struct with token counts

            response.content      = obj.CannedContent;
            response.finishReason = 'stop';
            response.usageTokens  = struct( ...
                'promptTokens',     10, ...
                'completionTokens', 5, ...
                'totalTokens',      15);
        end

        function tf = isConfigured(~)
            % isConfigured  Always returns true for the mock client.
            tf = true;
        end

    end

end
