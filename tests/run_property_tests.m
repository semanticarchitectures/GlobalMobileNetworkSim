%% run_property_tests.m
% Discovers and runs all property-based test files under the tests/
% directory tree.  Property-based test files match the patterns:
%   *PropTest.m  or  *PropertyTest.m
%
% Property-based tests use the matlab-prop-test library and are tagged
% with comments of the form:
%   % Feature: matlab-network-sim, Property N: <title>
%
% Usage (from the project root or the tests/ directory):
%   cd <project_root>
%   results = run_property_tests();
%
% Returns:
%   passed  - true if every property test passed, false otherwise

function passed = run_property_tests()

    % Locate the tests/ directory relative to this script.
    testsDir = fileparts(mfilename('fullpath'));

    % Add the project root to the path so packages are visible.
    projectRoot = fileparts(testsDir);
    addpath(projectRoot);

    % Discover property-based test files matching *PropTest.m or
    % *PropertyTest.m anywhere under tests/.
    propTestFiles = [
        dir(fullfile(testsDir, '**', '*PropTest.m'));
        dir(fullfile(testsDir, '**', '*PropertyTest.m'))
    ];

    if isempty(propTestFiles)
        warning('run_property_tests:noTestsFound', ...
            'No property-based test files found under: %s', testsDir);
        passed = true;
        return;
    end

    % Build a test suite from the discovered files.
    import matlab.unittest.TestSuite;
    import matlab.unittest.TestRunner;

    suite = matlab.unittest.TestSuite.fromFile(fullfile(propTestFiles(1).folder, propTestFiles(1).name));
    for k = 2:numel(propTestFiles)
        filePath = fullfile(propTestFiles(k).folder, propTestFiles(k).name);
        suite = [suite, TestSuite.fromFile(filePath)]; %#ok<AGROW>
    end

    % Run with verbose output.
    runner = TestRunner.withTextOutput('Verbosity', 2);
    results = runner.run(suite);

    % Summarise results.
    nTotal  = numel(results);
    nPassed = sum(~[results.Failed] & ~[results.Incomplete]);
    nFailed = sum([results.Failed]);
    nIncomplete = sum([results.Incomplete]);

    fprintf('\n=== Property Test Summary ===\n');
    fprintf('  Total:      %d\n', nTotal);
    fprintf('  Passed:     %d\n', nPassed);
    fprintf('  Failed:     %d\n', nFailed);
    fprintf('  Incomplete: %d\n', nIncomplete);
    fprintf('=============================\n\n');

    passed = (nFailed == 0) && (nIncomplete == 0);

    if ~passed
        error('run_property_tests:testsFailed', ...
            '%d property test(s) failed or were incomplete.', nFailed + nIncomplete);
    end

end
