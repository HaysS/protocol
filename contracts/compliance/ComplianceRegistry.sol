pragma solidity ^0.4.19;

import "zeppelin-solidity/contracts/ownership/Ownable.sol";
import "../NeedsAbacus.sol";
import "./ComplianceStandard.sol";
import "../provider/ProviderRegistry.sol";

/**
 * Registry for compliance providers.
 */
contract ComplianceRegistry is ProviderRegistry, NeedsAbacus {
    struct CheckStatus {
        // Block when this check status has expired.
        uint256 blockToExpire;

        // 0 indicates success, non-zero is left to the caller.
        uint8 checkResult;
    }

    /**
     * Mapping of provider id => address => action id => check status.
     */
    mapping (uint256 => mapping (address => mapping (uint256 => CheckStatus))) public statuses;

    uint256 providerIdAutoInc;

    event ComplianceCheckPerformed(
        uint256 providerId,
        address standard,
        address instrumentAddr,
        uint256 actionId,
        uint8 checkResult,
        uint256 nextProviderId
    );

    event ComplianceCheckRequested(
        uint256 providerId,
        address instrumentAddr,
        uint256 actionId,
        uint256 cost
    );

    event ComplianceCheckResultWritten(
        uint256 providerId,
        address instrumentAddr,
        uint256 actionId,
        uint256 blockToExpire,
        uint8 checkResult
    );

    /**
     * Requests a compliance check.
     */
    function requestCheck(
        uint256 providerId,
        address instrumentAddr,
        uint256 actionId,
        uint256 cost
    ) fromKernel external
    {
        ComplianceCheckRequested(providerId, instrumentAddr, actionId, cost);
    }

    /**
     * Writes the result of an asynchronous compliance check to the blockchain.
     */
    function writeCheckResult(
        uint256 providerId,
        address instrumentAddr,
        uint256 actionId,
        uint256 blockToExpire,
        uint8 checkResult
    ) external returns (uint8)
    {
        ProviderInfo storage providerInfo = providers[providerId];

        // Check service exists
        if (providerInfo.id == 0) {
            return 1;
        }
        // Check service owner is correct
        if (providerInfo.owner != msg.sender) {
            return 2;
        }

        statuses[providerId][instrumentAddr][actionId] = CheckStatus({
            blockToExpire: blockToExpire,
            checkResult: checkResult
        });
        ComplianceCheckResultWritten(
            providerId,
            instrumentAddr,
            actionId,
            blockToExpire,
            checkResult
        );
    }

    function invalidateCheckResult(
        uint256 providerId,
        address instrumentAddr,
        uint256 actionId
    ) external
    {
        ProviderInfo storage providerInfo = providers[providerId];
        require(providerInfo.owner == msg.sender || instrumentAddr == msg.sender);
        delete statuses[providerId][instrumentAddr][actionId];
    }

    /**
     * Computes an id for an action using keccak256.
     */
    function computeActionId(
        uint256 providerId,
        address instrumentAddr,
        uint256 instrumentIdOrAmt,
        address from,
        address to,
        bytes32 data
    ) view private returns (uint256)
    {
        return uint256(
            keccak256(
                providerId,
                instrumentAddr,
                instrumentIdOrAmt,
                from,
                to,
                data
            )
        );
    }

    /**
     * Checks the result of an async service.
     * Assumes the service is async. Check your preconditions before using.
     */
    function checkAsync(
        uint256 providerId,
        address instrumentAddr,
        uint256 instrumentIdOrAmt,
        address from,
        address to,
        bytes32 data
    ) view private returns (uint8)
    {
        uint256 actionId = computeActionId(
            providerId,
            instrumentAddr,
            instrumentIdOrAmt,
            from,
            to,
            data
        );
        CheckStatus storage status = statuses[providerId][instrumentAddr][actionId];

        // Check that the status check has been performed.
        if (status.blockToExpire == 0) {
            return 100;
        }

        // Check that the status check has not expired. 
        if (status.blockToExpire <= block.number) {
            return 101;
        }

        return  status.checkResult;
    }

    /**
     * Checks the result of a compliance check.
     */
    function check(
        uint256 providerId,
        address instrumentAddr,
        uint256 instrumentIdOrAmt,
        address from,
        address to,
        bytes32 data
    ) view public returns (uint8)
    {
        ProviderInfo storage providerInfo = providers[providerId];

        // Async checks
        if (bytes(providerInfo.metadata).length > 0) {
            return checkAsync(
                providerId,
                instrumentAddr,
                instrumentIdOrAmt,
                from,
                to,
                data
            );
        }

        // Sync checks
        ComplianceStandard standard = ComplianceStandard(providerInfo.owner);

        uint8 checkResult;
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
            checkResult = check(
                nextProviderId,
                instrumentAddr,
                instrumentIdOrAmt,
                from,
                to,
                data
            );
        }
        return checkResult;
    }

    /**
     * Checks the result of a compliance check, ensuring any necessary state changes are made.
     */
    function hardCheck(
        uint256 providerId,
        address instrumentAddr,
        uint256 actionId
    ) fromKernel public returns (uint8, uint256)
    {
        ProviderInfo storage providerInfo = providers[providerId];

        uint8 checkResult;

        // Async checks
        if (bytes(providerInfo.metadata).length > 0) {
            checkResult = checkAsync(
                providerId,
                instrumentAddr,
                actionId
            );
            ComplianceCheckPerformed(
                providerId,
                address(0),
                instrumentAddr,
                actionId,
                checkResult,
                0
            );
            if (checkResult != 0) {
                return (checkResult, providerId);
            }
            return (checkResult, 0);
        }

        // Sync checks
        ComplianceStandard standard = ComplianceStandard(providerInfo.owner);

        checkResult;
        uint256 nextProviderId;
        (checkResult, nextProviderId) = standard.check(instrumentAddr, actionId);
        standard.onHardCheck(instrumentAddr, actionId);

        // For auditing
        ComplianceCheckPerformed(
            providerId,
            standard,
            instrumentAddr,
            actionId,
            checkResult,
            nextProviderId
        );

        if (nextProviderId != 0) {
            // recursively check next service
            (checkResult, nextProviderId) = hardCheck(nextProviderId, instrumentAddr, actionId);
        }
        return (checkResult, nextProviderId);
    }
}
