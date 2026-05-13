classdef CredentialStoreTest < matlab.unittest.TestCase
    % CredentialStoreTest  Unit tests for icam.CredentialStore.
    %
    % Covers:
    %   1. issueCertificate stores cert with correct expirySec = simTimeSec + validityPeriodSec
    %   2. getCertificate returns stored cert; throws netsim:icam:noCertificate for unknown entity
    %   3. checkExpiry returns all and only entities with expirySec <= simTimeSec and isExpired == false
    %   4. checkExpiry marks returned entities as expired (subsequent call does not re-return them)
    %   5. revoke sets isExpired = true immediately
    %
    % Requirements: 18.1, 18.2, 18.3, 18.6

    % ======================================================================
    % Shared fixtures
    % ======================================================================
    methods (Access = private)

        function roleBindings = makeRoleBindings(~, enclaveId, roleName)
            % Build a minimal role bindings struct array.
            roleBindings.enclaveId = enclaveId;
            roleBindings.roleName  = roleName;
        end

    end

    % ======================================================================
    % Test 1: issueCertificate stores cert with correct expirySec
    % ======================================================================
    methods (Test)

        function testIssueCertificateComputesCorrectExpiry(testCase)
            % issueCertificate should set expirySec = simTimeSec + validityPeriodSec.
            %
            % Requirements: 18.1, 18.2

            cs = icam.CredentialStore();
            rb = testCase.makeRoleBindings('enc1', 'pilot');

            simTimeSec       = 100.0;
            validityPeriodSec = 3600.0;

            cs.issueCertificate('E1', 'TA1', rb, validityPeriodSec, simTimeSec);

            cert = cs.getCertificate('E1');
            testCase.verifyEqual(cert.expirySec, simTimeSec + validityPeriodSec, ...
                'expirySec should equal simTimeSec + validityPeriodSec');
        end

        function testIssueCertificateStoresIssuedTime(testCase)
            % issueCertificate should store issuedTimeSec = simTimeSec.
            %
            % Requirements: 18.1

            cs = icam.CredentialStore();
            rb = testCase.makeRoleBindings('enc1', 'pilot');

            simTimeSec = 250.0;
            cs.issueCertificate('E1', 'TA1', rb, 1000.0, simTimeSec);

            cert = cs.getCertificate('E1');
            testCase.verifyEqual(cert.issuedTimeSec, simTimeSec, ...
                'issuedTimeSec should equal simTimeSec');
        end

        function testIssueCertificateStoresIssuerAndSubject(testCase)
            % issueCertificate should store issuer and subjectId correctly.
            %
            % Requirements: 18.1

            cs = icam.CredentialStore();
            rb = testCase.makeRoleBindings('enc1', 'pilot');

            cs.issueCertificate('EntityA', 'TrustAnchorX', rb, 3600.0, 0.0);

            cert = cs.getCertificate('EntityA');
            testCase.verifyEqual(char(cert.issuer),    'TrustAnchorX', ...
                'issuer should match trustAnchorId');
            testCase.verifyEqual(char(cert.subjectId), 'EntityA', ...
                'subjectId should match entityId');
        end

        function testIssueCertificateGeneratesHexPublicKey(testCase)
            % issueCertificate should generate a non-empty hex public key.
            %
            % Requirements: 18.1

            cs = icam.CredentialStore();
            rb = testCase.makeRoleBindings('enc1', 'pilot');

            cs.issueCertificate('E1', 'TA1', rb, 3600.0, 0.0);

            cert = cs.getCertificate('E1');
            testCase.verifyNotEmpty(cert.publicKey, ...
                'publicKey should not be empty');
            % Should be a 32-character hex string
            testCase.verifyEqual(numel(cert.publicKey), 32, ...
                'publicKey should be 32 hex characters');
        end

        function testIssueCertificateInitiallyNotExpired(testCase)
            % A newly issued certificate should have isExpired = false.
            %
            % Requirements: 18.1

            cs = icam.CredentialStore();
            rb = testCase.makeRoleBindings('enc1', 'pilot');

            cs.issueCertificate('E1', 'TA1', rb, 3600.0, 0.0);

            cert = cs.getCertificate('E1');
            testCase.verifyFalse(cert.isExpired, ...
                'Newly issued certificate should have isExpired = false');
        end

        function testIssueCertificateAtTimeZero(testCase)
            % issueCertificate at simTimeSec=0 should work correctly.
            %
            % Requirements: 18.1

            cs = icam.CredentialStore();
            rb = testCase.makeRoleBindings('enc1', 'pilot');

            cs.issueCertificate('E1', 'TA1', rb, 7200.0, 0.0);

            cert = cs.getCertificate('E1');
            testCase.verifyEqual(cert.expirySec, 7200.0, ...
                'expirySec at t=0 should equal validityPeriodSec');
        end

        function testIssueCertificateOverwritesPrevious(testCase)
            % Issuing a second certificate for the same entity should overwrite
            % the first.
            %
            % Requirements: 18.1

            cs = icam.CredentialStore();
            rb = testCase.makeRoleBindings('enc1', 'pilot');

            cs.issueCertificate('E1', 'TA1', rb, 3600.0, 0.0);
            cs.issueCertificate('E1', 'TA2', rb, 7200.0, 100.0);

            cert = cs.getCertificate('E1');
            testCase.verifyEqual(char(cert.issuer), 'TA2', ...
                'Second issuance should overwrite issuer');
            testCase.verifyEqual(cert.expirySec, 7300.0, ...
                'Second issuance should overwrite expirySec (100 + 7200)');
        end

        % ------------------------------------------------------------------
        % Test 2: getCertificate returns stored cert; throws for unknown entity
        % ------------------------------------------------------------------

        function testGetCertificateReturnsStoredCert(testCase)
            % getCertificate should return the certificate that was stored.
            %
            % Requirements: 18.1, 18.2

            cs = icam.CredentialStore();
            rb = testCase.makeRoleBindings('enc1', 'pilot');

            cs.issueCertificate('E1', 'TA1', rb, 3600.0, 50.0);

            cert = cs.getCertificate('E1');
            testCase.verifyEqual(cert.expirySec, 3650.0, ...
                'getCertificate should return the stored certificate');
        end

        function testGetCertificateThrowsForUnknownEntity(testCase)
            % getCertificate should throw netsim:icam:noCertificate for an
            % entity with no certificate.
            %
            % Requirements: 18.2

            cs = icam.CredentialStore();

            testCase.verifyError( ...
                @() cs.getCertificate('NONEXISTENT'), ...
                'netsim:icam:noCertificate', ...
                'getCertificate should throw netsim:icam:noCertificate for unknown entity');
        end

        function testGetCertificateThrowsOnEmptyStore(testCase)
            % getCertificate on an empty store should throw netsim:icam:noCertificate.
            %
            % Requirements: 18.2

            cs = icam.CredentialStore();

            testCase.verifyError( ...
                @() cs.getCertificate('AnyEntity'), ...
                'netsim:icam:noCertificate', ...
                'getCertificate on empty store should throw netsim:icam:noCertificate');
        end

        % ------------------------------------------------------------------
        % Test 3: checkExpiry returns all and only expired entities
        % ------------------------------------------------------------------

        function testCheckExpiryReturnsExpiredEntities(testCase)
            % checkExpiry should return all entities whose expirySec <= simTimeSec
            % and isExpired == false.
            %
            % Requirements: 18.3

            cs = icam.CredentialStore();
            rb = testCase.makeRoleBindings('enc1', 'pilot');

            % E1 expires at t=100, E2 expires at t=200, E3 expires at t=300
            cs.issueCertificate('E1', 'TA1', rb, 100.0, 0.0);
            cs.issueCertificate('E2', 'TA1', rb, 200.0, 0.0);
            cs.issueCertificate('E3', 'TA1', rb, 300.0, 0.0);

            % At t=150: E1 (expiry=100) should be expired, E2 and E3 should not
            expiredIds = cs.checkExpiry(150.0);

            testCase.verifyEqual(numel(expiredIds), 1, ...
                'Only 1 entity should be expired at t=150');
            testCase.verifyTrue(any(strcmp(expiredIds, 'E1')), ...
                'E1 should be in the expired list');
        end

        function testCheckExpiryReturnsMultipleExpiredEntities(testCase)
            % checkExpiry should return all entities that have expired.
            %
            % Requirements: 18.3

            cs = icam.CredentialStore();
            rb = testCase.makeRoleBindings('enc1', 'pilot');

            cs.issueCertificate('E1', 'TA1', rb, 100.0, 0.0);
            cs.issueCertificate('E2', 'TA1', rb, 200.0, 0.0);
            cs.issueCertificate('E3', 'TA1', rb, 300.0, 0.0);

            % At t=250: E1 (expiry=100) and E2 (expiry=200) should be expired
            expiredIds = cs.checkExpiry(250.0);

            testCase.verifyEqual(numel(expiredIds), 2, ...
                '2 entities should be expired at t=250');
            testCase.verifyTrue(any(strcmp(expiredIds, 'E1')), ...
                'E1 should be in the expired list');
            testCase.verifyTrue(any(strcmp(expiredIds, 'E2')), ...
                'E2 should be in the expired list');
        end

        function testCheckExpiryExcludesNonExpiredEntities(testCase)
            % checkExpiry should not return entities whose expirySec > simTimeSec.
            %
            % Requirements: 18.3

            cs = icam.CredentialStore();
            rb = testCase.makeRoleBindings('enc1', 'pilot');

            cs.issueCertificate('E1', 'TA1', rb, 1000.0, 0.0);

            % At t=50: E1 (expiry=1000) should not be expired
            expiredIds = cs.checkExpiry(50.0);

            testCase.verifyEqual(numel(expiredIds), 0, ...
                'No entities should be expired at t=50');
        end

        function testCheckExpiryAtExactExpiryTime(testCase)
            % checkExpiry should return an entity when simTimeSec == expirySec
            % (boundary condition: expirySec <= simTimeSec).
            %
            % Requirements: 18.3

            cs = icam.CredentialStore();
            rb = testCase.makeRoleBindings('enc1', 'pilot');

            cs.issueCertificate('E1', 'TA1', rb, 500.0, 0.0);

            % At exactly t=500 (expirySec == simTimeSec)
            expiredIds = cs.checkExpiry(500.0);

            testCase.verifyEqual(numel(expiredIds), 1, ...
                'Entity should be expired at exactly its expiry time');
            testCase.verifyTrue(any(strcmp(expiredIds, 'E1')), ...
                'E1 should be in the expired list at t=500');
        end

        function testCheckExpiryReturnsEmptyWhenNoneExpired(testCase)
            % checkExpiry should return an empty cell array when no certs are expired.
            %
            % Requirements: 18.3

            cs = icam.CredentialStore();
            rb = testCase.makeRoleBindings('enc1', 'pilot');

            cs.issueCertificate('E1', 'TA1', rb, 3600.0, 0.0);

            expiredIds = cs.checkExpiry(0.0);

            testCase.verifyEqual(numel(expiredIds), 0, ...
                'checkExpiry should return empty cell array when no certs expired');
        end

        % ------------------------------------------------------------------
        % Test 4: checkExpiry marks returned entities as expired
        % ------------------------------------------------------------------

        function testCheckExpiryMarksEntitiesAsExpired(testCase)
            % After checkExpiry returns an entity, its isExpired flag should be true.
            %
            % Requirements: 18.3

            cs = icam.CredentialStore();
            rb = testCase.makeRoleBindings('enc1', 'pilot');

            cs.issueCertificate('E1', 'TA1', rb, 100.0, 0.0);

            % First call: should return E1 and mark it expired
            expiredIds = cs.checkExpiry(200.0);
            testCase.verifyEqual(numel(expiredIds), 1, ...
                'First checkExpiry call should return E1');

            % Verify isExpired is now true
            cert = cs.getCertificate('E1');
            testCase.verifyTrue(cert.isExpired, ...
                'isExpired should be true after checkExpiry marks it');
        end

        function testCheckExpiryDoesNotReReturnAlreadyExpiredEntities(testCase)
            % A subsequent call to checkExpiry should not re-return entities
            % that were already marked as expired.
            %
            % Requirements: 18.3

            cs = icam.CredentialStore();
            rb = testCase.makeRoleBindings('enc1', 'pilot');

            cs.issueCertificate('E1', 'TA1', rb, 100.0, 0.0);

            % First call at t=200: E1 expires and is marked
            expiredIds1 = cs.checkExpiry(200.0);
            testCase.verifyEqual(numel(expiredIds1), 1, ...
                'First call should return E1');

            % Second call at t=300: E1 is already expired, should not be returned again
            expiredIds2 = cs.checkExpiry(300.0);
            testCase.verifyEqual(numel(expiredIds2), 0, ...
                'Second call should not re-return already-expired E1');
        end

        function testCheckExpiryOnlyReturnsNewlyExpiredEntities(testCase)
            % checkExpiry should only return entities that are newly expired
            % (isExpired was false before the call).
            %
            % Requirements: 18.3

            cs = icam.CredentialStore();
            rb = testCase.makeRoleBindings('enc1', 'pilot');

            cs.issueCertificate('E1', 'TA1', rb, 100.0, 0.0);
            cs.issueCertificate('E2', 'TA1', rb, 300.0, 0.0);

            % First call at t=150: E1 expires
            expiredIds1 = cs.checkExpiry(150.0);
            testCase.verifyEqual(numel(expiredIds1), 1, ...
                'First call should return only E1');

            % Second call at t=350: E2 expires; E1 already expired
            expiredIds2 = cs.checkExpiry(350.0);
            testCase.verifyEqual(numel(expiredIds2), 1, ...
                'Second call should return only E2');
            testCase.verifyTrue(any(strcmp(expiredIds2, 'E2')), ...
                'E2 should be in the second expired list');
        end

        % ------------------------------------------------------------------
        % Test 5: revoke sets isExpired = true immediately
        % ------------------------------------------------------------------

        function testRevokeMarksExpiredImmediately(testCase)
            % revoke should set isExpired = true for the entity's certificate.
            %
            % Requirements: 18.6

            cs = icam.CredentialStore();
            rb = testCase.makeRoleBindings('enc1', 'pilot');

            cs.issueCertificate('E1', 'TA1', rb, 3600.0, 0.0);

            % Verify not expired before revoke
            cert = cs.getCertificate('E1');
            testCase.verifyFalse(cert.isExpired, ...
                'Certificate should not be expired before revoke');

            % Revoke
            cs.revoke('E1');

            % Verify expired after revoke
            cert = cs.getCertificate('E1');
            testCase.verifyTrue(cert.isExpired, ...
                'Certificate should be expired after revoke');
        end

        function testRevokeThrowsForUnknownEntity(testCase)
            % revoke should throw netsim:icam:noCertificate for an entity
            % with no certificate.
            %
            % Requirements: 18.6

            cs = icam.CredentialStore();

            testCase.verifyError( ...
                @() cs.revoke('NONEXISTENT'), ...
                'netsim:icam:noCertificate', ...
                'revoke should throw netsim:icam:noCertificate for unknown entity');
        end

        function testRevokedCertNotReturnedByCheckExpiry(testCase)
            % After revoke, checkExpiry should not re-return the entity
            % (isExpired is already true).
            %
            % Requirements: 18.3, 18.6

            cs = icam.CredentialStore();
            rb = testCase.makeRoleBindings('enc1', 'pilot');

            cs.issueCertificate('E1', 'TA1', rb, 3600.0, 0.0);

            % Revoke before expiry time
            cs.revoke('E1');

            % checkExpiry at a time past expiry should not return E1
            % (it's already marked expired)
            expiredIds = cs.checkExpiry(5000.0);
            testCase.verifyEqual(numel(expiredIds), 0, ...
                'Revoked cert should not be returned by checkExpiry');
        end

        function testRevokeDoesNotAffectOtherEntities(testCase)
            % Revoking one entity's certificate should not affect others.
            %
            % Requirements: 18.6

            cs = icam.CredentialStore();
            rb = testCase.makeRoleBindings('enc1', 'pilot');

            cs.issueCertificate('E1', 'TA1', rb, 3600.0, 0.0);
            cs.issueCertificate('E2', 'TA1', rb, 3600.0, 0.0);

            cs.revoke('E1');

            cert2 = cs.getCertificate('E2');
            testCase.verifyFalse(cert2.isExpired, ...
                'Revoking E1 should not affect E2');
        end

    end % methods (Test)

end % classdef
