pragma solidity ^0.4.21;

import "zeppelin-solidity/contracts/ownership/Ownable.sol";
import "../AbacusCoordinator.sol";
import "./ComplianceStandard.sol";
import "../provider/ProviderRegistry.sol";

/**
 * Registry for compliance providers.
 */
contract ComplianceCoordinator is AbacusCoordinator {
    ProviderRegistry public providerRegistry;

    function ComplianceCoordinator(ProviderRegistry _providerRegistry) public  {
        providerRegistry = _providerRegistry;
    }

    /**
     * @dev Mapping of actionId => requestId.
     */
    mapping (uint256 => uint256) actionRequests;

    uint256 nextRequestId = 1;

    struct Request {
        /**
         * @dev Id of the escrow associated with this request.
         */
        uint256 escrowId;

        /**
         * @dev Block when this check status has expired. 0 if we haven't writen.
         */
        uint256 blockToExpire;

        /**
         * @dev Result of the check. 0 indicates success, non-zero is left to the caller.
         */
        uint8 checkResult;

        /**
         * @dev Id of the action associated with the request.
         */
        uint256 actionId;
    }

    /**
     * @dev Mapping of all requestIds to the request.
     */
    mapping (uint256 => Request) requests;

    /**
     * @dev Emitted when a compliance check is performed.
     *
     * @param providerId The id of the provider.
     * @param providerVersion The version of the provider.
     * @param instrumentAddr The address of the instrument contract.
     * @param instrumentIdOrAmt The instrument id (NFT) or amount (ERC20).
     * @param from The from address of the token transfer.
     * @param to The to address of the token transfer.
     * @param data Any additional data related to the action.
     * @param checkResult The result of the compliance check.
     * @param nextProviderId The id of the compliance provider used after this provider.
     */
    event ComplianceCheckPerformed(
        uint256 providerId,
        uint256 providerVersion,
        address instrumentAddr,
        uint256 instrumentIdOrAmt,
        address from,
        address to,
        bytes32 data,
        uint8 checkResult,
        uint256 nextProviderId
    );

    /**
     * @dev Emitted when the result of an asynchronous compliance check is written.
     *
     * @param providerId The id of the compliance check request.
     * @param blockToExpire The block in which the compliance check result expires.
     * @param checkResult The result of the compliance check.
     */
    event ComplianceCheckResultWritten(
        uint256 requestId,
        uint256 blockToExpire,
        uint8 checkResult
    );

    /**
     * @dev Writes the result of an asynchronous compliance check to the blockchain.
     *
     * @param requestId The id of the request.
     * @param blockToExpire The block in which the compliance check result expires.
     * @param checkResult The result of the compliance check.
     */
    function writeCheckResult(
        uint256 requestId,
        uint256 blockToExpire,
        uint8 checkResult
    ) external returns (bool)
    {
        uint256 id;
        address owner;
        uint256 version;
        (id,,, owner,version,) = providerRegistry.latestProvider(providerId);

        // Check service exists
        require(id != 0);
        // Check provider version is correct
        require(version == providerVersion);
        // Check service owner is correct
        require(owner == msg.sender);

        uint256 actionId = computeActionId(
            providerId,
            providerVersion,
            instrumentAddr,
            instrumentIdOrAmt,
            from,
            to,
            data
        );

        requests[]
        actionRequests[actionId] = requestId;

        emit ComplianceCheckResultWritten(
            providerId,
            providerVersion,
            instrumentAddr,
            instrumentIdOrAmt,
            from,
            to,
            data,
            blockToExpire,
            checkResult
        );
        return true;
    }

    /**
     * @dev Invalidates a stored asynchronous compliance check result.
     * This can only be called by the owner of the provider or by the instrument that
     * requested the compliance check.
     */
    function invalidateCheckResult(
        uint256 providerId,
        address instrumentAddr,
        uint256 instrumentIdOrAmt,
        address from,
        address to,
        bytes32 data
    ) external returns (bool)
    {
        uint256 actionId = computeActionId(
            providerId,
            providerRegistry.latestProviderVersion(providerId),
            instrumentAddr,
            instrumentIdOrAmt,
            from,
            to,
            data
        );
        address owner = providerRegistry.providerOwner(providerId);
        if (owner != msg.sender || instrumentAddr != msg.sender) {
            return false;
        }
        delete statuses[actionId];
        return true;
    }

    /**
     * @dev Computes an id for an action using keccak256.
     */
    function computeActionId(
        uint256 providerId,
        uint256 providerVersion,
        address instrumentAddr,
        uint256 instrumentIdOrAmt,
        address from,
        address to,
        bytes32 data
    ) pure private returns (uint256)
    {
        return uint256(
            keccak256(
                providerId,
                providerVersion,
                instrumentAddr,
                instrumentIdOrAmt,
                from,
                to,
                data
            )
        );
    }

    uint8 constant E_CASYNC_CHECK_NOT_PERFORMED = 100;
    uint8 constant E_CASYNC_CHECK_NOT_EXPIRED = 101;

    /**
     * @dev Checks the result of an async service.
     * Assumes the service is async. Check your preconditions before using.
     */
    function checkAsync(
        uint256 providerId,
        address instrumentAddr,
        uint256 instrumentIdOrAmt,
        address from,
        address to,
        bytes32 data
    ) view private returns (uint8, uint256)
    {
        uint256 actionId = computeActionId(
            providerId,
            providerRegistry.latestProviderVersion(providerId),
            instrumentAddr,
            instrumentIdOrAmt,
            from,
            to,
            data
        );
        CheckStatus storage status = statuses[actionId];

        // Check that the status check has been performed.
        if (status.blockToExpire == 0) {
            return (E_CASYNC_CHECK_NOT_PERFORMED, 0);
        }

        // Check that the status check has not expired. 
        if (status.blockToExpire <= block.number) {
            return (E_CASYNC_CHECK_NOT_EXPIRED, 0);
        }

        return (status.checkResult, actionId);
    }

    /**
     * @dev Checks the result of a compliance check.
     */
    function check(
        uint256 providerId,
        address instrumentAddr,
        uint256 instrumentIdOrAmt,
        address from,
        address to,
        bytes32 data
    ) view public returns (uint8, uint256)
    {
        uint8 checkResult;
        address owner;
        bool isAsync;
        (,,, owner,, isAsync) = providerRegistry.latestProvider(providerId);

        // Async checks
        if (isAsync) {
            (checkResult,) = checkAsync(
                providerId,
                instrumentAddr,
                instrumentIdOrAmt,
                from,
                to,
                data
            );
            if (checkResult != 0) {
                return (checkResult, providerId);
            }
            return (checkResult, 0);
        }

        // Sync checks
        ComplianceStandard standard = ComplianceStandard(owner);

        uint256 nextProviderId;
        (checkResult, nextProviderId) = standard.check(
            instrumentAddr,
            instrumentIdOrAmt,
            from,
            to,
            data
        );

        if (nextProviderId != 0) {
            // recursively check next service
            (checkResult, nextProviderId) = check(
                nextProviderId,
                instrumentAddr,
                instrumentIdOrAmt,
                from,
                to,
                data
            );
        }
        return (checkResult, nextProviderId);
    }

    uint8 constant E_CHECK_INSTRUMENT_WRONG_SENDER = 140;

    /**
     * @dev Checks the result of a compliance check and performs any necessary state changes.
     */
    function hardCheck(
        uint256 providerId,
        address instrumentAddr,
        uint256 instrumentIdOrAmt,
        address from,
        address to,
        bytes32 data
    ) public returns (uint8, uint256)
    {
        if (msg.sender != instrumentAddr) {
            return (E_CHECK_INSTRUMENT_WRONG_SENDER, 0);
        }
        address owner;
        uint256 providerVersion;
        bool isAsync;
        (,,, owner, providerVersion, isAsync) = providerRegistry.latestProvider(providerId);

        uint8 checkResult;

        // This variable is used for two purposes to save on stack space.
        uint256 nextProviderIdOrActionId;

        // Async checks
        if (isAsync) {
            (checkResult, nextProviderIdOrActionId) = checkAsync(
                providerId,
                instrumentAddr,
                instrumentIdOrAmt,
                from,
                to,
                data
            );
            emit ComplianceCheckPerformed(
                providerId,
                providerVersion,
                instrumentAddr,
                instrumentIdOrAmt,
                from,
                to,
                data,
                checkResult,
                0
            );
            if (checkResult != 0) {
                return (checkResult, providerId);
            }
            // Invalidate status if successful check.
            delete statuses[nextProviderIdOrActionId];
            return (checkResult, 0);
        }

        // Sync checks
        ComplianceStandard standard = ComplianceStandard(owner);

        (checkResult, nextProviderIdOrActionId) = standard.check(
            instrumentAddr,
            instrumentIdOrAmt,
            from,
            to,
            data
        );
        standard.onHardCheck(
            instrumentAddr,
            instrumentIdOrAmt,
            from,
            to,
            data
        );

        // For auditing
        emit ComplianceCheckPerformed(
            providerId,
            providerVersion,
            instrumentAddr,
            instrumentIdOrAmt,
            from,
            to,
            data,
            checkResult,
            nextProviderIdOrActionId
        );

        if (nextProviderIdOrActionId != 0) {
            // recursively check next service
            (checkResult, nextProviderIdOrActionId) = hardCheck(
                nextProviderIdOrActionId,
                instrumentAddr,
                instrumentIdOrAmt,
                from,
                to,
                data
            );
        }
        return (checkResult, nextProviderIdOrActionId);
    }
}
