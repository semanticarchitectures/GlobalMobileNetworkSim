%% run_all_tests.m
% Discovers and runs all matlab.unittest.TestCase files under the tests/
% directory tree.  Returns a logical indicating overall pass/fail and
% prints a summary to the command window.
%
% Usage (from the project root or the tests/ directory):
%   cd <project_root>
%   results = run_all_tests();
%
% Returns:
%   passed  - true if every test passed, false otherwise

function passed = run_all_tests()

    % Locate the tests/ directory relative to this script.
    testsDir = fileparts(mfilename('fullpath'));

    % Add the project root (parent of tests/) to the path so that the
    % +sim, +network, +agent, and +io packages are visible.
    projectRoot = fileparts(testsDir);
    addpath(projectRoot);

    % Build a test suite by recursively discovering all TestCase subclasses
    % under the tests/ directory.
    import matlab.unittest.TestSuite;
    import matlab.unittest.TestRunner;

    suite = TestSuite.fromFolder(testsDir, 'IncludingSubfolders', true);

    if isempty(suite)
        warning('run_all_tests:noTestsFound', ...
            'No matlab.unittest.TestCase files found under: %s', testsDir);
        passed = true;
        return;
    end

    % Run the suite with a verbose text reporter.
    runner = TestRunner.withTextOutput('Verbosity', 2);
    results = runner.run(suite);

    % Summarise results.
    nTotal  = numel(results);
    nPassed = sum(~[results.Failed] & ~[results.Incomplete]);
    nFailed = sum([results.Failed]);
    nIncomplete = sum([results.Incomplete]);

    fprintf('\n=== Test Summary ===\n');
    fprintf('  Total:      %d\n', nTotal);
    fprintf('  Passed:     %d\n', nPassed);
    fprintf('  Failed:     %d\n', nFailed);
    fprintf('  Incomplete: %d\n', nIncomplete);
    fprintf('====================\n\n');

    passed = (nFailed == 0) && (nIncomplete == 0);

    if ~passed
        error('run_all_tests:testsFailed', ...
            '%d test(s) failed or were incomplete.', nFailed + nIncomplete);
    end

end
