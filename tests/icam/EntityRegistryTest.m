classdef EntityRegistryTest < matlab.unittest.TestCase
    % EntityRegistryTest  Unit tests for icam.EntityRegistry.
    %
    % Covers:
    %   1. Construction with valid entities succeeds
    %   2. Unknown nodeId throws netsim:icam:unknownNode
    %   3. Duplicate entityId throws netsim:icam:duplicateEntityId
    %   4. getSubEntities returns all entities for a node
    %   5. indexOf returns correct index; throws for unknown ID
    %   6. count returns correct total
    %
    % Requirements: 17.1, 17.2, 17.3, 17.4, 17.5

    % ======================================================================
    % Shared fixtures
    % ======================================================================
    methods (Access = private)

        function nr = makeNodeRegistry(~, varargin)
            % Build a NodeRegistry with one or more stationary nodes.
            % Usage: makeNodeRegistry('N1', 'N2', ...)
            nodeIds = varargin;
            nNodes = numel(nodeIds);
            nodes(nNodes) = struct();
            for k = 1:nNodes
                nodes(k).id            = nodeIds{k};
                nodes(k).type          = 'Stationary';
                nodes(k).lat           = 0;
                nodes(k).lon           = 0;
                nodes(k).altM          = 0;
                nodes(k).trajectory    = [];
                nodes(k).keplerElements = [];
            end
            nr = network.NodeRegistry(nodes);
        end

        function def = makeEntityDef(~, id, nodeId, type)
            % Build a minimal entity definition struct.
            def.id     = id;
            def.nodeId = nodeId;
            def.type   = type;
        end

    end

    % ======================================================================
    % Test 1: Construction with valid entities succeeds
    % ======================================================================
    methods (Test)

        function testConstructionWithValidEntities(testCase)
            % Construction with valid entity definitions referencing existing
            % nodes should succeed without error.
            %
            % Requirements: 17.1, 17.2

            nr = testCase.makeNodeRegistry('N1', 'N2');

            defs(1) = testCase.makeEntityDef('E1', 'N1', 'human');
            defs(2) = testCase.makeEntityDef('E2', 'N2', 'NPE');

            er = icam.EntityRegistry(defs, nr);

            testCase.verifyEqual(er.count(), 2, ...
                'Registry should contain 2 entities after construction');
        end

        function testConstructionWithEmptyDefs(testCase)
            % Construction with empty entity definitions should produce an
            % empty registry with count() == 0.
            %
            % Requirements: 17.1

            nr = testCase.makeNodeRegistry('N1');
            er = icam.EntityRegistry([], nr);

            testCase.verifyEqual(er.count(), 0, ...
                'Empty defs should produce count() == 0');
        end

        function testConstructionWithOptionalFields(testCase)
            % Construction with optional parentEntityId and enclaveIds fields
            % should succeed and store the values correctly.
            %
            % Requirements: 17.1, 17.2

            nr = testCase.makeNodeRegistry('N1');

            def.id             = 'E1';
            def.nodeId         = 'N1';
            def.type           = 'human';
            def.parentEntityId = '';
            def.enclaveIds     = {'enclave-alpha', 'enclave-bravo'};

            er = icam.EntityRegistry(def, nr);

            entity = er.getEntity('E1');
            testCase.verifyEqual(numel(entity.enclaveIds), 2, ...
                'Entity should have 2 enclave IDs');
        end

        % ------------------------------------------------------------------
        % Test 2: Unknown nodeId throws netsim:icam:unknownNode
        % ------------------------------------------------------------------

        function testUnknownNodeIdThrows(testCase)
            % An entity definition referencing a node that does not exist in
            % the NodeRegistry should throw netsim:icam:unknownNode.
            %
            % Requirements: 17.4

            nr = testCase.makeNodeRegistry('N1');

            def = testCase.makeEntityDef('E1', 'NONEXISTENT_NODE', 'human');

            testCase.verifyError( ...
                @() icam.EntityRegistry(def, nr), ...
                'netsim:icam:unknownNode', ...
                'Unknown nodeId should throw netsim:icam:unknownNode');
        end

        function testUnknownNodeIdErrorMentionsEntityAndNode(testCase)
            % The error message for an unknown nodeId should mention both the
            % entity ID and the missing node ID.
            %
            % Requirements: 17.4

            nr = testCase.makeNodeRegistry('N1');
            def = testCase.makeEntityDef('MyEntity', 'MissingNode', 'human');

            try
                icam.EntityRegistry(def, nr);
                testCase.verifyFail('Expected netsim:icam:unknownNode to be thrown');
            catch ME
                testCase.verifyEqual(ME.identifier, 'netsim:icam:unknownNode');
                testCase.verifyTrue( ...
                    contains(ME.message, 'MyEntity'), ...
                    'Error message should mention the entity ID');
                testCase.verifyTrue( ...
                    contains(ME.message, 'MissingNode'), ...
                    'Error message should mention the missing node ID');
            end
        end

        % ------------------------------------------------------------------
        % Test 3: Duplicate entityId throws netsim:icam:duplicateEntityId
        % ------------------------------------------------------------------

        function testDuplicateEntityIdThrows(testCase)
            % Two entity definitions with the same ID should throw
            % netsim:icam:duplicateEntityId.
            %
            % Requirements: 17.3

            nr = testCase.makeNodeRegistry('N1', 'N2');

            defs(1) = testCase.makeEntityDef('SAME_ID', 'N1', 'human');
            defs(2) = testCase.makeEntityDef('SAME_ID', 'N2', 'NPE');

            testCase.verifyError( ...
                @() icam.EntityRegistry(defs, nr), ...
                'netsim:icam:duplicateEntityId', ...
                'Duplicate entityId should throw netsim:icam:duplicateEntityId');
        end

        function testAddEntityDuplicateThrows(testCase)
            % addEntity with a duplicate ID should throw
            % netsim:icam:duplicateEntityId.
            %
            % Requirements: 17.3

            nr = testCase.makeNodeRegistry('N1');
            def = testCase.makeEntityDef('E1', 'N1', 'human');
            er = icam.EntityRegistry(def, nr);

            % Try to add the same ID again
            def2.id     = 'E1';
            def2.nodeId = 'N1';
            def2.type   = 'NPE';

            testCase.verifyError( ...
                @() er.addEntity(def2), ...
                'netsim:icam:duplicateEntityId', ...
                'addEntity with duplicate ID should throw netsim:icam:duplicateEntityId');
        end

        % ------------------------------------------------------------------
        % Test 4: getSubEntities returns all entities for a node
        % ------------------------------------------------------------------

        function testGetSubEntitiesReturnsAllForNode(testCase)
            % getSubEntities should return all and only entities whose nodeId
            % matches the given nodeId.
            %
            % Requirements: 17.2

            nr = testCase.makeNodeRegistry('N1', 'N2');

            defs(1) = testCase.makeEntityDef('E1', 'N1', 'human');
            defs(2) = testCase.makeEntityDef('E2', 'N1', 'NPE');
            defs(3) = testCase.makeEntityDef('E3', 'N2', 'human');

            er = icam.EntityRegistry(defs, nr);

            subN1 = er.getSubEntities('N1');
            testCase.verifyEqual(numel(subN1), 2, ...
                'N1 should have 2 sub-entities');

            ids = [subN1(1).entityId, subN1(2).entityId];
            testCase.verifyTrue(any(ids == "E1"), ...
                'E1 should be in N1 sub-entities');
            testCase.verifyTrue(any(ids == "E2"), ...
                'E2 should be in N1 sub-entities');
        end

        function testGetSubEntitiesReturnsEmptyForUnknownNode(testCase)
            % getSubEntities for a node with no entities should return an
            % empty struct array.
            %
            % Requirements: 17.2

            nr = testCase.makeNodeRegistry('N1', 'N2');
            def = testCase.makeEntityDef('E1', 'N1', 'human');
            er = icam.EntityRegistry(def, nr);

            subN2 = er.getSubEntities('N2');
            testCase.verifyEqual(numel(subN2), 0, ...
                'Node with no entities should return empty struct array');
        end

        function testGetSubEntitiesExcludesOtherNodes(testCase)
            % getSubEntities for N1 should not include entities from N2.
            %
            % Requirements: 17.2

            nr = testCase.makeNodeRegistry('N1', 'N2');

            defs(1) = testCase.makeEntityDef('E1', 'N1', 'human');
            defs(2) = testCase.makeEntityDef('E2', 'N2', 'NPE');

            er = icam.EntityRegistry(defs, nr);

            subN1 = er.getSubEntities('N1');
            testCase.verifyEqual(numel(subN1), 1, ...
                'N1 should have exactly 1 sub-entity');
            testCase.verifyEqual(char(subN1(1).entityId), 'E1', ...
                'The single N1 entity should be E1');
        end

        % ------------------------------------------------------------------
        % Test 5: indexOf returns correct index; throws for unknown ID
        % ------------------------------------------------------------------

        function testIndexOfReturnsCorrectIndex(testCase)
            % indexOf should return the 1-based index of the entity in the
            % internal struct-of-arrays.
            %
            % Requirements: 17.3

            nr = testCase.makeNodeRegistry('N1');

            defs(1) = testCase.makeEntityDef('A', 'N1', 'human');
            defs(2) = testCase.makeEntityDef('B', 'N1', 'NPE');
            defs(3) = testCase.makeEntityDef('C', 'N1', 'human');

            er = icam.EntityRegistry(defs, nr);

            testCase.verifyEqual(er.indexOf('A'), 1, 'indexOf("A") should be 1');
            testCase.verifyEqual(er.indexOf('B'), 2, 'indexOf("B") should be 2');
            testCase.verifyEqual(er.indexOf('C'), 3, 'indexOf("C") should be 3');
        end

        function testIndexOfThrowsForUnknownId(testCase)
            % indexOf should throw netsim:icam:unknownEntity for an unknown ID.
            %
            % Requirements: 17.3

            nr = testCase.makeNodeRegistry('N1');
            def = testCase.makeEntityDef('E1', 'N1', 'human');
            er = icam.EntityRegistry(def, nr);

            testCase.verifyError( ...
                @() er.indexOf('NONEXISTENT'), ...
                'netsim:icam:unknownEntity', ...
                'indexOf should throw netsim:icam:unknownEntity for unknown ID');
        end

        function testGetEntityThrowsForUnknownId(testCase)
            % getEntity should throw netsim:icam:unknownEntity for an unknown ID.
            %
            % Requirements: 17.3

            nr = testCase.makeNodeRegistry('N1');
            def = testCase.makeEntityDef('E1', 'N1', 'human');
            er = icam.EntityRegistry(def, nr);

            testCase.verifyError( ...
                @() er.getEntity('NONEXISTENT'), ...
                'netsim:icam:unknownEntity', ...
                'getEntity should throw netsim:icam:unknownEntity for unknown ID');
        end

        % ------------------------------------------------------------------
        % Test 6: count returns correct total
        % ------------------------------------------------------------------

        function testCountReturnsCorrectTotal(testCase)
            % count() should return the total number of entities in the registry.
            %
            % Requirements: 17.5

            nr = testCase.makeNodeRegistry('N1', 'N2');

            defs(1) = testCase.makeEntityDef('E1', 'N1', 'human');
            defs(2) = testCase.makeEntityDef('E2', 'N1', 'NPE');
            defs(3) = testCase.makeEntityDef('E3', 'N2', 'human');

            er = icam.EntityRegistry(defs, nr);

            testCase.verifyEqual(er.count(), 3, ...
                'count() should return 3 for 3 entities');
        end

        function testCountIncreasesAfterAddEntity(testCase)
            % count() should increase by 1 after addEntity.
            %
            % Requirements: 17.5

            nr = testCase.makeNodeRegistry('N1');
            def = testCase.makeEntityDef('E1', 'N1', 'human');
            er = icam.EntityRegistry(def, nr);

            testCase.verifyEqual(er.count(), 1, 'Initial count should be 1');

            def2.id     = 'E2';
            def2.nodeId = 'N1';
            def2.type   = 'NPE';
            er.addEntity(def2);

            testCase.verifyEqual(er.count(), 2, 'Count should be 2 after addEntity');
        end

        % ------------------------------------------------------------------
        % Additional: getEntityIds
        % ------------------------------------------------------------------

        function testGetEntityIdsReturnsAllIds(testCase)
            % getEntityIds should return a string array of all entity IDs.
            %
            % Requirements: 17.1

            nr = testCase.makeNodeRegistry('N1');

            defs(1) = testCase.makeEntityDef('Alpha', 'N1', 'human');
            defs(2) = testCase.makeEntityDef('Beta',  'N1', 'NPE');

            er = icam.EntityRegistry(defs, nr);
            ids = er.getEntityIds();

            testCase.verifyEqual(numel(ids), 2, 'Should return 2 IDs');
            testCase.verifyTrue(any(ids == "Alpha"), 'Alpha should be in IDs');
            testCase.verifyTrue(any(ids == "Beta"),  'Beta should be in IDs');
        end

        function testGetEntityReturnsCorrectFields(testCase)
            % getEntity should return a struct with all required fields.
            %
            % Requirements: 17.1

            nr = testCase.makeNodeRegistry('N1');

            def.id             = 'E1';
            def.nodeId         = 'N1';
            def.type           = 'human';
            def.parentEntityId = 'PARENT';
            def.enclaveIds     = {'enc1'};

            er = icam.EntityRegistry(def, nr);
            entity = er.getEntity('E1');

            testCase.verifyEqual(char(entity.entityId),       'E1',     'entityId mismatch');
            testCase.verifyEqual(char(entity.nodeId),         'N1',     'nodeId mismatch');
            testCase.verifyEqual(char(entity.entityType),     'human',  'entityType mismatch');
            testCase.verifyEqual(char(entity.parentEntityId), 'PARENT', 'parentEntityId mismatch');
            testCase.verifyEqual(numel(entity.enclaveIds),    1,        'enclaveIds count mismatch');
        end

    end % methods (Test)

end % classdef
