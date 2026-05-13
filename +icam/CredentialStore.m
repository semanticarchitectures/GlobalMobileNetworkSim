classdef CredentialStore < handle
    % CredentialStore  Manages certificates and their lifecycle per entity.
    %
    % Internal storage: containers.Map from entityId (char) to certificate struct.
    %
    % Certificate struct fields:
    %   issuer         (string)  — Trust_Anchor entity identifier
    %   subjectId      (string)  — subject Entity identifier
    %   publicKey      (string)  — synthetic public key value (hex string)
    %   roleBindings   (struct array) — {enclaveId, roleName}
    %   issuedTimeSec  (double)  — simulation time of issuance
    %   expirySec      (double)  — simulation time of expiry
    %   isExpired      (logical) — set true when expiry is detected or revoked
    %
    % Requirements: 18.1, 18.2, 18.3, 18.6

    properties (Access = private)
        % containers.Map from entityId (char) to certificate struct
        certMap     % containers.Map
    end

    methods (Access = public)

        % ------------------------------------------------------------------
        % Constructor
        % ------------------------------------------------------------------

        function obj = CredentialStore()
            % CredentialStore  Construct an empty CredentialStore.
            %
            %   cs = icam.CredentialStore()
            %
            % Requirements: 18.1

            obj.certMap = containers.Map('KeyType', 'char', 'ValueType', 'any');
        end

        % ------------------------------------------------------------------
        % Public methods
        % ------------------------------------------------------------------

        function issueCertificate(obj, entityId, trustAnchorId, roleBindings, ...
                validityPeriodSec, simTimeSec)
            % issueCertificate  Create and store a certificate for an entity.
            %
            %   cs.issueCertificate(entityId, trustAnchorId, roleBindings, ...
            %                       validityPeriodSec, simTimeSec)
            %
            %   Creates a certificate struct with:
            %     expirySec = simTimeSec + validityPeriodSec
            %     publicKey = synthetic 128-bit hex string (32 hex chars)
            %     isExpired = false
            %
            %   Overwrites any existing certificate for the entity.
            %
            % Requirements: 18.1, 18.2

            % Generate synthetic public key: 4 × 32-bit random integers → 32 hex chars
            keyParts = randi([0, 2^31-1], 1, 4);
            publicKey = sprintf('%08x%08x%08x%08x', ...
                keyParts(1), keyParts(2), keyParts(3), keyParts(4));

            cert.issuer        = string(trustAnchorId);
            cert.subjectId     = string(entityId);
            cert.publicKey     = publicKey;
            cert.roleBindings  = roleBindings;
            cert.issuedTimeSec = simTimeSec;
            cert.expirySec     = simTimeSec + validityPeriodSec;
            cert.isExpired     = false;

            obj.certMap(char(entityId)) = cert;
        end

        function cert = getCertificate(obj, entityId)
            % getCertificate  Return the certificate struct for an entity.
            %
            %   cert = cs.getCertificate(entityId)
            %
            %   Returns the certificate struct stored for entityId.
            %
            %   Throws netsim:icam:noCertificate if no certificate exists.
            %
            % Requirements: 18.1, 18.2

            key = char(entityId);
            if ~obj.certMap.isKey(key)
                error('netsim:icam:noCertificate', ...
                    'No certificate for entity "%s"', key);
            end
            cert = obj.certMap(key);
        end

        function expiredIds = checkExpiry(obj, simTimeSec)
            % checkExpiry  Return entity IDs whose certificates have expired.
            %
            %   expiredIds = cs.checkExpiry(simTimeSec)
            %
            %   Returns a cell array of entityId strings (char) where:
            %     cert.expirySec <= simTimeSec  AND  cert.isExpired == false
            %
            %   Marks matching certificates as expired (isExpired = true).
            %
            % Requirements: 18.3

            expiredIds = {};
            keys = obj.certMap.keys();

            for k = 1:numel(keys)
                key  = keys{k};
                cert = obj.certMap(key);

                if cert.expirySec <= simTimeSec && ~cert.isExpired
                    % Mark as expired
                    cert.isExpired = true;
                    obj.certMap(key) = cert;
                    expiredIds{end+1} = key; %#ok<AGROW>
                end
            end
        end

        function revoke(obj, entityId)
            % revoke  Mark a certificate as expired immediately.
            %
            %   cs.revoke(entityId)
            %
            %   Sets isExpired = true for the entity's certificate.
            %
            %   Throws netsim:icam:noCertificate if no certificate exists.
            %
            % Requirements: 18.6

            key = char(entityId);
            if ~obj.certMap.isKey(key)
                error('netsim:icam:noCertificate', ...
                    'No certificate for entity "%s"', key);
            end

            cert = obj.certMap(key);
            cert.isExpired = true;
            obj.certMap(key) = cert;
        end

    end % methods (Access = public)

end % classdef
