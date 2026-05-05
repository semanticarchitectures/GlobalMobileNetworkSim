classdef MockLLMClientImpl < agent.LLMClient
    % MockLLMClientImpl  Test double for agent.LLMClient.
    %
    % Overrides complete() to return a canned response without making any
    % HTTP call, allowing AgentRegistry tests to run without a live LLM
    % endpoint.

    methods
        function response = complete(~, ~, ~)
            % Return a minimal canned response struct.
            response.content      = "Acknowledged. Proceeding with mission.";
            response.finishReason = "stop";
            response.usageTokens  = struct( ...
                'promptTokens', 10, ...
                'completionTokens', 8, ...
                'totalTokens', 18);
        end
    end
end
