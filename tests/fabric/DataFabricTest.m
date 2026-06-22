classdef DataFabricTest < matlab.unittest.TestCase
    % DATAFABRICTEST Comprehensive tests for the Data Fabric Layer.
    %
    % Tests cover:
    %   - DataCatalog add/get/remove/query operations
    %   - ProvenanceGraph lineage traversal with depth bounds
    %   - DataStoreRegistry.fromScenario
    %   - FabricEventHandler ingest and routing error
    %   - ReplicationEngine 'all' policy
    %   - Property-based: DataItem ID uniqueness (P34)
    %   - Property-based: Provenance depth bound (P38)
    %   - Benchmark: Catalog lookup < 0.1ms avg (Task 61)
    %   - Stats consistency (Task 62)

    properties
        TempDir     % Temporary directory for test artifacts
        ProjectRoot % Project root path
    end

    methods (TestClassSetup)
        function addProjectToPath(testCase)
            testCase.ProjectRoot = fileparts(fileparts(fileparts(mfilename('fullpath'))));
            addpath(testCase.ProjectRoot);
        end
    end

    methods (TestMethodSetup)
        function createTempDir(testCase)
            testCase.TempDir = fullfile(tempdir, ...
                ['DataFabricTest_' char(java.util.UUID.randomUUID().toString())]);
            mkdir(testCase.TempDir);
        end
    end

    methods (TestMethodTeardown)
        function removeTempDir(testCase)
            if isfolder(testCase.TempDir)
                rmdir(testCase.TempDir, 's');
            end
        end
    end

    % =====================================================================
    % Unit Tests
    % =====================================================================
    methods (Test)

        %% 1. testDataCatalogAddGet — add item, get it back, verify fields match
        function testDataCatalogAddGet(testCase)
            catalog = fabric.DataCatalog();
            s = testCase.makeItemStruct("item-001");
            s.classification = "SECRET";
            s.sizeBytes = 2048;
            item = fabric.DataItem(s);

            catalog.add(item);
            retrieved = catalog.get(item.id);

            testCase.verifyEqual(retrieved.id, item.id);
            testCase.verifyEqual(retrieved.classification, "SECRET");
            testCase.verifyEqual(retrieved.sizeBytes, 2048);
            testCase.verifyEqual(retrieved.dataItemType, s.dataItemType);
            testCase.verifyEqual(retrieved.creatorEntityId, s.creatorEntityId);
            testCase.verifyEqual(retrieved.creatorNodeId, s.creatorNodeId);
        end

        %% 2. testDataCatalogRemove — add then remove, verify count and exists
        function testDataCatalogRemove(testCase)
            catalog = fabric.DataCatalog();
            s = testCase.makeItemStruct("remove-item");
            item = fabric.DataItem(s);

            catalog.add(item);
            testCase.verifyEqual(catalog.count(), 1);
            testCase.verifyTrue(catalog.exists(item.id));

            catalog.remove(item.id);
            testCase.verifyEqual(catalog.count(), 0);
            testCase.verifyFalse(catalog.exists(item.id));
        end

        %% 3. testDataCatalogQuery — add 5 items with varied classifications, query by classification
        function testDataCatalogQuery(testCase)
            catalog = fabric.DataCatalog();
            classifications = ["SECRET", "UNCLASSIFIED", "SECRET", "TOP_SECRET", "UNCLASSIFIED"];

            for i = 1:5
                s = testCase.makeItemStruct(sprintf("query-item-%d", i));
                s.classification = classifications(i);
                item = fabric.DataItem(s);
                catalog.add(item);
            end

            % Query for SECRET items
            results = catalog.query(struct('classification', "SECRET"));
            testCase.verifyEqual(numel(results), 2);
            for i = 1:numel(results)
                testCase.verifyEqual(results(i).classification, "SECRET");
            end

            % Query for UNCLASSIFIED items
            results2 = catalog.query(struct('classification', "UNCLASSIFIED"));
            testCase.verifyEqual(numel(results2), 2);

            % Query for TOP_SECRET items
            results3 = catalog.query(struct('classification', "TOP_SECRET"));
            testCase.verifyEqual(numel(results3), 1);
        end

        %% 4. testProvenanceGraphLineage — create chain A->B->C, getLineage(C, 5) returns A and B
        function testProvenanceGraphLineage(testCase)
            pg = fabric.ProvenanceGraph();

            pg.addItem("A");
            pg.addItem("B");
            pg.addItem("C");
            pg.addDerivation("A", "B", "transform", 1.0);
            pg.addDerivation("B", "C", "aggregate", 2.0);

            ancestors = pg.getLineage("C", 5);

            % Should return both A and B
            testCase.verifyEqual(numel(ancestors), 2);
            ancestorIds = sort([ancestors.itemId]);
            testCase.verifyEqual(ancestorIds, sort(["A", "B"]));
        end

        %% 5. testProvenanceGraphDepthBound — create 5-level chain, getLineage(leaf, 2) returns only 2 ancestors
        function testProvenanceGraphDepthBound(testCase)
            pg = fabric.ProvenanceGraph();

            % Create chain: n1 -> n2 -> n3 -> n4 -> n5 -> n6
            nodeIds = strings(1, 6);
            for i = 1:6
                nodeIds(i) = sprintf("n%d", i);
                pg.addItem(nodeIds(i));
            end
            for i = 1:5
                pg.addDerivation(nodeIds(i), nodeIds(i+1), "step", double(i));
            end

            % getLineage of leaf (n6) with maxDepth=2 should return only 2 ancestors
            ancestors = pg.getLineage("n6", 2);
            testCase.verifyEqual(numel(ancestors), 2);

            % They should be n5 (depth 1) and n4 (depth 2)
            ancestorIds = sort([ancestors.itemId]);
            testCase.verifyEqual(ancestorIds, sort(["n4", "n5"]));
        end

        %% 6. testDataStoreRegistryFromScenario — build scenario with dataStore nodes, verify fromScenario populates
        function testDataStoreRegistryFromScenario(testCase)
            % Build a scenario struct with nodes, some are DataStores
            scenario.nodes = struct( ...
                'id', {"ds_alpha", "relay_1", "ds_beta"}, ...
                'dataStore', {true, false, true}, ...
                'dataStoreConfig', {struct('replicationPolicy', 'all'), struct(), struct('replicationPolicy', 'none')});

            reg = fabric.DataStoreRegistry.fromScenario(scenario);

            testCase.verifyTrue(reg.isDataStore("ds_alpha"));
            testCase.verifyFalse(reg.isDataStore("relay_1"));
            testCase.verifyTrue(reg.isDataStore("ds_beta"));
            testCase.verifyEqual(double(reg.count()), 2);
        end

        %% 7. testFabricHandlerIngest — create handler, ingest an item, verify catalog has it
        function testFabricHandlerIngest(testCase)
            reg = fabric.DataStoreRegistry();
            reg.register("store_1", struct());

            handler = fabric.FabricEventHandler(reg);
            ec = sim.EventCalendar();

            s = testCase.makeItemStruct("ingest-item");
            item = fabric.DataItem(s);

            % Build ingest event
            event.time = 10.0;
            event.type = sim.EventCalendar.DATA_INGEST;
            event.id = uint64(1);
            event.payload.dataItemId = item.id;
            event.payload.dataItemStruct = item.toStruct();
            event.payload.targetDataStoreId = "store_1";

            logEntry = handler.handleIngest(event, 10.0, ec);

            testCase.verifyEqual(logEntry.type, "data_ingest_complete");

            % Verify catalog has the item
            catalog = reg.getCatalog("store_1");
            testCase.verifyTrue(catalog.exists(item.id));
        end

        %% 8. testFabricHandlerRoutingError — ingest to non-DataStore, verify routing error returned
        function testFabricHandlerRoutingError(testCase)
            reg = fabric.DataStoreRegistry();
            reg.register("store_1", struct());

            handler = fabric.FabricEventHandler(reg);
            ec = sim.EventCalendar();

            s = testCase.makeItemStruct("bad-route-item");
            item = fabric.DataItem(s);

            % Build ingest event targeting a non-existent DataStore
            event.time = 5.0;
            event.type = sim.EventCalendar.DATA_INGEST;
            event.id = uint64(2);
            event.payload.dataItemId = item.id;
            event.payload.dataItemStruct = item.toStruct();
            event.payload.targetDataStoreId = "nonexistent_store";

            logEntry = handler.handleIngest(event, 5.0, ec);

            testCase.verifyEqual(logEntry.type, "data_routing_error");
            testCase.verifyEqual(logEntry.targetDataStoreId, "nonexistent_store");
        end

        %% 9. testReplicationAll — register 2 stores with 'all' policy, ingest to first, verify replicated to second
        function testReplicationAll(testCase)
            reg = fabric.DataStoreRegistry();
            cfg.replicationPolicy = "all";
            reg.register("store_A", cfg);
            reg.register("store_B", cfg);

            ec = sim.EventCalendar();
            engine = fabric.ReplicationEngine(reg, ec);

            handler = fabric.FabricEventHandler(reg);
            handler.setReplicationEngine(engine);

            % Ingest an item to store_A
            s = testCase.makeItemStruct("repl-item");
            item = fabric.DataItem(s);

            event.time = 20.0;
            event.type = sim.EventCalendar.DATA_INGEST;
            event.id = uint64(3);
            event.payload.dataItemId = item.id;
            event.payload.dataItemStruct = item.toStruct();
            event.payload.targetDataStoreId = "store_A";

            handler.handleIngest(event, 20.0, ec);

            % A DATA_REPLICATE event should be scheduled
            testCase.verifyFalse(ec.isEmpty(), ...
                'Replication event should be scheduled.');

            % Process the replicate event
            replEvent = ec.popNext();
            engine.handleReplicate(replEvent, 20.0);

            % Verify store_B now has the item
            catalogB = reg.getCatalog("store_B");
            testCase.verifyTrue(catalogB.exists(item.id));
        end

        %% 10. testDataItemIdUniqueness — generate 200 IDs, verify all unique (P34)
        function testDataItemIdUniqueness(testCase)
            % **Validates: Requirements P34**
            ids = strings(1, 200);
            for i = 1:200
                ids(i) = fabric.DataItem.generateId();
            end
            uniqueIds = unique(ids);
            testCase.verifyEqual(numel(uniqueIds), 200, ...
                'All 200 generated DataItem IDs must be unique.');
        end

        %% 11. testProvenanceDepthBound100Iterations — 100 random chains of depth 3-10, verify getLineage respects maxDepth (P38)
        function testProvenanceDepthBound100Iterations(testCase)
            % **Validates: Requirements P38**
            for iter = 1:100
                pg = fabric.ProvenanceGraph();

                % Random chain depth between 3 and 10
                chainDepth = randi([3, 10]);
                nodeIds = strings(1, chainDepth + 1);
                for i = 1:(chainDepth + 1)
                    nodeIds(i) = sprintf("iter%d_n%d", iter, i);
                    pg.addItem(nodeIds(i));
                end
                for i = 1:chainDepth
                    pg.addDerivation(nodeIds(i), nodeIds(i+1), "op", double(i));
                end

                % Query leaf with a random maxDepth between 1 and chainDepth
                maxDepth = randi([1, chainDepth]);
                leaf = nodeIds(end);
                ancestors = pg.getLineage(leaf, maxDepth);

                % Verify depth bound: no ancestor deeper than maxDepth
                for a = 1:numel(ancestors)
                    testCase.verifyLessThanOrEqual(ancestors(a).depth, maxDepth, ...
                        sprintf('Iter %d: ancestor depth %d exceeds maxDepth %d', ...
                        iter, ancestors(a).depth, maxDepth));
                end

                % Verify count: in a linear chain, should get exactly min(maxDepth, chainDepth) ancestors
                expectedCount = min(maxDepth, chainDepth);
                testCase.verifyEqual(numel(ancestors), expectedCount, ...
                    sprintf('Iter %d: expected %d ancestors, got %d (chain=%d, maxD=%d)', ...
                    iter, expectedCount, numel(ancestors), chainDepth, maxDepth));
            end
        end

        %% 12. testCatalogLookupBenchmark — add 10000 items, time 1000 random gets, verify avg < 0.1ms (Task 61)
        function testCatalogLookupBenchmark(testCase)
            catalog = fabric.DataCatalog();
            ids = strings(1, 10000);

            % Add 10000 items
            for i = 1:10000
                s = testCase.makeItemStruct(sprintf("bench-%05d", i));
                item = fabric.DataItem(s);
                catalog.add(item);
                ids(i) = item.id;
            end

            % Randomly select 1000 IDs to lookup
            randIndices = randi(10000, 1, 1000);

            % Time 1000 random gets
            tic;
            for i = 1:1000
                catalog.get(ids(randIndices(i)));
            end
            elapsed = toc;

            avgMs = (elapsed / 1000) * 1000;
            testCase.verifyLessThan(avgMs, 0.1, ...
                sprintf('Average get() time %.4f ms exceeds 0.1ms threshold.', avgMs));
        end

        %% 13. testFabricStatsConsistency — ingest items to 2 stores, build stats, verify totals match (Task 62)
        function testFabricStatsConsistency(testCase)
            reg = fabric.DataStoreRegistry();
            reg.register("ds_1", struct());
            reg.register("ds_2", struct());

            handler = fabric.FabricEventHandler(reg);
            ec = sim.EventCalendar();

            % Ingest 5 items to ds_1
            for i = 1:5
                s = testCase.makeItemStruct(sprintf("stats-ds1-%d", i));
                item = fabric.DataItem(s);
                event.time = double(i);
                event.type = sim.EventCalendar.DATA_INGEST;
                event.id = uint64(100 + i);
                event.payload.dataItemId = item.id;
                event.payload.dataItemStruct = item.toStruct();
                event.payload.targetDataStoreId = "ds_1";
                handler.handleIngest(event, double(i), ec);
            end

            % Ingest 3 items to ds_2
            for i = 1:3
                s = testCase.makeItemStruct(sprintf("stats-ds2-%d", i));
                item = fabric.DataItem(s);
                event.time = double(10 + i);
                event.type = sim.EventCalendar.DATA_INGEST;
                event.id = uint64(200 + i);
                event.payload.dataItemId = item.id;
                event.payload.dataItemStruct = item.toStruct();
                event.payload.targetDataStoreId = "ds_2";
                handler.handleIngest(event, double(10 + i), ec);
            end

            % Build stats: totalDataItems should equal sum of per-store counts
            catalog1 = reg.getCatalog("ds_1");
            catalog2 = reg.getCatalog("ds_2");

            perStoreTotal = catalog1.count() + catalog2.count();
            expectedTotal = 8;  % 5 + 3

            testCase.verifyEqual(perStoreTotal, expectedTotal, ...
                'Total items across stores should equal sum of ingests.');
            testCase.verifyEqual(handler.stats.totalIngested, 8, ...
                'Handler stats totalIngested should match total successful ingests.');
            testCase.verifyEqual(catalog1.count(), 5);
            testCase.verifyEqual(catalog2.count(), 3);
        end

    end

    % =====================================================================
    % Helper Methods
    % =====================================================================
    methods (Access = private, Static)
        function s = makeItemStruct(itemId)
            % MAKEITEMSTRUCT Create a minimal valid DataItem struct for testing.
            s.id = string(itemId);
            s.dataItemType = "sensor_telemetry";
            s.creatorEntityId = "entity_test";
            s.creatorNodeId = "node_test";
            s.creationTimeSec = 0.0;
            s.sizeBytes = 512;
            s.classification = "UNCLASSIFIED";
            s.enclaveId = "enclave_default";
            s.provenanceChain = struct('sourceItemId', {}, ...
                'sourceDataStoreId', {}, 'transformationType', {}, ...
                'transformationTimeSec', {});
        end
    end
end
